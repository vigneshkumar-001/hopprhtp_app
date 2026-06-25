import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../app_button.dart';
import '../boxed_code_input.dart';

/// Prompts for the 6-digit transaction PIN in a bottom sheet. Returns the
/// entered PIN, or null if dismissed. The PIN is verified server-side against
/// the stored hash — it's never persisted on the device.
Future<String?> showPinSheet(
  BuildContext context, {
  String title = 'Enter your PIN',
  String subtitle = 'Confirm with your 6-digit transaction PIN.',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.rXl)),
    ),
    builder: (_) => _PinSheet(title: title, subtitle: subtitle),
  );
}

class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _submit() {
    if (_pin.text.length == 6) Navigator.of(context).pop(_pin.text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSizes.xl, AppSizes.lg, AppSizes.xl, AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: AppRadii.pill,
                ),
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            Text(widget.title, style: AppText.h2),
            const SizedBox(height: AppSizes.sm),
            Text(widget.subtitle, style: AppText.body),
            const SizedBox(height: AppSizes.xl),
            BoxedCodeInput(
              controller: _pin,
              length: 6,
              obscure: true,
              onChanged: (_) => setState(() {}),
              onCompleted: (_) => _submit(),
            ),
            const SizedBox(height: AppSizes.xl),
            AppButton(
              label: 'Confirm',
              enabled: _pin.text.length == 6,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
