import 'package:flutter/material.dart';
import 'package:lumisense/utils/theme.dart';
import 'package:lumisense/screens/splash_screen.dart';
import 'package:lumisense/screens/onboarding_screen.dart';
import 'package:lumisense/screens/home_screen.dart';
import 'package:lumisense/screens/caregiver_dashboard.dart';

void main() {
  runApp(const LumiSenseApp());
}

class LumiSenseApp extends StatelessWidget {
  const LumiSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LumiSense',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/home': (context) => const HomeScreen(),
        '/caregiver': (context) => const CaregiverDashboard(),
      },
    );
  }
}