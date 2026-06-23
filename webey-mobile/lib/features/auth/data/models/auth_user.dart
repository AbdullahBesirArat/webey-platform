import '../../../../shared/models/beauty_models.dart';

class MobileAuthUser {
  const MobileAuthUser({
    required this.id,
    required this.userType,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.avatarUrl = '',
    this.businessId,
    this.businessName,
    this.isPhoneVerified = false,
    this.isEmailVerified = false,
    this.businessOnboardingCompleted,
    this.adminOnboardingCompleted,
    this.onboardingStep,
    this.createdAt,
  });

  final String id;
  final String userType;
  final String name;
  final String email;
  final String phone;
  final String avatarUrl;
  final String? businessId;
  final String? businessName;
  final bool isPhoneVerified;
  final bool isEmailVerified;
  final bool? businessOnboardingCompleted;
  final bool? adminOnboardingCompleted;
  final int? onboardingStep;
  final DateTime? createdAt;

  factory MobileAuthUser.fromJson(Map<String, Object?> json) {
    final type = _string(json['type']).isNotEmpty
        ? _string(json['type'])
        : _string(json['role']);
    final firstName = _string(json['first_name']);
    final lastName = _string(json['last_name']);
    final fullName = _string(json['full_name']);
    final fallbackName = _string(json['name']);
    final combinedName = [
      firstName,
      lastName,
    ].where((part) => part.trim().isNotEmpty).join(' ').trim();

    return MobileAuthUser(
      id: _string(json['id']),
      userType: type.isEmpty ? 'customer' : type,
      name: combinedName.isNotEmpty
          ? combinedName
          : (fullName.isNotEmpty ? fullName : fallbackName),
      email: _string(json['email']),
      phone: _string(json['phone']),
      avatarUrl: _string(json['avatar_url']),
      businessId: _nullableString(json['business_id']),
      businessName: _nullableString(json['business_name']),
      isPhoneVerified: json['phone_verified'] == true,
      isEmailVerified:
          json['email_verified'] == true || json['email_ok'] == true,
      businessOnboardingCompleted: _nullableBool(
        json['business_onboarding_completed'] ??
            json['businessOnboardingCompleted'],
      ),
      adminOnboardingCompleted: _nullableBool(
        json['admin_onboarding_completed'] ?? json['adminOnboardingCompleted'],
      ),
      onboardingStep: _nullableInt(
        json['onboarding_step'] ?? json['onboardingStep'],
      ),
      createdAt: DateTime.tryParse(_string(json['created_at'])),
    );
  }

  AuthUser toBeautyAuthUser() {
    return AuthUser(
      id: id,
      fullName: name.isEmpty ? email : name,
      phone: phone,
      email: email,
      avatarUrl: avatarUrl,
      role: userType == 'business' || userType == 'admin'
          ? UserRole.businessOwner
          : UserRole.customer,
      isPhoneVerified: isPhoneVerified,
      isEmailVerified: isEmailVerified,
      businessOnboardingCompleted: businessOnboardingCompleted,
      adminOnboardingCompleted: adminOnboardingCompleted,
      onboardingStep: onboardingStep,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  static String _string(Object? value) => value?.toString() ?? '';

  static String? _nullableString(Object? value) {
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : text;
  }

  static bool? _nullableBool(Object? value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return null;
    if (text == '1' || text == 'true' || text == 'yes') return true;
    if (text == '0' || text == 'false' || text == 'no') return false;
    return null;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
