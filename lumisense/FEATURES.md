# LumiSense Features

## How to Read This Document

This file is intentionally written for two audiences.

For non-technical readers:

- Each feature starts with what it does and why it matters.

For technical readers:

- The same feature then maps to concrete screens and service paths in code.

## Feature Status Matrix

## Implemented and actively usable

1. OCR text reading
2. Object identification
3. Scene description
4. Real-time navigation mode announcements
5. Turn-by-turn walking directions
6. Voice command routing
7. QR scanning and UPI launch
8. Currency identification
9. Brightness check
10. Weather check
11. People detection (face and pose)
12. SOS emergency flow
13. History logging and replay
14. Settings and key management
15. Caregiver dashboard support actions

## Partial or still being refined

1. On-device assistant action orchestration
2. Contact voice-calling reliability for ambiguous names
3. Real-time walking behavior tuning across devices

## Planned but not implemented as product-ready features

1. Medication management workflows
2. Gamification and training programs
3. Calendar and fitness integrations
4. Broader predictive proactive routines

## Core Camera Features

## 1. Read Text (OCR)

What users get:

- Point to text, tap Read, hear spoken output.

Why it exists:

- Fast access to labels, signs, notes, and packaging.

Technical implementation:

- Trigger path: [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- OCR engine: [lib/services/ocr_service.dart](lib/services/ocr_service.dart)
- Result model: [lib/models/ocr_result.dart](lib/models/ocr_result.dart)
- Speech output: [lib/services/tts_service.dart](lib/services/tts_service.dart)
- History persistence: [lib/providers/history_provider.dart](lib/providers/history_provider.dart)

Behavior notes:

- Reading order is sorted for practical narration.
- Power-read chunking is available from settings.

## 2. Identify Objects

What users get:

- Quick spoken object labels from camera view.

Why it exists:

- Situational awareness for nearby objects.

Technical implementation:

- Camera and detection routing: [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- Real-time plugin path: ultralytics_yolo integration in [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- Overlay rendering: [lib/widgets/bounding_box_overlay.dart](lib/widgets/bounding_box_overlay.dart)

Behavior notes:

- Single-shot identify action uses the latest available detections with confidence filtering.

## 3. Describe Scene

What users get:

- A concise spoken summary of the scene in front of them.

Why it exists:

- Gives context beyond raw object names.

Technical implementation:

- Orchestration path: [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- Cloud provider chain: [lib/services/gemini_service.dart](lib/services/gemini_service.dart)
- On-device route: [lib/services/on_device_orchestrator.dart](lib/services/on_device_orchestrator.dart)

Behavior notes:

- Cooldown is applied to prevent excessive repeated requests.
- Falls back across providers when configured.

## 4. Real-Time Navigation Mode

What users get:

- Continuous spoken awareness while moving, including object presence and relative positioning.

Why it exists:

- Reduces repeated manual requests while walking.

Technical implementation:

- Navigation trigger and lifecycle: [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- Announcement policy and persistence logic: [lib/services/navigation_mode_controller.dart](lib/services/navigation_mode_controller.dart)
- Overlay: [lib/widgets/bounding_box_overlay.dart](lib/widgets/bounding_box_overlay.dart)

Behavior notes:

- Persistence threshold avoids announcing unstable detections.
- Cooldowns and summaries reduce cognitive overload.

## Mobility and Route Features

## 5. Turn-by-Turn Walking Directions

What users get:

- Spoken walking instructions, repeat/status controls, and optional route map view.

Why it exists:

- Enables destination guidance within the same interaction model as camera features.

Technical implementation:

- Core engine: [lib/services/directions_service.dart](lib/services/directions_service.dart)
- Panel controls: [lib/widgets/directions_panel.dart](lib/widgets/directions_panel.dart)
- Map screen: [lib/screens/route_map_screen.dart](lib/screens/route_map_screen.dart)

Behavior notes:

- Includes reroute logic and step progression tracking.

## Voice and Accessibility Features

## 6. Voice Commands

What users get:

- Speak commands instead of tapping controls.

Why it exists:

- Faster hands-free operation for frequent actions.

Technical implementation:

- Command mapping and extraction: [lib/services/stt_service.dart](lib/services/stt_service.dart)
- Command dispatch and action execution: [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)

Behavior notes:

- Supports task commands plus navigation-status commands.
- Phrase precedence is good but still under refinement for edge phrasing.

## 7. Spoken Feedback and Chunked Narration

What users get:

- Consistent voice output for results, status, and guidance.

Why it exists:

- Voice output is the primary user feedback path.

Technical implementation:

- Speech singleton, queue controls, urgent speech, and cancellation hooks: [lib/services/tts_service.dart](lib/services/tts_service.dart)
- Power-read setting integration: [lib/providers/settings_provider.dart](lib/providers/settings_provider.dart)

## Utility and Daily-Living Features

## 8. QR Payment Scan and UPI Launch

What users get:

- Scan payment QR and open compatible payment app.

Why it exists:

- Supports independent digital transaction flow with spoken verification.

Technical implementation:

- QR parse service: [lib/services/qr_scanner_service.dart](lib/services/qr_scanner_service.dart)
- UPI model parse: [lib/models/upi_payment_info.dart](lib/models/upi_payment_info.dart)
- Launch integration: [lib/services/upi_payment_service.dart](lib/services/upi_payment_service.dart)

## 9. Currency Identification

What users get:

- Spoken denomination result from camera image.

Why it exists:

- Fast confidence check for cash handling.

Technical implementation:

- Cloud route: [lib/services/currency_detector_service.dart](lib/services/currency_detector_service.dart)
- On-device route support through orchestrator path in [lib/services/on_device_orchestrator.dart](lib/services/on_device_orchestrator.dart)

## 10. Brightness Check

What users get:

- Spoken estimate of scene brightness and practical context.

Why it exists:

- Helps determine lighting conditions for safer movement and better camera usage.

Technical implementation:

- Brightness analysis service: [lib/services/brightness_detector_service.dart](lib/services/brightness_detector_service.dart)

## 11. Weather Check

What users get:

- Spoken current weather and safety-relevant weather context.

Why it exists:

- Helps with route and outing decisions.

Technical implementation:

- Service path: [lib/services/weather_service.dart](lib/services/weather_service.dart)
- Trigger path: [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)

## 12. People Detection

What users get:

- Spoken awareness of faces and posture cues.

Why it exists:

- Improves social and nearby-presence awareness.

Technical implementation:

- Face path: [lib/services/face_detection_service.dart](lib/services/face_detection_service.dart)
- Pose path: [lib/services/pose_detection_service.dart](lib/services/pose_detection_service.dart)
- Combined action handling in [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)

## Safety and Care Features

## 13. SOS Emergency Flow

What users get:

- Rapid emergency flow with location-aware messaging and fallback behavior.

Why it exists:

- Safety-critical assistance path when immediate help is needed.

Technical implementation:

- Core SOS logic: [lib/services/sos_service.dart](lib/services/sos_service.dart)
- Trigger points: [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart), [lib/screens/home_screen.dart](lib/screens/home_screen.dart), [lib/screens/caregiver_dashboard.dart](lib/screens/caregiver_dashboard.dart)

## 14. Caregiver Dashboard Actions

What users get:

- Visibility into activity and quick call/message/location actions.

Why it exists:

- Supports assisted usage scenarios without changing the core user workflow.

Technical implementation:

- Screen and tabs: [lib/screens/caregiver_dashboard.dart](lib/screens/caregiver_dashboard.dart)

## Platform Features

## 15. Settings and Configuration

What users get:

- Control over speech behavior, emergency contact, model mode, and provider keys.

Why it exists:

- Keeps the app adaptable to user preference and environment.

Technical implementation:

- Settings state and secure storage integration: [lib/providers/settings_provider.dart](lib/providers/settings_provider.dart)
- Settings UI and model download cards: [lib/screens/settings_screen.dart](lib/screens/settings_screen.dart)

## 16. History and Replay

What users get:

- View and replay recent outputs.

Why it exists:

- Supports confirmation and recall without re-running perception.

Technical implementation:

- Provider and model: [lib/providers/history_provider.dart](lib/providers/history_provider.dart), [lib/models/history_entry.dart](lib/models/history_entry.dart)
- UI: [lib/screens/history_screen.dart](lib/screens/history_screen.dart)

## Feature-Level Dependencies and Permissions

Not every feature requires the same resources. Key dependencies and permission paths are reflected in:

- Package dependencies: [pubspec.yaml](pubspec.yaml)
- Android permission and intent declarations: [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)

Commonly used runtime capabilities:

1. Camera
2. Microphone
3. Location
4. SMS intent
5. Contacts
6. Internet

## Limitations and Active Work Areas

1. Feature breadth is high, but automated test depth is still limited.
2. Device performance differences significantly affect real-time behavior.
3. Voice command phrase ambiguity still exists for some overlapping phrasing.
4. Some forward-looking ideas previously discussed in project planning docs are not yet shipped features and should not be treated as current product behavior.

## Source of Truth Policy

This features document is aligned to the current codebase. If a mismatch is found:

1. Treat code behavior as ground truth.
2. Update this file and related docs to match runtime reality.