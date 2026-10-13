import os
import sys
import time
import subprocess
from pathlib import Path
from datetime import datetime

# Setup log directory
BASE_DIR = Path(__file__).resolve().parent
LOG_DIR = BASE_DIR / "logs"
LOG_DIR.mkdir(exist_ok=True)
LOG_FILE = LOG_DIR / "sentinel.log"

MAX_CONSECUTIVE_CRASHES = 10
CRASH_WINDOW_SECONDS = 60
BACKOFF_BASE_SECONDS = 3

def log_event(message: str):
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    entry = f"[{timestamp}] [SUPERVISOR] {message}\n"
    print(entry, end="")
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(entry)

def run_supervisor():
    log_event("=== SahayAyu Edge Sentinel Supervisor Started ===")
    sentinel_script = BASE_DIR / "cctv_sentinel.py"
    python_executable = sys.executable

    crash_history = []

    while True:
        log_event(f"Spawning Sentinel worker: {python_executable} {sentinel_script}")
        
        with open(LOG_FILE, "a", encoding="utf-8") as log_out:
            start_time = time.time()
            process = subprocess.Popen(
                [python_executable, str(sentinel_script)],
                stdout=log_out,
                stderr=subprocess.STDOUT,
                cwd=str(BASE_DIR)
            )

            # Wait for sentinel to exit (crash or intentional quit)
            exit_code = process.wait()

        uptime = time.time() - start_time
        now = time.time()

        # If user exited cleanly via key 'Q', terminate supervisor
        if exit_code == 0:
            log_event("Sentinel terminated cleanly (Exit Code 0). Shutting down supervisor.")
            break

        log_event(f"Sentinel process crashed with exit code {exit_code} (Uptime: {uptime:.1f}s).")

        # Track rapid crash cycles
        crash_history = [t for t in crash_history if now - t < CRASH_WINDOW_SECONDS]
        crash_history.append(now)

        if len(crash_history) >= MAX_CONSECUTIVE_CRASHES:
            log_event("[FATAL] Exceeded maximum restart threshold. Halting to prevent CPU throttling.")
            sys.exit(1)

        # Backoff before restarting
        backoff = min(BACKOFF_BASE_SECONDS * len(crash_history), 30)
        log_event(f"Restarting Sentinel in {backoff} seconds...")
        time.sleep(backoff)

if __name__ == "__main__":
    try:
        run_supervisor()
    except KeyboardInterrupt:
        log_event("Supervisor interrupted by operator. Exiting.")
        sys.exit(0)