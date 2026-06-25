import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/routing/app_transitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/feedback/app_snackbar.dart';
import '../auth/application/auth_controller.dart';
import 'change_pin_screen.dart';

/// More → Security. Manage biometric unlock and change the PIN.
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _loading = true;
  bool _busy = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = ref.read(authControllerProvider.notifier);
    final available = await n.isBiometricAvailable();
    final enabled = await n.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
        _loading = false;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (_busy) return;
    final n = ref.read(authControllerProvider.notifier);
    setState(() => _busy = true);
    try {
      if (value) {
        final ok = await n.enableBiometric();
        if (!mounted) return;
        if (ok) {
          setState(() => _biometricEnabled = true);
          AppSnackbar.success(context, 'Biometric unlock enabled.');
        } else {
          AppSnackbar.error(context,
              "Couldn't enable biometrics. Make sure it's set up on your device.");
        }
      } else {
        await n.disableBiometric();
        if (!mounted) return;
        setState(() => _biometricEnabled = false);
        AppSnackbar.info(context, 'Biometric unlock disabled.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Security',
      body: _loading
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSizes.sm),
                Text('Keep your account safe', style: AppText.h1),
                const SizedBox(height: AppSizes.sm),
                Text('Manage your PIN and biometric unlock.', style: AppText.body),
                const SizedBox(height: AppSizes.xl),
                AppCard(
                  child: Row(
                    children: [
                      const Icon(Icons.fingerprint_rounded, size: 22),
                      const SizedBox(width: AppSizes.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Sign in with biometrics',
                                style: AppText.bodyStrong),
                            const SizedBox(height: 2),
                            Text(
                              _biometricAvailable
                                  ? 'Unlock with fingerprint or face'
                                  : 'Not available on this device',
                              style: AppText.caption,
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _biometricEnabled,
                        onChanged: (_biometricAvailable && !_busy)
                            ? _toggleBiometric
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.md),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => AppNav.push(context, const ChangePinScreen()),
                  child: AppCard(
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline_rounded, size: 22),
                        const SizedBox(width: AppSizes.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Change PIN', style: AppText.bodyStrong),
                              const SizedBox(height: 2),
                              Text('Update your 6-digit transaction PIN',
                                  style: AppText.caption),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
