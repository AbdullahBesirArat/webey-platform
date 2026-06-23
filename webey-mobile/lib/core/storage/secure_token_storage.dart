import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureTokenStorage {
  const SecureTokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const tokenKey = 'webey_mobile_token';
  static const userTypeKey = 'webey_mobile_user_type';

  final FlutterSecureStorage _storage;

  Future<void> saveToken(String token) {
    return _storage.write(key: tokenKey, value: token);
  }

  Future<String?> readToken() {
    return _storage.read(key: tokenKey);
  }

  Future<void> clearToken() {
    return _storage.delete(key: tokenKey);
  }

  Future<void> saveUserType(String userType) {
    return _storage.write(key: userTypeKey, value: userType);
  }

  Future<String?> readUserType() {
    return _storage.read(key: userTypeKey);
  }

  Future<void> clearAll() async {
    await _storage.delete(key: tokenKey);
    await _storage.delete(key: userTypeKey);
  }
}
