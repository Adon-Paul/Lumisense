# Project LumiSense - Master Context & System Specification

**Document Version:** 1.0  
**Date Compiled:** August 2, 2025  
**Project Status:** Final Year Project Proposal (Zeroth Review Stage)  
**Core Vision:** To develop a proactive AI co-pilot for the visually impaired that is affordable, scalable, and deeply integrated with the user's life and the Indian digital ecosystem.

## Section 1: Core Philosophy & Unique Value Proposition

### 1.1. Project Name: LumiSense

### 1.2. Core Concept
A hybrid AI system that uses a simple, low-cost wearable camera module, leverages the user's smartphone as the primary processing "brain," and connects to a cloud backend for complex tasks. Feedback is delivered through audio and haptics.

### 1.3. Unique Differentiators (vs. OrCam, etc.)

**Proactive, Not Reactive:** Integrates with personal data (Calendar, Health) to anticipate user needs, rather than just describing what it sees on command.

**Software-First & Affordable:** The "smartphone-centric" architecture drastically reduces hardware costs, making it accessible. The platform's intelligence is in the software, allowing for continuous updates.

**Deeply Localized (India Focus):** Built to integrate with the Indian digital ecosystem, including UPI payments (Razorpay), local ride-sharing (Ola/Uber), and public transit.

**Complete Support Network:** Features like "Caregiver Connect" extend the system's benefits to the user's family, providing a shared safety net.

## Section 2: Final Feature Set (Version 2.3)

### Tier 1: Essential Navigational & Safety Features
- **1.1:** Real-Time Obstacle Detection
- **1.2:** Drop-Off & Curb Detection
- **1.3:** Path Quality Assessment
- **1.4:** Head-Level Obstacle Warning
- **1.5:** Ambient Light Detection

### Tier 2: Information & Object Interaction
- **2.1:** Instant Text Reader (OCR)
- **2.2:** Power Reading Mode
- **2.3:** Object Identification
- **2.4:** "Find My Stuff" Mode (Personalized Object Recognition)
- **2.5:** Live Language Translator

### Tier 3: Advanced Scene & Social Understanding
- **3.1:** Conversational Scene Description (via Cloud VLM)
- **3.2:** Personalized Facial Recognition (Opt-in)
- **3.3:** Discreet Mode (Haptics-only for social situations)

### Tier 4: Integrated Services & Connectivity
- **4.1:** Smart UPI Payments (via Razorpay API)
- **4.2:** Ride-Sharing Assistant
- **4.3:** Public Transit Navigator
- **4.4:** Enhanced SOS & Emergency Response Mechanism
- **4.5:** Caregiver Connect (Remote View & Assistance)

### Tier 5: User Experience & System Management
- **5.1:** Training & Gamification Module
- **5.2:** Smart Power Management (with Deep Sleep Mode)
- **5.3:** Dirty Lens & Obstruction Warning

### Tier 6: Proactive Assistance & Personalization
- **6.1:** Google Calendar Integration
- **6.2:** Google Fit Integration
- **6.3:** Proactive Weather Alerts

### Tier 7: Health & Wellness
- **7.1:** Comprehensive Medication Manager

## Section 3: Detailed Technical Architecture & Stack

### 3.1. System Architecture
A three-tier distributed model: Edge (Wearable), Hub (Smartphone), and Cloud (Backend).

### 3.2. Wearable Hardware Module ("The Edge")
- **SoC:** ESP32-WROVER-E (with 8MB PSRAM)
- **Camera:** OV5640 5MP sensor
- **Firmware Language:** C++ (in PlatformIO)
- **Communication:** Streams video via a local Wi-Fi MJPEG server; receives commands and sends status via Bluetooth Low Energy (BLE).

### 3.3. Mobile Application ("The Hub")
- **Framework:** Flutter
- **Language:** Dart
- **On-Device AI:** TensorFlow Lite
- **Function:** Acts as the primary "brain," running all real-time AI models, managing the UI, and serving as a secure gateway to the cloud.

### 3.4. Cloud Backend
- **Provider:** Google Cloud Platform (GCP)
- **Architecture:** Serverless (Cloud Functions)
- **Language:** Python
- **Database:** Cloud Firestore (NoSQL)
- **Function:** Hosts large Vision-Language Models for complex, non-real-time analysis and manages all user data. Operates within the free tier for project scale.

### 3.5. API Integrations
- **Internal:** A REST API built with GCP API Gateway.
- **External:** Google APIs (Maps, Calendar, Fit), Razorpay (for UPI), OpenWeatherMap.

## Section 4: Project Plan & Scope (Final Year Project)

### 4.1. Project Goal
To build a robust proof-of-concept that validates the core architecture.

### 4.2. Team Structure
A 5-person team with defined roles:
- Team Lead & AI Specialist
- Mobile Application Developer
- Hardware & IoT Specialist
- Cloud & Backend Developer
- Project Manager & QA Lead

### 4.3. Key Deliverables
- A functional ESP32-CAM based wearable prototype.
- A polished Flutter mobile application.
- Two perfected on-device AI modules: Instant Text Reader (OCR) and General Object Recognition.
- One functional cloud endpoint to demonstrate the hybrid architecture.

### 4.4. Project Timeline (Gantt Chart Summary)
An 8-month plan divided into four phases:

- **Phase 1 (Months 1-2):** Research & Design
- **Phase 2 (Months 3-5):** Core Module Development
- **Phase 3 (Months 6-7):** Integration & Testing
- **Phase 4 (Month 8):** Finalization & Delivery

## Section 5: Budget & Cost Analysis (Prototype Stage)

### 5.1. Hardware Cost
Estimated at ~₹4,000 per prototype. A budget of ₹8,000 is recommended for the team to build two units. This equates to a manageable ₹1,600 per team member.

### 5.2. Software & Services Cost
₹0. This is achieved by using open-source software (Flutter, TensorFlow) and by operating entirely within the generous free tiers of cloud platforms like GCP. Billing alerts must be set up as a mandatory safety measure.

## Section 6: Startup Potential & Strategy (Post-Project)

### 6.1. Potential
The concept has very high potential due to the massive, underserved market and a strong, recurring revenue model. However, the risk is also extremely high.

### 6.2. Key Risks
The "Hardware Trap" (manufacturing is difficult), competition from free apps (Microsoft Seeing AI), and a complex go-to-market strategy.

### 6.3. Strategic Path Forward

**Launch an App First:** Do not start with hardware. Launch a software-only "LumiSense AI" app.

**Dominate a Niche:** Focus initially on solving one critical problem brilliantly. The strongest starting niche is the combination of the Medication Manager (Tier 7) and Caregiver Connect (Tier 4.5).

**Build a Community:** Work directly with the visually impaired community in India from day one. Their trust and feedback are the most valuable assets.

**Introduce Hardware Later:** Once the software has proven its value and has a loyal user base, introduce a low-cost wearable as an optional, premium accessory.

---

*This document contains a complete, refined, and structured summary of the LumiSense project. It serves as the master context for understanding the project in its entirety.*