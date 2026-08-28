import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'push_notification_service.dart';

const _kLastShownMs = 'notif_prompt_last_shown_ms';
const _kShownCount = 'notif_prompt_shown_count';

/// Gaps (in days) between successive re-prompts, indexed by how many times
/// we've already shown the sheet — 2 days after the first "Not now", then 5,
/// then 10, then we stop for good. Nagging past this point trains people to
/// dismiss it on reflex instead of actually reconsidering.
const _gapsDays = [2, 5, 10];
final _maxPrompts = _gapsDays.length;

/// Decides when the in-app "don't miss updates" bottom sheet should
/// re-ask a user who already denied OS notification permission — the real
/// system dialog only gets one shot, so this is the only way to ever change
/// their mind, but showing it every app open would just train them to
/// dismiss it on reflex. State lives in [SharedPreferences] (device-local,
/// not synced to the backend — losing it on reinstall just resets the
/// cadence, which is harmless).
class NotificationPermissionPrompt {
  /// True only when it's actually worth interrupting the user: Firebase
  /// initialized, permission is concretely denied (not just
  /// not-yet-decided — that's the OS's own first-ask to handle, not ours),
  /// and enough time has passed since we last asked.
  static Future<bool> shouldShow() async {
    if (!PushNotificationService.firebaseReady) return false;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.denied) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    final shownCount = prefs.getInt(_kShownCount) ?? 0;
    if (shownCount >= _maxPrompts) return false;

    final lastShownMs = prefs.getInt(_kLastShownMs);
    if (lastShownMs == null) return true; // never shown yet — first ask

    final daysSince = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(lastShownMs))
        .inDays;
    final requiredGap = _gapsDays[shownCount.clamp(0, _gapsDays.length - 1)];
    return daysSince >= requiredGap;
  }

  /// Call right after the sheet is shown (whichever button they tap, or if
  /// they swipe it away) — this is what makes the cadence advance regardless
  /// of their answer.
  static Future<void> recordShown() async {
    final prefs = await SharedPreferences.getInstance();
    final shownCount = prefs.getInt(_kShownCount) ?? 0;
    await prefs.setInt(_kShownCount, shownCount + 1);
    await prefs.setInt(_kLastShownMs, DateTime.now().millisecondsSinceEpoch);
  }

  /// Re-runs the real OS permission request. On Android this can still show
  /// the native dialog again (unless the user previously ticked "don't ask
  /// again"); on iOS, once a decision has been made the OS never shows the
  /// dialog a second time and this just returns the existing (still denied)
  /// status immediately. Returns whether permission actually ended up
  /// granted — the caller falls back to opening Settings when it's false.
  static Future<bool> requestAgain() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }
}
