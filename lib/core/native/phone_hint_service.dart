import 'package:flutter/services.dart';

class PhoneHintService {
  static const MethodChannel _channel =
      MethodChannel('com.fenizotechnologies.escrow/phone_hint');

  static Future<String?> pickPhoneNumber() async {
    try {
      return await _channel.invokeMethod<String>('choosePhoneNumber');
    } on PlatformException {
      return null;
    }
  }
}
