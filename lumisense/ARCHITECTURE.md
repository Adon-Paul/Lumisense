# LumiSense Technical Architecture

## Overview

LumiSense employs a sophisticated three-tier distributed architecture designed for optimal performance, affordability, and scalability. This document details the technical implementation of each layer and their interactions.

## Architecture Diagram

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Edge Layer     │    │  Hub Layer      │    │  Cloud Layer    │
│  (Wearable)     │    │  (Smartphone)   │    │  (GCP Backend)  │
│                 │    │                 │    │                 │
│  ESP32-WROVER-E │◄──►│  Flutter App    │◄──►│  Cloud Functions│
│  OV5640 Camera  │    │  TensorFlow Lite│    │  Firestore DB   │
│  BLE + WiFi     │    │  Audio/Haptic   │    │  Vision APIs    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Layer 1: Edge (Wearable Hardware)

### Hardware Specifications

**System-on-Chip (SoC):**
- **Model:** ESP32-WROVER-E
- **CPU:** Dual-core Xtensa LX6 @ 240MHz
- **Memory:** 8MB PSRAM + 4MB Flash
- **Connectivity:** Wi-Fi 802.11b/g/n + Bluetooth 4.2/BLE

**Camera Module:**
- **Sensor:** OV5640 5MP CMOS
- **Resolution:** Up to 2592x1944 (5MP)
- **Video:** 1080p@30fps, 720p@60fps
- **Features:** Auto-focus, auto-exposure, white balance
- **Interface:** SCCB (I2C-like) control, DVP parallel data

**Form Factor:**
- **Design:** Lightweight, clip-on glasses attachment
- **Power:** Rechargeable Li-Po battery (estimated 6-8 hours continuous use)
- **Dimensions:** Approximately 40x25x15mm
- **Weight:** Under 30 grams

### Firmware Architecture

**Development Environment:**
- **Framework:** PlatformIO with Arduino Core for ESP32
- **Language:** C++17
- **Real-time OS:** FreeRTOS (built into ESP32)

**Core Components:**

1. **Camera Manager**
   ```cpp
   class CameraManager {
   private:
       camera_config_t config;
       camera_fb_t* frame_buffer;
   public:
       bool initialize();
       camera_fb_t* captureFrame();
       void startStream();
       void stopStream();
   };
   ```

2. **Communication Manager**
   ```cpp
   class CommManager {
   private:
       WiFiServer mjpeg_server;
       BLEServer* ble_server;
   public:
       void initWiFiStream();
       void initBLE();
       void sendStatus(DeviceStatus status);
       void receiveCommands();
   };
   ```

3. **Power Manager**
   ```cpp
   class PowerManager {
   public:
       void enterDeepSleep();
       void configureSleepWakeup();
       float getBatteryLevel();
       void optimizePowerConsumption();
   };
   ```

**Communication Protocols:**

1. **Video Streaming (Wi-Fi):**
   - **Protocol:** HTTP MJPEG Server
   - **Port:** 8080
   - **Quality:** Configurable (240p-1080p)
   - **Latency:** <100ms local network

2. **Control Channel (BLE):**
   - **Service UUID:** Custom LumiSense service
   - **Characteristics:** Command, Status, Configuration
   - **Range:** 10-15 meters typical
   - **Power:** Ultra-low energy consumption

## Layer 2: Hub (Mobile Application)

### Flutter Application Architecture

**Framework & Dependencies:**
- **Flutter SDK:** Latest stable (3.x+)
- **State Management:** Provider pattern with ChangeNotifier
- **Database:** SQLite with sqflite package
- **Networking:** http package for REST APIs
- **AI/ML:** tflite_flutter for TensorFlow Lite integration

**Core Application Structure:**

```
lib/
├── main.dart                 # Application entry point
├── models/                   # Data models
│   ├── user_profile.dart
│   ├── device_status.dart
│   └── ai_response.dart
├── services/                 # Business logic services
│   ├── camera_service.dart
│   ├── ai_inference_service.dart
│   ├── audio_service.dart
│   ├── haptic_service.dart
│   └── cloud_service.dart
├── providers/                # State management
│   ├── app_state_provider.dart
│   ├── device_provider.dart
│   └── user_provider.dart
├── screens/                  # UI screens
│   ├── home_screen.dart
│   ├── settings_screen.dart
│   └── training_screen.dart
├── widgets/                  # Reusable UI components
│   ├── status_indicator.dart
│   └── feature_toggle.dart
└── utils/                    # Utility functions
    ├── audio_utils.dart
    ├── haptic_utils.dart
    └── network_utils.dart
```

### AI/ML Pipeline

**On-Device Models (TensorFlow Lite):**

1. **Instant Text Reader (OCR)**
   ```dart
   class OCRService {
     late Interpreter _interpreter;
     
     Future<String> extractText(Uint8List imageBytes) async {
       // Preprocess image
       var input = preprocessImage(imageBytes);
       
       // Run inference
       var output = List.filled(1000, 0.0).reshape([1, 1000]);
       _interpreter.run(input, output);
       
       // Post-process and return text
       return postprocessOCR(output);
     }
   }
   ```

2. **Object Recognition**
   ```dart
   class ObjectDetectionService {
     late Interpreter _interpreter;
     
     Future<List<DetectedObject>> detectObjects(Uint8List imageBytes) async {
       var input = preprocessForDetection(imageBytes);
       var outputs = {
         0: Array.fill([1, 10, 4], 0.0), // Bounding boxes
         1: Array.fill([1, 10], 0.0),    // Confidence scores
         2: Array.fill([1, 10], 0.0),    // Class IDs
       };
       
       _interpreter.runForMultipleInputs([input], outputs);
       return parseDetectionResults(outputs);
     }
   }
   ```

**Performance Optimizations:**
- **Model Quantization:** INT8 quantization for 4x smaller models
- **GPU Acceleration:** Metal (iOS) / OpenGL (Android) delegates
- **Memory Management:** Efficient tensor reuse and garbage collection
- **Preprocessing Pipeline:** Optimized image scaling and normalization

### Audio & Haptic Feedback

**Audio Engine:**
```dart
class AudioService {
  late AudioPlayer _player;
  late SpeechToText _stt;
  late TextToSpeech _tts;
  
  Future<void> speakText(String text, {Priority priority = Priority.normal}) async {
    if (priority == Priority.urgent) {
      await _player.stop(); // Interrupt current audio
    }
    await _tts.speak(text);
  }
  
  Future<void> playNotificationSound(NotificationType type) async {
    String soundFile = getSoundForType(type);
    await _player.play(AssetSource(soundFile));
  }
}
```

**Haptic Patterns:**
```dart
class HapticService {
  static const Map<HapticType, List<int>> patterns = {
    HapticType.obstacle: [100, 50, 100, 50, 200],
    HapticType.dropOff: [300, 100, 300],
    HapticType.notification: [50, 25, 50],
  };
  
  Future<void> playPattern(HapticType type) async {
    List<int> pattern = patterns[type] ?? [100];
    for (int i = 0; i < pattern.length; i += 2) {
      if (i < pattern.length) {
        HapticFeedback.heavyImpact();
        await Future.delayed(Duration(milliseconds: pattern[i]));
      }
      if (i + 1 < pattern.length) {
        await Future.delayed(Duration(milliseconds: pattern[i + 1]));
      }
    }
  }
}
```

## Layer 3: Cloud (Backend Services)

### Google Cloud Platform Architecture

**Core Services:**
- **Compute:** Cloud Functions (Serverless)
- **Database:** Cloud Firestore (NoSQL)
- **Storage:** Cloud Storage for model files and user data
- **APIs:** Vision AI, Translation AI, Natural Language AI
- **Networking:** Cloud Load Balancing, Cloud CDN

**Cloud Functions Structure:**

```python
# main.py - Primary cloud function entry point
import functions_framework
from google.cloud import firestore
from google.cloud import vision
import tensorflow as tf

@functions_framework.http
def process_complex_scene(request):
    """
    Process complex scene analysis using Vision-Language Models
    """
    # Extract image from request
    image_data = request.get_json()['image']
    user_id = request.get_json()['user_id']
    
    # Initialize services
    vision_client = vision.ImageAnnotatorClient()
    db = firestore.Client()
    
    # Perform comprehensive scene analysis
    result = analyze_scene_with_context(
        image_data, 
        user_id, 
        vision_client, 
        db
    )
    
    return {'analysis': result, 'timestamp': firestore.SERVER_TIMESTAMP}

def analyze_scene_with_context(image_data, user_id, vision_client, db):
    """
    Perform context-aware scene analysis
    """
    # Get user preferences and history
    user_doc = db.collection('users').document(user_id).get()
    user_context = user_doc.to_dict()
    
    # Vision API analysis
    image = vision.Image(content=image_data)
    
    # Multiple analysis types
    objects = vision_client.object_localization(image=image)
    text = vision_client.text_detection(image=image)
    landmarks = vision_client.landmark_detection(image=image)
    
    # Combine results with user context
    comprehensive_analysis = combine_analysis_results(
        objects, text, landmarks, user_context
    )
    
    return comprehensive_analysis
```

### Database Schema (Firestore)

```javascript
// Users Collection
users/{userId} {
  profile: {
    name: string,
    preferences: {
      audioSpeed: number,
      hapticIntensity: number,
      privacyMode: boolean
    },
    accessibility: {
      visionLevel: string, // "none", "low", "partial"
      assistanceLevel: string // "minimal", "moderate", "comprehensive"
    }
  },
  devices: {
    wearableId: string,
    phoneModel: string,
    lastSync: timestamp
  },
  history: {
    interactions: array,
    emergencyContacts: array
  }
}

// Sessions Collection  
sessions/{sessionId} {
  userId: string,
  startTime: timestamp,
  endTime: timestamp,
  activities: [
    {
      type: string, // "navigation", "reading", "object_recognition"
      timestamp: timestamp,
      result: object,
      confidence: number
    }
  ],
  analytics: {
    featuresUsed: array,
    responseTime: number,
    userSatisfaction: number
  }
}

// Emergency Collection
emergencies/{emergencyId} {
  userId: string,
  timestamp: timestamp,
  location: geopoint,
  type: string, // "fall", "panic", "medical"
  status: string, // "active", "resolved", "false_alarm"
  responders: [
    {
      contactId: string,
      notified: boolean,
      responded: boolean
    }
  ]
}
```

### API Gateway Configuration

**REST API Endpoints:**

```yaml
# api-gateway.yaml
swagger: "2.0"
info:
  title: LumiSense API
  version: "1.0.0"
host: api.lumisense.app
basePath: /v1

paths:
  /scene/analyze:
    post:
      summary: Analyze complex scene
      parameters:
        - name: image
          in: body
          required: true
          schema:
            type: object
            properties:
              image_data: {type: string, format: base64}
              user_id: {type: string}
              context: {type: object}
      responses:
        200:
          description: Scene analysis result
  
  /emergency/trigger:
    post:
      summary: Trigger emergency response
      parameters:
        - name: emergency
          in: body
          required: true
          schema:
            type: object
            properties:
              user_id: {type: string}
              type: {type: string}
              location: {type: object}
      responses:
        200:
          description: Emergency response initiated
```

## Inter-Layer Communication

### Edge ↔ Hub Communication

**Video Streaming Protocol:**
```cpp
// ESP32 MJPEG Server Implementation
void handleJPGStream() {
  WiFiClient client = server.available();
  if (client) {
    String response = "HTTP/1.1 200 OK\r\n";
    response += "Content-Type: multipart/x-mixed-replace; boundary=frame\r\n\r\n";
    client.print(response);
    
    while (client.connected()) {
      camera_fb_t * fb = esp_camera_fb_get();
      if (fb) {
        client.print("--frame\r\n");
        client.print("Content-Type: image/jpeg\r\nContent-Length: " + String(fb->len) + "\r\n\r\n");
        client.write(fb->buf, fb->len);
        client.print("\r\n");
        esp_camera_fb_return(fb);
      }
      delay(16); // ~60 FPS
    }
  }
}
```

**BLE Command Protocol:**
```dart
// Flutter BLE Communication
class BLEService {
  static const String SERVICE_UUID = "12345678-1234-1234-1234-123456789abc";
  static const String COMMAND_CHAR = "12345678-1234-1234-1234-123456789abd";
  static const String STATUS_CHAR = "12345678-1234-1234-1234-123456789abe";
  
  Future<void> sendCommand(DeviceCommand command) async {
    BluetoothCharacteristic characteristic = await getCharacteristic(COMMAND_CHAR);
    List<int> commandBytes = command.toBytes();
    await characteristic.write(commandBytes);
  }
  
  Stream<DeviceStatus> getStatusStream() async* {
    BluetoothCharacteristic characteristic = await getCharacteristic(STATUS_CHAR);
    await characteristic.setNotifyValue(true);
    
    await for (List<int> data in characteristic.value) {
      yield DeviceStatus.fromBytes(data);
    }
  }
}
```

### Hub ↔ Cloud Communication

**Secure API Communication:**
```dart
// Authenticated cloud requests
class CloudService {
  static const String BASE_URL = 'https://api.lumisense.app/v1';
  
  Future<SceneAnalysis> analyzeScene(
    Uint8List imageData, 
    SceneContext context
  ) async {
    String token = await FirebaseAuth.instance.currentUser?.getIdToken() ?? '';
    
    var request = http.MultipartRequest('POST', Uri.parse('$BASE_URL/scene/analyze'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes(
      'image', 
      imageData,
      filename: 'scene.jpg'
    ));
    request.fields['context'] = jsonEncode(context.toJson());
    
    var response = await request.send();
    var responseBody = await response.stream.bytesToString();
    
    return SceneAnalysis.fromJson(jsonDecode(responseBody));
  }
}
```

## Performance & Scalability

### Performance Targets

**Latency Requirements:**
- **On-device inference:** <200ms
- **Edge to Hub communication:** <100ms
- **Cloud round-trip:** <2 seconds
- **Audio feedback delay:** <300ms total

**Throughput Specifications:**
- **Video streaming:** 30 FPS @ 720p
- **Concurrent users (cloud):** 1000+ with auto-scaling
- **API requests:** 100 req/sec per function

### Monitoring & Analytics

**Performance Monitoring:**
```dart
class PerformanceMonitor {
  static void trackInference(String modelName, Duration duration) {
    FirebaseAnalytics.instance.logEvent(
      name: 'model_inference',
      parameters: {
        'model_name': modelName,
        'duration_ms': duration.inMilliseconds,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }
  
  static void trackUserInteraction(String feature, bool success) {
    FirebaseAnalytics.instance.logEvent(
      name: 'feature_usage',
      parameters: {
        'feature': feature,
        'success': success,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }
}
```

This architecture ensures optimal performance, maintainability, and scalability while keeping costs minimal through efficient resource utilization and cloud service optimization.