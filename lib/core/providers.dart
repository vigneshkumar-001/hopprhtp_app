import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/models.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/dispute_repository.dart';
import '../data/repositories/fee_settings_repository.dart';
import '../data/repositories/merchant_repository.dart';
import '../data/repositories/public_config_repository.dart';
import '../data/dto/merchant_dto.dart';
import '../data/dto/wallet_dto.dart';
import '../data/repositories/notification_repository.dart';
import '../data/repositories/support_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/repositories/wallet_repository.dart';
import '../data/repositories/upload_repository.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/transaction/application/transactions_provider.dart';
import 'auth/biometric_service.dart';
import 'env/app_config.dart';
import 'network/auth_interceptor.dart';
import 'network/logging_interceptor.dart';
import 'notifications/push_notification_service.dart';
import 'storage/token_store.dart';
import 'utils/delivery_fee_estimator.dart';

// Re-export so feature files can import a single `core/providers.dart`.
export 'storage/token_store.dart' show TokenStore;

/// Secure token store — one instance app-wide.
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Real installed version + build number — read from the platform (Android's
/// versionName/versionCode, iOS's CFBundleShortVersionString/Version), never
/// hand-copied from pubspec.yaml, so it can never drift out of sync with
/// what actually shipped. Shown on the splash screen and in Profile.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'v${info.version} (${info.buildNumber})';
});

/// Biometric (fingerprint / face) unlock service.
final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(),
);

/// The configured [Dio] every repository shares. Carries the auth interceptor,
/// which refreshes tokens on 401 and signals the [AuthController] on hard expiry.
final dioProvider = Provider<Dio>((ref) {
  final tokens = ref.watch(tokenStoreProvider);

  // Timeouts are sized to survive a Heroku eco/basic dyno COLD START: the dyno
  // sleeps after ~30 min idle, and the first request then waits for it to boot
  // (typically 10–30s). At 12s the client aborted before the server answered
  // (see the `/public-config` + `/users/me` cold-start aborts). 30s covers a
  // normal boot; a genuinely dead network still fails, just a bit later.
  // NOTE: the durable fix is to keep the dyno warm (see comment below) so these
  // long waits only ever happen on a truly cold first hit.
  BaseOptions options() => BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    contentType: 'application/json',
    headers: const {'Accept': 'application/json'},
  );

  final logging = LoggingInterceptor();

  // Client used only for the refresh call + replays. It carries NO AuthInterceptor
  // (so it can never recurse) but does log, so refreshes/retries are visible.
  final refreshDio = Dio(options())..interceptors.add(logging);

  final dio = Dio(options());
  dio.interceptors.add(
    AuthInterceptor(
      tokens: tokens,
      refreshDio: refreshDio,
      onSessionExpired: () =>
          ref.read(authControllerProvider.notifier).forceLogout(),
    ),
  );
  // Added AFTER the auth interceptor so the request log sees the attached token.
  dio.interceptors.add(logging);
  return dio;
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(dioProvider)),
);

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(dioProvider)),
);

final disputeRepositoryProvider = Provider<DisputeRepository>(
  (ref) => DisputeRepository(ref.watch(dioProvider)),
);

/// One instance app-wide — created lazily on first use (see `app.dart`).
final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  final service = PushNotificationService(
    onToken: (token, platform) {
      // A token refresh can fire before sign-in (or after sign-out) — skip
      // the call rather than sending a request guaranteed to 401.
      final authed =
          ref.read(authControllerProvider).valueOrNull?.isAuthenticated ??
          false;
      if (!authed) return Future.value();
      return ref
          .read(authRepositoryProvider)
          .updateFcmToken(fcmToken: token, platform: platform);
    },
  );
  ref.onDispose(service.dispose);
  return service;
});

final merchantRepositoryProvider = Provider<MerchantRepository>(
  (ref) => MerchantRepository(ref.watch(dioProvider)),
);

/// A merchant's public-safe profile, keyed by merchant id. Auto-disposed so
/// re-opening a Merchant Profile always shows fresh stats.
final merchantProfileProvider = FutureProvider.autoDispose
    .family<MerchantProfile, String>(
      (ref, merchantId) =>
          ref.watch(merchantRepositoryProvider).getProfile(merchantId),
    );

final uploadRepositoryProvider = Provider<UploadRepository>(
  (ref) => UploadRepository(ref.watch(dioProvider)),
);

final supportRepositoryProvider = Provider<SupportRepository>(
  (ref) => SupportRepository(ref.watch(dioProvider)),
);

final publicConfigRepositoryProvider = Provider<PublicConfigRepository>(
  (ref) => PublicConfigRepository(ref.watch(dioProvider)),
);

const _googleApiKeyCache = 'public_config_google_api_key';
final _publicConfigLog = Logger(printer: PrettyPrinter(methodCount: 0));

final googleApiKeyProvider = FutureProvider<String?>((ref) async {
  _publicConfigLog.i('Loading public config for Google Maps key...');
  final prefs = await SharedPreferences.getInstance();
  final cached = prefs.getString(_googleApiKeyCache);
  try {
    final key = await ref.read(publicConfigRepositoryProvider).googleApiKey();
    if (key != null && key.isNotEmpty) {
      await prefs.setString(_googleApiKeyCache, key);
      _publicConfigLog.i('Google Maps key loaded from backend config.');
      return key;
    }
    _publicConfigLog.w('Backend returned an empty Google Maps key.');
  } catch (_) {
    // Fall back to the last known key if the network/config endpoint is down.
    _publicConfigLog.w(
      'Public config fetch failed, falling back to cached key.',
    );
  }
  if (cached != null && cached.isNotEmpty) {
    _publicConfigLog.i('Google Maps key loaded from cache.');
  } else {
    _publicConfigLog.w('No cached Google Maps key available.');
  }
  return cached;
});

/// Admin-configured "latest build" gate — powers the "Update available"
/// bottom sheet (see UpdateGate). Failures resolve to null so a config fetch
/// hiccup never blocks the app from opening — the sheet just doesn't show.
final appUpdateInfoProvider = FutureProvider<AppUpdateInfo?>((ref) async {
  try {
    return await ref.read(publicConfigRepositoryProvider).appUpdateInfo();
  } catch (_) {
    return null;
  }
});

final feeSettingsRepositoryProvider = Provider<FeeSettingsRepository>(
  (ref) => FeeSettingsRepository(ref.watch(dioProvider)),
);

final _feeSettingsLog = Logger(printer: PrettyPrinter(methodCount: 0));

/// Fetched once per app session (see `HopprApp.initState`) and applied
/// straight onto the [DeliveryFeeEstimator] / [PaymentDraft] statics that
/// Payment Setup previews with, so an admin's Fees & Charges change is
/// reflected the next time the app opens instead of the shipped defaults
/// silently drifting from what the backend actually charges. Display-only:
/// the backend always recomputes and is the authoritative figure once a
/// transaction is created. Failures are swallowed — the shipped defaults
/// (already identical to the backend's own defaults) are a safe fallback.
final feeSettingsProvider = FutureProvider<PublicFeeSettings?>((ref) async {
  try {
    final settings = await ref.read(feeSettingsRepositoryProvider).fetch();
    DeliveryFeeEstimator.applyRemoteConfig(
      baseFee: settings.deliveryBaseFee,
      perKmFee: settings.deliveryPerKmFee,
      freeWeightKg: settings.deliveryFreeWeightKg,
      extraWeightFeePerKg: settings.deliveryExtraWeightFee,
      minimumFee: settings.deliveryMinimumFee,
    );
    if (settings.platformFeeMode == 'percentage') {
      PaymentDraft.trustRate = settings.platformFeePercentage / 100;
    } else {
      _feeSettingsLog.w(
        'Platform fee mode is "${settings.platformFeeMode}" — local '
        'preview only supports percentage mode, leaving trustRate as-is.',
      );
    }
    _feeSettingsLog.i('Fee settings preview synced from backend.');
    return settings;
  } catch (_) {
    _feeSettingsLog.w('Fee settings fetch failed, keeping shipped defaults.');
    return null;
  }
});

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(dioProvider)),
);

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => WalletRepository(ref.watch(dioProvider)),
);

/// Wallet balance — auto-disposed so it re-fetches each time Wallet is opened.
final walletBalanceProvider = FutureProvider.autoDispose<WalletBalance>(
  (ref) => ref.watch(walletRepositoryProvider).balance(),
);

/// Recent ledger activity (first page), scoped to the selected date filter
/// (All / Today / Yesterday / a custom range — see [WalletActivityFilter]).
final walletLedgerProvider = FutureProvider.autoDispose
    .family<WalletLedgerPage, WalletActivityFilter>(
      (ref, filter) => ref
          .watch(walletRepositoryProvider)
          .ledger(page: 1, perPage: 30, from: filter.from, to: filter.to),
    );

/// This user's withdrawal (payout) requests — auto-disposed so it re-fetches
/// each time the Wallet screen is opened; also invalidated after creating a
/// new request and on withdrawal socket events (see [SocketService]).
final walletWithdrawalsProvider =
    FutureProvider.autoDispose<List<WithdrawalRequest>>(
      (ref) => ref.watch(walletRepositoryProvider).withdrawals(),
    );

/// Unread-notification count for the home bell badge. Invalidate it after the
/// notifications screen marks items read so the badge updates.
final unreadNotificationsProvider = FutureProvider<int>(
  (ref) => ref.watch(notificationRepositoryProvider).unreadCount(),
);

/// Invalidates every provider that caches data for the signed-in user. Called
/// on login, register, and logout so a new session never shows the previous
/// account's transactions, wallet, or notifications. Repository/dio/token
/// providers are intentionally left alone — they hold no per-user data.
void resetUserScopedProviders(Ref ref) {
  ref.invalidate(
    transactionsProvider,
  ); // also refreshes transactionsByStageProvider
  ref.invalidate(transactionDetailProvider);
  ref.invalidate(transactionDisputesProvider);
  ref.invalidate(disputeDetailProvider);
  ref.invalidate(merchantProfileProvider);
  ref.invalidate(walletBalanceProvider);
  ref.invalidate(walletLedgerProvider);
  ref.invalidate(walletWithdrawalsProvider);
  ref.invalidate(unreadNotificationsProvider);
}
