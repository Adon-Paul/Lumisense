# LumiSense Technical Architecture

## Purpose of This Document

This document explains how LumiSense is built today.

For non-technical readers:

- LumiSense runs primarily on a smartphone.
- It uses the camera to understand surroundings.
- It speaks answers and guidance back to the user.
- It can run AI locally on-device, and can also use cloud providers.

For technical readers, this is an implementation-accurate architecture reference tied to the current source under [lib](lib), configuration under [android](android), and dependencies in [pubspec.yaml](pubspec.yaml).

## System Overview

At runtime, the architecture is a mobile-first pipeline.

```text
Camera and Sensors -> Flutter Application Layer -> AI and Perception Services -> TTS Output
```

The AI and perception layer is hybrid:

- On-device perception: ML Kit OCR, barcode, face, pose, brightness analysis
- Real-time object detection: ultralytics_yolo
- On-device language and vision: llama.cpp via llamadart and GGUF models
- Cloud inference fallback: Gemini -> OpenRouter -> Groq -> Ollama

## Architectural Principles

### Accessibility-first interaction

For non-technical readers:

- The app is built to be operated with speech and large controls.

Technical implementation:

- TTS is centralized in [lib/services/tts_service.dart](lib/services/tts_service.dart).
- Voice command recognition and command mapping are in [lib/services/stt_service.dart](lib/services/stt_service.dart).
- Main action surface is [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart) with large action buttons, semantics usage, and spoken status updates.

### Execution flexibility

For non-technical readers:

- If one AI path fails, the app tries another path.

Technical implementation:

- Cloud chain in [lib/services/gemini_service.dart](lib/services/gemini_service.dart).
- On-device path in [lib/services/on_device_orchestrator.dart](lib/services/on_device_orchestrator.dart), [lib/services/on_device_vision_service.dart](lib/services/on_device_vision_service.dart), and [lib/services/on_device_assistant_service.dart](lib/services/on_device_assistant_service.dart).
- Model lifecycle in [lib/services/model_manager.dart](lib/services/model_manager.dart).

### Modular feature services

For non-technical readers:

- Each feature has a dedicated engine so issues in one feature do not collapse everything.

Technical implementation:

- OCR: [lib/services/ocr_service.dart](lib/services/ocr_service.dart)
- Navigation intelligence: [lib/services/navigation_mode_controller.dart](lib/services/navigation_mode_controller.dart)
- Turn-by-turn routing: [lib/services/directions_service.dart](lib/services/directions_service.dart)
- Weather: [lib/services/weather_service.dart](lib/services/weather_service.dart)
- SOS: [lib/services/sos_service.dart](lib/services/sos_service.dart)
- QR and UPI: [lib/services/qr_scanner_service.dart](lib/services/qr_scanner_service.dart), [lib/services/upi_payment_service.dart](lib/services/upi_payment_service.dart)
- Face and pose: [lib/services/face_detection_service.dart](lib/services/face_detection_service.dart), [lib/services/pose_detection_service.dart](lib/services/pose_detection_service.dart)

## Runtime Layering

## 1. Presentation and Interaction Layer

Main screens:

- [lib/screens/splash_screen.dart](lib/screens/splash_screen.dart)
- [lib/screens/onboarding_screen.dart](lib/screens/onboarding_screen.dart)
- [lib/screens/home_screen.dart](lib/screens/home_screen.dart)
- [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- [lib/screens/settings_screen.dart](lib/screens/settings_screen.dart)
- [lib/screens/history_screen.dart](lib/screens/history_screen.dart)
- [lib/screens/caregiver_dashboard.dart](lib/screens/caregiver_dashboard.dart)
- [lib/screens/route_map_screen.dart](lib/screens/route_map_screen.dart)

The camera screen is the central orchestrator for user-triggered actions and voice-triggered actions.

## 2. State and Persistence Layer

Global and feature state:

- App mode and processing state: [lib/providers/app_state.dart](lib/providers/app_state.dart)
- User settings and API keys: [lib/providers/settings_provider.dart](lib/providers/settings_provider.dart)
- User history: [lib/providers/history_provider.dart](lib/providers/history_provider.dart)

Data models:

- History entries: [lib/models/history_entry.dart](lib/models/history_entry.dart)
- OCR result model: [lib/models/ocr_result.dart](lib/models/ocr_result.dart)
- UPI payload model: [lib/models/upi_payment_info.dart](lib/models/upi_payment_info.dart)

## 3. AI and Perception Layer

### Cloud provider chain

Cloud scene description is managed by [lib/services/gemini_service.dart](lib/services/gemini_service.dart), with sequential fallback across configured providers.

### On-device local model stack

- Model download and cache: [lib/services/model_manager.dart](lib/services/model_manager.dart)
- Vision task inference: [lib/services/on_device_vision_service.dart](lib/services/on_device_vision_service.dart)
- Conversational and action inference: [lib/services/on_device_assistant_service.dart](lib/services/on_device_assistant_service.dart)
- Routing between services: [lib/services/on_device_orchestrator.dart](lib/services/on_device_orchestrator.dart)

### Real-time object and navigation loop

- Camera inference feed and action routing: [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- Navigation announcement policy and persistence logic: [lib/services/navigation_mode_controller.dart](lib/services/navigation_mode_controller.dart)
- Visual overlays: [lib/widgets/bounding_box_overlay.dart](lib/widgets/bounding_box_overlay.dart)

### Additional perception services

- OCR: [lib/services/ocr_service.dart](lib/services/ocr_service.dart)
- Barcode and QR: [lib/services/qr_scanner_service.dart](lib/services/qr_scanner_service.dart)
- Brightness: [lib/services/brightness_detector_service.dart](lib/services/brightness_detector_service.dart)
- Face: [lib/services/face_detection_service.dart](lib/services/face_detection_service.dart)
- Pose: [lib/services/pose_detection_service.dart](lib/services/pose_detection_service.dart)
- Currency: [lib/services/currency_detector_service.dart](lib/services/currency_detector_service.dart)

## 4. Device and Platform Integration Layer

- Speech output engine: [lib/services/tts_service.dart](lib/services/tts_service.dart)
- Speech input engine: [lib/services/stt_service.dart](lib/services/stt_service.dart)
- GPS and SOS transport: [lib/services/sos_service.dart](lib/services/sos_service.dart)
- Contact call integration: [lib/services/contact_caller_service.dart](lib/services/contact_caller_service.dart)
- Turn-by-turn directions provider integration: [lib/services/directions_service.dart](lib/services/directions_service.dart)

## End-to-End Data Flows

### OCR flow

```text
User tap or voice command -> Camera frame capture -> OCR service -> Text result ->
History write -> TTS narration
```

Primary code path:

- [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- [lib/services/ocr_service.dart](lib/services/ocr_service.dart)

### Scene description flow

```text
Describe trigger -> Frame capture -> On-device or cloud decision ->
Inference result -> History write -> Spoken response
```

Primary code path:

- [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- [lib/services/on_device_orchestrator.dart](lib/services/on_device_orchestrator.dart)
- [lib/services/gemini_service.dart](lib/services/gemini_service.dart)

### Real-time navigation mode flow

```text
Navigate on -> Continuous detections -> Object persistence and priority logic ->
Debounced announcements and haptics -> Overlay and status updates
```

Primary code path:

- [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- [lib/services/navigation_mode_controller.dart](lib/services/navigation_mode_controller.dart)
- [lib/widgets/bounding_box_overlay.dart](lib/widgets/bounding_box_overlay.dart)

### Turn-by-turn walking flow

```text
Destination input or voice command -> Geocoding -> Route fetch ->
GPS stream tracking -> Step advancement and rerouting -> Spoken guidance
```

Primary code path:

- [lib/widgets/directions_panel.dart](lib/widgets/directions_panel.dart)
- [lib/services/directions_service.dart](lib/services/directions_service.dart)
- [lib/screens/route_map_screen.dart](lib/screens/route_map_screen.dart)

### SOS flow

```text
SOS trigger -> Permission check -> GPS fix -> SMS intent launch ->
Fallback dial if needed -> Spoken status
```

Primary code path:

- [lib/services/sos_service.dart](lib/services/sos_service.dart)
- [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- [lib/screens/home_screen.dart](lib/screens/home_screen.dart)

## On-Device Model Management Architecture

For non-technical readers:

- Large AI models are downloaded once, stored locally, and reused.
- The app can load and unload models to avoid memory pressure.

Technical behavior:

- Model metadata, size estimates, and URLs are defined in [lib/services/model_manager.dart](lib/services/model_manager.dart).
- Downloads support resume behavior via HTTP range handling.
- Loading uses guarded futures in model services to avoid duplicate concurrent loads.
- Orchestration can load only the needed model path for a task.

## Voice and Action Routing Architecture

For non-technical readers:

- User can speak commands like read, identify, describe, weather, or SOS.

Technical behavior:

- Phrase mapping and extraction logic are in [lib/services/stt_service.dart](lib/services/stt_service.dart).
- Camera screen command handler dispatches commands to feature handlers in [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart).
- Assistant action markers are parsed in [lib/services/on_device_assistant_service.dart](lib/services/on_device_assistant_service.dart).

## Security and Data Handling

Sensitive configuration:

- API keys are stored through secure storage paths in [lib/providers/settings_provider.dart](lib/providers/settings_provider.dart).

Local persistence:

- Non-sensitive app preferences and history are persisted via shared preferences and serialized models.

Operational privacy boundary:

- On-device mode can keep inference local.
- Cloud mode transmits image content to configured provider endpoints for inference tasks.

## Android Platform Configuration

Build and SDK configuration:

- [android/app/build.gradle.kts](android/app/build.gradle.kts)

Permissions and intent queries:

- [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)

Notable runtime requirements:

- minSdk is 24
- Camera, microphone, location, contacts, SMS, and internet permissions are used by feature-specific paths

## Performance and Reliability Controls

Current defensive controls include:

- Detection and speech throttling in navigation controller
- Retry and timeout handling in cloud service calls
- Cancellation hooks for on-device inference loops
- Cooldowns in scene description triggering
- Graceful fallback messaging for missing permissions or missing API keys

## Known Architectural Gaps

1. Test coverage is still narrow relative to feature breadth.
2. Command phrase precedence in speech mapping can still produce occasional ambiguous intent selection.
3. Device-specific performance variability remains a practical deployment constraint for camera-heavy, real-time workloads.
4. Documentation and implementation are being aligned; this file reflects current architecture and should be treated as the primary technical architecture reference in this repository.

## Non-Goals for This Architecture Version

The current runtime architecture does not rely on a required external wearable hardware tier.

If future versions introduce external edge devices or dedicated cloud backends, those should be documented as future architecture variants rather than mixed into this current-state document.
