# LumiSense Project Specification

Document version: 2.0  
Status: Current-state master specification  
Date: 2026-03-25

## 1. Project Definition

For non-technical readers:

LumiSense is a smartphone app that helps blind and low-vision users understand their surroundings through camera-based AI and spoken guidance. The app is designed to reduce dependency in everyday tasks like reading text, identifying objects, navigating, and sending emergency alerts.

For technical readers:

LumiSense is an Android-first Flutter system with a hybrid inference model:

1. On-device perception and model execution where practical
2. Cloud provider fallback for richer scene interpretation and resilience

The implementation root is [lib](lib), with app setup in [main.dart](lib/main.dart).

## 2. Product Intent and Positioning

## 2.1 Core intent

1. Deliver immediate, speech-first situational assistance.
2. Keep interaction low-friction with large controls and voice commands.
3. Support both offline-capable local workflows and online-enhanced workflows.

## 2.2 User profile

Primary:

1. Blind and low-vision users who need practical daily assistance.

Secondary:

1. Caregivers who monitor status and help remotely when needed.

## 2.3 Success criteria for this version

1. Core camera actions are stable and understandable by voice output.
2. Safety-critical SOS flow is reachable quickly and behaves predictably.
3. Navigation and perception features are usable on real devices with variable performance.

## 3. Current Implementation Scope

This section is the authoritative scope for what is implemented now.

## 3.1 Implemented capabilities

1. OCR read-aloud
2. Single-shot object identification
3. Scene description
4. Real-time navigation mode announcements
5. Turn-by-turn walking directions
6. Voice command mapping and action dispatch
7. QR scan and UPI handoff
8. Currency identification
9. Brightness analysis
10. Weather status narration
11. People awareness via face and pose detection
12. Emergency SOS flow with GPS-aware messaging path
13. Caregiver dashboard actions
14. History logging and replay
15. Settings for keys, speech behavior, emergency contact, and model mode

## 3.2 Partial or in-progress capabilities

1. On-device assistant action orchestration hardening
2. Voice command disambiguation in overlapping phrase cases
3. Device-level runtime tuning for heavy real-time workloads

## 3.3 Out-of-scope for current release

1. Production-grade medication management
2. Full calendar and health ecosystem integrations
3. Gamification and adaptive training curriculum
4. Dedicated external edge hardware runtime dependency

## 4. Architecture Specification

For non-technical readers:

The phone is the main runtime unit. It captures camera input, runs AI services, and speaks results.

For technical readers:

### 4.1 Runtime pipeline

```text
Camera/Sensors -> Flutter Screen and Service Layer -> Inference and Decision Layer -> TTS and UX Feedback
```

### 4.2 Inference and decision layer

1. ML Kit paths for OCR, barcode, face, pose
2. ultralytics_yolo path for real-time object detections
3. On-device LLM and VLM path via llama.cpp through llamadart
4. Cloud fallback chain for scene description and related tasks

### 4.3 Main implementation anchors

1. Camera orchestration: [screens/camera_screen.dart](lib/screens/camera_screen.dart)
2. Cloud fallback chain: [services/gemini_service.dart](lib/services/gemini_service.dart)
3. On-device model orchestration: [services/on_device_orchestrator.dart](lib/services/on_device_orchestrator.dart)
4. Model lifecycle and downloads: [services/model_manager.dart](lib/services/model_manager.dart)
5. Navigation route engine: [services/directions_service.dart](lib/services/directions_service.dart)

Detailed architecture coverage is documented in [ARCHITECTURE.md](ARCHITECTURE.md).

## 5. State, Data, and Storage

## 5.1 Runtime state

1. App mode and processing state are maintained by [providers/app_state.dart](lib/providers/app_state.dart).
2. User settings and API key state are managed by [providers/settings_provider.dart](lib/providers/settings_provider.dart).
3. User action history is managed by [providers/history_provider.dart](lib/providers/history_provider.dart).

## 5.2 Persisted data

1. Preferences and history use SharedPreferences serialization paths.
2. Sensitive keys use secure storage integration through settings provider logic.

## 5.3 Data models

1. History entries: [models/history_entry.dart](lib/models/history_entry.dart)
2. OCR results: [models/ocr_result.dart](lib/models/ocr_result.dart)
3. UPI payload parsing: [models/upi_payment_info.dart](lib/models/upi_payment_info.dart)

## 6. Platform and Dependency Specification

## 6.1 Platform targets

1. Android-first deployment target.
2. Build configuration in [android/app/build.gradle.kts](android/app/build.gradle.kts).

## 6.2 Dependency profile

Primary dependency contract is in [pubspec.yaml](pubspec.yaml), including:

1. Flutter and Provider
2. speech_to_text and flutter_tts
3. ML Kit packages
4. ultralytics_yolo
5. llamadart and dio
6. geolocator, url_launcher, open_route_service, flutter_map

## 6.3 Permission profile

Runtime permission and intent requirements are defined in [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml).

## 7. Quality and Reliability Specification

## 7.1 Reliability expectations

1. Feature handlers should fail gracefully with user-readable spoken messages.
2. Cloud requests should apply timeout and fallback controls.
3. Navigation announcements should avoid noisy repetition.
4. SOS flow should remain quickly accessible regardless of active task.

## 7.2 Current testing posture

Existing unit and smoke tests are present but limited in breadth, concentrated around:

1. History model and provider behaviors
2. STT command mapping
3. Basic history-screen widget smoke path

Broader integration coverage is still an active need.

## 8. Risk Register (Current)

1. High feature breadth with limited automated coverage can increase regression risk.
2. Real-time performance can vary widely across devices.
3. Voice command phrase overlap can still produce occasional intent ambiguity.
4. Large on-device model downloads and memory requirements can impact user setup and runtime behavior.

## 9. Roadmap Context (Separated From Current Scope)

This section preserves strategic direction without claiming it is shipped.

Potential roadmap directions:

1. Medication and health workflow support
2. Richer proactive scheduling behavior
3. Deeper caregiver collaboration tools
4. Optional future edge-device exploration

Any roadmap feature should be documented as planned until implemented and validated in code.

## 10. Source-of-Truth Rule

If this specification conflicts with runtime behavior:

1. Code in [lib](lib) is authoritative.
2. Update this file and related docs to match implementation reality.

Related documents:

1. [README.md](README.md)
2. [ARCHITECTURE.md](ARCHITECTURE.md)
3. [FEATURES.md](FEATURES.md)
4. [SETUP.md](SETUP.md)