import 'dart:io' show Platform;
import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/json.dart';

/// Admin-configured "latest build" gate for one platform — see
/// admin/settings/App Version. Android and iOS are gated independently
/// (separate store submissions, separate build numbers).
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.forceUpdate,
    required this.updateMessage,
    required this.storeUrl,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        latestVersion: asString(json['latestVersion']),
        latestBuildNumber: asInt(json['latestBuildNumber']),
        forceUpdate: asBool(json['forceUpdate']),
        updateMessage: asString(json['updateMessage']),
        storeUrl: asString(json['storeUrl']),
      );

  final String latestVersion;
  final int latestBuildNumber;
  final bool forceUpdate;
  final String updateMessage;
  final String storeUrl;
}

class PublicConfigRepository {
  PublicConfigRepository(this._dio);

  final Dio _dio;

  Future<String?> googleApiKey() => apiCall(
        () => _dio.get('/public-config'),
        (d) => asStringOrNull(asMap(d)['googleApiKey']),
      );

  Future<AppUpdateInfo?> appUpdateInfo() => apiCall(
        () => _dio.get('/public-config'),
        (d) {
          final appVersion = asMap(asMap(d)['appVersion']);
          final platformKey = Platform.isIOS ? 'ios' : 'android';
          final raw = appVersion[platformKey];
          if (raw == null) return null;
          return AppUpdateInfo.fromJson(asMap(raw));
        },
      );
}
