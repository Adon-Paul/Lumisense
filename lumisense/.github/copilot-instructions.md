# LumiSense AI Coding Agent Instructions

## Project Overview

LumiSense is a **proactive AI co-pilot for the visually impaired** using a **three-tier distributed architecture**:
- **Edge** (ESP32-WROVER-E wearable with OV5640 camera) - streams video via Wi-Fi MJPEG, communicates via BLE
- **Hub** (Flutter smartphone app) - primary "brain" running TensorFlow Lite models, audio/haptic feedback
- **Cloud** (GCP serverless) - Vision-Language Models for complex scene analysis, Firestore database

**Core Philosophy**: Software-first, smartphone-centric approach for affordability. Proactive assistance (anticipates needs) vs reactive systems (responds to commands).

## Architecture Patterns

### Three-Tier Communication Flow
```
ESP32 Camera → Wi-Fi MJPEG Stream → Flutter App → HTTP/REST → GCP Functions
            ← BLE Commands      ←              ← JSON Response ←
```

### Flutter App Structure (Hub Layer)
Follow this modular pattern seen in `ARCHITECTURE.md`:
```dart
lib/
├── models/          # Data models (user_profile.dart, device_status.dart)
├── services/        # Business logic (camera_service.dart, ai_inference_service.dart)
├── providers/       # State management (Provider pattern with ChangeNotifier)
├── screens/         # UI screens (home_screen.dart, settings_screen.dart)
├── widgets/         # Reusable components (status_indicator.dart)
└── utils/           # Utility functions (audio_utils.dart, haptic_utils.dart)
```

### Hardware Communication Patterns
- **Video**: ESP32 runs HTTP MJPEG server on port 8080 for continuous streaming
- **Control**: BLE with custom service UUID for commands/status exchange
- **Power**: Deep sleep mode integration with wake-up triggers

## Feature Tier System

Implement features following the **7-tier priority system** (see `FEATURES.md`):
1. **Tier 1** (MVP): Real-time obstacle detection, drop-off detection, text OCR
2. **Tier 2**: Object identification, "Find My Stuff" mode, live translation  
3. **Tier 3**: Scene descriptions via cloud VLM, facial recognition, discreet haptic mode
4. **Tier 4**: UPI payments (Razorpay), ride-sharing, emergency SOS, caregiver connect
5. **Tier 5**: Training modules, power management, lens obstruction warnings
6. **Tier 6**: Calendar/Fit integration, proactive weather alerts
7. **Tier 7**: Comprehensive medication manager

## Development Workflows

### Flutter Development
```bash
# Standard development cycle
flutter pub get                    # Install dependencies
flutter run                       # Debug mode with hot reload
flutter run --profile             # Performance profiling
flutter test                      # Run unit tests
flutter analyze                   # Static analysis
flutter build apk --release       # Production builds
```

### ESP32/PlatformIO Development  
```bash
pio run                           # Build firmware
pio run --target upload           # Flash to device (GPIO0→GND for programming)
pio device monitor                # Serial debugging
pio run --target clean            # Clean build
```

### Cloud Functions (GCP)
```bash
firebase deploy --only functions  # Deploy all functions
firebase functions:log            # View logs
gcloud functions deploy analyze-scene --runtime python39 --trigger-http
```

## AI/ML Integration Patterns

### On-Device Models (TensorFlow Lite)
- **OCR Service**: Text extraction with preprocessing pipeline
- **Object Detection**: Real-time inference with GPU acceleration (Metal/OpenGL)
- **Performance**: INT8 quantization, efficient tensor reuse, <200ms latency target

### Cloud AI Integration
- **Vision API**: Scene analysis, landmark detection, text recognition
- **Custom VLM**: Context-aware scene descriptions for complex understanding
- **Audio Processing**: Text-to-Speech with priority interruption system

## Audio & Haptic Feedback Patterns

### Audio Service Pattern
```dart
class AudioService {
  Future<void> speakText(String text, {Priority priority = Priority.normal}) async {
    if (priority == Priority.urgent) {
      await _player.stop(); // Interrupt current audio
    }
    await _tts.speak(text);
  }
}
```

### Haptic Patterns
```dart
static const Map<HapticType, List<int>> patterns = {
  HapticType.obstacle: [100, 50, 100, 50, 200],    // Rapid pulses
  HapticType.dropOff: [300, 100, 300],             // Strong warning
  HapticType.notification: [50, 25, 50],           // Gentle alert
};
```

## Environment Configuration

### Required Environment Variables
```bash
# Flutter (.env)
FIREBASE_PROJECT_ID=lumisense-project
RAZORPAY_KEY_ID=your_razorpay_key
OPENWEATHER_API_KEY=your_openweather_key
DEBUG_MODE=true

# GCP Functions  
GOOGLE_CLOUD_PROJECT=lumisense-project
FIRESTORE_EMULATOR_HOST=localhost:8080  # For local dev
```

### API Integration Points
- **Internal**: GCP API Gateway for serverless functions
- **External**: Google Maps/Calendar/Fit, Razorpay UPI, OpenWeatherMap
- **Local Services**: Ola/Uber APIs for ride-sharing, Indian transit APIs

## Testing Strategies

### Unit Testing Pattern
```dart
// test/services/ocr_service_test.dart
group('OCR Service Tests', () {
  test('should extract text from image', () async {
    final result = await ocrService.extractText(testImageBytes);
    expect(result, contains('expected text'));
  });
});
```

### Hardware Testing
- Serial monitoring for ESP32 debugging with timestamp logging
- Camera initialization verification before streaming
- BLE connection stability testing

### Performance Monitoring
```dart
class PerformanceMonitor {
  static void trackInference(String modelName, Duration duration) {
    FirebaseAnalytics.instance.logEvent(
      name: 'model_inference',
      parameters: {'model_name': modelName, 'duration_ms': duration.inMilliseconds}
    );
  }
}
```

## Critical Development Considerations

### Accessibility-First Design
- **Audio feedback**: Priority-based interruption system for urgent alerts
- **Haptic patterns**: Distinct vibration sequences for different alert types  
- **UI**: High contrast, large touch targets, screen reader compatibility

### Power Optimization
- **ESP32**: Deep sleep between captures, configurable wake triggers
- **Flutter**: Efficient image processing pipelines, background task management
- **Cloud**: Minimize API calls, cache frequently accessed data

### Indian Localization
- **Languages**: Hindi, English, regional language support for OCR/TTS
- **Services**: UPI integration, local transport APIs, cultural context awareness
- **Network**: Offline capability for core features, 2G/3G optimization

## Troubleshooting Quick Reference

### Common ESP32 Issues
- **Upload fails**: Ensure GPIO0→GND during programming, check USB connection
- **Camera init fails**: Verify 5V power supply, test cable connections
- **Wi-Fi issues**: Check network credentials, signal strength

### Flutter Issues  
- **Build failures**: `flutter clean && flutter pub get`, accept Android licenses
- **iOS issues**: `cd ios && pod install`, clean derived data
- **Performance**: Use `flutter run --profile` for optimization analysis

### Cloud Issues
- **Function deployment**: Verify GCP quotas, check IAM permissions  
- **Firestore errors**: Review security rules, test with emulator
- **Vision API**: Check API key validity, monitor usage quotas

## Project Context & Goals

This is a **Final Year Project** with 5-person team structure:
- Team Lead & AI Specialist
- Mobile Application Developer  
- Hardware & IoT Specialist
- Cloud & Backend Developer
- Project Manager & QA Lead

**Key Deliverables**: ESP32-CAM prototype, polished Flutter app, 2 perfected AI modules (OCR + Object Recognition), functional cloud endpoint demonstrating hybrid architecture.

**Documentation**: Always reference `PROJECT_SPEC.md` for complete context, `ARCHITECTURE.md` for technical details, `FEATURES.md` for implementation priorities, and `SETUP.md` for environment configuration.