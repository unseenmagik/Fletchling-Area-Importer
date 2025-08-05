from datetime import datetime

LOG_FILE = "import-areas.log"
ENABLE_LOGS = False  # Set by config at runtime

def log(msg):
    timestamped = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    if ENABLE_LOGS:
        with open(LOG_FILE, "a") as f:
            f.write(timestamped + "\n")
    print(timestamped)
