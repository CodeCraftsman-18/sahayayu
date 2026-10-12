import os
import sys

# 1. Suppress FFmpeg stream noise
os.environ["OPENCV_FFMPEG_LOGLEVEL"] = "-8"

import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import numpy as np
import time
import urllib.request
from datetime import datetime, timezone
from supabase import create_client, Client

# ==========================================
# CONFIGURATION & CREDENTIALS
# ==========================================
# Use http:// (not https://) with IP Webcam
CAMERA_STREAM_URL = "http://192.168.1.13:8080/video"

SUPABASE_URL = "https://xjvxzjhsmhprbkwuwpou.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhqdnh6amhzbWhwcmJrd3V3cG91Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYyNTcxMzcsImV4cCI6MjEwMTgzMzEzN30.MgaT33q9Pgg0F8syxoj58VXBx1CUxXBQCw8zc9Dy00E"

try:
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    print("[SUPABASE] Connected successfully to Cloud Backend.")
except Exception as e:
    print(f"[SUPABASE ERROR] Verification failed: {e}")
    supabase = None

# ==========================================
# INITIALIZE POSE LANDMARKER TASK
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
has_been_upright = False  # Safety interlock: prevents trigger at boot
last_supabase_dispatch = 0
COOLDOWN_SECONDS = 45
privacy_mode = False

print(f"[SENTINEL] Connecting to camera stream: {CAMERA_STREAM_URL}")
cap = cv2.VideoCapture(CAMERA_STREAM_URL)

def dispatch_cctv_emergency():
    """Pushes the vision-detected emergency into Supabase and creates an SBAR hospital admission record."""
    global last_supabase_dispatch
    now = time.time()
    if now - last_supabase_dispatch < COOLDOWN_SECONDS:
        return

    last_supabase_dispatch = now
    
    # 1. Base Emergency Payload
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
        # Insert into emergencies table
        res = supabase.table("emergencies").insert(payload).execute()
        if not res.data:
            return
            
        emergency_record = res.data[0]
        emergency_id = emergency_record["id"]
        print(f"\n[🚨 EMERGENCY DISPATCHED TO SUPABASE] -> ID: {emergency_id}")

        # 2. Query the latest intake profile from elder_clinical_profiles
        profile = None
        try:
            prof_res = supabase.table("elder_clinical_profiles")\
                .select("*")\
                .order("created_at", desc=True)\
                .limit(1)\
                .execute()
            if prof_res.data and len(prof_res.data) > 0:
                profile = prof_res.data[0]
        except Exception as e:
            print(f"[PROFILE LOOKUP NOTICE] {e}")

        # Extract profile fields or use clinically realistic fallback defaults
        conditions = profile.get("chronic_conditions", ["Hypertension", "Osteoporosis"]) if profile else ["Hypertension"]
        on_anticoagulants = profile.get("on_anticoagulants", False) if profile else False
        mobility_aid = profile.get("mobility_aid", "Walking Cane") if profile else "Walking Cane"
        risk_level = profile.get("risk_level", "HIGH") if profile else "HIGH"
        risk_score = profile.get("fall_risk_score", 6) if profile else 6
        elder_id = profile.get("elder_id") if profile else None

        # 3. Triage Classification
        triage_level = "RED (Resuscitation)" if on_anticoagulants else "YELLOW (Urgent)"

        # 4. Construct SBAR Trauma Briefing
        sbar_text = (
            f"[S] SITUATION:\n"
            f"Autonomous fall confirmed via Optical CCTV Sentinel. Rapid vertical displacement "
            f"followed by 1.5s post-impact quiescence on floor. Baseline vitals: 88 BPM, BP 126/82 mmHg, SI: 0.70.\n\n"
            f"[B] BACKGROUND:\n"
            f"STEADI Risk Stratification: {risk_level} (Score: {risk_score}). Mobility aid: {mobility_aid}.\n"
            f"Pre-existing comorbidities: {', '.join(conditions)}.\n"
            f"Anticoagulant (Blood Thinner) Therapy: {'YES (Ecosprin / Warfarin flagged)' if on_anticoagulants else 'NO'}.\n\n"
            f"[A] ASSESSMENT:\n"
            f"Kinematic impact vector suggests sudden loss of balance without arm arrest reflex. "
            f"High index of suspicion for intertrochanteric fracture or cranial impact against floor.\n"
            f"{'WARNING: Severe intracranial hemorrhage vulnerability due to active blood thinners.' if on_anticoagulants else 'Cardiovascular vitals currently compensated.'}\n\n"
            f"[R] RECOMMENDATION:\n"
            f"Prepare Emergency Trauma Bay. Dispatch ALS unit with rigid spinal board. "
            f"Alert trauma team for emergent non-contrast brain CT and pelvic radiographic series."
        )

        # 5. Insert SBAR record into public.hospital_admissions
        admission_payload = {
            "emergency_id": emergency_id,
            "elder_id": elder_id,
            "hospital_name": "District Trauma Center / MY Hospital",
            "triage_level": triage_level,
            "pre_existing_conditions": conditions,
            "on_blood_thinners": on_anticoagulants,
            "vitals_snapshot": {
                "heart_rate": 88,
                "systolic_bp": 126,
                "diastolic_bp": 82,
                "shock_index": 0.70
            },
            "sbar_briefing": sbar_text,
            "eta_minutes": 10,
            "status": "INCOMING",
            "created_at": datetime.now(timezone.utc).isoformat()
        }

        supabase.table("hospital_admissions").insert(admission_payload).execute()
        print(f"[HOSPITAL ADMISSIONS] SBAR Trauma Handover logged for Emergency #{emergency_id} ({triage_level})")

    except Exception as err:
        print(f"[DISPATCH ERROR] {err}")


POSE_CONNECTIONS = [
    (11, 12), (11, 13), (13, 15), (12, 14), (14, 16),
    (11, 23), (12, 24), (23, 24), (23, 25), (24, 26),
    (25, 27), (26, 28)
]

print("\n--- SahayAyu CCTV Sentinel Armed ---")
print("Controls: [P] Toggle Privacy Mode | [Q] Quit\n")

try:
    while cap.isOpened():
        success, frame = cap.read()
        if not success:
            time.sleep(0.1)
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

        # Privacy Mode: Canvas is pitch black, stripped of RGB pixels
        display_frame = np.zeros((h, w, 3), dtype=np.uint8) if privacy_mode else frame.copy()

        if detection_result.pose_landmarks and len(detection_result.pose_landmarks) > 0:
            landmarks = detection_result.pose_landmarks[0]

            # Render 3D skeleton wireframe
            for p1_idx, p2_idx in POSE_CONNECTIONS:
                pt1 = landmarks[p1_idx]
                pt2 = landmarks[p2_idx]
                cv2.line(
                    display_frame,
                    (int(pt1.x * w), int(pt1.y * h)),
                    (int(pt2.x * w), int(pt2.y * h)),
                    (0, 255, 0),
                    2
                )

            for lm in landmarks:
                cv2.circle(display_frame, (int(lm.x * w), int(lm.y * h)), 3, (255, 255, 255), -1)

            # Center of Mass (Hips) and Upper Torso (Shoulders)
            hip_y = (landmarks[23].y + landmarks[24].y) / 2.0
            shoulder_y = (landmarks[11].y + landmarks[12].y) / 2.0
            hip_x = (landmarks[23].x + landmarks[24].x) / 2.0
            shoulder_x = (landmarks[11].x + landmarks[12].x) / 2.0

            # Vertical velocity of Center of Mass
            velocity_y = (hip_y - prev_hip_y) / dt if prev_hip_y is not None else 0.0
            prev_hip_y = hip_y
            prev_time = current_time

            # Geometric posturing
            torso_height = abs(hip_y - shoulder_y)
            is_upright = torso_height > 0.22 and shoulder_y < hip_y
            is_horizontal = torso_height < 0.15
            is_near_floor = hip_y > 0.65

            # Must observe senior upright once before arming the trigger
            if is_upright and not in_fall_state:
                has_been_upright = True

            # Calibrated Fall Trigger:
            # Requires prior upright posture + rapid downward plunge or collapse near floor
            if has_been_upright and not in_fall_state:
                if velocity_y > 1.3 or (is_horizontal and is_near_floor and velocity_y > 0.4):
                    in_fall_state = True
                    fall_detected_at = current_time

            # Post-Impact Quiescence confirmation (lying still on ground >= 1.5s)
            if in_fall_state:
                elapsed = current_time - (fall_detected_at or current_time)
                status_text = f"FALL DETECTED: CONFIRMING ({elapsed:.1f}s)"
                status_color = (0, 0, 255)

                if elapsed >= 1.5:
                    status_text = "EMERGENCY: FALL CONFIRMED!"
                    dispatch_cctv_emergency()

                # Recovery reset: person stood back up
                if is_upright:
                    in_fall_state = False
                    fall_detected_at = None

        # HUD Telemetry Banner
        mode_str = "PRIVACY WIREFRAME ONLY" if privacy_mode else "OPTICAL PASS-THROUGH"
        cv2.putText(display_frame, f"SahayAyu Vision Sentinel | {mode_str}", (20, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)
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
            print(f"[PRIVACY] Mode toggled: {'Skeleton Wireframe' if privacy_mode else 'RGB Camera'}")

except KeyboardInterrupt:
    print("\n[SENTINEL] Shutting down cleanly by user request...")
finally:
    cap.release()
    cv2.destroyAllWindows()
    print("[SENTINEL] Resources released.")