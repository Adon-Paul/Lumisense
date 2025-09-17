# LumiSense Development Setup Guide

This guide will help you set up the development environment for the LumiSense project, including all necessary tools, dependencies, and configurations for the three-tier architecture.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Flutter Mobile App Setup](#flutter-mobile-app-setup)
3. [ESP32 Hardware Development Setup](#esp32-hardware-development-setup)
4. [Google Cloud Platform Setup](#google-cloud-platform-setup)
5. [Development Workflow](#development-workflow)
6. [Testing & Debugging](#testing--debugging)
7. [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

**Operating System:**
- Windows 10/11 (Primary development environment)
- macOS 10.14+ (For iOS development)
- Linux Ubuntu 18.04+ (Alternative)

**Hardware Requirements:**
- RAM: 8GB minimum, 16GB recommended
- Storage: 50GB free space
- USB ports for ESP32 development
- Android device or iOS device for testing

### Required Accounts

1. **Google Account** - For GCP services and Firebase
2. **GitHub Account** - For version control and collaboration
3. **Razorpay Account** - For payment integration (testing)

## Flutter Mobile App Setup

### 1. Install Flutter SDK

**Windows:**
```powershell
# Download Flutter SDK
Invoke-WebRequest -Uri "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_stable.zip" -OutFile "flutter_windows_stable.zip"

# Extract to C:\flutter
Expand-Archive flutter_windows_stable.zip C:\

# Add to PATH
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\flutter\bin", "User")
```

**macOS/Linux:**
```bash
# Download and extract Flutter
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:`pwd`/flutter/bin"

# Add to shell profile
echo 'export PATH="$PATH:[PATH_TO_FLUTTER_GIT_DIRECTORY]/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
```

### 2. Verify Flutter Installation

```bash
flutter doctor
```

Expected output should show no critical issues. Install any missing dependencies as suggested.

### 3. Configure IDEs

**VS Code (Recommended):**
```bash
# Install Flutter and Dart extensions
code --install-extension Dart-Code.flutter
code --install-extension Dart-Code.dart-code
```

**Android Studio:**
- Install Flutter and Dart plugins
- Configure Android SDK (API level 21+)
- Set up Android Virtual Device (AVD)

### 4. Project Dependencies

Navigate to the project directory and install dependencies:

```bash
cd lumisense
flutter pub get
```

### 5. Platform-Specific Setup

**Android:**
- Install Android Studio
- Accept Android licenses: `flutter doctor --android-licenses`
- Connect Android device or start emulator

**iOS (macOS only):**
- Install Xcode from App Store
- Install CocoaPods: `sudo gem install cocoapods`
- Run: `cd ios && pod install`

## ESP32 Hardware Development Setup

### 1. Install PlatformIO

**VS Code Extension:**
```bash
code --install-extension platformio.platformio-ide
```

**Standalone CLI:**
```bash
# Windows (using pip)
pip install platformio

# macOS (using Homebrew)
brew install platformio

# Linux (using pip)
pip3 install platformio
```

### 2. Hardware Requirements

**ESP32 Development Board:**
- ESP32-WROVER-E or ESP32-CAM module
- USB-to-Serial programmer (if not built-in)
- Breadboard and jumper wires
- 5MP camera module (OV5640 recommended)

**Connections:**
```
ESP32-CAM Pinout:
- VCC: 5V
- GND: Ground
- U0T: GPIO1 (TX)
- U0R: GPIO3 (RX)
- GPIO0: Programming mode (connect to GND during upload)
```

### 3. PlatformIO Project Configuration

Create `platformio.ini` in the hardware directory:

```ini
[env:esp32cam]
platform = espressif32
board = esp32cam
framework = arduino
monitor_speed = 115200
upload_speed = 921600

lib_deps = 
    esp32-camera
    WiFi
    BluetoothSerial
    ArduinoJson

build_flags = 
    -DCORE_DEBUG_LEVEL=3
    -DBOARD_HAS_PSRAM

monitor_filters = esp32_exception_decoder
```

### 4. Test Hardware Setup

```cpp
// test_camera.cpp
#include "esp_camera.h"
#include "WiFi.h"

void setup() {
    Serial.begin(115200);
    
    // Initialize camera
    camera_config_t config;
    config.ledc_channel = LEDC_CHANNEL_0;
    config.ledc_timer = LEDC_TIMER_0;
    config.pin_d0 = 5;
    config.pin_d1 = 18;
    // ... additional pin configurations
    
    if (esp_camera_init(&config) != ESP_OK) {
        Serial.println("Camera init failed");
        return;
    }
    
    Serial.println("Camera initialized successfully");
}

void loop() {
    camera_fb_t * fb = esp_camera_fb_get();
    if (fb) {
        Serial.printf("Image size: %d bytes\n", fb->len);
        esp_camera_fb_return(fb);
    }
    delay(1000);
}
```

## Google Cloud Platform Setup

### 1. Create GCP Project

```bash
# Install Google Cloud CLI
# Windows: Download from https://cloud.google.com/sdk/docs/install
# macOS: brew install google-cloud-sdk
# Linux: Follow official documentation

# Initialize gcloud
gcloud init

# Create new project
gcloud projects create lumisense-project --name="LumiSense"

# Set project as default
gcloud config set project lumisense-project
```

### 2. Enable Required APIs

```bash
# Enable necessary APIs
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable firestore.googleapis.com
gcloud services enable vision.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable apigateway.googleapis.com
```

### 3. Set Up Firebase

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize Firebase in project
firebase init

# Select:
# - Firestore
# - Functions
# - Storage
# - Hosting (optional)
```

### 4. Create Service Account

```bash
# Create service account
gcloud iam service-accounts create lumisense-service \
    --display-name="LumiSense Service Account"

# Generate key file
gcloud iam service-accounts keys create credentials.json \
    --iam-account=lumisense-service@lumisense-project.iam.gserviceaccount.com

# Set environment variable
export GOOGLE_APPLICATION_CREDENTIALS="./credentials.json"
```

### 5. Deploy Cloud Functions

Create `functions/main.py`:

```python
import functions_framework
from google.cloud import firestore
from google.cloud import vision

@functions_framework.http
def analyze_scene(request):
    """HTTP Cloud Function for scene analysis"""
    
    # Enable CORS
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Process scene analysis request
    try:
        request_json = request.get_json()
        image_data = request_json.get('image')
        user_id = request_json.get('user_id')
        
        # Initialize services
        vision_client = vision.ImageAnnotatorClient()
        db = firestore.Client()
        
        # Perform analysis
        # ... implementation details
        
        return {'status': 'success', 'analysis': 'Scene analysis result'}
        
    except Exception as e:
        return {'status': 'error', 'message': str(e)}, 500
```

Deploy function:
```bash
cd functions
gcloud functions deploy analyze-scene \
    --runtime python39 \
    --trigger-http \
    --allow-unauthenticated
```

## Development Workflow

### 1. Project Structure

```
lumisense/
├── lib/                    # Flutter app source
│   ├── main.dart
│   ├── models/
│   ├── services/
│   ├── providers/
│   ├── screens/
│   └── widgets/
├── hardware/               # ESP32 firmware
│   ├── src/
│   ├── lib/
│   └── platformio.ini
├── cloud/                  # GCP functions
│   ├── functions/
│   ├── firestore.rules
│   └── firebase.json
├── docs/                   # Documentation
├── test/                   # Flutter tests
└── integration_test/       # E2E tests
```

### 2. Version Control

```bash
# Clone repository
git clone https://github.com/Adon-Paul/Lumisense.git
cd Lumisense

# Create feature branch
git checkout -b feature/obstacle-detection

# Make changes and commit
git add .
git commit -m "feat: implement obstacle detection algorithm"

# Push to remote
git push origin feature/obstacle-detection

# Create pull request on GitHub
```

### 3. Development Commands

**Flutter App:**
```bash
# Run app in debug mode
flutter run

# Run on specific device
flutter run -d <device-id>

# Build for release
flutter build apk --release

# Run tests
flutter test

# Analyze code
flutter analyze
```

**ESP32 Firmware:**
```bash
# Build firmware
pio run

# Upload to device
pio run --target upload

# Monitor serial output
pio device monitor

# Clean build
pio run --target clean
```

**Cloud Functions:**
```bash
# Deploy all functions
firebase deploy --only functions

# Deploy specific function
firebase deploy --only functions:analyzeScene

# View logs
firebase functions:log
```

## Testing & Debugging

### 1. Flutter App Testing

**Unit Tests:**
```dart
// test/services/ocr_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lumisense/services/ocr_service.dart';

void main() {
  group('OCR Service Tests', () {
    test('should extract text from image', () async {
      final ocrService = OCRService();
      final result = await ocrService.extractText(testImageBytes);
      expect(result, contains('expected text'));
    });
  });
}
```

**Widget Tests:**
```dart
// test/widgets/status_indicator_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumisense/widgets/status_indicator.dart';

void main() {
  testWidgets('StatusIndicator displays correct status', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StatusIndicator(status: DeviceStatus.connected),
      ),
    );
    
    expect(find.text('Connected'), findsOneWidget);
  });
}
```

### 2. Hardware Testing

**Serial Monitor Setup:**
```cpp
// Add debug output to firmware
void debugPrint(String message) {
  Serial.print("[DEBUG] ");
  Serial.print(millis());
  Serial.print(": ");
  Serial.println(message);
}
```

**Camera Test Procedure:**
1. Upload test firmware
2. Monitor serial output
3. Verify camera initialization
4. Check image capture functionality
5. Test Wi-Fi connectivity

### 3. Cloud Function Testing

**Local Testing:**
```bash
# Install Functions Framework
pip install functions-framework

# Run function locally
functions-framework --target=analyze_scene --debug
```

**Unit Tests:**
```python
# test_functions.py
import pytest
from unittest.mock import Mock
from main import analyze_scene

def test_analyze_scene():
    # Mock request object
    request = Mock()
    request.get_json.return_value = {
        'image': 'base64_image_data',
        'user_id': 'test_user'
    }
    
    # Test function
    result = analyze_scene(request)
    assert result['status'] == 'success'
```

## Troubleshooting

### Common Flutter Issues

**Issue: Flutter doctor shows Android license issues**
```bash
# Solution: Accept Android licenses
flutter doctor --android-licenses
```

**Issue: iOS build fails**
```bash
# Solution: Clean and rebuild
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
flutter clean
flutter build ios
```

### Common ESP32 Issues

**Issue: Upload failed**
- Ensure GPIO0 is connected to GND during upload
- Check USB cable connection
- Verify correct board selection in PlatformIO

**Issue: Camera initialization failed**
- Check camera module connections
- Verify power supply (5V for ESP32-CAM)
- Test with known working camera module

### Common Cloud Issues

**Issue: Functions deployment fails**
```bash
# Check quotas and permissions
gcloud auth list
gcloud projects get-iam-policy lumisense-project
```

**Issue: Firestore permission denied**
- Check security rules
- Verify authentication token
- Test with Firebase emulator

### Performance Optimization

**Flutter App:**
- Use `const` constructors for widgets
- Implement lazy loading for lists
- Optimize image loading and caching
- Profile with `flutter run --profile`

**ESP32 Firmware:**
- Optimize camera settings for performance
- Implement efficient power management
- Use appropriate task priorities in FreeRTOS

**Cloud Functions:**
- Minimize cold starts with warm-up requests
- Optimize memory allocation
- Use connection pooling for database connections

## Environment Variables

Create `.env` files for different environments:

**Flutter (.env):**
```
FIREBASE_PROJECT_ID=lumisense-project
RAZORPAY_KEY_ID=your_razorpay_key
OPENWEATHER_API_KEY=your_openweather_key
DEBUG_MODE=true
```

**Cloud Functions (.env):**
```
GOOGLE_CLOUD_PROJECT=lumisense-project
FIRESTORE_EMULATOR_HOST=localhost:8080
VISION_API_ENDPOINT=https://vision.googleapis.com/v1
```

## Continuous Integration

Set up GitHub Actions for automated testing:

```yaml
# .github/workflows/flutter.yml
name: Flutter CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.0.0'
    - run: flutter pub get
    - run: flutter test
    - run: flutter analyze
    - run: flutter build apk --debug
```

This setup guide provides a comprehensive foundation for developing the LumiSense project across all three tiers of the architecture. Follow the sections relevant to your role in the development team.