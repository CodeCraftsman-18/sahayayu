# SahayAyu: Multi-Modal AI Elderly Care & Clinical Emergency Triage Platform

[![Flutter](https://img.shields.io/badge/Flutter-3.19+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL%20%7C%20PostGIS-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![MediaPipe](https://img.shields.io/badge/MediaPipe-Pose%20Estimation-00A67E?logo=google&logoColor=white)](https://developers.google.com/mediapipe)
[![Python](https://img.shields.io/badge/Python-3.11%20--%203.13-3776AB?logo=python&logoColor=white)](https://python.org)
[![Clinical](https://img.shields.io/badge/Clinical-CDC%20STEADI%20%7C%20SBAR-E11D48)](#clinical-intelligence--triage)

SahayAyu is an end-to-end geriatric emergency response and proactive triage platform. It couples **preventive clinical risk assessment (CDC STEADI)** and **continuous shock index monitoring** with an independent, **zero-latency ambient computer vision sentinel** that autonomously logs structured **SBAR trauma briefings** into hospital emergency department queues.

---

## System Architecture

```text
       [Elder Mobile Client]                    [Ambient Vision Sentinel]
  (Flutter / Kinematics / STEADI)             (Python / MediaPipe / Threaded)
                 │                                           │
       Adaptive Fall Triggers,                     Zero-Latency CoM Plunge,
      Pulse, BP & Shock Index                     Post-Impact Quiescence State
                 │                                           │
                 └────────────────────┬──────────────────────┘
                                      │ HTTPS / WebSocket Telemetry
                                      ▼
                           [Supabase Cloud Engine]
                 ┌───────────────────────────────────────────┐
                 │  - PostgreSQL Realtime Broadcast          │
                 │  - PostGIS ST_Distance Geolocation        │
                 │  - Autonomous SBAR Triage Generation      │
                 │  - Ranked Responders Spatial RPC          │
                 └───────┬───────────────────────────┬───────┘
                         │                           │
                         ▼                           ▼
            [Hospital Emergency Dept]     [Volunteer & Paramedic Feed]
      ┌───────────────────────────────┐ ┌──────────────────────────────────┐
      │ - Real-Time Admission Queue   │ │ - Real-Time WebSocket Alerts     │
      │ - Automated SBAR Handover     │ │ - Ranked Responders (PostGIS)    │
      │ - Anticoagulant Bleed Flags   │ │ - Native Map Navigation & Call   │
      └───────────────────────────────┘ └──────────────────────────────────┘