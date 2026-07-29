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

/// One realtime withdrawal-status change, pushed from the backend's
/// Socket.IO server to the requesting user's own room only (a withdrawal has
/// exactly one owner, unlike a transaction's buyer/seller pair). Never
/// carries the payout account/bank details — only what the wallet screen
/// needs to refresh (see `emitWithdrawalEvent` on the backend).
@immutable
class WithdrawalSocketEvent {
  const WithdrawalSocketEvent({
    required this.withdrawalId,
    required this.status,
    required this.amountKobo,
    required this.rejectionReason,
    required this.failureReason,
    required this.updatedAt,
  });

  final String withdrawalId;
  final String status;
  final int amountKobo;
  final String? rejectionReason;
  final String? failureReason;
  final DateTime? updatedAt;

  factory WithdrawalSocketEvent.fromJson(Map<dynamic, dynamic> json) {
    return WithdrawalSocketEvent(
      withdrawalId: (json['withdrawalId'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      amountKobo: (json['amountKobo'] as num?)?.toInt() ?? 0,
      rejectionReason: json['rejectionReason'] as String?,
      failureReason: json['failureReason'] as String?,
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? ''),
    );
  }
}

/// Same contract as [WithdrawalSocketEvent] — a support ticket also only
/// ever belongs to one user. Never carries the admin's reply text itself
/// (the app must fetch the real ticket); this is a "go refetch" signal only.
@immutable
class SupportTicketSocketEvent {
  const SupportTicketSocketEvent({required this.ticketId, required this.status, required this.updatedAt});

  final String ticketId;
  final String status;
  final DateTime? updatedAt;

  factory SupportTicketSocketEvent.fromJson(Map<dynamic, dynamic> json) {
    return SupportTicketSocketEvent(
      ticketId: (json['ticketId'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? ''),
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
  final _withdrawalController =
      StreamController<WithdrawalSocketEvent>.broadcast();
  final _supportTicketController =
      StreamController<SupportTicketSocketEvent>.broadcast();

  /// Coalesces rapid-fire events for the same transaction (a single lifecycle
  /// action can trigger more than one hook in quick succession) into one
  /// downstream emission, so listeners never re-fetch several times in a row
  /// for what is really one change.
  final Map<String, Timer> _debounce = {};
  final Map<String, TransactionSocketEvent> _pending = {};
  static const _debounceWindow = Duration(milliseconds: 400);

  final Map<String, Timer> _withdrawalDebounce = {};
  final Map<String, WithdrawalSocketEvent> _withdrawalPending = {};

  final Map<String, Timer> _supportTicketDebounce = {};
  final Map<String, SupportTicketSocketEvent> _supportTicketPending = {};

  /// Every transaction event this signed-in user is entitled to see — the
  /// server auto-joins each connection to `user:<id>`, which receives every
  /// transaction they're a party to, not just ones this device has explicitly
  /// opened via [joinTransaction]. That's what lets Home/History pick up a
  /// change without the user having Transaction Details open at all.
  Stream<TransactionSocketEvent> get events => _controller.stream;

  /// Every withdrawal-status change for this signed-in user — same
  /// auto-join-to-own-room delivery as [events], just a distinct socket.io
  /// event name/payload shape so listeners never have to sniff a generic
  /// payload to tell the two apart.
  Stream<WithdrawalSocketEvent> get withdrawalEvents =>
      _withdrawalController.stream;

  /// Every support-ticket status change for this signed-in user (admin
  /// marked in review / replied / closed) — same delivery contract as
  /// [withdrawalEvents].
  Stream<SupportTicketSocketEvent> get supportTicketEvents =>
      _supportTicketController.stream;

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

    _socket!.on('withdrawal_event', (data) {
      if (data is! Map) return;
      try {
        final event = WithdrawalSocketEvent.fromJson(data);
        _log(
          'withdrawal event received: withdrawal=${event.withdrawalId} '
          'status=${event.status}',
        );
        _debouncedEmitWithdrawal(event);
      } catch (_) {
        // Malformed/unexpected payload — never let a bad frame crash the app.
      }
    });

    _socket!.on('support_ticket_event', (data) {
      if (data is! Map) return;
      try {
        final event = SupportTicketSocketEvent.fromJson(data);
        _log(
          'support ticket event received: ticket=${event.ticketId} '
          'status=${event.status}',
        );
        _debouncedEmitSupportTicket(event);
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

  void _debouncedEmitWithdrawal(WithdrawalSocketEvent event) {
    _withdrawalPending[event.withdrawalId] = event;
    _withdrawalDebounce[event.withdrawalId]?.cancel();
    _withdrawalDebounce[event.withdrawalId] = Timer(_debounceWindow, () {
      _withdrawalDebounce.remove(event.withdrawalId);
      final e = _withdrawalPending.remove(event.withdrawalId);
      if (e != null && !_withdrawalController.isClosed) {
        _withdrawalController.add(e);
      }
    });
  }

  void _debouncedEmitSupportTicket(SupportTicketSocketEvent event) {
    _supportTicketPending[event.ticketId] = event;
    _supportTicketDebounce[event.ticketId]?.cancel();
    _supportTicketDebounce[event.ticketId] = Timer(_debounceWindow, () {
      _supportTicketDebounce.remove(event.ticketId);
      final e = _supportTicketPending.remove(event.ticketId);
      if (e != null && !_supportTicketController.isClosed) {
        _supportTicketController.add(e);
      }
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
    for (final timer in _withdrawalDebounce.values) {
      timer.cancel();
    }
    _withdrawalDebounce.clear();
    _withdrawalPending.clear();
    for (final timer in _supportTicketDebounce.values) {
      timer.cancel();
    }
    _supportTicketDebounce.clear();
    _supportTicketPending.clear();
    _socket?.dispose();
    _socket = null;
  }
}

final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService(ref.watch(tokenStoreProvider));
  ref.onDispose(service.disconnect);
  return service;
});
