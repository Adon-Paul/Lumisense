import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'package:lumisense/providers/app_state.dart';
import 'package:lumisense/providers/history_provider.dart';
import 'package:lumisense/providers/settings_provider.dart';
import 'package:lumisense/screens/camera_screen.dart';
import 'package:lumisense/screens/caregiver_dashboard.dart';
import 'package:lumisense/screens/history_screen.dart';
import 'package:lumisense/screens/home_screen.dart';
import 'package:lumisense/screens/onboarding_screen.dart';
import 'package:lumisense/screens/settings_screen.dart';
import 'package:lumisense/screens/splash_screen.dart';
import 'package:lumisense/services/model_manager.dart';
import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error handlers ──────────────────────────────────────────────
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    return true;
  };

  // ── Pre-load SharedPreferences ────────────────────────────────────────
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // ── Run app ───────────────────────────────────────────────────────────
  runApp(
    MultiProvider(
      providers: [
        Provider<TtsService>(
          create: (_) {
            final TtsService tts = TtsService();
            unawaited(
              tts.init().catchError((Object error, StackTrace stack) {
                debugPrint('TtsService init failed — running in silent mode: $error\n$stack');
              }),
            );
            return tts;
          },
          dispose: (_, svc) => svc.dispose(),
        ),

        Provider<SharedPreferences>.value(value: prefs),

        Provider<FlutterSecureStorage>(
          create: (_) => const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          ),
        ),

        // SettingsProvider bridges TTS engine + persistent storage.
        ChangeNotifierProvider<SettingsProvider>(
          create: (ctx) {
            final SettingsProvider provider = SettingsProvider(
              prefs: ctx.read<SharedPreferences>(),
              tts: ctx.read<TtsService>(),
              secureStorage: ctx.read<FlutterSecureStorage>(),
            );
            unawaited(provider.loadApiKey());
            return provider;
          },
        ),

        ChangeNotifierProvider<AppStateProvider>(
          create: (_) => AppStateProvider(),
        ),

        ChangeNotifierProvider<HistoryProvider>(
          create: (ctx) => HistoryProvider(
            prefs: ctx.read<SharedPreferences>(),
          ),
        ),

        // On-device model manager (download, cache, lifecycle).
        Provider<ModelManager>(
          create: (_) => ModelManager(),
          dispose: (_, mgr) => mgr.dispose(),
        ),
      ],
      child: const LumiSenseApp(),
    ),
  );
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
        '/onboarding': (_) => const OnboardingScreen(),
        '/home': (_) => const HomeScreen(),
        '/camera': (_) => const CameraScreen(),
        '/history': (_) => const HistoryScreen(),
        '/caregiver': (_) => const CaregiverDashboard(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
