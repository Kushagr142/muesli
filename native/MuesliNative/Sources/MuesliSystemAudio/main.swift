import AudioToolbox
import CoreAudio
import Foundation

struct WAVHeader {
    static func create(sampleRate: Int, channels: Int, bitsPerSample: Int, dataSize: Int) -> Data {
        var header = Data()
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8

        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        return header
    }
}

let sampleRate: Float64 = 16_000
let channels: UInt32 = 1

var outputFile: FileHandle?
var outputPath: String?
var maxDuration: Double = 0
var totalBytesWritten = 0
var startTime: Date?
var isRunning = true

let tapCallback: AudioDeviceIOProc = { _, _, inputData, _, _, _, _ in
    let bufferList = inputData.pointee

    for _ in 0 ..< Int(bufferList.mNumberBuffers) {
        let buffer = bufferList.mBuffers
        guard let data = buffer.mData else { continue }
        let byteCount = Int(buffer.mDataByteSize)
        let rawData = Data(bytes: data, count: byteCount)

        if let file = outputFile {
            file.write(rawData)
        } else {
            FileHandle.standardOutput.write(rawData)
        }
        totalBytesWritten += byteCount
    }

    if maxDuration > 0, let startTime, Date().timeIntervalSince(startTime) >= maxDuration {
        isRunning = false
    }

    return noErr
}

@available(macOS 14.2, *)
func main() {
    let args = CommandLine.arguments

    var index = 1
    while index < args.count {
        if args[index] == "--duration", index + 1 < args.count {
            maxDuration = Double(args[index + 1]) ?? 0
            index += 2
        } else {
            outputPath = args[index]
            index += 1
        }
    }

    if let outputPath {
        FileManager.default.createFile(atPath: outputPath, contents: nil)
        outputFile = FileHandle(forWritingAtPath: outputPath)
        outputFile?.write(
            WAVHeader.create(
                sampleRate: Int(sampleRate),
                channels: Int(channels),
                bitsPerSample: 16,
                dataSize: 0
            )
        )
    }

    var deviceID: AudioDeviceID = 0
    var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        &propertySize,
        &deviceID
    )

    guard status == noErr else {
        fputs("Error: Could not get default output device (status: \(status))\n", stderr)
        exit(1)
    }

    let tapDescription = CATapDescription(stereoMixdownOfProcesses: [])
    tapDescription.uuid = UUID()
    tapDescription.name = "MuesliSystemAudio"

    var desiredFormat = AudioStreamBasicDescription(
        mSampleRate: sampleRate,
        mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
        mBytesPerPacket: 2 * channels,
        mFramesPerPacket: 1,
        mBytesPerFrame: 2 * channels,
        mChannelsPerFrame: channels,
        mBitsPerChannel: 16,
        mReserved: 0
    )

    var tapID: AudioObjectID = 0
    var createStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
    guard createStatus == noErr else {
        fputs("Error: Could not create process tap (status: \(createStatus))\n", stderr)
        exit(1)
    }

    let aggregateDescription: CFDictionary = [
        kAudioAggregateDeviceNameKey: "MuesliCapture",
        kAudioAggregateDeviceUIDKey: "com.muesli.capture.\(UUID().uuidString)",
        kAudioAggregateDeviceIsPrivateKey: true,
        kAudioAggregateDeviceTapAutoStartKey: true,
        kAudioAggregateDeviceTapListKey: [[
            kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
        ]],
        kAudioAggregateDeviceMainSubDeviceKey: tapDescription.uuid.uuidString,
    ] as CFDictionary

    var aggregateDevice: AudioDeviceID = 0
    createStatus = AudioHardwareCreateAggregateDevice(aggregateDescription, &aggregateDevice)
    guard createStatus == noErr else {
        fputs("Error: Could not create aggregate device (status: \(createStatus))\n", stderr)
        AudioHardwareDestroyProcessTap(tapID)
        exit(1)
    }

    var formatAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamFormat,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: 0
    )
    let formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    AudioObjectSetPropertyData(aggregateDevice, &formatAddress, 0, nil, formatSize, &desiredFormat)

    var procID: AudioDeviceIOProcID?
    AudioDeviceCreateIOProcID(aggregateDevice, tapCallback, nil, &procID)

    startTime = Date()
    AudioDeviceStart(aggregateDevice, procID)

    signal(SIGINT) { _ in isRunning = false }
    signal(SIGTERM) { _ in isRunning = false }

    while isRunning {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
    }

    AudioDeviceStop(aggregateDevice, procID)
    if let procID {
        AudioDeviceDestroyIOProcID(aggregateDevice, procID)
    }
    AudioHardwareDestroyAggregateDevice(aggregateDevice)
    AudioHardwareDestroyProcessTap(tapID)

    if let outputFile, let outputPath {
        let header = WAVHeader.create(
            sampleRate: Int(sampleRate),
            channels: Int(channels),
            bitsPerSample: 16,
            dataSize: totalBytesWritten
        )
        outputFile.seek(toFileOffset: 0)
        outputFile.write(header)
        outputFile.closeFile()
        fputs("Wrote \(totalBytesWritten) bytes to \(outputPath)\n", stderr)
    }
}

if #available(macOS 14.2, *) {
    main()
} else {
    fputs("MuesliSystemAudio requires macOS 14.2 or later.\n", stderr)
    exit(1)
}
