import time
import ctypes
import os
import sys
from datetime import datetime, timezone
from supabase import create_client
from dotenv import load_dotenv

load_dotenv()
supabase = create_client(os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY"))
USER_ID = os.getenv("USER_ID")
LOCK_FILE = r"C:\tracker-arquitetura\tracker.lock"

if os.path.exists(LOCK_FILE):
    print("Tracker ja esta rodando. Encerrando esta instancia.")
    sys.exit(0)

with open(LOCK_FILE, "w") as f:
    f.write(str(os.getpid()))

ORG_ID = os.getenv("ORG_ID")

IDLE_LIMIT = 600
KEEPALIVE_INTERVAL = 300

APP_PATTERNS = {
    "autocad": ("AutoCAD", "CAD"),
    "acad": ("AutoCAD", "CAD"),
    "sketchup": ("SketchUp", "Modelagem 3D"),
    "revit": ("Revit", "BIM"),
    "vray": ("V-Ray", "Renderizacao"),
    "enscape": ("Enscape", "Renderizacao"),
    "chrome": ("Chrome", "Navegador"),
    "firefox": ("Firefox", "Navegador"),
    "edge": ("Edge", "Navegador"),
    "excel": ("Excel", "Planilha"),
    "winword": ("Word", "Documento"),
    "illustrator": ("Illustrator", "Design"),
    "photoshop": ("Photoshop", "Design"),
    "whatsapp": ("WhatsApp", "Comunicacao"),
    "3Dmax": ("3Dmax", "Renderizacao"),
}

def get_title():
    hwnd = ctypes.windll.user32.GetForegroundWindow()
    length = ctypes.windll.user32.GetWindowTextLengthW(hwnd)
    buf = ctypes.create_unicode_buffer(length + 1)
    ctypes.windll.user32.GetWindowTextW(hwnd, buf, length + 1)
    return buf.value

def get_process():
    try:
        hwnd = ctypes.windll.user32.GetForegroundWindow()
        pid = ctypes.c_ulong()
        ctypes.windll.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        h = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid.value)
        buf = ctypes.create_unicode_buffer(260)
        size = ctypes.c_ulong(260)
        ctypes.windll.kernel32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size))
        ctypes.windll.kernel32.CloseHandle(h)
        return os.path.basename(buf.value).lower()
    except:
        return ""

def get_idle_seconds():
    class LASTINPUTINFO(ctypes.Structure):
        _fields_ = [("cbSize", ctypes.c_uint), ("dwTime", ctypes.c_ulong)]
    lii = LASTINPUTINFO()
    lii.cbSize = ctypes.sizeof(LASTINPUTINFO)
    ctypes.windll.user32.GetLastInputInfo(ctypes.byref(lii))
    millis = ctypes.windll.kernel32.GetTickCount() - lii.dwTime
    return millis / 1000.0

def get_tracking_status():
    try:
        res = supabase.table("tracker_control").select("tracking").eq("user_id", USER_ID).execute()
        return res.data[0]["tracking"]
    except:
        return False

def tracker_loop():
    last_title = None
    last_recorded_at = 0
    print(f"Tracker iniciado para: {USER_ID}")
    try:
        while True:
            try:
                tracking = get_tracking_status()
                if tracking:
                    idle = get_idle_seconds()
                    if idle >= IDLE_LIMIT:
                        last_title = None
                        last_recorded_at = 0
                    else:
                        title = get_title()
                        now = time.time()
                        new_window = title and title != last_title
                        keepalive = (
                            title
                            and title == last_title
                            and (now - last_recorded_at) >= KEEPALIVE_INTERVAL
                        )
                        if new_window or keepalive:
                            process = get_process()
                            for key, (app_name, category) in APP_PATTERNS.items():
                                if key in process or key in title.lower():
                                    try:
                                        supabase.table("time_tracking").insert({
                                            "recorded_at": datetime.now(timezone.utc).isoformat(),
                                            "app": app_name,
                                            "category": category,
                                            "filename": title[:80],
                                            "raw_title": title,
                                            "user_id": USER_ID,
                                            "org_id": ORG_ID,
                                        }).execute()
                                        print(f"OK: {app_name} - {title[:50]}")
                                    except Exception as e:
                                        print(f"Erro: {e}")
                                    break
                            last_title = title
                            last_recorded_at = now
                else:
                    last_title = None
                    last_recorded_at = 0
            except Exception as e:
                print(f"Erro geral: {e}")
            time.sleep(15)
    finally:
        if os.path.exists(LOCK_FILE):
            os.remove(LOCK_FILE)

if __name__ == "__main__":
    tracker_loop()
