import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/notifications/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureSystemUi();
  // Registers the background message handler — must happen before runApp.
  // Safe to call even before this Firebase project has been configured (see
  // PushNotificationService.initializeFirebase); never throws.
  await PushNotificationService.initializeFirebase();
  // Load persisted preferences (selected theme) before the first frame.
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    prefs = null; // fall back to defaults if storage is unavailable
  }
  // ProviderScope hosts every Riverpod provider (network layer, auth, data).
  runApp(ProviderScope(child: HopprApp(prefs: prefs)));
}
