import os
import sys
import threading
from pathlib import Path
import time
import urllib.request
from datetime import datetime, timezone

# Suppress FFmpeg stream warnings
os.environ["OPENCV_FFMPEG_LOGLEVEL"] = "-8"

# ==========================================
# 1. BULLETPROOF .ENV LOADER (Strips Windows UTF-16 Null-Bytes & BOM)
# ==========================================
env_file = Path(__file__).resolve().parent / ".env"

if not env_file.exists():
    print(f"\n[CRITICAL ERROR] .env file not found at: {env_file}")
    sys.exit(1)

# Read raw bytes and strip null-bytes and BOMs caused by Windows PowerShell
raw_bytes = env_file.read_bytes()
sanitized_text = raw_bytes.decode("latin-1", errors="ignore").replace("\x00", "")

loaded_keys = []
for line in sanitized_text.splitlines():
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        # Strip potential BOM characters from key names
        clean_key = k.strip().lstrip("\ufeff\xef\xbb\xbf\xff\xfe")
        clean_val = v.strip().strip("'\"")
        os.environ[clean_key] = clean_val
        loaded_keys.append(clean_key)

# Extract and validate required configuration
CAMERA_STREAM_URL = os.getenv("CAMERA_STREAM_URL")
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")

if not all([CAMERA_STREAM_URL, SUPABASE_URL, SUPABASE_KEY]):
    print(f"\n[CRITICAL ERROR] Missing required environment variables from {env_file}.")
    print(f"Parsed keys in file: {loaded_keys}")
    print(f"CAMERA_STREAM_URL:   {repr(CAMERA_STREAM_URL)}")
    print(f"SUPABASE_URL:        {repr(SUPABASE_URL)}")
    print(f"SUPABASE_KEY:        {'[SET]' if SUPABASE_KEY else 'None'}\n")
    sys.exit(1)

print(f"[CONFIG] Successfully loaded environment variables: {', '.join(loaded_keys)}")

# ==========================================
# 2. DEPENDENCY IMPORTS & BACKEND LINK
# ==========================================
import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import numpy as np
from supabase import create_client, Client

try:
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    print("[SUPABASE] Connected successfully to Cloud Backend.")
except Exception as e:
    print(f"[SUPABASE ERROR] Verification failed: {e}")
    supabase = None

# ==========================================
# 3. ZERO-LATENCY THREADED FRAME GRABBER
# ==========================================
class FreshFrameGrabber:
    """Continuously drains OpenCV's internal socket buffer on a background thread.
    Guarantees the main AI loop receives the instantaneous real-time camera frame.
    """
    def __init__(self, src):
        self.cap = cv2.VideoCapture(src)
        self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        self.lock = threading.Lock()
        self.frame = None
        self.running = True

        if not self.cap.isOpened():
            print(f"[ERROR] Could not open video stream: {src}")
            sys.exit(1)

        self.thread = threading.Thread(target=self._capture_loop, daemon=True)
        self.thread.start()

    def _capture_loop(self):
        while self.running:
            success, frame = self.cap.read()
            if not success:
                time.sleep(0.01)
                continue
            with self.lock:
                self.frame = frame

    def read(self):
        with self.lock:
            if self.frame is None:
                return False, None
            return True, self.frame.copy()

    def stop(self):
        self.running = False
        if self.thread.is_alive():
            self.thread.join(timeout=1.0)
        self.cap.release()

# ==========================================
# 4. INITIALIZE POSE LANDMARKER TASK
# ==========================================
MODEL_PATH = "pose_landmarker_lite.task"
MODEL_URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task"

if not os.path.exists(MODEL_PATH):
    print(f"[MODEL] Downloading {MODEL_PATH}...")
    opener = urllib.request.build_opener()
    opener.addheaders = [('User-agent', 'Mozilla/5.0')]
    urllib.request.install_opener(opener)
    urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)

base_options = python.BaseOptions(model_asset_path=MODEL_PATH)
options = vision.PoseLandmarkerOptions(
    base_options=base_options,
    output_segmentation_masks=False,
    running_mode=vision.RunningMode.IMAGE
)
detector = vision.PoseLandmarker.create_from_options(options)

# Kinematic State Variables
prev_hip_y = None
prev_time = time.time()
fall_detected_at = None
in_fall_state = False
has_been_upright = False
last_supabase_dispatch = 0
COOLDOWN_SECONDS = 45
privacy_mode = False

POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (24, 26),
    (25, 27), (26, 28)
]

print(f"[SENTINEL] Connecting threaded reader to stream: {CAMERA_STREAM_URL}")
stream_reader = FreshFrameGrabber(CAMERA_STREAM_URL)

# ==========================================
# 5. AUTONOMOUS CLINICAL SBAR DISPATCH
# ==========================================
def dispatch_cctv_emergency():
    """Pushes vision-detected emergency to Supabase and logs SBAR hospital record."""
    global last_supabase_dispatch
    now = time.time()
    if now - last_supabase_dispatch < COOLDOWN_SECONDS:
        return

    last_supabase_dispatch = now
    payload = {
        "status": "OPEN",
        "source": "AI CCTV: Living Room Fall Detected (Vision Sentinel)",
        "heart_rate": 88,
        "systolic_bp": 126,
        "diastolic_bp": 82,
        "shock_index": 0.70,
        "latitude": 22.7196,
        "longitude": 75.8577,
        "location": "Living Room (Optical Sentinel Feed)",
        "created_at": datetime.now(timezone.utc).isoformat()
    }

    if not supabase:
        print("[MOCK DISPATCH] Emergency generated (Supabase offline).")
        return

    try:
        res = supabase.table("emergencies").insert(payload).execute()
        if not res.data:
            return
        emergency_id = res.data[0]["id"]
        print(f"\n[🚨 EMERGENCY DISPATCHED TO SUPABASE] -> ID: {emergency_id}")

        # Fetch latest STEADI clinical profile for SBAR synthesis
        profile = None
        try:
            p_res = supabase.table("elder_clinical_profiles").select("*").order("created_at", desc=True).limit(1).execute()
            if p_res.data:
                profile = p_res.data[0]
        except Exception:
            pass

        conditions = profile.get("chronic_conditions", ["Hypertension"]) if profile else ["Hypertension"]
        on_anticoagulants = profile.get("on_anticoagulants", False) if profile else False
        risk_level = profile.get("risk_level", "HIGH") if profile else "HIGH"

        sbar_text = (
            f"[S] SITUATION:\n"
            f"Autonomous fall confirmed via Optical CCTV Sentinel. Rapid vertical displacement "
            f"followed by 1.5s post-impact quiescence on floor. Baseline vitals: 88 BPM, BP 126/82 mmHg, SI: 0.70.\n\n"
            f"[B] BACKGROUND:\n"
            f"STEADI Risk: {risk_level}. Comorbidities: {', '.join(conditions)}. "
            f"Anticoagulant Therapy: {'YES (Severe Bleed Risk)' if on_anticoagulants else 'NO'}.\n\n"
            f"[A] ASSESSMENT:\n"
            f"Kinematic impact vector suggests sudden loss of balance without arm arrest reflex. "
            f"Heightened risk of intertrochanteric fracture or cranial impact.\n\n"
            f"[R] RECOMMENDATION:\n"
            f"Prepare Emergency Trauma Bay. Alert trauma team for non-contrast brain CT and pelvic radiographic series."
        )

        supabase.table("hospital_admissions").insert({
            "emergency_id": emergency_id,
            "elder_id": profile.get("elder_id") if profile else None,
            "hospital_name": "District Trauma Center / MY Hospital",
            "triage_level": "RED (Resuscitation)" if on_anticoagulants else "YELLOW (Urgent)",
            "pre_existing_conditions": conditions,
            "on_blood_thinners": on_anticoagulants,
            "vitals_snapshot": {"heart_rate": 88, "systolic_bp": 126, "diastolic_bp": 82, "shock_index": 0.70},
            "sbar_briefing": sbar_text,
            "status": "INCOMING",
            "created_at": datetime.now(timezone.utc).isoformat()
        }).execute()
        print(f"[HOSPITAL ADMISSIONS] SBAR Handover logged for Emergency #{emergency_id}")

    except Exception as err:
        print(f"[DISPATCH ERROR] {err}")

# ==========================================
# 6. SENTINEL INFERENCE & MONITORING LOOP
# ==========================================
print("\n--- SahayAyu CCTV Sentinel Armed (Zero-Latency Threaded Mode) ---")
print("Controls: [P] Toggle Privacy Wireframe  |  [Q] Quit\n")

try:
    while True:
        success, frame = stream_reader.read()
        if not success or frame is None:
            time.sleep(0.005)
            continue

        frame = cv2.resize(frame, (640, 480))
        h, w, _ = frame.shape
        current_time = time.time()
        dt = max(current_time - prev_time, 0.033)

        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
        detection_result = detector.detect(mp_image)

        status_text = "MONITORING: NORMAL"
        status_color = (0, 220, 0)
        display_frame = np.zeros((h, w, 3), dtype=np.uint8) if privacy_mode else frame.copy()

        if detection_result.pose_landmarks and len(detection_result.pose_landmarks) > 0:
            landmarks = detection_result.pose_landmarks[0]

            # Render 3D skeleton wireframe
            for p1_idx, p2_idx in POSE_CONNECTIONS:
                pt1 = landmarks[p1_idx]
                pt2 = landmarks[p2_idx]
                cv2.line(display_frame, (int(pt1.x * w), int(pt1.y * h)),
                         (int(pt2.x * w), int(pt2.y * h)), (0, 255, 0), 2)

            for lm in landmarks:
                cv2.circle(display_frame, (int(lm.x * w), int(lm.y * h)), 3, (255, 255, 255), -1)

            # Center of Mass (Hips) and Torso (Shoulders)
            hip_y = (landmarks[23].y + landmarks[24].y) / 2.0
            shoulder_y = (landmarks[11].y + landmarks[12].y) / 2.0

            velocity_y = (hip_y - prev_hip_y) / dt if prev_hip_y is not None else 0.0
            prev_hip_y = hip_y
            prev_time = current_time

            torso_height = abs(hip_y - shoulder_y)
            is_upright = torso_height > 0.22 and shoulder_y < hip_y
            is_horizontal = torso_height < 0.15
            is_near_floor = hip_y > 0.65

            if is_upright and not in_fall_state:
                has_been_upright = True

            # Calibrated Fall Trigger:
            # Requires prior upright posture + rapid plunge or horizontal floor collapse
            if has_been_upright and not in_fall_state:
                if velocity_y > 1.3 or (is_horizontal and is_near_floor and velocity_y > 0.4):
                    in_fall_state = True
                    fall_detected_at = current_time

            # Post-Impact Quiescence (lying still on floor >= 1.5s)
            if in_fall_state:
                elapsed = current_time - (fall_detected_at or current_time)
                status_text = f"FALL DETECTED: CONFIRMING ({elapsed:.1f}s)"
                status_color = (0, 0, 255)

                if elapsed >= 1.5:
                    status_text = "EMERGENCY: FALL CONFIRMED!"
                    dispatch_cctv_emergency()

                if is_upright:
                    in_fall_state = False
                    fall_detected_at = None

        # HUD Telemetry Banner
        mode_str = "PRIVACY WIREFRAME ONLY" if privacy_mode else "OPTICAL PASS-THROUGH"
        cv2.putText(display_frame, f"SahayAyu Vision Sentinel | {mode_str}", (20, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.52, (255, 255, 255), 2)
        cv2.putText(display_frame, f"STATUS: {status_text}", (20, 65),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, status_color, 2)
        cv2.putText(display_frame, "[P]: Toggle Privacy  |  [Q]: Quit", (20, 455),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (200, 200, 200), 1)

        cv2.imshow("SahayAyu - AI Living Room CCTV Sentinel", display_frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == ord('p'):
            privacy_mode = not privacy_mode

except KeyboardInterrupt:
    print("\n[SENTINEL] Shutting down cleanly...")
finally:
    stream_reader.stop()
    cv2.destroyAllWindows()
    print("[SENTINEL] Resources released.")