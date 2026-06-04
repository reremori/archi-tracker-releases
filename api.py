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
ORG_ID = os.getenv("ORG_ID")

# Instancia unica via Named Mutex do Windows.
# O kernel libera automaticamente quando o processo morre — sem lock residual.
_mutex = ctypes.windll.kernel32.CreateMutexW(None, True, "Global\\ArchiTrackerMutex")
if ctypes.windll.kernel32.GetLastError() == 183:  # ERROR_ALREADY_EXISTS
    print("Tracker ja esta rodando. Encerrando esta instancia.")
    sys.exit(0)

IDLE_LIMIT = 600
KEEPALIVE_INTERVAL = 300
CONFIG_REFRESH_INTERVAL = 300

BROWSER_KEYS = {'chrome', 'firefox', 'edge', 'opera', 'brave', 'arc', 'vivaldi'}

def load_monitored_apps():
    try:
        res = supabase.table("monitored_apps") \
            .select("process_key, app_name, category") \
            .eq("org_id", ORG_ID) \
            .eq("active", True) \
            .execute()
        patterns = {}
        for row in res.data:
            patterns[row['process_key'].lower()] = (row['app_name'], row['category'])
        print(f"Apps carregados: {len(patterns)}")
        return patterns
    except Exception as e:
        print(f"Erro ao carregar apps: {e}")
        return {}

def load_monitored_sites():
    try:
        res = supabase.table("monitored_sites") \
            .select("keyword, display_name, category") \
            .eq("org_id", ORG_ID) \
            .execute()
        sites = []
        for row in res.data:
            sites.append((row['keyword'].lower(), row['display_name'], row['category']))
        print(f"Sites carregados: {len(sites)}")
        return sites
    except Exception as e:
        print(f"Erro ao carregar sites: {e}")
        return []

def match_site(title_lower, monitored_sites):
    for keyword, display_name, category in monitored_sites:
        if keyword in title_lower:
            return display_name, category
    return None, None

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
    idle_registered = False
    last_config_load = 0

    app_patterns = load_monitored_apps()
    monitored_sites = load_monitored_sites()

    print(f"Tracker iniciado para: {USER_ID}")
    try:
        while True:
            try:
                now = time.time()

                if now - last_config_load >= CONFIG_REFRESH_INTERVAL:
                    app_patterns = load_monitored_apps()
                    monitored_sites = load_monitored_sites()
                    last_config_load = now

                tracking = get_tracking_status()
                if tracking:
                    idle = get_idle_seconds()
                    if idle >= IDLE_LIMIT:
                        if last_title is not None and not idle_registered:
                            try:
                                supabase.table("time_tracking").insert({
                                    "recorded_at": datetime.now(timezone.utc).isoformat(),
                                    "app": "Inativo",
                                    "category": "Inativo",
                                    "filename": "",
                                    "raw_title": "",
                                    "user_id": USER_ID,
                                    "org_id": ORG_ID,
                                }).execute()
                                print("Inatividade registrada")
                            except Exception as e:
                                print(f"Erro ao registrar inatividade: {e}")
                            idle_registered = True
                        last_title = None
                        last_recorded_at = 0
                    else:
                        idle_registered = False
                        title = get_title()
                        new_window = title and title != last_title
                        keepalive = (
                            title
                            and title == last_title
                            and (now - last_recorded_at) >= KEEPALIVE_INTERVAL
                        )
                        if new_window or keepalive:
                            process = get_process()
                            title_lower = title.lower()

                            for key, (app_name, category) in app_patterns.items():
                                if key in process or key in title_lower:
                                    if key in BROWSER_KEYS:
                                        site_name, site_category = match_site(title_lower, monitored_sites)
                                        if site_name:
                                            app_name = site_name
                                            category = site_category
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
                    idle_registered = False
            except Exception as e:
                print(f"Erro geral: {e}")
            time.sleep(30)
    finally:
        # Mutex liberado automaticamente pelo kernel. Nada para limpar.
        pass

if __name__ == "__main__":
    tracker_loop()
