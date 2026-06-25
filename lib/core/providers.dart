import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/auth_repository.dart';
import '../data/dto/wallet_dto.dart';
import '../data/repositories/notification_repository.dart';
import '../data/repositories/support_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../data/repositories/wallet_repository.dart';
import '../data/repositories/upload_repository.dart';
import '../features/auth/application/auth_controller.dart';
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
final biometricServiceProvider =
    Provider<BiometricService>((ref) => BiometricService());

/// The configured [Dio] every repository shares. Carries the auth interceptor,
/// which refreshes tokens on 401 and signals the [AuthController] on hard expiry.
final dioProvider = Provider<Dio>((ref) {
  final tokens = ref.watch(tokenStoreProvider);

  BaseOptions options() => BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
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

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref.watch(dioProvider)));

final transactionRepositoryProvider = Provider<TransactionRepository>(
    (ref) => TransactionRepository(ref.watch(dioProvider)));

final uploadRepositoryProvider =
    Provider<UploadRepository>((ref) => UploadRepository(ref.watch(dioProvider)));

final supportRepositoryProvider =
    Provider<SupportRepository>((ref) => SupportRepository(ref.watch(dioProvider)));

final notificationRepositoryProvider = Provider<NotificationRepository>(
    (ref) => NotificationRepository(ref.watch(dioProvider)));

final walletRepositoryProvider =
    Provider<WalletRepository>((ref) => WalletRepository(ref.watch(dioProvider)));

/// Wallet balance — auto-disposed so it re-fetches each time Wallet is opened.
final walletBalanceProvider = FutureProvider.autoDispose<WalletBalance>(
    (ref) => ref.watch(walletRepositoryProvider).balance());

/// Recent ledger activity (first page).
final walletLedgerProvider = FutureProvider.autoDispose<WalletLedgerPage>(
    (ref) => ref.watch(walletRepositoryProvider).ledger(page: 1, perPage: 30));

/// Unread-notification count for the home bell badge. Invalidate it after the
/// notifications screen marks items read so the badge updates.
final unreadNotificationsProvider = FutureProvider<int>(
    (ref) => ref.watch(notificationRepositoryProvider).unreadCount());
