# Lumisense
Final Year Project


# LumiSense 🌟

**A Proactive AI Co-Pilot for the Visually Impaired**

LumiSense is an innovative AI-powered navigation and assistance system designed specifically for the visually impaired community. Unlike reactive systems that only respond to commands, LumiSense proactively anticipates user needs and provides intelligent assistance throughout daily activities.

## 🎯 Vision

To develop a proactive AI co-pilot for the visually impaired that is affordable, scalable, and deeply integrated with the user's life and the Indian digital ecosystem.

## ✨ Key Features

### Tier 1: Essential Navigation & Safety
- Real-time obstacle detection and path quality assessment
- Drop-off & curb detection with head-level obstacle warnings
- Ambient light detection for optimal guidance

### Tier 2: Information & Object Interaction  
- Instant text reader with advanced OCR capabilities
- Intelligent object identification and personalized recognition
- Live language translation for multilingual support

### Tier 3: Advanced Scene Understanding
- Conversational scene descriptions via cloud Vision-Language Models
- Personalized facial recognition (opt-in) for social interactions
- Discreet haptic-only mode for sensitive situations

### Tier 4: Integrated Services
- Smart UPI payments integration (Razorpay API)
- Ride-sharing assistant for Ola/Uber bookings
- Public transit navigation with real-time updates
- Enhanced SOS & emergency response with caregiver connectivity

### Tier 5: User Experience
- Gamified training modules for skill development
- Smart power management with deep sleep optimization
- Intelligent lens obstruction detection and warnings

### Tier 6: Proactive Intelligence
- Google Calendar integration for schedule awareness
- Google Fit integration for health monitoring
- Proactive weather alerts and recommendations

### Tier 7: Health & Wellness
- Comprehensive medication management system

## 🏗️ Technical Architecture

LumiSense uses a sophisticated three-tier distributed architecture:

### Edge Layer (Wearable Hardware)
- **SoC**: ESP32-WROVER-E with 8MB PSRAM
- **Camera**: OV5640 5MP sensor
- **Communication**: Wi-Fi MJPEG streaming + Bluetooth Low Energy
- **Firmware**: C++ with PlatformIO

### Hub Layer (Mobile Application)
- **Framework**: Flutter with Dart
- **AI Processing**: TensorFlow Lite for on-device inference
- **Role**: Primary processing "brain" and secure cloud gateway

### Cloud Layer (Backend Services)
- **Platform**: Google Cloud Platform (GCP)
- **Architecture**: Serverless with Cloud Functions
- **Language**: Python
- **Database**: Cloud Firestore
- **APIs**: Google Maps, Calendar, Fit, Razorpay, OpenWeatherMap

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (latest stable version)
- Android Studio / VS Code with Flutter extensions
- Git for version control

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/Adon-Paul/Lumisense.git
   cd lumisense
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the application**
   ```bash
   flutter run
   ```

For detailed setup instructions, see [SETUP.md](SETUP.md).

## 📚 Documentation

- [Project Specification](PROJECT_SPEC.md) - Complete system specification and master context
- [Technical Architecture](ARCHITECTURE.md) - Detailed technical design and implementation
- [Features Documentation](FEATURES.md) - Comprehensive feature breakdown
- [Development Setup](SETUP.md) - Environment setup and development guidelines

## 🤝 Contributing

This is a Final Year Project developed by a 5-person team:
- Team Lead & AI Specialist
- Mobile Application Developer  
- Hardware & IoT Specialist
- Cloud & Backend Developer
- Project Manager & QA Lead

## 🌍 Impact & Vision

LumiSense aims to bridge the accessibility gap in the Indian digital ecosystem by:
- Providing affordable, smartphone-centric architecture
- Deep integration with local services (UPI, Ola/Uber, public transit)
- Building a comprehensive support network for users and caregivers
- Focusing on proactive assistance rather than reactive responses

## 📄 License

This project is part of a Final Year academic project. All rights reserved.

## 📞 Contact

For questions or collaboration opportunities, please reach out through the project repository.
