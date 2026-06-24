import 'package:flutter/material.dart';
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
  runApp(HopprApp(prefs: prefs));
}
