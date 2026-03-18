import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lumisense/providers/app_state.dart';
import 'package:lumisense/providers/settings_provider.dart';
import 'package:lumisense/screens/camera_screen.dart';
import 'package:lumisense/screens/caregiver_dashboard.dart';
import 'package:lumisense/screens/home_screen.dart';
import 'package:lumisense/screens/onboarding_screen.dart';
import 'package:lumisense/screens/splash_screen.dart';
import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Global error handlers ──────────────────────────────────────────────────
  // Catch all Flutter framework errors (widget build failures, etc.) and log
  // them instead of crashing silently. For a visually impaired user a crash
  // leaves no audio feedback — graceful degradation is always preferable.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}\n${details.stack}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PlatformDispatcher error: $error\n$stack');
    return true; // Handled — prevent crash.
  };

  // ── Pre-load SharedPreferences ────────────────────────────────────────────
  // Loading here (before runApp) means SettingsProvider can read persisted
  // values synchronously in its constructor — no FutureBuilder needed.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // ── Initialise services ───────────────────────────────────────────────────
  await _initializeServices();

  // ── Run app ───────────────────────────────────────────────────────────────
  runApp(
    MultiProvider(
      providers: [
        // TtsService is exposed as a plain Provider so the DI container
        // manages its lifetime and can call dispose() automatically.
        Provider<TtsService>(
          create: (_) => TtsService(),
          dispose: (_, svc) => svc.dispose(),
        ),

        // SharedPreferences instance shared across providers.
        Provider<SharedPreferences>.value(value: prefs),

        // Secure storage for sensitive values (e.g. Gemini API key).
        Provider<FlutterSecureStorage>(
          create: (_) => const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          ),
        ),

        // SettingsProvider receives TtsService so speech-rate / volume /
        // pitch changes are immediately forwarded to the engine.
        ChangeNotifierProxyProvider3<TtsService, SharedPreferences,
            FlutterSecureStorage, SettingsProvider>(
          create: (ctx) => SettingsProvider(
            prefs: ctx.read<SharedPreferences>(),
            tts: ctx.read<TtsService>(),
            secureStorage: ctx.read<FlutterSecureStorage>(),
          ),
          update: (_, __, ___, ____, previous) => previous!,
        ),

        ChangeNotifierProvider<AppStateProvider>(
          create: (_) => AppStateProvider(),
        ),
      ],
      child: const LumiSenseApp(),
    ),
  );
}

/// Initialises shared services before the widget tree starts.
///
/// TTS failure is caught and logged rather than crashing — the app runs in
/// degraded (silent) mode instead of presenting a blank screen to the user.
Future<void> _initializeServices() async {
  try {
    await TtsService().init();
  } catch (e, stack) {
    // TTS unavailable (no engine installed, permissions denied, etc.).
    // The app continues without audio output.
    debugPrint('TtsService init failed — running in silent mode: $e\n$stack');
  }
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
        '/caregiver': (_) => const CaregiverDashboard(),
      },
    );
  }
}
