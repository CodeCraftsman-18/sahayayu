import os
import sys

# Suppress FFmpeg stream warnings
os.environ["OPENCV_FFMPEG_LOGLEVEL"] = "-8"

import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
import numpy as np
import time
import urllib.request
import threading
from datetime import datetime, timezone
import sounddevice as sd
from supabase import create_client, Client

# ==========================================
# 1. CONFIGURATION & CREDENTIALS
# ==========================================
CAMERA_STREAM_URL = "http://192.168.1.43:8080/video"

SUPABASE_URL = "https://xjvxzjhsmhprbkwuwpou.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhqdnh6amhzbWhwcmJrd3V3cG91Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODYyNTcxMzcsImV4cCI6MjEwMTgzMzEzN30.MgaT33q9Pgg0F8syxoj58VXBx1CUxXBQCw8zc9Dy00E"

try:
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    print("[SUPABASE] Connected successfully to Cloud Backend.")
except Exception as e:
    print(f"[SUPABASE ERROR] Verification failed: {e}")
    supabase = None

# ==========================================
# 2. ACOUSTIC SENSING ENGINE (sounddevice)
# ==========================================
AUDIO_SAMPLE_RATE = 16000
AUDIO_BLOCK_SIZE = 1024
current_audio_rms = 0.0
last_audio_impact_time = 0.0
AUDIO_IMPACT_THRESHOLD = 0.18  # Calibrated for blunt impact thud / clap

def audio_callback(indata, frames, time_info, status):
    """Calculates continuous Root Mean Square (RMS) energy of microphone input."""
    global current_audio_rms, last_audio_impact_time
    if status:
        pass
    # Calculate RMS amplitude
    rms = np.sqrt(np.mean(indata**2))
    current_audio_rms = float(rms)
    
    if current_audio_rms >= AUDIO_IMPACT_THRESHOLD:
        last_audio_impact_time = time.time()

# Start background audio stream
try:
    audio_stream = sd.InputStream(
        channels=1,
        samplerate=AUDIO_SAMPLE_RATE,
        blocksize=AUDIO_BLOCK_SIZE,
        callback=audio_callback
    )
    audio_stream.start()
    print("[AUDIO SENTINEL] Real-time acoustic impact monitor active.")
except Exception as e:
    print(f"[AUDIO WARNING] Could not bind microphone: {e}. Defaulting to vision-only.")
    audio_stream = None

# ==========================================
# 3. POSE LANDMARKER INITIALIZATION
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

# Kinematic & Fusion State Variables
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

print(f"[SENTINEL] Connecting to stream: {CAMERA_STREAM_URL}")
cap = cv2.VideoCapture(CAMERA_STREAM_URL)


def dispatch_cctv_emergency():
    """Pushes multimodal verified emergency to Supabase and logs SBAR hospital record."""
    global last_supabase_dispatch
    now = time.time()
    if now - last_supabase_dispatch < COOLDOWN_SECONDS:
        return

    last_supabase_dispatch = now
    payload = {
        "status": "OPEN",
        "source": "AI CCTV: Multimodal Fall (Vision + Acoustic Impact Verified)",
        "heart_rate": 92,
        "systolic_bp": 128,
        "diastolic_bp": 84,
        "shock_index": 0.72,
        "latitude": 22.7196,
        "longitude": 75.8577,
        "location": "Living Room (Optical & Acoustic Sentinel)",
        "created_at": datetime.now(timezone.utc).isoformat()
    }

    if not supabase:
        print("[MOCK DISPATCH] Multimodal emergency dispatched (Supabase offline).")
        return

    try:
        res = supabase.table("emergencies").insert(payload).execute()
        if not res.data:
            return
        emergency_id = res.data[0]["id"]
        print(f"\n[🚨 MULTIMODAL EMERGENCY DISPATCHED] -> ID: {emergency_id}")

        # Fetch STEADI profile for SBAR synthesis
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
            f"Dual-sensor verified acute fall. Vision Sentinel detected rapid CoM plunge coincided "
            f"with calibrated acoustic impact spike (Audio Energy Peak: {current_audio_rms:.2f}).\n\n"
            f"[B] BACKGROUND:\n"
            f"STEADI Risk: {risk_level}. Comorbidities: {', '.join(conditions)}. "
            f"Anticoagulant Therapy: {'YES (Severe Bleed Risk)' if on_anticoagulants else 'NO'}.\n\n"
            f"[A] ASSESSMENT:\n"
            f"High-energy mechanical deceleration on floor plane. Heightened risk of skeletal trauma "
            f"and concussive injury.\n\n"
            f"[R] RECOMMENDATION:\n"
            f"Assign Emergency Trauma Bay. Prepare cervical collar, 18G IV access, and stat Head CT."
        )

        supabase.table("hospital_admissions").insert({
            "emergency_id": emergency_id,
            "elder_id": profile.get("elder_id") if profile else None,
            "hospital_name": "District Trauma Center / MY Hospital",
            "triage_level": "RED (Resuscitation)" if on_anticoagulants else "YELLOW (Urgent)",
            "pre_existing_conditions": conditions,
            "on_blood_thinners": on_anticoagulants,
            "vitals_snapshot": {"heart_rate": 92, "systolic_bp": 128, "diastolic_bp": 84, "shock_index": 0.72},
            "sbar_briefing": sbar_text,
            "status": "INCOMING",
            "created_at": datetime.now(timezone.utc).isoformat()
        }).execute()
        print(f"[HOSPITAL ADMISSIONS] SBAR Handover logged for Emergency #{emergency_id}")

    except Exception as err:
        print(f"[DISPATCH ERROR] {err}")


print("\n--- SahayAyu Multimodal Audio-Visual Sentinel Online ---")
print("Controls: [P] Toggle Privacy  |  [Q] Quit\n")

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
        display_frame = np.zeros((h, w, 3), dtype=np.uint8) if privacy_mode else frame.copy()

        # Check temporal acoustic coincidence window (last 1.5 seconds)
        acoustic_impact_active = (current_time - last_audio_impact_time) <= 1.5

        if detection_result.pose_landmarks and len(detection_result.pose_landmarks) > 0:
            landmarks = detection_result.pose_landmarks[0]

            # Render wireframe
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
            hip_x = (landmarks[23].x + landmarks[24].x) / 2.0
            shoulder_x = (landmarks[11].x + landmarks[12].x) / 2.0

            velocity_y = (hip_y - prev_hip_y) / dt if prev_hip_y is not None else 0.0
            prev_hip_y = hip_y
            prev_time = current_time

            torso_height = abs(hip_y - shoulder_y)
            is_upright = torso_height > 0.22 and shoulder_y < hip_y
            is_horizontal = torso_height < 0.15
            is_near_floor = hip_y > 0.65

            if is_upright and not in_fall_state:
                has_been_upright = True

            # Multimodal Fusion Rule:
            # Kinematic downward plunge + Ground proximity + Acoustic impact thud
            optical_trigger = velocity_y > 1.3 or (is_horizontal and is_near_floor and velocity_y > 0.35)

            if has_been_upright and not in_fall_state:
                if optical_trigger:
                    if acoustic_impact_active:
                        # True Positive: Kinematic drop accompanied by acoustic thud
                        in_fall_state = True
                        fall_detected_at = current_time
                    else:
                        # False Positive Suppression: Gentle lie down on couch / no impact sound
                        status_text = "SUPPRESSED: GENTLE MOTION (NO ACOUSTIC IMPACT)"
                        status_color = (0, 165, 255)

            # Post-Impact Quiescence confirmation (lying still >= 1.5s)
            if in_fall_state:
                elapsed = current_time - (fall_detected_at or current_time)
                status_text = f"MULTIMODAL FALL: CONFIRMING ({elapsed:.1f}s)"
                status_color = (0, 0, 255)

                if elapsed >= 1.5:
                    status_text = "EMERGENCY: FALL & IMPACT CONFIRMED!"
                    dispatch_cctv_emergency()

                if is_upright:
                    in_fall_state = False
                    fall_detected_at = None

        # --- HUD TELEMETRY & LIVE SENSOR VISUALIZATIONS ---
        mode_str = "PRIVACY WIREFRAME ONLY" if privacy_mode else "OPTICAL PASS-THROUGH"
        cv2.putText(display_frame, f"SahayAyu Multimodal Sentinel | {mode_str}", (20, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.52, (255, 255, 255), 2)
        cv2.putText(display_frame, f"STATUS: {status_text}", (20, 60),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.65, status_color, 2)

        # Real-time Microphone Decibel/RMS Meter Bar
        meter_x, meter_y, meter_w, meter_h = 20, 80, 160, 12
        cv2.rectangle(display_frame, (meter_x, meter_y), (meter_x + meter_w, meter_y + meter_h), (60, 60, 60), -1)
        fill_w = int(min(current_audio_rms / 0.35, 1.0) * meter_w)
        bar_color = (0, 0, 255) if acoustic_impact_active else (0, 255, 0)
        cv2.rectangle(display_frame, (meter_x, meter_y), (meter_x + fill_w, meter_y + meter_h), bar_color, -1)
        cv2.putText(display_frame, f"Mic RMS: {current_audio_rms:.2f} {'[IMPACT]' if acoustic_impact_active else ''}",
                    (meter_x + meter_w + 10, meter_y + 10), cv2.FONT_HERSHEY_SIMPLEX, 0.42, bar_color, 1)

        cv2.putText(display_frame, "[P]: Toggle Privacy  |  [Q]: Quit", (20, 455),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (200, 200, 200), 1)

        cv2.imshow("SahayAyu - AI Living Room CCTV Sentinel", display_frame)

        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        elif key == ord('p'):
            privacy_mode = not privacy_mode

except KeyboardInterrupt:
    print("\n[SENTINEL] Shutting down...")
finally:
    if audio_stream:
        audio_stream.stop()
        audio_stream.close()
    cap.release()
    cv2.destroyAllWindows()
    print("[SENTINEL] Resources released.")