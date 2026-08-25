import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/network/socket_service.dart';
import '../../core/providers.dart';
import '../auth/application/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/formatters.dart';
import '../../data/dto/message_dto.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';

/// In-transaction chat — buyer and seller only, kept inside Hoppr (not
/// WhatsApp/SMS) so the conversation stays part of the same auditable record
/// as the rest of the transaction. History loads once; new messages arrive
/// live over the same per-transaction socket room Transaction Details
/// already joins (see SocketService.chatMessages) — the sender's own message
/// is appended immediately from the send response, not by waiting on the
/// realtime echo, which is de-duplicated by id when it arrives a moment later.
class TransactionChatScreen extends ConsumerStatefulWidget {
  const TransactionChatScreen({
    super.key,
    required this.transactionId,
    required this.counterpartyName,
  });

  final String transactionId;
  final String counterpartyName;

  @override
  ConsumerState<TransactionChatScreen> createState() =>
      _TransactionChatScreenState();
}

class _TransactionChatScreenState extends ConsumerState<TransactionChatScreen> {
  final List<ChatMessage> _messages = [];
  final Set<String> _seenIds = {};
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<ChatMessageSocketEvent>? _sub;
  late final SocketService _socket;

  bool _loading = true;
  bool _sending = false;
  String? _loadError;
  String? _myUserId;

  @override
  void initState() {
    super.initState();
    _socket = ref.read(socketServiceProvider);
    _socket.joinTransaction(widget.transactionId);
    _sub = _socket.chatMessages
        .where((e) => e.transactionId == widget.transactionId)
        .listen(_onIncoming);
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _socket.leaveTransaction(widget.transactionId);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _myUserId = ref.read(authControllerProvider).valueOrNull?.user?.id;
    try {
      final messages = await ref
          .read(transactionRepositoryProvider)
          .listMessages(widget.transactionId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(messages);
        _seenIds.addAll(messages.map((m) => m.id));
        _loading = false;
      });
      _scrollToBottomSoon();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e.userMessage;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load messages. Please try again.';
        });
      }
    }
  }

  void _onIncoming(ChatMessageSocketEvent e) {
    if (!mounted || _seenIds.contains(e.messageId)) return;
    setState(() {
      _seenIds.add(e.messageId);
      _messages.add(
        ChatMessage(
          id: e.messageId,
          senderId: e.senderId,
          senderRole: e.senderRole,
          text: e.text,
          createdAt: e.createdAt,
        ),
      );
    });
    _scrollToBottomSoon();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    try {
      final sent = await ref
          .read(transactionRepositoryProvider)
          .sendMessage(widget.transactionId, text);
      if (!mounted) return;
      setState(() {
        _seenIds.add(sent.id);
        _messages.add(sent);
      });
      _scrollToBottomSoon();
    } on ApiException catch (e) {
      if (mounted) {
        _input.text = text;
        AppSnackbar.error(context, e.userMessage);
      }
    } catch (_) {
      if (mounted) {
        _input.text = text;
        AppSnackbar.error(context, 'Could not send. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppDurations.normal,
        curve: AppDurations.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: widget.counterpartyName,
      scrollable: false,
      padding: EdgeInsets.zero,
      body: _buildBody(),
      bottomAction: _ChatInputBar(
        controller: _input,
        sending: _sending,
        onSend: _send,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_loadError != null) {
      return ErrorRetryView(
        message: _loadError!,
        onRetry: () {
          setState(() {
            _loading = true;
            _loadError = null;
          });
          _load();
        },
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Text(
            'No messages yet. Say hello to get things moving.',
            style: AppText.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.screenPad,
        vertical: AppSizes.md,
      ),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        return _MessageBubble(message: m, isMine: m.senderId == _myUserId);
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md,
                vertical: AppSizes.sm,
              ),
              decoration: BoxDecoration(
                color: isMine ? AppColors.ink : AppColors.surface,
                border: isMine ? null : Border.all(color: AppColors.border),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMine ? 16 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.text,
                    style: AppText.body.copyWith(
                      color: isMine
                          ? AppColors.textOnDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.createdAt == null
                        ? ''
                        : Dates.time(message.createdAt!),
                    style: AppText.caption.copyWith(
                      color: isMine
                          ? AppColors.textOnDark.withValues(alpha: 0.65)
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 120),
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(24),
            ),
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              style: AppText.body,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Type a message…',
                hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: AppSizes.sm,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Material(
          color: AppColors.ink,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: sending ? null : onSend,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          AppColors.textOnDark,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.arrow_upward_rounded,
                      color: AppColors.textOnDark,
                      size: 20,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
