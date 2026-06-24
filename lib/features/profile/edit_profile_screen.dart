import 'package:flutter/material.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../data/app_state.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_text_field.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;

  @override
  void initState() {
    super.initState();
    final u = AppScope.read(context).user;
    _name = TextEditingController(text: u?.fullName ?? '');
    _phone = TextEditingController(text: u?.phone ?? '');
    _email = TextEditingController(text: u?.email ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  void _save() {
    AppScope.read(context).updateProfile(
      fullName: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
    );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Edit profile',
      bottomAction: AppButton(label: 'Save changes', onPressed: _save),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSizes.sm),
          Text('Update your details', style: AppText.h1),
          const SizedBox(height: AppSizes.sm),
          Text('This is how merchants and buyers see you.',
              style: AppText.body),
          const SizedBox(height: AppSizes.xxl),
          AppTextField(
            label: 'Full name',
            icon: Icons.person_outline_rounded,
            controller: _name,
          ),
          const SizedBox(height: AppSizes.lg),
          AppTextField(
            label: 'Phone number',
            icon: Icons.phone_outlined,
            controller: _phone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: AppSizes.lg),
          AppTextField(
            label: 'Email',
            icon: Icons.chat_bubble_outline_rounded,
            controller: _email,
            keyboardType: TextInputType.emailAddress,
          ),
        ],
      ),
    );
  }
}
