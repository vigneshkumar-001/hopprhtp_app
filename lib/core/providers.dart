import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/dispute_repository.dart';
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
import 'storage/token_store.dart';

// Re-export so feature files can import a single `core/providers.dart`.
export 'storage/token_store.dart' show TokenStore;

/// Secure token store — one instance app-wide.
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

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

/// Recent ledger activity (first page).
final walletLedgerProvider = FutureProvider.autoDispose<WalletLedgerPage>(
  (ref) => ref.watch(walletRepositoryProvider).ledger(page: 1, perPage: 30),
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
  ref.invalidate(unreadNotificationsProvider);
}
