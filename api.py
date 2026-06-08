import time
import ctypes
import os
import sys
import json
import threading
import urllib.request
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()

SUPABASE_URL  = os.getenv("SUPABASE_URL")
SUPABASE_ANON = os.getenv("SUPABASE_ANON_KEY")
USER_TOKEN    = os.getenv("USER_TOKEN")
USER_ID       = os.getenv("USER_ID")
ORG_ID        = os.getenv("ORG_ID")

EDGE_FUNCTION_URL = f"{SUPABASE_URL}/functions/v1/dynamic-handler"

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
FALLBACK_INTERVAL  = 300   # segundos entre polls de fallback se realtime cair

# Usado apenas para suprimir registros redundantes de troca de aba
BROWSER_KEYS = {'chrome', 'firefox', 'edge', 'opera', 'brave', 'arc', 'vivaldi'}

# -------------------------------------------------------------------
# Estado compartilhado entre threads
# -------------------------------------------------------------------
_tracking_lock = threading.Lock()
_tracking      = False          # status atual de play/pause
_realtime_ok   = False          # indica se a conexao realtime esta ativa
_last_poll     = 0.0            # timestamp do ultimo poll de fallback

def get_tracking():
    with _tracking_lock:
        return _tracking

def set_tracking(value):
    with _tracking_lock:
        global _tracking
        _tracking = value

def get_realtime_ok():
    with _tracking_lock:
        return _realtime_ok

def set_realtime_ok(value):
    with _tracking_lock:
        global _realtime_ok
        _realtime_ok = value

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
# Fallback poll — usado quando o Realtime esta fora
# Le o tracker_control diretamente via REST com a anon key
# -------------------------------------------------------------------

def poll_tracking_status():
    try:
        url = f"{SUPABASE_URL}/rest/v1/tracker_control?user_id=eq.{USER_ID}&select=tracking"
        req = urllib.request.Request(url)
        req.add_header('apikey', SUPABASE_ANON)
        req.add_header('Authorization', f'Bearer {SUPABASE_ANON}')
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
            if data:
                set_tracking(data[0]['tracking'])
                print(f"[fallback poll] tracking = {data[0]['tracking']}")
    except Exception as e:
        print(f"[fallback poll] erro: {e}")

# -------------------------------------------------------------------
# Thread do Realtime — escuta mudancas no tracker_control
# Se a conexao cair, marca realtime_ok = False e o loop principal
# faz fallback para poll a cada FALLBACK_INTERVAL segundos
# -------------------------------------------------------------------

def realtime_thread():
    try:
        supabase = create_client(SUPABASE_URL, SUPABASE_ANON)

        def on_change(payload):
            new_tracking = payload.get('new', {}).get('tracking')
            if new_tracking is not None:
                set_tracking(new_tracking)
                print(f"[realtime] tracking = {new_tracking}")

        def on_subscribe(status, err=None):
            if status == 'SUBSCRIBED':
                set_realtime_ok(True)
                print("[realtime] conectado")
            else:
                set_realtime_ok(False)
                print(f"[realtime] status: {status}")

        channel = (
            supabase.channel('tracker-control')
            .on(
                'postgres_changes',
                event='UPDATE',
                schema='public',
                table='tracker_control',
                filter=f'user_id=eq.{USER_ID}',
                callback=on_change
            )
            .subscribe(on_subscribe)
        )

        # Carrega estado inicial antes de comecar a escutar
        poll_tracking_status()

        # Mantem a thread viva
        while True:
            time.sleep(60)

    except Exception as e:
        print(f"[realtime] erro fatal: {e}")
        set_realtime_ok(False)

# -------------------------------------------------------------------
# Envio para a Edge Function
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
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read())
            print(f"[{event_type}] {result.get('action', '?')} — {result.get('app', '')}")
    except Exception as e:
        print(f"Erro ao chamar Edge Function: {e}")

# -------------------------------------------------------------------
# Loop principal
# -------------------------------------------------------------------

def tracker_loop():
    global _last_poll
    SENTINEL_FILE = r"C:\tracker-arquitetura\tracker.running"

    last_title       = None
    last_recorded_at = 0
    idle_registered  = False
    last_was_browser = False

    print(f"Tracker iniciado para: {USER_ID}")

    # Inicia thread do Realtime em background
    t = threading.Thread(target=realtime_thread, daemon=True)
    t.start()

    with open(SENTINEL_FILE, "w") as f:
        f.write(str(os.getpid()))

    try:
        while True:
            try:
                now = time.time()

                # Fallback: se realtime caiu, faz poll a cada FALLBACK_INTERVAL
                if not get_realtime_ok() and (now - _last_poll) >= FALLBACK_INTERVAL:
                    poll_tracking_status()
                    _last_poll = now

                tracking = get_tracking()

                if tracking:
                    idle = get_idle_seconds()

                    if idle >= IDLE_LIMIT:
                        if last_title is not None and not idle_registered:
                            call_edge_function("", "", "idle")
                            idle_registered = True
                        last_title       = None
                        last_recorded_at = 0
                        last_was_browser = False

                    else:
                        idle_registered = False
                        title   = get_title()
                        process = get_process()

                        if not title:
                            time.sleep(30)
                            continue

                        current_is_browser = any(bk in process for bk in BROWSER_KEYS)
                        new_window = title != last_title
                        keepalive  = (
                            title == last_title
                            and (now - last_recorded_at) >= KEEPALIVE_INTERVAL
                        )

                        if new_window or keepalive:
                            # Suprime troca de aba entre sites nao monitorados
                            if new_window and current_is_browser and last_was_browser:
                                last_title = title
                                time.sleep(30)
                                continue

                            event = 'keepalive' if keepalive else 'window_change'
                            call_edge_function(process, title, event)
                            last_title       = title
                            last_recorded_at = now
                            last_was_browser = current_is_browser

                else:
                    last_title       = None
                    last_recorded_at = 0
                    idle_registered  = False
                    last_was_browser = False

            except Exception as e:
                print(f"Erro geral: {e}")

            time.sleep(30)

    finally:
        if os.path.exists(SENTINEL_FILE):
            os.remove(SENTINEL_FILE)

if __name__ == "__main__":
    tracker_loop()
