import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../env/app_config.dart';
import '../providers.dart';
import '../utils/app_logger.dart';

/// One realtime transaction change, pushed from the backend's Socket.IO
/// server. Mirrors the safe subset of fields the server ever sends — no
/// delivery code, no payout/bank details (see `socket.service.ts` on the
/// backend for the emit side, which enforces this).
@immutable
class TransactionSocketEvent {
  const TransactionSocketEvent({
    required this.type,
    required this.transactionId,
    required this.status,
    required this.updatedAt,
    required this.changedFields,
  });

  final String type;
  final String transactionId;
  final String status;
  final DateTime? updatedAt;
  final List<String> changedFields;

  factory TransactionSocketEvent.fromJson(Map<dynamic, dynamic> json) {
    return TransactionSocketEvent(
      type: (json['type'] as String?) ?? 'transaction_updated',
      transactionId: (json['transactionId'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? ''),
      changedFields: ((json['changedFields'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );
  }
}

/// Realtime transaction updates over Socket.IO — best-effort only. If the
/// socket never connects, or drops and can't reconnect, the app's existing
/// fallback (pull-to-refresh + refetch on app resume — see
/// `TransactionDetailScreen`) remains the source of truth; nothing here is
/// load-bearing for correctness, only for how *fast* the UI reflects a
/// change made elsewhere.
class SocketService {
  SocketService(this._tokens);

  final TokenStore _tokens;
  io.Socket? _socket;

  final _controller = StreamController<TransactionSocketEvent>.broadcast();

  /// Coalesces rapid-fire events for the same transaction (a single lifecycle
  /// action can trigger more than one hook in quick succession) into one
  /// downstream emission, so listeners never re-fetch several times in a row
  /// for what is really one change.
  final Map<String, Timer> _debounce = {};
  final Map<String, TransactionSocketEvent> _pending = {};
  static const _debounceWindow = Duration(milliseconds: 400);

  /// Every transaction event this signed-in user is entitled to see — the
  /// server auto-joins each connection to `user:<id>`, which receives every
  /// transaction they're a party to, not just ones this device has explicitly
  /// opened via [joinTransaction]. That's what lets Home/History pick up a
  /// change without the user having Transaction Details open at all.
  Stream<TransactionSocketEvent> get events => _controller.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Debug-only lifecycle logging, routed through the shared [AppLogger]
  /// (debug-build-only — see there). Only ever logs safe identifiers already
  /// visible in the UI (transaction id, status, event type) — never the
  /// access token, a delivery code, or any payout/bank field, none of which
  /// this payload even carries.
  void _log(String message) {
    AppLogger.debug('[socket] $message');
  }

  /// Connects using the current access token. A no-op if there's no session
  /// (nothing to authenticate the handshake with) or a socket is already
  /// live. Reconnects automatically on drop — no manual retry loop needed.
  void connect() {
    final token = _tokens.accessToken;
    if (token == null || token.isEmpty) return;
    if (_socket != null) return;

    _socket = io.io(
      AppConfig.webBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .build(),
    );

    _socket!.on('connect', (_) => _log('connected'));
    _socket!.on(
      'disconnect',
      (reason) => _log('disconnected (reason: $reason)'),
    );
    _socket!.io.on(
      'reconnect_attempt',
      (attempt) => _log('reconnect attempt #$attempt'),
    );

    _socket!.on('transaction_event', (data) {
      if (data is! Map) return;
      try {
        final event = TransactionSocketEvent.fromJson(data);
        _log(
          'transaction event received: type=${event.type} '
          'tx=${event.transactionId} status=${event.status}',
        );
        _debouncedEmit(event);
      } catch (_) {
        // Malformed/unexpected payload — never let a bad frame crash the app.
      }
    });
  }

  void _debouncedEmit(TransactionSocketEvent event) {
    _pending[event.transactionId] = event;
    _debounce[event.transactionId]?.cancel();
    _debounce[event.transactionId] = Timer(_debounceWindow, () {
      _debounce.remove(event.transactionId);
      final e = _pending.remove(event.transactionId);
      if (e != null && !_controller.isClosed) _controller.add(e);
    });
  }

  /// Scopes this connection into `transaction:<id>` while its detail screen
  /// is open. The backend verifies the signed-in user is actually the buyer
  /// or seller before allowing the join, so this is a request, not a
  /// guarantee — a stranger who knows/guesses the id is never let in. Asks
  /// for an ack purely so [_log] can report whether the join was actually
  /// granted; the join itself doesn't depend on the ack arriving.
  void joinTransaction(String transactionId) {
    _socket?.emitWithAck(
      'join_transaction',
      {'transactionId': transactionId},
      ack: (dynamic data) {
        final ok = data is Map && data['ok'] == true;
        _log(
          ok
              ? 'join_transaction ok tx=$transactionId'
              : 'join_transaction FAILED tx=$transactionId',
        );
      },
    );
  }

  void leaveTransaction(String transactionId) {
    _socket?.emit('leave_transaction', {'transactionId': transactionId});
  }

  /// Re-establishes the connection with a *fresh* read of the current access
  /// token if it isn't currently connected. `connect()` alone won't do this:
  /// its handshake auth is a snapshot taken once at connection time, so if
  /// the token was silently rotated by [AuthInterceptor] (a 401 refresh)
  /// while this socket was disconnected — dropped network, server restart —
  /// a plain reconnect would keep retrying with the now-stale token forever.
  /// Call this on app resume (see `app.dart`) as a periodic self-heal; a
  /// no-op while already healthily connected.
  void ensureConnected() {
    if (isConnected) return;
    _log('ensureConnected: reconnecting with a fresh token');
    disconnect();
    connect();
  }

  /// Tears the connection down (logout, forced session expiry). Safe to call
  /// even if never connected.
  void disconnect() {
    for (final timer in _debounce.values) {
      timer.cancel();
    }
    _debounce.clear();
    _pending.clear();
    _socket?.dispose();
    _socket = null;
  }
}

final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService(ref.watch(tokenStoreProvider));
  ref.onDispose(service.disconnect);
  return service;
});
