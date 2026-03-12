import sys
import time

import pyperclip
from pynput.keyboard import Controller, Key


def main() -> int:
    text = sys.stdin.read()
    if not text:
        return 0

    keyboard = Controller()
    pyperclip.copy(text)
    time.sleep(0.05)
    keyboard.press(Key.cmd)
    keyboard.press("v")
    keyboard.release("v")
    keyboard.release(Key.cmd)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
