import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configureSystemUi();
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
