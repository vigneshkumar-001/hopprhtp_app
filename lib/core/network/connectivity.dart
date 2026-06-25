import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams whether the device currently has a network transport. Emits the
/// current status immediately, then every change.
///
/// This reflects transport (wifi/mobile/none), not guaranteed reachability of
/// our API — pair it with request-level error handling for full coverage.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  yield isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnline);
});

extension ConnectivityRef on Ref {
  /// Optimistic synchronous read — treats "unknown" as online so we attempt the
  /// request and let it fail loudly rather than blocking on a cold stream.
  bool get isOnline => read(connectivityProvider).valueOrNull ?? true;
}

extension ConnectivityWidgetRef on WidgetRef {
  bool get isOnline => read(connectivityProvider).valueOrNull ?? true;
}
