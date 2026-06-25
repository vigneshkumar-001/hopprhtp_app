import '../../core/network/json.dart';
import 'user_dto.dart';

/// A fresh access/refresh pair (returned bare by `POST /auth/refresh`).
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory AuthTokens.fromJson(Map<String, dynamic> j) => AuthTokens(
        accessToken: asString(j['accessToken']),
        refreshToken: asString(j['refreshToken']),
      );
}

/// Result of a successful login / register-confirm: the user plus their tokens.
class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  final ApiUser user;
  final String accessToken;
  final String refreshToken;

  factory AuthSession.fromJson(Map<String, dynamic> j) => AuthSession(
        user: ApiUser.fromJson(asMap(j['user'])),
        accessToken: asString(j['accessToken']),
        refreshToken: asString(j['refreshToken']),
      );
}
