# LumiSense

LumiSense is an accessibility-focused AI assistant app for blind and low-vision users, built in Flutter.

This repository contains both project-level planning documents and the actual mobile application source under [lumisense](lumisense).

## Project In One Minute

For non-technical readers:

- The app uses your phone camera to help you read text, identify objects, navigate, and get help in emergencies.
- It is designed to speak results clearly and support voice-driven interaction.
- The current build is a working software demo focused on Android.

For technical readers:

- Core runtime is Flutter plus Provider state management.
- Vision and accessibility stack combines ML Kit, ultralytics_yolo, speech_to_text, and flutter_tts.
- AI path supports cloud and local execution:
  - Cloud chain: Gemini -> OpenRouter -> Groq -> Ollama
  - On-device stack: llama.cpp via llamadart with GGUF model management

## Repository Layout

- Application code: [lumisense](lumisense)
- App readme: [lumisense/README.md](lumisense/README.md)
- Current architecture doc: [lumisense/ARCHITECTURE.md](lumisense/ARCHITECTURE.md)
- Feature catalog: [lumisense/FEATURES.md](lumisense/FEATURES.md)
- Setup guide: [lumisense/SETUP.md](lumisense/SETUP.md)
- Project specification/context: [lumisense/PROJECT_SPEC.md](lumisense/PROJECT_SPEC.md)
- Additional context and plans: [CLAUDE.md](CLAUDE.md), [LUMISENSE_FUTURE_CONTEXT.md](LUMISENSE_FUTURE_CONTEXT.md), [docs/superpowers/plans/2026-03-24-fix-on-device-model-stack.md](docs/superpowers/plans/2026-03-24-fix-on-device-model-stack.md)

## What Is Implemented Today

Highlights from the current app implementation:

- OCR read-aloud
- Object identification and real-time navigation announcements
- Scene description with provider fallback
- On-device model execution path
- QR scanning and UPI payment handoff
- Currency detection
- Weather and brightness checks
- Face and pose-based people awareness
- Voice command routing
- GPS SOS flow and caregiver-focused utilities
- Turn-by-turn walking directions with map view

See [lumisense/README.md](lumisense/README.md) for the detailed, implementation-accurate breakdown.

## Quick Start

From the app folder:

```bash
cd lumisense
flutter pub get
flutter run
```

## Scope Note

This codebase is actively evolving. Some documents describe long-term vision; implementation-accurate behavior is always represented by the source code in [lumisense/lib](lumisense/lib) and the app-focused docs in [lumisense](lumisense).
