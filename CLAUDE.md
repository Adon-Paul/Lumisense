# CLAUDE.md — LumiSense Project Context

## What This Project Is

LumiSense is a purely software-based Flutter mobile app that acts as a proactive AI co-pilot for the visually impaired. It uses the phone's built-in camera + on-device AI + cloud AI to help blind/low-vision users read text, recognize objects, navigate surroundings, and get emergency help — all from their existing smartphone with zero external hardware.

This is a final-year B.Tech CS project. The goal is a working demo prototype — not a commercial product.

---

## Architecture

```
[Phone Camera] → [Flutter App] → [AI Layer] → [TTS Audio Output]
                                      │
                         ┌────────────┴────────────┐
                    On-Device AI               Cloud AI
                    (Google ML Kit)        (Gemini 2.0 Flash)
                    (YOLOv8 via TFLite)    - Scene description
                    - OCR/Text             - Complex Q&A
                    - Object detection
                    - Real-time navigation
```

Everything runs on the user's phone. No ESP32, no wearables, no external hardware.

---

## Tech Stack

| Layer | Technology |
|---|---|
| App Framework | Flutter (Dart), SDK >=3.10.0 |
| On-Device OCR | Google ML Kit (`google_mlkit_text_recognition`) |
| Object Detection | YOLOv8n via TFLite (`flutter_vision`) — 80 COCO classes |
| Cloud AI | Google Gemini 2.0 Flash API (REST + base64 JPEG) |
| Voice Output | `flutter_tts` (Text-to-Speech, singleton) |
| Voice Input | `speech_to_text` v7.x (voice commands) |
| Camera | `camera` ^0.11.2 (back camera, medium res, YUV420) |
| State Management | Provider (`MultiProvider`) |
| Storage | `SharedPreferences` + `FlutterSecureStorage` (API key) |
| GPS/SOS | `geolocator` + `url_launcher` (SMS) |
| Platform | Android-first (compileSdk 36, targetSdk 36) |

---

## Core Features (Implemented)

### Phase 1 — Foundation ✅
1. Camera live feed with permission handling
2. OCR text reading via ML Kit (offline, reading-order sorted)
3. TTS voice output (singleton, queue management, speech rate control)
4. Accessibility-first UI (72dp buttons, Semantics, HapticFeedback)
5. Splash → Onboarding → Home → Camera screen flow

### Phase 2 — Intelligence ✅
1. Gemini 2.0 Flash scene description (base64 JPEG, timeout handling)
2. Voice commands via STT (read, identify, describe, navigate, help, SOS, stop)
3. SOS emergency SMS with GPS coordinates
4. Settings screen (TTS rate/volume/pitch, emergency contact, API key)
5. History logging for all detection/OCR/description results

### Phase 3 — Real-Time Navigation ✅
1. **YOLOv8n object detection** — 80 COCO classes, GPU-accelerated via TFLite
2. **Real-time bounding box overlay** on camera preview
3. **Navigation mode** — continuous detection with smart TTS announcements
4. **Object persistence tracking** — only confirmed objects (2+ frames) are announced
5. **TTS debouncing** — 3-second cooldown, change-only announcements
6. **FPS indicator** showing live inference speed
7. **Pause/resume** navigation for tap-based features (Read, Describe)

---

## Screen Flow

```
App Launch
  → Splash Screen (TTS welcome, auto-nav for returning users)
  → Onboarding (name, emergency contact, API key) → sets hasOnboarded
  → Home Dashboard
      ├── [📷 Camera / Live View]  ← primary screen
      │     ├── [Read] button       → OCR → TTS
      │     ├── [Identify] button   → YOLO single-shot → TTS
      │     ├── [Navigate] button   → Toggle real-time YOLO + bounding boxes + TTS
      │     ├── [Describe] button   → Gemini API → TTS
      │     ├── [🎤 Voice] button   → STT voice commands
      │     └── [🆘 SOS] button    → Emergency SMS
      ├── [⚙️ Settings]            → TTS, contact, API key
      ├── [📋 History]             → Past results
      └── [👥 Caregiver]           → Dashboard
```

---

## Navigation Mode — How It Works

```
Camera 30fps → Image Stream → YoloService.detectOnFrame() → NavigationModeController
                                     │                              │
                              flutter_vision                Smart TTS Logic:
                              (native YUV→RGB,              - Object persistence (2+ frames)
                               GPU delegate,                - Change-only announcements
                               built-in NMS)                - 3-second cooldown
                                     │                      - Object forget after 5s absent
                                     ↓                              │
                              BoundingBoxOverlay             TtsService.speak()
                              (Positioned widgets,           "person and laptop"
                               color-coded boxes,
                               label + confidence)
```

### Key Design Decisions:
- **Flag-based throttling**: Only one frame processed at a time (`_isInferring` flag)
- **No Dart isolates for YOLO**: `flutter_vision` runs inference natively (C++/Java) off the UI thread
- **Stream pause/resume**: `takePicture()` requires stopping the stream first
- **GPU delegate with CPU fallback**: Tries GPU first, falls back to CPU if unsupported
- **Model preloaded at screen init**: No cold-start delay when toggling navigation

---

## Project Structure

```
lumisense/
├── lib/
│   ├── main.dart                          # Entry, providers, routes, error handlers
│   ├── screens/
│   │   ├── splash_screen.dart             # TTS welcome + auto-nav
│   │   ├── onboarding_screen.dart         # Name, contact, API key setup
│   │   ├── home_screen.dart               # Dashboard with nav buttons
│   │   ├── camera_screen.dart             # Live camera + YOLO + actions
│   │   ├── settings_screen.dart           # TTS sliders, contact, API key
│   │   ├── history_screen.dart            # Past results log
│   │   └── caregiver_dashboard.dart       # Caregiver info screen
│   ├── services/
│   │   ├── tts_service.dart               # Singleton TTS wrapper
│   │   ├── stt_service.dart               # Voice command recognition
│   │   ├── ocr_service.dart               # ML Kit text recognition
│   │   ├── yolo_service.dart              # YOLOv8n via flutter_vision
│   │   ├── navigation_mode_controller.dart # Smart TTS + object tracking
│   │   ├── gemini_service.dart            # Gemini 2.0 Flash API
│   │   ├── camera_service.dart            # Camera + image stream
│   │   ├── sos_service.dart               # Emergency SMS + GPS
│   │   └── object_detection_service.dart  # [DEPRECATED] ML Kit stub
│   ├── providers/
│   │   ├── app_state.dart                 # AppMode, ProcessingState
│   │   ├── settings_provider.dart         # Prefs + SecureStorage bridge
│   │   └── history_provider.dart          # History entries
│   ├── models/
│   │   ├── detection_result.dart          # DetectedObjectItem + bounding box
│   │   ├── ocr_result.dart                # OcrResult
│   │   └── history_entry.dart             # HistoryEntry + types
│   ├── widgets/
│   │   └── bounding_box_overlay.dart      # YOLO box renderer + nav indicator
│   └── utils/
│       ├── theme.dart                     # AppTheme (dark, yellow accent)
│       └── image_utils.dart               # JPEG byte utilities
├── assets/
│   ├── labels.txt                         # COCO 80 class labels
│   └── models/
│       └── yolov8n.tflite                 # YOLOv8 nano model (~12.8 MB)
├── android/
│   └── app/
│       ├── build.gradle.kts               # compileSdk 36, aaptOptions, proguard
│       ├── proguard-rules.pro             # ML Kit + TFLite keep rules
│       └── src/main/AndroidManifest.xml   # All permissions + ML Kit metadata
├── scripts/
│   └── download_model.py                  # Export YOLOv8n to TFLite
├── pubspec.yaml
└── CLAUDE.md
```

---

## Key Dependencies (pubspec.yaml)

```yaml
dependencies:
  camera: ^0.11.2                          # Camera + image stream
  flutter_vision: ^2.0.0                   # YOLOv8 object detection (TFLite)
  google_mlkit_text_recognition: ^0.15.1   # On-device OCR
  flutter_tts: ^4.2.5                      # Text-to-Speech
  speech_to_text: ^7.0.0                   # Voice commands
  http: ^1.6.0                             # Gemini API calls
  provider: ^6.1.2                         # State management
  geolocator: ^13.0.0                      # GPS for SOS
  url_launcher: ^6.3.0                     # SMS for SOS
  permission_handler: ^11.3.1              # Runtime permissions
  shared_preferences: ^2.5.4              # Local settings
  flutter_secure_storage: ^9.2.2          # API key storage
  path_provider: ^2.1.0                   # File paths
  image: ^4.8.0                           # Image processing
  intl: ^0.19.0                           # Date formatting
```

---

## Android Configuration

- **compileSdk**: 36
- **targetSdk**: 36
- **minSdk**: Flutter default (21)
- **JDK**: Android Studio bundled JDK (OpenJDK 21) at `C:\Program Files\Android\Android Studio\jbr`
- **Android SDK**: `C:\Users\adonp\AppData\Local\Android\Sdk`
- **aaptOptions**: `noCompress += "tflite"` (required for TFLite memory-mapped loading)
- **ProGuard**: ML Kit language module warnings + TFLite delegate keep rules

### Permissions (AndroidManifest.xml)
```xml
CAMERA, RECORD_AUDIO, SEND_SMS, ACCESS_FINE_LOCATION,
ACCESS_COARSE_LOCATION, INTERNET, VIBRATE,
RECEIVE_BOOT_COMPLETED, FOREGROUND_SERVICE
```

---

## YOLO Model Setup

The YOLOv8n model file (`assets/models/yolov8n.tflite`) is required for object detection and navigation mode.

### To download/export the model:
```bash
# Option 1: Use the provided script (requires Python + ultralytics)
pip install ultralytics
python scripts/download_model.py

# Option 2: Manual export
pip install ultralytics
python -c "from ultralytics import YOLO; YOLO('yolov8n.pt').export(format='tflite')"
# Copy the exported yolov8n_float32.tflite to assets/models/yolov8n.tflite
```

The model detects 80 COCO classes (person, car, chair, laptop, phone, etc.) and runs at 30+ FPS on Snapdragon 8 Gen 2 with GPU delegate.

---

## Build Commands

```bash
# Set environment
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
export ANDROID_SDK_ROOT="/c/Users/adonp/AppData/Local/Android/Sdk"

# Get dependencies
flutter pub get

# Run analyzer
flutter analyze

# Build release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk (~188 MB)
```

---

## What "Done" Looks Like for Demo

A working Android app where a visually impaired user (or evaluator simulating one) can:

1. Open the app and hear a welcome message
2. Point the phone camera at text → tap "Read" → hear text spoken aloud
3. Point at objects → tap "Identify" → hear 80 COCO object names via YOLO
4. Tap "Navigate" → see real-time bounding boxes + hear smart announcements
5. Tap "Describe" → hear Gemini AI's rich scene description
6. Say voice commands to do all of the above hands-free
7. Tap SOS → emergency SMS sent with GPS location
8. Navigate the entire app via large buttons with voice feedback
9. Walk around with Navigation Mode and hear objects announced as they appear
