import time
import ctypes
import os
import sys
import json
import urllib.request
from supabase import create_client
from dotenv import load_dotenv

load_dotenv()

supabase   = create_client(os.getenv("SUPABASE_URL"), os.getenv("SUPABASE_KEY"))
USER_ID    = os.getenv("USER_ID")
ORG_ID     = os.getenv("ORG_ID")
USER_TOKEN = os.getenv("USER_TOKEN")
ANON_KEY   = os.getenv("SUPABASE_ANON_KEY")

EDGE_FUNCTION_URL = f"{os.getenv('SUPABASE_URL')}/functions/v1/dynamic-handler"

# -------------------------------------------------------------------
# Instancia unica via Named Mutex do Windows.
# O kernel libera automaticamente quando o processo morre.
# -------------------------------------------------------------------
_mutex = ctypes.windll.kernel32.CreateMutexW(None, True, "Global\\ArchiTrackerMutex")
if ctypes.windll.kernel32.GetLastError() == 183:  # ERROR_ALREADY_EXISTS
    print("Tracker ja esta rodando. Encerrando esta instancia.")
    sys.exit(0)

IDLE_LIMIT         = 600   # segundos sem input para considerar inativo
KEEPALIVE_INTERVAL = 300   # segundos para gravar keepalive na mesma janela

# -------------------------------------------------------------------
# Funcoes de leitura do Windows
# -------------------------------------------------------------------

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

# -------------------------------------------------------------------
# Le status de tracking via service_role key (bypassa RLS)
# Sera removido na reescrita em Electron com Realtime nativo
# -------------------------------------------------------------------

def get_tracking_status():
    try:
        res = supabase.table('tracker_control').select('tracking').eq('user_id', USER_ID).execute()
        return res.data[0]['tracking'] if res.data else False
    except:
        return False

# -------------------------------------------------------------------
# Envia dados brutos para a Edge Function
# Toda classificacao e decisao de gravar acontece no servidor
# -------------------------------------------------------------------

def call_edge_function(process, title, event_type):
    payload = json.dumps({
        'process':    process,
        'title':      title,
        'user_token': USER_TOKEN,
        'user_id':    USER_ID,
        'org_id':     ORG_ID,
        'event_type': event_type,
    }).encode('utf-8')
    try:
        req = urllib.request.Request(EDGE_FUNCTION_URL, data=payload, method='POST')
        req.add_header('Content-Type', 'application/json')
        req.add_header('Authorization', f'Bearer {ANON_KEY}')
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read())
            print(f"[{event_type}] {result.get('action', '?')} — {result.get('app', '')}")
    except Exception as e:
        print(f"Erro ao chamar Edge Function: {e}")

# -------------------------------------------------------------------
# Loop principal
# -------------------------------------------------------------------

def tracker_loop():
    SENTINEL_FILE = r"C:\tracker-arquitetura\tracker.running"

    last_title       = None
    last_recorded_at = 0
    idle_registered  = False

    print(f"Tracker iniciado para: {USER_ID}")

    with open(SENTINEL_FILE, "w") as f:
        f.write(str(os.getpid()))

    try:
        while True:
            try:
                now      = time.time()
                tracking = get_tracking_status()

                if tracking:
                    idle = get_idle_seconds()

                    if idle >= IDLE_LIMIT:
                        if last_title is not None and not idle_registered:
                            call_edge_function("", "", "idle")
                            idle_registered = True
                        last_title       = None
                        last_recorded_at = 0

                    else:
                        idle_registered = False
                        title   = get_title()
                        process = get_process()

                        if not title:
                            time.sleep(30)
                            continue

                        new_window = title != last_title
                        keepalive  = (
                            title == last_title
                            and (now - last_recorded_at) >= KEEPALIVE_INTERVAL
                        )

                        if new_window or keepalive:
                            event = 'keepalive' if keepalive else 'window_change'
                            call_edge_function(process, title, event)
                            last_title       = title
                            last_recorded_at = now

                else:
                    last_title       = None
                    last_recorded_at = 0
                    idle_registered  = False

            except Exception as e:
                print(f"Erro geral: {e}")

            time.sleep(30)

    finally:
        if os.path.exists(SENTINEL_FILE):
            os.remove(SENTINEL_FILE)

if __name__ == "__main__":
    tracker_loop()
