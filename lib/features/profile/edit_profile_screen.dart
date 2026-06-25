import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/data/countries.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/connectivity.dart';
import '../../core/network/error_messages.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../auth/application/auth_controller.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/country_picker_sheet.dart';
import '../../widgets/feedback/app_snackbar.dart';

const List<String> _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Edit Profile — structured account details (account type, name, DOB, phone,
/// address) saved via `PATCH /users/me`.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  String _accountType = 'individual';
  late final TextEditingController _first, _middle, _last, _phone;
  late final TextEditingController _day, _year;
  late final TextEditingController _line1, _line2, _city, _state, _zip;
  int? _month;
  String? _phoneCountry; // ISO-2
  String? _country; // country name
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final u = ref.read(authControllerProvider).valueOrNull?.user;
    _accountType = u?.accountType ?? 'individual';

    // Fall back to splitting the existing fullName so a user who registered with
    // just a name still sees First/Last pre-filled before they've structured it.
    final parts = (u?.fullName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    final firstFromFull = parts.isNotEmpty ? parts.first : '';
    final lastFromFull = parts.length > 1 ? parts.last : '';
    final middleFromFull =
        parts.length > 2 ? parts.sublist(1, parts.length - 1).join(' ') : '';

    _first = TextEditingController(text: u?.firstName ?? firstFromFull);
    _middle = TextEditingController(text: u?.middleName ?? middleFromFull);
    _last = TextEditingController(text: u?.lastName ?? lastFromFull);
    _phone = TextEditingController(text: u?.phone ?? '');
    _day = TextEditingController(text: u?.dob?.day.toString() ?? '');
    _year = TextEditingController(text: u?.dob?.year.toString() ?? '');
    _month = u?.dob?.month;
    // Nigeria-based app → default to NG / Nigeria when nothing is saved yet.
    _phoneCountry = u?.phoneCountry ?? kDefaultCountryIso2;
    _country = u?.address?.country ?? countryByIso2(kDefaultCountryIso2)?.name;
    _line1 = TextEditingController(text: u?.address?.line1 ?? '');
    _line2 = TextEditingController(text: u?.address?.line2 ?? '');
    _city = TextEditingController(text: u?.address?.city ?? '');
    _state = TextEditingController(text: u?.address?.state ?? '');
    _zip = TextEditingController(text: u?.address?.postalCode ?? '');

    for (final c in _controllers) {
      c.addListener(_refresh);
    }
  }

  List<TextEditingController> get _controllers =>
      [_first, _middle, _last, _phone, _day, _year, _line1, _line2, _city, _state, _zip];

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSave =>
      _first.text.trim().isNotEmpty &&
      _last.text.trim().isNotEmpty &&
      _month != null &&
      _day.text.trim().isNotEmpty &&
      _year.text.trim().isNotEmpty &&
      _phoneCountry != null &&
      _phone.text.trim().isNotEmpty &&
      _line1.text.trim().isNotEmpty &&
      _city.text.trim().isNotEmpty &&
      _country != null;

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_canSave) return;

    final day = int.tryParse(_day.text.trim()) ?? 0;
    final year = int.tryParse(_year.text.trim()) ?? 0;
    if (day < 1 || day > 31 || year < 1900 || year > DateTime.now().year) {
      AppSnackbar.error(context, 'Please enter a valid date of birth.');
      return;
    }
    if (!ref.isOnline) {
      AppSnackbar.error(context,
          'No internet connection. Please check your network and try again.');
      return;
    }

    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'accountType': _accountType,
        'firstName': _first.text.trim(),
        if (_middle.text.trim().isNotEmpty) 'middleName': _middle.text.trim(),
        'lastName': _last.text.trim(),
        'phone': _phone.text.trim(),
        'phoneCountry': _phoneCountry,
        'dob': {'day': day, 'month': _month, 'year': year},
        'address': {
          'line1': _line1.text.trim(),
          if (_line2.text.trim().isNotEmpty) 'line2': _line2.text.trim(),
          'city': _city.text.trim(),
          if (_state.text.trim().isNotEmpty) 'state': _state.text.trim(),
          if (_zip.text.trim().isNotEmpty) 'postalCode': _zip.text.trim(),
          'country': _country,
        },
      };
      await ref.read(authControllerProvider.notifier).updateProfile(body);
      if (!mounted) return;
      AppSnackbar.success(context, 'Profile updated.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) AppSnackbar.error(context, e.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Edit profile',
      bottomAction: AppButton(
        label: 'Save changes',
        enabled: _canSave,
        loading: _busy,
        onPressed: _save,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          _labeled('Your account type', _accountTypeSelector()),
          const SizedBox(height: AppSizes.lg),

          // Name
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeled('First name',
                    AppTextField(controller: _first), required: true),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: _labeled('Last name',
                    AppTextField(controller: _last), required: true),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          _labeled('Middle name', AppTextField(controller: _middle)),
          const SizedBox(height: AppSizes.lg),

          // Date of birth
          _labeled(
            'Date of birth',
            Row(
              children: [
                Expanded(
                  flex: 5,
                  child: AppDropdown<int>(
                    value: _month,
                    hint: 'Month',
                    items: [
                      for (var i = 0; i < 12; i++)
                        DropdownMenuItem(value: i + 1, child: Text(_months[i])),
                    ],
                    onChanged: (v) => setState(() => _month = v),
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  flex: 3,
                  child: AppTextField(
                    controller: _day,
                    hint: 'Day',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  flex: 4,
                  child: AppTextField(
                    controller: _year,
                    hint: 'Year',
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                  ),
                ),
              ],
            ),
            required: true,
          ),
          const SizedBox(height: AppSizes.lg),

          // Phone
          _labeled(
            'Primary phone number',
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _pickerField(
                      onTap: _pickPhoneCountry, child: _phoneCountryLabel()),
                ),
                const SizedBox(width: AppSizes.sm),
                Expanded(
                  flex: 5,
                  child: AppTextField(
                    controller: _phone,
                    hint: 'Phone number',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[+0-9 ()-]')),
                    ],
                  ),
                ),
              ],
            ),
            required: true,
          ),
          const SizedBox(height: AppSizes.lg),

          // Address
          _labeled('Address line 1',
              AppTextField(controller: _line1, hint: 'Enter a location'),
              required: true),
          const SizedBox(height: AppSizes.lg),
          _labeled('Address line 2 (optional)', AppTextField(controller: _line2)),
          const SizedBox(height: AppSizes.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _labeled('City', AppTextField(controller: _city),
                    required: true),
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: _labeled('State', AppTextField(controller: _state)),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.lg),
          _labeled('Zip code / post code', AppTextField(controller: _zip)),
          const SizedBox(height: AppSizes.lg),
          _labeled(
            'Country',
            _pickerField(onTap: _pickCountry, child: _countryLabel()),
            required: true,
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoneCountry() async {
    final c = await showCountryPicker(context, selectedIso2: _phoneCountry);
    if (c != null) setState(() => _phoneCountry = c.iso2);
  }

  Future<void> _pickCountry() async {
    final c = await showCountryPicker(context,
        selectedIso2: countryByName(_country)?.iso2);
    if (c != null) setState(() => _country = c.name);
  }

  Widget _phoneCountryLabel() {
    final c = countryByIso2(_phoneCountry);
    if (c == null) {
      return Text('country',
          style: AppText.body.copyWith(color: AppColors.textTertiary));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(c.flag, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: AppSizes.sm),
        Text(c.dialCode, style: AppText.bodyStrong),
      ],
    );
  }

  Widget _countryLabel() {
    final c = countryByName(_country);
    if (c == null) {
      return Text('-- please select your country --',
          style: AppText.body.copyWith(color: AppColors.textTertiary),
          overflow: TextOverflow.ellipsis);
    }
    return Row(
      children: [
        Text(c.flag, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: AppSizes.sm),
        Expanded(
          child: Text(c.name,
              style: AppText.bodyStrong, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _pickerField({required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: AppSizes.fieldHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.md,
          border: Border.all(color: AppColors.border, width: 1.2),
        ),
        child: Row(
          children: [
            Expanded(child: child),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _labeled(String label, Widget child, {bool required = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(), style: AppText.label),
            if (required)
              Text(' *', style: AppText.label.copyWith(color: AppColors.danger)),
          ],
        ),
        const SizedBox(height: AppSizes.sm),
        child,
      ],
    );
  }

  Widget _accountTypeSelector() {
    Widget option(String value, String label) {
      final selected = _accountType == value;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _accountType = value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.ink : AppColors.border,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.ink,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: AppSizes.sm),
            Text(label, style: AppText.bodyStrong),
          ],
        ),
      );
    }

    return Row(
      children: [
        option('individual', 'Individual'),
        const SizedBox(width: AppSizes.xl),
        option('company', 'Company'),
      ],
    );
  }
}
