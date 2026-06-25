import 'package:flutter/material.dart';
import '../core/data/countries.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_sizes.dart';
import '../core/theme/app_typography.dart';
import 'app_text_field.dart';

/// Opens a modern country-picker bottom sheet — flag + name + dial code, with
/// live search. Returns the chosen [Country], or null if dismissed.
Future<Country?> showCountryPicker(BuildContext context, {String? selectedIso2}) {
  return showModalBottomSheet<Country>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.rXl)),
    ),
    builder: (_) => _CountryPickerSheet(selectedIso2: selectedIso2),
  );
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({this.selectedIso2});
  final String? selectedIso2;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? kCountries
        : kCountries
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.dialCode.contains(q) ||
                c.iso2.toLowerCase().contains(q))
            .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            const SizedBox(height: AppSizes.sm),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: AppRadii.pill,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSizes.screenPad, AppSizes.lg, AppSizes.screenPad, AppSizes.md),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Select country', style: AppText.h2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.screenPad),
              child: AppTextField(
                hint: 'Search country or code',
                icon: Icons.search_rounded,
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: AppSizes.sm),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  return ListTile(
                    onTap: () => Navigator.of(context).pop(c),
                    selected: c.iso2 == widget.selectedIso2,
                    selectedTileColor: AppColors.surfaceMuted,
                    leading: Text(c.flag, style: const TextStyle(fontSize: 26)),
                    title: Text(c.name, style: AppText.bodyStrong),
                    trailing: Text(
                      c.dialCode,
                      style: AppText.body.copyWith(color: AppColors.textTertiary),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
