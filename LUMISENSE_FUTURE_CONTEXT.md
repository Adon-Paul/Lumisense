## What This Project Is

**LumiSense** is a **purely software-based** Flutter mobile app that acts as a **proactive AI co-pilot for the visually impaired**. It uses the phone's own built-in camera + on-device AI + cloud AI to help blind/low-vision users read text, recognize objects, and navigate daily life -- all from their existing smartphone with **zero external hardware**.

This is a final-year B.Tech CS project. The goal is a **working demo prototype** -- not a commercial product.

---

## Architecture (Simple)

```
[Phone Camera] -> [Flutter App] -> [AI Layer] -> [TTS Audio Output]
                                      |
                           +----------+----------+
                      On-Device AI           Cloud AI
                      (Google ML Kit)     (Gemini API)
                      - OCR/Text           - Scene description
                      - Object labels      - Complex Q&A about surroundings
```

Everything runs on the user's phone. No ESP32, no wearables, no external hardware whatsoever.

---

## Tech Stack

| Layer             | Technology                                                    |
| ----------------- | ------------------------------------------------------------- |
| App Framework     | **Flutter** (Dart)                                            |
| On-Device OCR     | **Google ML Kit** (`google_mlkit_text_recognition`)           |
| On-Device Objects | **Google ML Kit** (`google_mlkit_object_detection`) OR **TFLite** with MobileNet/SSD |
| Cloud AI          | **Google Gemini API** (send image -> get rich scene description) |
| Voice Output      | **flutter_tts** (Text-to-Speech)                              |
| Voice Input       | **speech_to_text** (for voice commands)                       |
| Camera            | **camera** package (phone's built-in camera)                  |
| State Management  | **Provider** or **Riverpod**                                  |
| Platform          | Android-first (iOS optional)                                  |

---

## Core Features to Build (Priority Order)

### P0 -- Must Have (build these first)

1. **Camera Live Feed Screen**
   - Full-screen camera preview
   - Large, accessible action buttons at the bottom
   - Tap anywhere or voice command to trigger AI

2. **Instant Text Reader (OCR)**
   - User points camera at text -> app reads it aloud via TTS
   - Uses Google ML Kit on-device (works offline, zero latency)
   - Handles: menus, signs, labels, medicine bottles, documents

3. **Object Recognition**
   - User points camera -> app identifies objects and speaks labels
   - On-device via ML Kit or TFLite (MobileNet SSD)
   - Speaks: "Chair ahead", "Bottle on table", "Person detected"

4. **Scene Description (Cloud AI)**
   - User taps "Describe" button or says "describe"
   - App captures frame -> sends to Gemini API -> gets rich scene description -> speaks it
   - Example output: "You are in a kitchen. There's a gas stove on your left with a pot on it. A window ahead shows daylight."
   - This is the WOW feature for the demo

5. **Voice Command System**
   - "Read" -> triggers OCR
   - "What is this?" -> triggers object recognition
   - "Describe" -> triggers scene description
   - "Help" -> lists available commands
   - Always listening or activated by a button

6. **Text-to-Speech Output**
   - ALL results spoken aloud automatically
   - Adjustable speech rate
   - Queue management (don't overlap speech)

### P1 -- Nice to Have (if time permits)

7. **SOS / Emergency Button**
   - Big red button on home screen
   - Sends SMS with GPS location to preset emergency contact
   - Simple -- just uses `url_launcher` or `telephony` package

8. **Medication Reminder (Simplified)**
   - User photographs prescription -> OCR extracts medicine name
   - Set a simple local notification reminder
   - Uses `flutter_local_notifications`

9. **History/Log Screen**
   - Keeps a log of recent OCR reads and scene descriptions
   - User can replay any past result via TTS

---

## Screen Flow

```
App Launch
  -> Splash Screen (app name + tagline spoken aloud)
  -> Home Dashboard
      |- [Camera / Live View]  <- primary screen, always accessible
      |    |- [Read Text] button  -> OCR -> TTS
      |    |- [Identify] button   -> Object Detection -> TTS
      |    '- [Describe Scene] button -> Gemini API -> TTS
      |- [SOS] button          -> Send emergency SMS
      |- [Medication] button   -> Reminder setup (P1)
      |- [History] button      -> Past results (P1)
      '- [Settings]            -> Speech rate, emergency contact, Gemini API key
```

---

## UI/UX Requirements (Accessibility-First)

- **High contrast** -- dark background, bright text/icons (think white-on-black or yellow-on-black)
- **Large touch targets** -- minimum 72dp buttons, ideally bigger
- **Minimal UI elements** -- no clutter, max 3-4 buttons visible at once
- **Everything has TTS labels** -- every screen, every button speaks its purpose on focus
- **Haptic feedback** on button press (HapticFeedback.heavyImpact)
- **No text-only navigation** -- every action reachable by voice or large buttons
- **Auto-speak results** -- never require the user to read something on screen
- **Semantic labels** on all widgets for TalkBack/VoiceOver

---

## Key Implementation Details

### Camera Setup
```dart
// Use the camera package, prefer back camera, medium resolution for speed
// Resolution: ResolutionPreset.medium (720p) -- balances quality vs processing speed
// Image format: YUV420 for ML Kit, JPEG for Gemini API
```

### OCR (Google ML Kit)
```dart
// google_mlkit_text_recognition package
// Process camera frame -> extract text blocks -> concatenate -> speak via TTS
// Handle: multiple text blocks, reading order (top-to-bottom, left-to-right)
// Language: English default, add Hindi if time permits
```

### Object Detection
```dart
// Option A: google_mlkit_object_detection (simpler, fewer labels)
// Option B: tflite_flutter with MobileNet SSD (more labels, needs model file)
// Speak top 3-5 detected objects with confidence > 60%
```

### Scene Description (Gemini API)
```dart
// Capture single frame as JPEG
// Send to Gemini API (gemini-2.0-flash for speed, or gemini-2.0-flash-lite for cost)
// Prompt: "You are an assistant for a visually impaired person. Describe this scene
//          in 2-3 clear, concise sentences. Focus on: what objects are present,
//          their spatial arrangement, any text visible, and potential hazards.
//          Be specific about directions (left, right, ahead)."
// Parse response -> speak via TTS
```

### Voice Commands
```dart
// speech_to_text package
// Listen for wake words or run in push-to-talk mode
// Map recognized text to commands:
//   contains("read") -> triggerOCR()
//   contains("describe") || contains("what do you see") -> triggerSceneDescription()
//   contains("identify") || contains("what is") -> triggerObjectDetection()
//   contains("help") -> speakAvailableCommands()
//   contains("emergency") || contains("sos") -> triggerSOS()
```

### TTS
```dart
// flutter_tts package
// Set language: en-IN (Indian English) or en-US
// Default rate: 0.5 (slightly slow for clarity)
// Queue: stop current speech before starting new result
// Speak immediately on every AI result -- never wait for user action
```

---

## Project Structure

```
lumisense/
|- lib/
|  |- main.dart                     # App entry, theme, routes
|  |- app.dart                      # MaterialApp config, accessibility theme
|  |
|  |- screens/
|  |  |- splash_screen.dart         # Animated splash + TTS welcome
|  |  |- home_screen.dart           # Main dashboard with big buttons
|  |  |- camera_screen.dart         # Live camera + action buttons
|  |  |- settings_screen.dart       # Speech rate, contacts, API key
|  |  |- history_screen.dart        # Past results log (P1)
|  |  '- medication_screen.dart     # Medication reminder (P1)
|  |
|  |- services/
|  |  |- tts_service.dart           # Text-to-Speech wrapper (singleton)
|  |  |- stt_service.dart           # Speech-to-Text / voice command handler
|  |  |- ocr_service.dart           # Google ML Kit text recognition
|  |  |- object_detection_service.dart  # ML Kit or TFLite object detection
|  |  |- gemini_service.dart        # Gemini API calls for scene description
|  |  |- camera_service.dart        # Camera controller management
|  |  '- sos_service.dart           # Emergency SMS + location
|  |
|  |- providers/
|  |  |- app_state.dart             # Global app state
|  |  '- settings_provider.dart     # User preferences
|  |
|  |- models/
|  |  |- detection_result.dart      # Object detection result model
|  |  |- ocr_result.dart            # OCR result model
|  |  '- history_entry.dart         # History log entry
|  |
|  |- widgets/
|  |  |- accessible_button.dart     # Large, high-contrast button with TTS
|  |  |- action_bar.dart            # Bottom action buttons on camera screen
|  |  '- result_overlay.dart        # Shows result text over camera
|  |
|  |- utils/
|  |  |- constants.dart             # Colors, sizes, strings
|  |  |- accessibility_helpers.dart # Semantic wrappers, TTS helpers
|  |  '- image_utils.dart           # Frame capture, JPEG conversion
|  |
|  '- config/
|     '- api_keys.dart              # Gemini API key (use --dart-define in prod)
|
|- assets/
|  |- models/                       # TFLite model files (if using TFLite)
|  |  |- ssd_mobilenet.tflite
|  |  '- labels.txt
|  '- sounds/                       # UI sounds (optional)
|
|- android/
|  '- app/src/main/AndroidManifest.xml  # Camera, microphone, SMS, location permissions
|
|- pubspec.yaml
'- README.md
```

---

## pubspec.yaml Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  camera: ^0.11.0                           # Camera access
  google_mlkit_text_recognition: ^0.14.0    # On-device OCR
  google_mlkit_object_detection: ^0.14.0    # On-device object detection
  flutter_tts: ^4.2.0                       # Text-to-Speech
  speech_to_text: ^7.0.0                    # Voice commands
  http: ^1.2.0                              # For Gemini API calls
  provider: ^6.1.0                          # State management
  geolocator: ^13.0.0                       # GPS for SOS
  url_launcher: ^6.3.0                      # SMS/phone for SOS
  permission_handler: ^11.3.0               # Runtime permissions
  shared_preferences: ^2.3.0                # Local settings storage
  flutter_local_notifications: ^18.0.0      # Medication reminders (P1)
  path_provider: ^2.1.0                     # Local file storage
  image: ^4.3.0                             # Image processing
```

---

## Android Permissions Needed

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.SEND_SMS" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.VIBRATE" />
```

---

## Gemini API Integration

```dart
// Endpoint: https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent
// Auth: API key as query param ?key=YOUR_KEY
// Send image as base64 in the request body
//
// Request body:
// {
//   "contents": [{
//     "parts": [
//       {"inlineData": {"mimeType": "image/jpeg", "data": "<base64>"}},
//       {"text": "You are an assistant for a visually impaired person. Describe what you see in 2-3 sentences. Focus on objects, spatial layout, text, and hazards. Use directional cues like left, right, ahead."}
//     ]
//   }]
// }
```

---

## Build Order (Do This Sequence)

1. `flutter create lumisense` -> set up project skeleton
2. Add all dependencies to pubspec.yaml -> `flutter pub get`
3. Build `tts_service.dart` -> test TTS works
4. Build `camera_service.dart` + `camera_screen.dart` -> test camera preview works
5. Build `ocr_service.dart` -> wire to camera -> test: point at text, hear it spoken
6. Build `gemini_service.dart` -> wire to camera -> test: tap describe, hear scene description
7. Build `object_detection_service.dart` -> wire to camera -> test object labels spoken
8. Build `stt_service.dart` -> wire voice commands to trigger OCR/describe/detect
9. Build `home_screen.dart` -> main dashboard with navigation
10. Build `settings_screen.dart` -> speech rate, emergency contact, API key
11. Build `sos_service.dart` -> emergency SMS feature
12. Polish UI -> high contrast theme, large buttons, accessibility labels
13. Test full flow end-to-end

---

## What "Done" Looks Like for Demo

A working Android app where a visually impaired user (or evaluator simulating one) can:
1. Open the app and hear a welcome message
2. Point the phone camera at text -> tap "Read" -> hear the text spoken aloud
3. Point at objects -> tap "Identify" -> hear object names
4. Tap "Describe" -> hear a rich AI-generated description of the scene
5. Say voice commands to do all of the above hands-free
6. Tap SOS -> emergency SMS sent with location
7. Navigate the entire app via large buttons with voice feedback

