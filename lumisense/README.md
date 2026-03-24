# LumiSense

LumiSense is a software-only Flutter app that helps blind and low-vision users understand their surroundings using a phone camera, voice input, and spoken feedback.

This repository represents the current working demo implementation. It does not require external wearable hardware.

## What This App Does

In plain terms, LumiSense tries to answer the questions a visually impaired user asks dozens of times per day:

- What is in front of me?
- Can you read this text?
- Is this a payment QR code?
- Is this note 100 or 500 rupees?
- Who is near me?
- What is the weather like right now?
- Can you guide me to a place?

Technically, it combines on-device computer vision, optional on-device language models, and cloud AI fallbacks. It is built around an accessibility-first interaction model with large touch targets, speech output, and voice commands.

## Current Implementation Status

The table below describes what exists in code today.

### Implemented and usable

- Camera-based OCR text reading with speech output
- Real-time object detection overlay and smart navigation announcements
- Scene description using cloud AI with provider fallback chain
- On-device model stack for local scene understanding and assistant flows
- Voice commands for core actions
- SOS flow with GPS-based emergency SMS handoff
- QR scanning and UPI payment intent launch
- Currency identification from camera frame
- Face and pose detection for people awareness
- Brightness and weather checks
- Turn-by-turn walking directions with map and spoken steps
- History log and replay
- Settings for TTS, API keys, emergency contact, and on-device mode toggle

### Partial or evolving

- On-device assistant tool-calling workflows are implemented but still under active hardening
- Contact calling by voice works but depends on contact naming quality and permissions
- Some advanced navigation behaviors are still being tuned for real-world walking variability

### Planned, not implemented as production features

- Gamification and training modules
- Calendar and fitness integrations
- Medication management workflows
- Broader proactive life-assistant automation

## Architecture Snapshot

For non-technical readers: the phone does almost everything.

- The app sees through the camera
- Runs AI locally when possible
- Uses cloud AI when needed
- Speaks results immediately

For technical readers, the high-level flow is:

```text
Camera Frame -> Flutter UI + Services -> AI Execution Layer -> TTS Output

AI Execution Layer:
- On-device CV: ML Kit OCR, face, pose, barcode
- On-device detection: ultralytics_yolo plugin (YOLO)
- On-device LLM/VLM: llama.cpp via llamadart and GGUF models
- Cloud fallback: Gemini -> OpenRouter -> Groq -> Ollama
```

Key service entry points:

- App bootstrap: [lib/main.dart](lib/main.dart)
- Main interaction hub: [lib/screens/camera_screen.dart](lib/screens/camera_screen.dart)
- Cloud multi-provider vision: [lib/services/gemini_service.dart](lib/services/gemini_service.dart)
- On-device orchestration: [lib/services/on_device_orchestrator.dart](lib/services/on_device_orchestrator.dart)
- Model download/cache: [lib/services/model_manager.dart](lib/services/model_manager.dart)
- Navigation logic: [lib/services/directions_service.dart](lib/services/directions_service.dart)

## Core User Flow

For non-technical readers:

1. Open the app
2. Go to camera
3. Tap a task button or speak a command
4. Hear the result

Technical screen flow:

```text
Splash -> Onboarding -> Home -> Camera
                         |-> History
                         |-> Settings
                         |-> Caregiver Dashboard

Camera actions:
- Read
- Identify
- Describe
- Navigate
- Pay (QR)
- Currency
- Light
- Weather
- People
- Voice command trigger
```

## Tech Stack

Primary stack from [pubspec.yaml](pubspec.yaml):

- Flutter and Dart
- Provider state management
- flutter_tts and speech_to_text
- google_mlkit_text_recognition
- google_mlkit_barcode_scanning
- google_mlkit_face_detection
- google_mlkit_pose_detection
- ultralytics_yolo
- llamadart
- dio for large model download management
- geolocator and url_launcher
- open_route_service and flutter_map

Android runtime configuration:

- minSdk 24
- compileSdk 36
- targetSdk 36

See [android/app/build.gradle.kts](android/app/build.gradle.kts) and [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml).

## Quick Start

1. Install Flutter SDK and Android toolchain.
2. From [lumisense](.), install dependencies.
3. Run the app on Android.

```bash
flutter pub get
flutter run
```

For setup detail and environment requirements, use [SETUP.md](SETUP.md).

## Known Constraints

- On-device model downloads are large and can take time on slower networks.
- Some features require API keys and permissions to be configured in Settings.
- Real-time camera AI behavior can vary by device performance and thermal limits.
- The project is optimized for Android-first demo use.

## Documentation Map

- Feature catalog: [FEATURES.md](FEATURES.md)
- Technical architecture: [ARCHITECTURE.md](ARCHITECTURE.md)
- Project scope and context: [PROJECT_SPEC.md](PROJECT_SPEC.md)
- Environment setup: [SETUP.md](SETUP.md)

## Scope Note

This repository is maintained as a final-year project demo codebase with active iteration. Documentation is being continuously aligned to implementation reality.
