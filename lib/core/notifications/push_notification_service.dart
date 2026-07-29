import 'dart:async';
import 'dart:io' show Platform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/app_logger.dart';

/// Handles a push while the app is fully backgrounded/terminated. Must be a
/// top-level function annotated `@pragma('vm:entry-point')` — the engine may
/// spin up a fresh isolate just for this, with no prior app state, so
/// Firebase is (re-)initialized here independently of [PushNotificationService].
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  AppLogger.debug(
    '[push] background message: ${message.messageId} data=${message.data}',
  );
}

const _androidChannel = AndroidNotificationChannel(
  'high_importance_channel',
  'Important notifications',
  description: 'Payment, delivery and dispute alerts.',
  importance: Importance.high,
);

/// Firebase Cloud Messaging + local notification display, wired app-wide
/// from `app.dart`. Every failure here is caught and logged — push
/// notifications are best-effort and must never break auth/transaction/
/// wallet/navigation flows, including before this Firebase project has
/// actually been configured (see [initializeFirebase]).
class PushNotificationService {
  PushNotificationService({this.onToken});

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  final _tapController = StreamController<(String, String?)>.broadcast();
  final _withdrawalTapController =
      StreamController<(String, String?)>.broadcast();
  final _supportTicketTapController =
      StreamController<(String, String?)>.broadcast();

  /// Called with a real, non-empty device token whenever one becomes
  /// available (initial fetch or a refresh) — the actual `POST
  /// /users/me/fcm-token` call lives in `AuthRepository`/`core/providers.dart`,
  /// injected here so this class stays a plain platform wrapper with no
  /// Riverpod/Dio dependency of its own.
  final Future<void> Function(String token, String? platform)? onToken;

  String? get _platformName {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return null;
  }

  /// Never null/empty-guards let the backend see a bad value, and never lets
  /// a backend failure (network, auth) propagate — registering a token is
  /// best-effort, same as every other push-related operation on this class.
  Future<void> _sendToken(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await onToken?.call(token, _platformName);
    } catch (e) {
      AppLogger.debug('[push] posting FCM token failed: $e');
    }
  }

  /// Emits a real transaction id (+ the payload's `screen` hint, if any)
  /// whenever the user taps a notification (foreground-shown local
  /// notification, background tap, or the message that launched the app from
  /// terminated). Both are the ONLY things taken from the payload — the
  /// caller must still fetch the transaction from the backend before
  /// navigating; the payload is never trusted as data, `screen` is only ever
  /// used to pick which real, re-fetched screen to open.
  Stream<(String, String?)> get transactionTaps => _tapController.stream;

  /// Same contract as [transactionTaps], for a withdrawal-lifecycle push
  /// instead (withdrawal_under_review/approved/paid/rejected/failed — see
  /// pushMessages.ts on the backend). A withdrawal payload never carries a
  /// transactionId, so without this stream those taps had nowhere to go —
  /// [transactionTaps] only ever fires when transactionId is non-empty.
  Stream<(String, String?)> get withdrawalTaps =>
      _withdrawalTapController.stream;

  /// Same contract as [transactionTaps]/[withdrawalTaps], for a
  /// support-ticket-replied push (a ticket payload carries `ticketId`,
  /// never a transactionId/withdrawalId).
  Stream<(String, String?)> get supportTicketTaps =>
      _supportTicketTapController.stream;

  /// True once [initializeFirebase] actually succeeded. Every other method
  /// on this class no-ops when false instead of throwing.
  static bool firebaseReady = false;

  /// Call once, early in `main()`, before `runApp`. Registers the background
  /// handler immediately after a successful init (Firebase requires this to
  /// happen before any message can be delivered).
  ///
  /// Never throws: reads native platform config directly (no
  /// `firebase_options.dart`/FlutterFire CLI involved) —
  /// `android/app/google-services.json` (present, plugin applied in
  /// android/app/build.gradle.kts) on Android, and
  /// `ios/Runner/GoogleService-Info.plist` on iOS (present on disk, but not
  /// yet added to the Xcode project's build resources — see the iOS setup
  /// notes). If either is missing/unwired, this fails on that platform only,
  /// and the rest of the app must keep working regardless.
  static Future<void> initializeFirebase() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      firebaseReady = true;
    } catch (e) {
      AppLogger.debug('[push] Firebase.initializeApp failed: $e');
    }
  }

  /// Call once the app is up (see `app.dart` initState). No-op if
  /// [initializeFirebase] didn't succeed.
  Future<void> init() async {
    if (!firebaseReady) return;
    try {
      await _initLocalNotifications();
      await _requestPermission();
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageTapped);
      FirebaseMessaging.instance.onTokenRefresh.listen((refreshed) {
        AppLogger.debug('[push] FCM token refreshed');
        unawaited(_sendToken(refreshed));
      });
      // The app was launched by tapping a notification from a fully
      // terminated state — handle it once, after listeners are wired.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _onMessageTapped(initial);
    } catch (e) {
      AppLogger.debug('[push] init failed: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        // Encoded as "tx:<id>|<screen>" or "wd:<id>|<screen>" by
        // _onForegroundMessage below — flutter_local_notifications only
        // carries a single string payload, so the type prefix is what lets
        // this tell a transaction tap from a withdrawal tap apart.
        final typeSplit = payload.indexOf(':');
        if (typeSplit < 0) return;
        final type = payload.substring(0, typeSplit);
        final rest = payload.substring(typeSplit + 1);
        final parts = rest.split('|');
        final id = parts.isNotEmpty ? parts[0] : '';
        if (id.isEmpty) return;
        final screen = parts.length > 1 && parts[1].isNotEmpty
            ? parts[1]
            : null;
        if (type == 'wd') {
          _withdrawalTapController.add((id, screen));
        } else if (type == 'sp') {
          _supportTicketTapController.add((id, screen));
        } else {
          _tapController.add((id, screen));
        }
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);
  }

  /// iOS shows its own system permission prompt; on Android 13+ (API 33)
  /// this also triggers the POST_NOTIFICATIONS runtime permission dialog —
  /// the `firebase_messaging` plugin handles that natively when called.
  ///
  /// TODO(push-notifications, iOS): a physical device push still needs an
  /// APNs Auth Key uploaded once — Firebase Console → Project Settings →
  /// Cloud Messaging → Apple app configuration → APNs Authentication Key.
  /// Without it, `requestPermission()`/token fetch still succeed on iOS but
  /// no push is ever actually delivered by Apple.
  Future<void> _requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    AppLogger.debug(
      '[push] permission status: ${settings.authorizationStatus}',
    );
    // iOS only (a no-op on Android): without this, a foreground push would
    // ALSO trigger iOS's own native banner in addition to the local
    // notification [_onForegroundMessage] already shows via
    // flutter_local_notifications — leaving these true would double-display
    // every foreground push. All `false` keeps PushNotificationService the
    // single source of truth for what's shown, on both platforms.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
  }

  void _onForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    final transactionId = message.data['transactionId'] as String?;
    final withdrawalId = message.data['withdrawalId'] as String?;
    final ticketId = message.data['ticketId'] as String?;
    final screen = message.data['screen'] as String?;
    final id =
        (message.messageId ?? notification.hashCode.toString()).hashCode &
        0x7fffffff;
    _local.show(
      id: id,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Encoded as "tx:<id>|<screen>" / "wd:<id>|<screen>" / "sp:<id>|<screen>"
      // — decoded in onDidReceiveNotificationResponse above (a single string
      // is all this plugin's payload supports). transactionId takes priority
      // in the rare case a payload somehow carried more than one.
      payload: transactionId != null && transactionId.isNotEmpty
          ? 'tx:$transactionId|${screen ?? ''}'
          : withdrawalId != null && withdrawalId.isNotEmpty
          ? 'wd:$withdrawalId|${screen ?? ''}'
          : ticketId != null && ticketId.isNotEmpty
          ? 'sp:$ticketId|${screen ?? ''}'
          : null,
    );
  }

  void _onMessageTapped(RemoteMessage message) {
    final transactionId = message.data['transactionId'] as String?;
    if (transactionId != null && transactionId.isNotEmpty) {
      _tapController.add((transactionId, message.data['screen'] as String?));
      return;
    }
    final withdrawalId = message.data['withdrawalId'] as String?;
    if (withdrawalId != null && withdrawalId.isNotEmpty) {
      _withdrawalTapController.add((
        withdrawalId,
        message.data['screen'] as String?,
      ));
      return;
    }
    final ticketId = message.data['ticketId'] as String?;
    if (ticketId != null && ticketId.isNotEmpty) {
      _supportTicketTapController.add((
        ticketId,
        message.data['screen'] as String?,
      ));
    }
  }

  /// Get the FCM token after app start/login (see `app.dart`'s auth-state
  /// listener) and persist it via [onToken]. Never logs the token value
  /// itself — only that one was (or wasn't) obtained.
  Future<void> registerToken() async {
    if (!firebaseReady) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      AppLogger.debug(
        '[push] FCM token ${token == null ? 'unavailable' : 'obtained'}',
      );
      await _sendToken(token);
    } catch (e) {
      AppLogger.debug('[push] getToken failed: $e');
    }
  }

  void dispose() {
    _tapController.close();
    _withdrawalTapController.close();
    _supportTicketTapController.close();
  }
}
