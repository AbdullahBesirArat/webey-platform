import 'auth_user.dart';

class AuthResponse {
  const AuthResponse({
    required this.token,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
  });

  final String token;
  final String tokenType;
  final int expiresIn;
  final MobileAuthUser user;

  factory AuthResponse.fromJson(Map<String, Object?> json) {
    final userJson = json['user'];
    return AuthResponse(
      token: json['token']?.toString() ?? '',
      tokenType: json['token_type']?.toString() ?? 'Bearer',
      expiresIn: int.tryParse(json['expires_in']?.toString() ?? '') ?? 0,
      user: userJson is Map
          ? MobileAuthUser.fromJson(Map<String, Object?>.from(userJson))
          : const MobileAuthUser(id: '', userType: 'customer'),
    );
  }
}
