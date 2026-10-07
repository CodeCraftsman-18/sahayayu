# SahayAyu: Multi-Modal AI Elderly Care & Rapid Emergency Dispatch Ecosystem

[![Flutter](https://img.shields.io/badge/Flutter-3.19+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL%20%7C%20Realtime-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
[![MediaPipe](https://img.shields.io/badge/MediaPipe-Pose%20Estimation-00A67E?logo=google&logoColor=white)](https://developers.google.com/mediapipe)
[![Python](https://img.shields.io/badge/Python-3.11%20--%203.13-3776AB?logo=python&logoColor=white)](https://python.org)
[![PostGIS](https://img.shields.io/badge/PostGIS-Spatial%20Indexing-336791?logo=postgresql&logoColor=white)](https://postgis.net)

SahayAyu is an end-to-end community health and automated emergency triage platform. Designed for vulnerable and elderly populations living independently, it couples multi-sensor mobile telemetry with privacy-preserving ambient edge computer vision to eliminate manual response delays during acute medical events.

---

## System Architecture

```text
       [Elder Mobile Client]              [Ambient Vision Sentinel]
  (Flutter / Sensors / Voice SOS)          (Python / MediaPipe Pose)
                 │                                     │
    Kinematic Impact / Distress Voice          Center of Mass Plunge /
   Continuous Pulse, BP & Shock Index          Post-Impact Quiescence
                 │                                     │
                 └──────────────────┬──────────────────┘
                                    │ HTTPS / WSS
                                    ▼
                         [Supabase Cloud Engine]
                 ┌─────────────────────────────────────┐
                 │  - PostgreSQL Realtime Broadcast    │
                 │  - PostGIS ST_Distance Geolocation  │
                 │  - Remote Incident State Machine    │
                 └──────────────────┬──────────────────┘
                                    │ WebSocket Streams
                                    ▼
                       [Volunteer Responder Feed]
                 ┌─────────────────────────────────────┐
                 │  - Real-Time Incident Ingestion     │
                 │  - Autonomous AI Paramedic Triage   │
                 │  - Ranked Responders (PostGIS)      │
                 │  - 108 Dispatch & Native Map Nav    │
                 └─────────────────────────────────────┘
