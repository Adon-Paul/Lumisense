# LumiSense Setup Guide

## Who This Guide Is For

For non-technical readers:

- This guide helps you run LumiSense on an Android phone for demo and testing.

For technical readers:

- This is the canonical setup path for local development in the current codebase.
- It focuses on the app under [lumisense](.), not historical hardware or external backend stacks.

## 1. Environment Prerequisites

## 1.1 Required software

1. Flutter SDK (stable channel)
2. Android Studio with Android SDK
3. JDK 17
4. Git

Optional but useful:

1. VS Code with Flutter and Dart extensions

## 1.2 Required hardware

1. Android phone or Android emulator
2. Enough free storage for app plus optional local model downloads

## 1.3 Verify your toolchain

Run:

```bash
flutter doctor
```

Resolve blocking issues before continuing.

## 2. Get and Run the App

From the repository root:

```bash
cd lumisense
flutter pub get
flutter run
```

If multiple devices are connected:

```bash
flutter devices
flutter run -d <device-id>
```

## 3. Android Configuration Notes

Current Android configuration is defined in:

1. [android/app/build.gradle.kts](android/app/build.gradle.kts)
2. [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)

Important runtime points:

1. minSdk is 24
2. Camera, microphone, location, contacts, SMS, and internet permissions are used by feature paths

## 4. Initial App Onboarding

When the app first launches:

1. Complete onboarding fields
2. Add emergency contact
3. Add API keys you plan to use

Core settings screen is [lib/screens/settings_screen.dart](lib/screens/settings_screen.dart), backed by [lib/providers/settings_provider.dart](lib/providers/settings_provider.dart).

## 5. API Keys and External Services

For non-technical readers:

- Some features work without keys.
- Some features need keys to call online services.

For technical readers:

Configure keys through the in-app Settings UI.

## 5.1 Key types used by current implementation

1. Gemini API key
2. OpenRouter API key (fallback)
3. Groq API key (fallback)
4. Ollama server URL (local network/server fallback)
5. OpenRouteService API key (walking directions)
6. OpenWeatherMap API key (weather)

Service handling references:

1. [lib/services/gemini_service.dart](lib/services/gemini_service.dart)
2. [lib/services/directions_service.dart](lib/services/directions_service.dart)
3. [lib/services/weather_service.dart](lib/services/weather_service.dart)

## 5.2 Features that can run without cloud keys

1. OCR text reading
2. Brightness detection
3. Face and pose detection
4. QR parsing (payment app launch still depends on installed UPI app)
5. Some on-device model workflows after model download

## 6. On-Device Model Setup

For non-technical readers:

- If you enable on-device AI, the app can run more tasks locally.
- First-time model download can take significant time and storage.

For technical readers:

Model lifecycle is managed by [lib/services/model_manager.dart](lib/services/model_manager.dart) and toggled in [lib/screens/settings_screen.dart](lib/screens/settings_screen.dart).

## 6.1 Download flow

1. Open Settings
2. Go to On-Device AI Models
3. Download required models
4. Enable On-Device AI switch

## 6.2 Runtime behavior

1. Models are cached locally
2. Loading is performed on demand
3. Services can unload models to reduce memory pressure

Main on-device services:

1. [lib/services/on_device_vision_service.dart](lib/services/on_device_vision_service.dart)
2. [lib/services/on_device_assistant_service.dart](lib/services/on_device_assistant_service.dart)
3. [lib/services/on_device_orchestrator.dart](lib/services/on_device_orchestrator.dart)

## 7. Recommended Validation Checklist

After setup, verify these flows manually:

1. Read Text in camera screen
2. Identify objects in camera screen
3. Describe scene with configured cloud key
4. Weather with weather key
5. Navigate to a destination with ORS key
6. SOS test with a safe test contact
7. QR scan test using a test UPI code

## 8. Developer Validation Commands

Use these routine commands during development:

```bash
flutter pub get
flutter analyze
flutter test
```

Note:

1. Analyze and test are safe for validation.
2. Build commands are optional and only needed when packaging artifacts.

## 9. Troubleshooting

## 9.1 Camera does not start

Check:

1. Camera permission granted in system settings
2. No other app is holding camera
3. Manifest includes camera permission in [android/app/src/main/AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)

## 9.2 Voice commands not triggering

Check:

1. Microphone permission granted
2. STT listening indicator in camera screen
3. Phrase clarity and command wording
4. Command mapping logic in [lib/services/stt_service.dart](lib/services/stt_service.dart)

## 9.3 Scene description fails

Check:

1. At least one provider key configured
2. Network connectivity for cloud mode
3. On-device models downloaded and enabled for local mode
4. Error output from provider fallback behavior in [lib/services/gemini_service.dart](lib/services/gemini_service.dart)

## 9.4 Directions fail to start

Check:

1. OpenRouteService key is set
2. Location permission is granted
3. GPS is enabled on device
4. Destination phrase is specific enough

## 9.5 SOS flow does not complete

Check:

1. Emergency contact is configured
2. Location permission is granted
3. SMS or dial intent is available on device
4. SOS logic in [lib/services/sos_service.dart](lib/services/sos_service.dart)

## 9.6 On-device models fail to run

Check:

1. Model download completed in Settings
2. Enough free storage and RAM
3. On-device mode enabled
4. Service load path in [lib/services/on_device_orchestrator.dart](lib/services/on_device_orchestrator.dart)

## 10. Development Workflow Notes

1. Keep implementation changes and doc changes together.
2. Treat code behavior as source of truth.
3. Update [README.md](README.md), [FEATURES.md](FEATURES.md), and [ARCHITECTURE.md](ARCHITECTURE.md) when setup assumptions change.

## 11. Reference Index

1. App overview: [README.md](README.md)
2. Architecture: [ARCHITECTURE.md](ARCHITECTURE.md)
3. Feature behavior: [FEATURES.md](FEATURES.md)
4. Master specification: [PROJECT_SPEC.md](PROJECT_SPEC.md)