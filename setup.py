from setuptools import setup


APP = ["main.py"]
DATA_FILES = [
    (
        "assets",
        [
            "assets/menu_m_template.png",
            "assets/muesli_app_icon.png",
        ],
    )
]
OPTIONS = {
    "iconfile": "assets/muesli.icns",
    "argv_emulation": False,
    "plist": {
        "CFBundleName": "Muesli",
        "CFBundleDisplayName": "Muesli",
        "CFBundleIdentifier": "com.muesli.app",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "0.1.0",
        "LSUIElement": True,
        "NSMicrophoneUsageDescription": "Muesli records microphone audio for dictation and meeting transcription.",
        "NSCalendarsUsageDescription": "Muesli reads your calendar to help prepare for meeting transcription.",
        "NSScreenCaptureUsageDescription": "Muesli captures system audio during meeting transcription when you enable it.",
    },
    "packages": [
        "audio",
        "cal_monitor",
        "dictation",
        "meeting",
        "storage",
        "transcribe",
        "ui",
    ],
    "includes": [
        "sounddevice",
        "pynput",
        "pyperclip",
        "mlx_whisper",
        "mlx_audio",
        "jaraco.text",
    ],
}


setup(
    app=APP,
    name="Muesli",
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
