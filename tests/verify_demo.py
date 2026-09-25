"""启动导出的 exe，用 PrintWindow 抓它的窗口内容（不看 z 序），然后关掉。

用法：python verify_demo.py <exe路径> <输出png> [等待秒数] [按键序列]
按键序列形如 "RETURN|0.5|RETURN"，按一下键、等 0.5 秒、再按一下。
"""
import ctypes
import ctypes.wintypes as wt
import subprocess
import sys
import time

VK = {"RETURN": 0x0D, "ESC": 0x1B, "DOWN": 0x28, "UP": 0x26, "LEFT": 0x25,
      "RIGHT": 0x27, "W": 0x57, "A": 0x41, "S": 0x53, "D": 0x44, "R": 0x52, "SPACE": 0x20}

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32

PW_RENDERFULLCONTENT = 0x00000002


def make_dpi_aware() -> None:
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except OSError:
        user32.SetProcessDPIAware()


_SCANCODE = 0x0008
_KEYUP = 0x0002


def _send_scan(scan: int, up: bool) -> None:
    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [("wVk", wt.WORD), ("wScan", wt.WORD), ("dwFlags", wt.DWORD),
                    ("time", wt.DWORD), ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong))]

    class INPUT(ctypes.Structure):
        class _U(ctypes.Union):
            _fields_ = [("ki", KEYBDINPUT)]
        _anonymous_ = ("_U",)
        _fields_ = [("type", wt.DWORD), ("_U", _U)]

    i = INPUT()
    i.type = 1  # INPUT_KEYBOARD
    i.ki.wScan = scan
    i.ki.dwFlags = _SCANCODE | (_KEYUP if up else 0)
    user32.SendInput(1, ctypes.byref(i), ctypes.sizeof(INPUT))


def press(code: int) -> None:
    scan = user32.MapVirtualKeyW(code, 0)
    _send_scan(scan, False)
    time.sleep(0.05)
    _send_scan(scan, True)


def hold(code: int, seconds: float) -> None:
    scan = user32.MapVirtualKeyW(code, 0)
    _send_scan(scan, False)
    time.sleep(seconds)
    _send_scan(scan, True)


def focus_window(hwnd: int) -> None:
    """把游戏窗抢到前台。直接 SetForegroundWindow 会被系统拒，先借 AttachThreadInput 绕开。"""
    kernel32 = ctypes.windll.kernel32
    user32.ShowWindow(hwnd, 9)  # SW_RESTORE
    user32.SetWindowPos(hwnd, -1, 0, 0, 0, 0, 0x0053)  # TOPMOST, NOMOVE|NOSIZE
    our_tid = kernel32.GetCurrentThreadId()
    fg = user32.GetForegroundWindow()
    fg_tid = user32.GetWindowThreadProcessId(fg, None)
    game_tid = user32.GetWindowThreadProcessId(hwnd, None)
    user32.AttachThreadInput(our_tid, fg_tid, True)
    user32.AttachThreadInput(our_tid, game_tid, True)
    user32.SetForegroundWindow(hwnd)
    user32.SetFocus(hwnd)
    user32.AttachThreadInput(our_tid, fg_tid, False)
    user32.AttachThreadInput(our_tid, game_tid, False)
    time.sleep(0.4)


def shoot_title(title: str, out_png: str) -> None:
    hwnd = user32.FindWindowW(None, title)
    if not hwnd:
        raise SystemExit(f"找不到窗口：{title}")
    rect = wt.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    w, h = rect.right - rect.left, rect.bottom - rect.top
    print(f"窗口 {w}x{h} @ ({rect.left}, {rect.top})")

    hdc_win = user32.GetWindowDC(hwnd)
    hdc_mem = gdi32.CreateCompatibleDC(hdc_win)
    bmp = gdi32.CreateCompatibleBitmap(hdc_win, w, h)
    gdi32.SelectObject(hdc_mem, bmp)
    ok = user32.PrintWindow(hwnd, hdc_mem, PW_RENDERFULLCONTENT)
    if not ok:
        raise SystemExit("PrintWindow 失败")

    # BITMAPINFOHEADER，biHeight 取负 = 自上而下
    class BMI(ctypes.Structure):
        _fields_ = [
            ("biSize", wt.DWORD), ("biWidth", wt.LONG), ("biHeight", wt.LONG),
            ("biPlanes", wt.WORD), ("biBitCount", wt.WORD), ("biCompression", wt.DWORD),
            ("biSizeImage", wt.DWORD), ("biXPelsPerMeter", wt.LONG),
            ("biYPelsPerMeter", wt.LONG), ("biClrUsed", wt.DWORD), ("biClrImportant", wt.DWORD),
        ]

    bmi = BMI()
    bmi.biSize = ctypes.sizeof(BMI)
    bmi.biWidth = w
    bmi.biHeight = -h
    bmi.biPlanes = 1
    bmi.biBitCount = 32
    bmi.biCompression = 0
    buf = ctypes.create_string_buffer(w * h * 4)
    gdi32.GetDIBits(hdc_mem, bmp, 0, h, buf, ctypes.byref(bmi), 0)

    from PIL import Image

    img = Image.frombuffer("RGBA", (w, h), buf.raw, "raw", "BGRA", 0, 1)
    img.convert("RGB").save(out_png)
    print("saved", out_png)

    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(hdc_mem)
    user32.ReleaseDC(hwnd, hdc_win)


def main() -> None:
    make_dpi_aware()
    exe, out_png = sys.argv[1], sys.argv[2]
    wait = float(sys.argv[3]) if len(sys.argv) > 3 else 8.0
    keys = sys.argv[4] if len(sys.argv) > 4 else ""

    proc = subprocess.Popen([exe])
    time.sleep(wait)
    shoot_title("IF：如果之间", out_png)
    if keys:
        hwnd = user32.FindWindowW(None, "IF：如果之间")
        focus_window(hwnd)
        shots = 0
        for step in keys.split("|"):
            low = step.lower()
            if low == "shot":
                shots += 1
                shoot_title("IF：如果之间", out_png.replace(".png", f"_step{shots}.png"))
            elif low.startswith("hold:"):
                _, k, secs = low.split(":")
                hold(VK[k.upper()], float(secs))
            elif step.upper() in VK:
                press(VK[step.upper()])
            else:
                time.sleep(float(step))
    proc.kill()


if __name__ == "__main__":
    main()
