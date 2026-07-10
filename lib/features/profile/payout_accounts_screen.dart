import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/error_messages.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/dto/user_dto.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/blur_sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/feedback/app_loaders.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../../widgets/feedback/state_views.dart';
import '../transaction/widgets/transaction_widgets.dart';
import '../auth/application/auth_controller.dart';

/// Payout Accounts — the seller/dispatcher's saved bank accounts for wallet
/// withdrawals, loaded from the real `/users/me` profile (`payoutAccounts`).
/// Never collects bank details for Create Transaction — this screen (and
/// Wallet withdrawal) is the only place they're managed.
class PayoutAccountsScreen extends ConsumerStatefulWidget {
  const PayoutAccountsScreen({super.key});

  @override
  ConsumerState<PayoutAccountsScreen> createState() =>
      _PayoutAccountsScreenState();
}

class _PayoutAccountsScreenState extends ConsumerState<PayoutAccountsScreen> {
  bool _loading = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    // Always re-fetch on open so an account added/removed elsewhere (or in a
    // prior session) is reflected immediately, not a stale cached list.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).refreshProfile();
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setDefault(PayoutAccount account) async {
    if (account.isDefault) return;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .setDefaultPayoutAccount(account.id);
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Could not set that as your default payout account. Please try again.',
        );
      }
    }
  }

  Future<void> _confirmRemove(PayoutAccount account) async {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.xl),
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.xl,
          AppSizes.xl,
          AppSizes.xl,
          AppSizes.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Remove this payout account?', style: AppText.h2),
            const SizedBox(height: AppSizes.sm),
            Text(
              '${account.bank} · •••• ${account.accountNumberLast4} will no '
              "longer be available for withdrawals. This can't be undone.",
              style: AppText.body,
            ),
            const SizedBox(height: AppSizes.xl),
            AppButton(
              label: 'Remove payout account',
              icon: Icons.delete_outline_rounded,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
            const SizedBox(height: AppSizes.sm),
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.soft,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
          ],
        ),
      ),
    );
    if (remove != true || !mounted) return;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .removePayoutAccount(account.id);
      if (mounted) AppSnackbar.success(context, 'Payout account removed');
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Could not remove that payout account. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts =
        ref.watch(authControllerProvider).valueOrNull?.user?.payoutAccounts ??
        const <PayoutAccount>[];

    return AppScaffold(
      title: 'Payout Accounts',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          Text(
            'Where your settlements and withdrawals are paid. The default account receives seller payouts automatically.',
            style: AppText.body,
          ),
          const SizedBox(height: AppSizes.xl),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSizes.xxl),
              child: Center(child: AppCircularLoader()),
            )
          else if (_loadError != null)
            ErrorRetryView(
              message: 'Unable to load payout accounts. Please try again.',
              onRetry: _refresh,
            )
          else if (accounts.isEmpty)
            const EmptyStateView(
              icon: Icons.account_balance_outlined,
              title: 'No payout account added yet',
              subtitle: 'Add a payout account to withdraw your wallet balance.',
            )
          else ...[
            for (final account in accounts) ...[
              _AccountCard(
                account: account,
                onTap: () => _setDefault(account),
                onRemove: () => _confirmRemove(account),
              ),
              const SizedBox(height: AppSizes.md),
            ],
          ],
          if (!_loading) ...[
            const SizedBox(height: AppSizes.sm),
            _AddAccountButton(onTap: () => _showAddBankSheet(context)),
          ],
          const SizedBox(height: AppSizes.lg),
          const NoteBanner(
            text:
                'Account names must match your verified identity. Payouts to mismatched names are held for review.',
          ),
        ],
      ),
    );
  }
}

/// Animated bottom sheet (blurred backdrop) to add a new payout bank account.
void _showAddBankSheet(BuildContext context) {
  showBlurredSheet(
    context,
    builder: (ctx) => _AddBankAccountSheet(rootContext: context),
  );
}

class _AddBankAccountSheet extends ConsumerStatefulWidget {
  const _AddBankAccountSheet({required this.rootContext});
  final BuildContext rootContext;

  @override
  ConsumerState<_AddBankAccountSheet> createState() =>
      _AddBankAccountSheetState();
}

class _AddBankAccountSheetState extends ConsumerState<_AddBankAccountSheet> {
  final _bank = TextEditingController();
  final _accountNumber = TextEditingController();
  final _accountName = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _bank.dispose();
    _accountNumber.dispose();
    _accountName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final bank = _bank.text.trim();
    final accountNumber = _accountNumber.text.trim();
    final accountName = _accountName.text.trim();

    if (bank.isEmpty) {
      AppSnackbar.error(widget.rootContext, 'Enter the bank name.');
      return;
    }
    if (!RegExp(r'^\d{10}$').hasMatch(accountNumber)) {
      AppSnackbar.error(
        widget.rootContext,
        'Enter a valid 10-digit account number.',
      );
      return;
    }
    if (accountName.isEmpty) {
      AppSnackbar.error(widget.rootContext, 'Enter the account name.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .addPayoutAccount(
            bank: bank,
            accountNumber: accountNumber,
            accountName: accountName,
          );
      if (mounted) Navigator.of(context).pop();
      if (widget.rootContext.mounted) {
        AppSnackbar.success(widget.rootContext, 'Payout account added');
      }
    } on ApiException catch (e) {
      if (widget.rootContext.mounted) {
        AppSnackbar.error(widget.rootContext, e.userMessage);
      }
    } catch (_) {
      if (widget.rootContext.mounted) {
        AppSnackbar.error(
          widget.rootContext,
          'Could not add that payout account. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.xl,
        AppSizes.md,
        AppSizes.xl,
        AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add bank account', style: AppText.h2),
          const SizedBox(height: AppSizes.lg),
          AppTextField(
            label: 'Bank',
            hint: 'Select bank',
            icon: Icons.account_balance_outlined,
            controller: _bank,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSizes.md),
          AppTextField(
            label: 'Account number',
            hint: '0000000000',
            keyboardType: TextInputType.number,
            controller: _accountNumber,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSizes.md),
          AppTextField(
            label: 'Account name',
            hint: 'As shown on the account',
            icon: Icons.verified_user_outlined,
            controller: _accountName,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSizes.xl),
          AppButton(
            label: 'Verify & save',
            icon: Icons.check_rounded,
            variant: AppButtonVariant.outline,
            loading: _busy,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.onTap,
    required this.onRemove,
  });

  final PayoutAccount account;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  String get _statusLabel => switch (account.status) {
    'verified' => 'Verified',
    'failed' => 'Verification failed',
    'disabled' => 'Disabled',
    _ => 'Pending verification',
  };

  @override
  Widget build(BuildContext context) {
    final isDefault = account.isDefault;
    return AppCard(
      onTap: onTap,
      border: Border.all(
        color: isDefault ? AppColors.borderStrong : AppColors.border,
        width: isDefault ? 1.6 : 1.2,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: AppRadii.sm,
            ),
            child: const Icon(Icons.account_balance_outlined, size: 20),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.bank, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  '···· ${account.accountNumberLast4} · ${account.accountName}',
                  style: AppText.caption.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 2),
                Text(_statusLabel, style: AppText.caption),
              ],
            ),
          ),
          if (isDefault)
            const StatusPill(label: 'Default', dense: true)
          else
            const Icon(
              Icons.radio_button_unchecked_rounded,
              color: AppColors.textTertiary,
              size: 22,
            ),
          const SizedBox(width: AppSizes.sm),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: const Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddAccountButton extends StatelessWidget {
  const _AddAccountButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DottedBorderBox(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSizes.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, size: 20),
              const SizedBox(width: AppSizes.sm),
              Text('Add bank account', style: AppText.bodyStrong),
            ],
          ),
        ),
      ),
    );
  }
}
