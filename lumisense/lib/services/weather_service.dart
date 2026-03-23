import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Current weather conditions.
class WeatherInfo {
  const WeatherInfo({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.condition,
    required this.description,
    required this.windSpeed,
    required this.cityName,
    this.alerts = const <String>[],
  });

  final double temperature;
  final double feelsLike;
  final int humidity;
  final String condition; // e.g. "Rain", "Clear", "Clouds"
  final String description; // e.g. "light rain", "overcast clouds"
  final double windSpeed; // m/s
  final String cityName;
  final List<String> alerts;

  /// Human-readable, TTS-friendly weather summary.
  String get spokenSummary {
    final StringBuffer sb = StringBuffer();
    sb.write('Weather in $cityName: ');
    sb.write('${temperature.round()} degrees celsius, $description. ');
    sb.write('Feels like ${feelsLike.round()} degrees. ');
    sb.write('Humidity $humidity%. ');
    sb.write('Wind speed ${windSpeed.toStringAsFixed(1)} meters per second. ');

    // Add contextual safety alerts for visually impaired users.
    if (condition == 'Rain' || condition == 'Drizzle' || condition == 'Thunderstorm') {
      sb.write('Warning: Rain expected. Roads may be slippery. Carry an umbrella. ');
    }
    if (temperature > 40) {
      sb.write('Heat warning: It is extremely hot. Stay hydrated and avoid prolonged outdoor exposure. ');
    }
    if (temperature < 10) {
      sb.write('Cold weather alert. Dress warmly before going outside. ');
    }
    if (windSpeed > 10) {
      sb.write('Strong winds detected. Be cautious while walking. ');
    }
    if (condition == 'Fog' || condition == 'Mist' || condition == 'Haze') {
      sb.write('Low visibility conditions. Be extra cautious near roads. ');
    }

    for (final String alert in alerts) {
      sb.write('Alert: $alert. ');
    }

    return sb.toString();
  }
}

/// Fetches weather data from OpenWeatherMap API.
///
/// Uses the free tier (current weather endpoint). Requires an API key
/// from openweathermap.org.
class WeatherService {
  const WeatherService();

  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';
  static const Duration _timeout = Duration(seconds: 15);

  /// Fetches current weather at the given GPS position.
  ///
  /// [apiKey] is the OpenWeatherMap API key.
  /// Returns null on any error.
  Future<WeatherInfo?> getCurrentWeather({
    required String apiKey,
    required double latitude,
    required double longitude,
  }) async {
    if (apiKey.trim().isEmpty) return null;

    final Uri uri = Uri.parse(
      '$_baseUrl/weather?lat=$latitude&lon=$longitude'
      '&appid=$apiKey&units=metric',
    );

    try {
      final http.Response response =
          await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        debugPrint('WeatherService: HTTP ${response.statusCode}');
        return null;
      }

      return _parseCurrentWeather(response.body);
    } on TimeoutException {
      debugPrint('WeatherService: timeout');
      return null;
    } on SocketException {
      debugPrint('WeatherService: no internet');
      return null;
    } catch (e) {
      debugPrint('WeatherService: error: $e');
      return null;
    }
  }

  /// Fetches current weather using the device's GPS position.
  Future<WeatherInfo?> getCurrentWeatherByGps({
    required String apiKey,
  }) async {
    try {
      // Check if location services are enabled.
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('WeatherService: location services disabled');
        return null;
      }

      // Check permission.
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          debugPrint('WeatherService: location permission denied');
          return null;
        }
      }

      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low, // Low accuracy is fine for weather
          timeLimit: Duration(seconds: 10),
        ),
      );

      return getCurrentWeather(
        apiKey: apiKey,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    } catch (e) {
      debugPrint('WeatherService: GPS error: $e');
      return null;
    }
  }

  WeatherInfo? _parseCurrentWeather(String body) {
    try {
      final Map<String, dynamic> json =
          jsonDecode(body) as Map<String, dynamic>;

      final Map<String, dynamic> main =
          json['main'] as Map<String, dynamic>;
      final Map<String, dynamic> wind =
          json['wind'] as Map<String, dynamic>;
      final List<dynamic> weatherList =
          json['weather'] as List<dynamic>;

      if (weatherList.isEmpty) return null;

      final Map<String, dynamic> weather =
          weatherList.first as Map<String, dynamic>;

      return WeatherInfo(
        temperature: (main['temp'] as num).toDouble(),
        feelsLike: (main['feels_like'] as num).toDouble(),
        humidity: (main['humidity'] as num).toInt(),
        condition: weather['main'] as String? ?? 'Unknown',
        description: weather['description'] as String? ?? 'unknown',
        windSpeed: (wind['speed'] as num).toDouble(),
        cityName: json['name'] as String? ?? 'your location',
      );
    } catch (e) {
      debugPrint('WeatherService: parse error: $e');
      return null;
    }
  }
}
