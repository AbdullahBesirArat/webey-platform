// lib/features/business/presentation/business_management_screens.dart
//
// Claude Design → Flutter dönüşümü
// Webey İşletme — 4 Yönetim Ekranı
// Personel · Hizmet Kataloğu · Gelir Raporu · Kapora Politikası

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/webey_colors.dart';
import '../../../shared/models/beauty_models.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/widgets/webey_toast.dart';
import '../data/models/business_service_category.dart';
import '../data/models/business_service_item.dart';
import '../data/models/business_staff_item.dart';
import '../data/repositories/business_repository.dart';
import '../data/tr_bank_codes.dart';
import 'business_campaigns_screen.dart';
import 'business_gallery_screen.dart';
import 'business_service_categories_screen.dart';
import 'widgets/service_category_picker.dart';

const _serviceDurationOptions = [15, 30, 45, 60, 90, 120];
const _depositRateOptions = [25, 50, 75, 100];

int _nearestServiceDuration(int value) {
  var best = _serviceDurationOptions.first;
  var bestDistance = (value - best).abs();
  for (final option in _serviceDurationOptions.skip(1)) {
    final distance = (value - option).abs();
    if (distance < bestDistance) {
      best = option;
      bestDistance = distance;
    }
  }
  return best;
}

int _normalizedDepositRate(int value) {
  return _depositRateOptions.contains(value) ? value : 25;
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA
// ─────────────────────────────────────────────────────────────────────────────

class _StaffMember {
  _StaffMember({
    this.backendId,
    required this.id,
    required this.name,
    required this.role,
    required this.rating,
    required this.rdv,
    required this.initial,
    required this.colorA,
    required this.colorB,
    required this.chips,
    required this.avail,
    this.isOnline = false,
    this.isOffline = false,
    required this.isAvailableToday,
  });
  final int? backendId;
  final String id, name, role, rating, rdv, initial, avail;
  final Color colorA, colorB;
  final List<String> chips;
  final bool isOnline, isOffline;
  bool isAvailableToday;
}

// ignore: unused_element
final _kStaff = [
  _StaffMember(
    id: 's1',
    name: 'Ece Yıldız',
    role: 'Nail Artist',
    rating: '4.9',
    rdv: '320',
    initial: 'EY',
    colorA: const Color(0xFFD4B574),
    colorB: const Color(0xFF8C6F38),
    chips: ['Protez Tırnak', 'Kalıcı Oje', 'Nail Art'],
    avail: 'Bugün 16:30 sonrası uygun',
    isOnline: true,
    isAvailableToday: true,
  ),
  _StaffMember(
    id: 's2',
    name: 'Mina Acar',
    role: 'Kaş & Kirpik Uzmanı',
    rating: '4.8',
    rdv: '210',
    initial: 'MA',
    colorA: const Color(0xFFB8964E),
    colorB: const Color(0xFF5d4a2c),
    chips: ['Kaş Tasarımı', 'Lifting', 'Brow Lamination'],
    avail: 'Yarın 11:00\'den itibaren uygun',
    isAvailableToday: true,
  ),
  _StaffMember(
    id: 's3',
    name: 'Lara Demir',
    role: 'Nail Art Uzmanı',
    rating: '4.9',
    rdv: '185',
    initial: 'LD',
    colorA: const Color(0xFFC7A26A),
    colorB: const Color(0xFF806440),
    chips: ['Krom Nail Art', 'Press-On'],
    avail: 'Bugün müsait değil',
    isOffline: true,
    isAvailableToday: false,
  ),
  _StaffMember(
    id: 's4',
    name: 'Naz Öztürk',
    role: 'Pedikür Uzmanı',
    rating: '4.7',
    rdv: '163',
    initial: 'NÖ',
    colorA: const Color(0xFFA0824A),
    colorB: const Color(0xFF503e23),
    chips: ['Pedikür', 'Medikal Tırnak'],
    avail: 'Bugün 14:00–18:00 uygun',
    isOnline: true,
    isAvailableToday: true,
  ),
];

class _SvcItem {
  _SvcItem({
    this.backendId,
    required this.name,
    required this.desc,
    required this.dur,
    required this.price,
    this.durationMinutes = 60,
    this.priceValue = 0,
    this.category,
    required this.staff,
    required this.isActive,
  });
  final int? backendId;
  final String name, desc, dur, price;
  final int durationMinutes;
  final double priceValue;
  final String? category;
  final List<({String initial, Color colorA, Color colorB})> staff;
  bool isActive;
}

// ignore: unused_element
final _kSvcs = [
  _SvcItem(
    name: 'Protez Tırnak + Kalıcı Oje',
    desc: 'Premium jel uygulama ve kalıcı oje.',
    dur: '90 dk',
    price: '1.200',
    staff: [
      (
        initial: 'EY',
        colorA: const Color(0xFFD4B574),
        colorB: const Color(0xFF8C6F38),
      ),
      (
        initial: 'MA',
        colorA: const Color(0xFFB8964E),
        colorB: const Color(0xFF5d4a2c),
      ),
    ],
    isActive: true,
  ),
  _SvcItem(
    name: 'Kalıcı Oje',
    desc: 'Uzun süre dayanıklı parlak görünüm.',
    dur: '45 dk',
    price: '650',
    staff: [
      (
        initial: 'EY',
        colorA: const Color(0xFFD4B574),
        colorB: const Color(0xFF8C6F38),
      ),
    ],
    isActive: true,
  ),
  _SvcItem(
    name: 'Manikür',
    desc: 'Klasik bakım ve şekillendirme.',
    dur: '35 dk',
    price: '450',
    staff: [
      (
        initial: 'MA',
        colorA: const Color(0xFFB8964E),
        colorB: const Color(0xFF5d4a2c),
      ),
      (
        initial: 'LD',
        colorA: const Color(0xFFC7A26A),
        colorB: const Color(0xFF806440),
      ),
    ],
    isActive: true,
  ),
  _SvcItem(
    name: 'Nail Art Tasarım',
    desc: 'Kişiye özel desen ve detaylandırma.',
    dur: '75 dk',
    price: '880',
    staff: [
      (
        initial: 'LD',
        colorA: const Color(0xFFC7A26A),
        colorB: const Color(0xFF806440),
      ),
    ],
    isActive: true,
  ),
  _SvcItem(
    name: 'Pedikür',
    desc: 'Topuk bakımı ve kalıcı oje.',
    dur: '60 dk',
    price: '620',
    staff: [
      (
        initial: 'NÖ',
        colorA: const Color(0xFFA0824A),
        colorB: const Color(0xFF503e23),
      ),
    ],
    isActive: true,
  ),
  _SvcItem(
    name: 'Lazer Epilasyon',
    desc: 'Bölgesel lazer epilasyon seansı.',
    dur: '45 dk',
    price: '500',
    staff: [],
    isActive: false,
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: Page Header
// ─────────────────────────────────────────────────────────────────────────────

class _MgmtHeader extends StatelessWidget {
  const _MgmtHeader({
    required this.titleBold,
    required this.titleItalic,
    required this.onBack,
    this.subtitle,
    this.trailingWidget,
  });
  final String titleBold, titleItalic;
  final VoidCallback onBack;
  final String? subtitle;
  final Widget? trailingWidget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onBack,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: WebeyColors.warmCream,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: const Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: WebeyColors.darkEspresso,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 20,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(text: titleBold),
                        TextSpan(
                          text: titleItalic,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              trailingWidget ?? const SizedBox(width: 34),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(
              subtitle!,
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _SecH extends StatelessWidget {
  const _SecH({required this.eyebrow, required this.title, this.meta});
  final String eyebrow, title;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 1,
                      color: WebeyColors.primaryGold,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      eyebrow,
                      style: TextStyle(
                        color: WebeyColors.primaryGold,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 15,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (meta != null)
            Text(
              meta!,
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED: FAB Bar
// ─────────────────────────────────────────────────────────────────────────────

class _FabBar extends StatelessWidget {
  const _FabBar({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: WebeyColors.ivory,
        border: Border(top: BorderSide(color: WebeyColors.borderSand)),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: WebeyColors.primaryGold,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                size: 16,
                color: WebeyColors.darkEspresso,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 1 — Personel Yönetimi
// ─────────────────────────────────────────────────────────────────────────────

class _MgmtInlineState extends StatelessWidget {
  const _MgmtInlineState({
    required this.message,
    this.onRetry,
    this.isLoading = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        children: [
          if (isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: WebeyColors.primaryGold,
              ),
            )
          else
            Icon(
              onRetry == null ? Icons.inbox_outlined : Icons.refresh_rounded,
              color: WebeyColors.mutedTaupe,
              size: 24,
            ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12.5),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: WebeyColors.warmCream,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: WebeyColors.borderSand),
                ),
                child: const Text(
                  'Tekrar dene',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _businessManagementError(Object error, String fallback) {
  if (error is ApiException) {
    if (error.message.trim().isNotEmpty) return error.message;
    if (error.code == 'business_required' || error.statusCode == 403) {
      return 'Bu hesaba bağlı işletme bulunamadı.';
    }
    if (error.code == 'service_in_use' || error.statusCode == 409) {
      return 'Bu hizmet geçmiş veya mevcut randevularda kullanıldığı için silinemiyor.';
    }
  }
  return fallback;
}

void _showMgmtSnack(BuildContext context, String message) {
  // Android default toast yerine Webey tasarımında üstten banner.
  final lower = message.toLowerCase();
  const errorHints = [
    'hata',
    'olamaz',
    'geçerli',
    'yüklenemedi',
    'başarısız',
    'alınamadı',
    'gerekli',
    'girin',
    'seçin',
  ];
  const successHints = [
    'kaydedildi',
    'güncellendi',
    'silindi',
    'eklendi',
    'oluşturuldu',
  ];
  if (errorHints.any(lower.contains)) {
    WebeyToast.error(context, message);
  } else if (successHints.any(lower.contains)) {
    WebeyToast.success(context, message);
  } else {
    WebeyToast.info(context, message);
  }
}

Future<bool> _confirmMgmtDelete({
  required BuildContext context,
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: WebeyColors.errorRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sil'),
          ),
        ],
      );
    },
  );
  return result == true;
}

String _initialsForName(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  String firstLetter(String value) => value.isEmpty ? '' : value[0];
  if (parts.length == 1) {
    final value = parts.first;
    return value.length <= 2 ? value.toUpperCase() : value.substring(0, 2);
  }
  return '${firstLetter(parts.first)}${firstLetter(parts.last)}'.toUpperCase();
}

String _formatMoney(double value) {
  return value.round().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
}

Widget _managementSheetFrame({
  required BuildContext context,
  required Widget child,
}) {
  return SafeArea(
    child: Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Material(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    ),
  );
}

Color _avatarColorA(int seed) {
  const colors = [
    Color(0xFFD4B574),
    Color(0xFFB8964E),
    Color(0xFFC7A26A),
    Color(0xFFA0824A),
  ];
  return colors[seed.abs() % colors.length];
}

Color _avatarColorB(int seed) {
  const colors = [
    Color(0xFF8C6F38),
    Color(0xFF5D4A2C),
    Color(0xFF806440),
    Color(0xFF503E23),
  ];
  return colors[seed.abs() % colors.length];
}

class _MgmtTextField extends StatelessWidget {
  const _MgmtTextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      buildCounter:
          (context, {required currentLength, required isFocused, maxLength}) =>
              null,
      style: const TextStyle(color: WebeyColors.darkEspresso, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: WebeyColors.darkEspresso,
          fontSize: 12,
        ),
        hintStyle: const TextStyle(color: WebeyColors.mutedTaupe),
        filled: true,
        fillColor: WebeyColors.softWhite,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: WebeyColors.borderSand,
            width: 1.15,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: WebeyColors.primaryGold,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

// Süre seçimi — kompakt chip grid (15/30/45/60/90/120 dk).
class _MgmtDurationChips extends StatelessWidget {
  const _MgmtDurationChips({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Süre',
          style: TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _serviceDurationOptions.map((minutes) {
            final selected = minutes == value;
            return GestureDetector(
              onTap: () => onChanged(minutes),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? WebeyColors.primaryGold
                      : WebeyColors.softWhite,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: selected
                        ? WebeyColors.primaryGold
                        : WebeyColors.borderSand,
                  ),
                ),
                child: Text(
                  '$minutes dk',
                  style: TextStyle(
                    color: selected
                        ? WebeyColors.darkEspresso
                        : WebeyColors.darkEspresso,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class BusinessStaffScreen extends StatefulWidget {
  const BusinessStaffScreen({super.key});

  @override
  State<BusinessStaffScreen> createState() => _BusinessStaffScreenState();
}

class _BusinessStaffScreenState extends State<BusinessStaffScreen> {
  final _repository = BusinessRepository.instance;
  var _staff = <BusinessStaffItem>[];
  var _services = <BusinessServiceItem>[];
  var _isLoading = true;
  String? _busyStaffId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final staff = await _repository.getStaff(includeInactive: true);
      final services = await _repository.getServices(includeInactive: true);
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _services = services;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(
          error,
          'Personel listesi yüklenemedi.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleStaff(BusinessStaffItem item) async {
    final busyId = '${item.id ?? item.name}';
    if (_busyStaffId != null) return;
    setState(() => _busyStaffId = busyId);
    try {
      await _repository.saveStaff(item.copyWith(isActive: !item.isActive));
      await _loadStaff();
    } catch (error) {
      if (!mounted) return;
      _showMgmtSnack(
        context,
        _businessManagementError(error, 'Personel kaydedilemedi.'),
      );
    } finally {
      if (mounted) setState(() => _busyStaffId = null);
    }
  }

  Future<void> _openStaffCrudEditor([BusinessStaffItem? item]) async {
    final nameController = TextEditingController(text: item?.name ?? '');
    final roleController = TextEditingController(text: item?.role ?? '');
    final phoneController = TextEditingController(text: item?.phone ?? '');
    final emailController = TextEditingController(text: item?.email ?? '');
    var isActive = item?.isActive ?? true;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var isSaving = false;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> save() async {
              if (isSaving) return;
              final name = nameController.text.trim();
              final email = emailController.text.trim();
              if (name.isEmpty) {
                _showMgmtSnack(sheetContext, 'Personel adı boş olamaz.');
                return;
              }
              if (email.isNotEmpty &&
                  !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                _showMgmtSnack(sheetContext, 'Geçerli bir e-posta girin.');
                return;
              }
              final phoneDigits = phoneController.text.replaceAll(
                RegExp(r'\D'),
                '',
              );
              if (phoneDigits.isNotEmpty &&
                  phoneDigits.length != 10 &&
                  phoneDigits.length != 11) {
                _showMgmtSnack(
                  sheetContext,
                  'Telefon numarası 10 veya 11 haneli olmalı.',
                );
                return;
              }

              final payload = BusinessStaffItem(
                id: item?.id,
                name: name,
                role: roleController.text.trim().isEmpty
                    ? null
                    : roleController.text.trim(),
                phone: phoneDigits.isEmpty ? null : phoneDigits,
                email: email.isEmpty ? null : email,
                avatarUrl: item?.avatarUrl,
                isActive: isActive,
                serviceIds: item?.serviceIds ?? const [],
                hours: item?.hours ?? const [],
              );

              setSheetState(() => isSaving = true);
              try {
                await _repository.saveStaff(payload);
                if (!mounted) return;
                await _loadStaff();
                if (sheetContext.mounted) {
                  Navigator.pop(
                    sheetContext,
                    item == null ? 'created' : 'updated',
                  );
                }
              } catch (error) {
                if (!sheetContext.mounted) return;
                _showMgmtSnack(
                  sheetContext,
                  _businessManagementError(error, 'Personel kaydedilemedi.'),
                );
                setSheetState(() => isSaving = false);
              }
            }

            Future<void> remove() async {
              if (isSaving) return;
              final id = item?.id;
              if (id == null) return;
              final confirmed = await _confirmMgmtDelete(
                context: sheetContext,
                title: 'Personel silinsin mi?',
                message: 'Bu personel listeden kaldırılacak.',
              );
              if (!confirmed || !sheetContext.mounted) return;

              setSheetState(() => isSaving = true);
              try {
                await _repository.deleteStaff(id);
                if (!mounted) return;
                await _loadStaff();
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext, 'deleted');
                }
              } catch (error) {
                if (!sheetContext.mounted) return;
                _showMgmtSnack(
                  sheetContext,
                  _businessManagementError(error, 'Personel silinemedi.'),
                );
                setSheetState(() => isSaving = false);
              }
            }

            return _managementSheetFrame(
              context: sheetContext,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item == null ? 'Yeni uzman' : 'Uzmanı düzenle',
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 18,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MgmtTextField(controller: nameController, label: 'Ad'),
                  const SizedBox(height: 10),
                  _MgmtTextField(controller: roleController, label: 'Rol'),
                  const SizedBox(height: 10),
                  _MgmtTextField(
                    controller: phoneController,
                    label: 'Telefon (10-11 hane)',
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _MgmtTextField(
                    controller: emailController,
                    label: 'E-posta',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Aktif',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: isActive,
                        activeThumbColor: WebeyColors.primaryGold,
                        onChanged: isSaving
                            ? null
                            : (value) => setSheetState(() => isActive = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (item?.id != null)
                        TextButton(
                          onPressed: isSaving ? null : remove,
                          child: const Text('Sil'),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: isSaving
                            ? null
                            : () => Navigator.pop(sheetContext),
                        child: const Text('Vazgeç'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(96, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        onPressed: isSaving ? null : save,
                        child: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: WebeyColors.darkEspresso,
                                ),
                              )
                            : const Text('Kaydet'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    final message = switch (result) {
      'created' => 'Personel kaydedildi.',
      'updated' => 'Personel güncellendi.',
      'deleted' => 'Personel silindi.',
      _ => null,
    };
    if (message != null) _showMgmtSnack(context, message);
  }

  // ignore: unused_element
  Future<void> _openStaffEditor([BusinessStaffItem? item]) async {
    final nameController = TextEditingController(text: item?.name ?? '');
    final roleController = TextEditingController(text: item?.role ?? '');
    final phoneController = TextEditingController(text: item?.phone ?? '');
    final emailController = TextEditingController(text: item?.email ?? '');
    var isActive = item?.isActive ?? true;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return _managementSheetFrame(
              context: context,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item == null ? 'Yeni uzman' : 'Uzmanı düzenle',
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 18,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MgmtTextField(controller: nameController, label: 'Ad'),
                  const SizedBox(height: 10),
                  _MgmtTextField(controller: roleController, label: 'Rol'),
                  const SizedBox(height: 10),
                  _MgmtTextField(
                    controller: phoneController,
                    label: 'Telefon (10-11 hane)',
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _MgmtTextField(
                    controller: emailController,
                    label: 'E-posta',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Aktif',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: isActive,
                        activeThumbColor: WebeyColors.primaryGold,
                        onChanged: (value) =>
                            setSheetState(() => isActive = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (item?.id != null)
                        TextButton(
                          onPressed: () => Navigator.pop(context, 'delete'),
                          child: const Text('Sil'),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Vazgeç'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(96, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        onPressed: () => Navigator.pop(context, 'save'),
                        child: const Text('Kaydet'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;

    if (result == 'delete') {
      final id = item?.id;
      if (id == null) return;
      try {
        await _repository.deleteStaff(id);
        await _loadStaff();
        if (mounted) _showMgmtSnack(context, 'Personel silindi.');
      } catch (error) {
        if (!mounted) return;
        _showMgmtSnack(
          context,
          _businessManagementError(error, 'Personel silinemedi.'),
        );
      }
      return;
    }

    final name = nameController.text.trim();
    final email = emailController.text.trim();
    if (name.isEmpty) {
      _showMgmtSnack(context, 'Personel adı boş olamaz.');
      return;
    }
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _showMgmtSnack(context, 'Geçerli bir e-posta girin.');
      return;
    }
    final phoneDigits = phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.isNotEmpty &&
        phoneDigits.length != 10 &&
        phoneDigits.length != 11) {
      _showMgmtSnack(context, 'Telefon numarası 10 veya 11 haneli olmalı.');
      return;
    }

    final payload = BusinessStaffItem(
      id: item?.id,
      name: name,
      role: roleController.text.trim().isEmpty
          ? null
          : roleController.text.trim(),
      phone: phoneDigits.isEmpty ? null : phoneDigits,
      email: email.isEmpty ? null : email,
      avatarUrl: item?.avatarUrl,
      isActive: isActive,
      serviceIds: item?.serviceIds ?? const [],
      hours: item?.hours ?? const [],
    );

    try {
      await _repository.saveStaff(payload);
      await _loadStaff();
      if (mounted) _showMgmtSnack(context, 'Personel kaydedildi.');
    } catch (error) {
      if (!mounted) return;
      _showMgmtSnack(
        context,
        _businessManagementError(error, 'Personel kaydedilemedi.'),
      );
    }
  }

  _StaffMember _staffCardItem(BusinessStaffItem item, int index) {
    final serviceNames = _services
        .where(
          (service) =>
              service.id != null && item.serviceIds.contains(service.id),
        )
        .map((service) => service.name)
        .where((name) => name.isNotEmpty)
        .take(3)
        .toList();
    return _StaffMember(
      backendId: item.id,
      id: '${item.id ?? index}',
      name: item.name.isEmpty ? 'Uzman' : item.name,
      role: item.role?.isNotEmpty == true ? item.role! : 'Uzman',
      rating: '-',
      rdv: '-',
      initial: _initialsForName(item.name),
      colorA: _avatarColorA(index),
      colorB: _avatarColorB(index),
      chips: serviceNames.isEmpty ? ['Hizmet atanmamış'] : serviceNames,
      avail: item.isActive ? 'Bugün müsait' : 'Bugün müsait değil',
      isOnline: item.isActive,
      isOffline: !item.isActive,
      isAvailableToday: item.isActive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _staff.where((item) => item.isActive).length;
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: WebeyColors.primaryGold,
                onRefresh: _loadStaff,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _MgmtHeader(
                        titleBold: 'Per',
                        titleItalic: 'sonel',
                        onBack: () => Navigator.maybePop(context),
                        subtitle:
                            'Uzmanlarınızı ve müsaitlik saatlerini yönetin.',
                        trailingWidget: GestureDetector(
                          onTap: () => _openStaffCrudEditor(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: WebeyColors.primaryGold,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.add_rounded,
                                  size: 13,
                                  color: WebeyColors.darkEspresso,
                                ),
                                const SizedBox(width: 4),
                                const Text(
                                  'Ekle',
                                  style: TextStyle(
                                    color: WebeyColors.darkEspresso,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Stats row
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: WebeyColors.softWhite,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: WebeyColors.borderSand),
                          ),
                          child: Row(
                            children: [
                              _StatsCell(
                                value: '$activeCount',
                                unit: 'uzm.',
                                label: 'Aktif',
                              ),
                              Container(
                                width: 1,
                                height: 44,
                                color: WebeyColors.borderSand,
                              ),
                              _StatsCell(
                                value: '${_staff.length}',
                                unit: '',
                                label: 'Toplam',
                              ),
                              Container(
                                width: 1,
                                height: 44,
                                color: WebeyColors.borderSand,
                              ),
                              _StatsCell(
                                value: '-',
                                unit: '★',
                                label: 'Ort. puan',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SecH(
                        eyebrow: 'EKİP',
                        title: 'Tüm uzmanlar',
                        meta: '${_staff.length} / ${_staff.length}',
                      ),
                    ),
                    // Staff cards
                    if (_isLoading)
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _MgmtInlineState(
                            message: 'Personel listesi yükleniyor...',
                            isLoading: true,
                          ),
                        ),
                      )
                    else if (_error != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _MgmtInlineState(
                            message: _error!,
                            onRetry: _loadStaff,
                          ),
                        ),
                      )
                    else if (_staff.isEmpty)
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _MgmtInlineState(
                            message: 'Henüz personel eklenmemiş.',
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((context, i) {
                            final item = _staff[i];
                            return _StaffCard(
                              member: _staffCardItem(item, i),
                              onToggle: () => _toggleStaff(item),
                              onEdit: () => _openStaffCrudEditor(item),
                              onViewCalendar: () {},
                            );
                          }, childCount: _staff.length),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],
                ),
              ),
            ),
          ),
          _FabBar(
            label: 'Yeni Uzman Ekle',
            onTap: () => _openStaffCrudEditor(),
          ),
        ],
      ),
    );
  }
}

class _StatsCell extends StatelessWidget {
  const _StatsCell({
    required this.value,
    required this.unit,
    required this.label,
  });
  final String value, unit, label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 18,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  TextSpan(text: value),
                  if (unit.isNotEmpty)
                    TextSpan(
                      text: unit,
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({
    required this.member,
    required this.onToggle,
    required this.onEdit,
    required this.onViewCalendar,
  });
  final _StaffMember member;
  final VoidCallback onToggle, onEdit, onViewCalendar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                Stack(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [member.colorA, member.colorB],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          member.initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    if (member.isOnline)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: WebeyColors.successGreen,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                    if (member.isOffline)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: WebeyColors.mutedTaupe,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        member.role,
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.star_rounded,
                            size: 11,
                            color: WebeyColors.primaryGold,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            member.rating,
                            style: const TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            ' · ${member.rdv} rdv',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: member.chips
                            .map(
                              (c) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: WebeyColors.warmCream,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: WebeyColors.borderSand,
                                  ),
                                ),
                                child: Text(
                                  c,
                                  style: TextStyle(
                                    color: WebeyColors.mutedTaupe,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                // Edit
                GestureDetector(
                  onTap: onEdit,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: WebeyColors.warmCream,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: WebeyColors.borderSand),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      size: 13,
                      color: WebeyColors.darkEspresso,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: WebeyColors.borderSand),
            const SizedBox(height: 10),
            // Footer
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: member.isOffline
                        ? WebeyColors.mutedTaupe
                        : WebeyColors.successGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    member.avail,
                    style: TextStyle(
                      color: member.isOffline
                          ? WebeyColors.mutedTaupe
                          : WebeyColors.darkEspresso,
                      fontSize: 12,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onViewCalendar,
                  child: Row(
                    children: [
                      Text(
                        'Takvimi Gör',
                        style: TextStyle(
                          color: WebeyColors.primaryGold,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 13,
                        color: WebeyColors.primaryGold,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Today availability toggle
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 12,
                  color: WebeyColors.mutedTaupe,
                ),
                const SizedBox(width: 6),
                Text(
                  'Bugün müsait',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onToggle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 42,
                    height: 24,
                    decoration: BoxDecoration(
                      color: member.isAvailableToday
                          ? WebeyColors.primaryGold
                          : WebeyColors.borderSand,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        alignment: member.isAvailableToday
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 2 — Hizmet Kataloğu
// ─────────────────────────────────────────────────────────────────────────────

class BusinessServicesScreen extends StatefulWidget {
  const BusinessServicesScreen({super.key});

  @override
  State<BusinessServicesScreen> createState() => _BusinessServicesScreenState();
}

class _BusinessServicesScreenState extends State<BusinessServicesScreen> {
  final _repository = BusinessRepository.instance;
  var _services = <BusinessServiceItem>[];
  var _staff = <BusinessStaffItem>[];
  var _serviceCategories = <BusinessServiceCategory>[];
  var _isLoading = true;
  String? _busyServiceId;
  String? _error;
  String _activeCat = 'Tümü';
  String _statusFilter = 'all';
  String _assignmentFilter = 'all';
  String _sortMode = 'default';

  static const _cats = ['Tümü', 'Tırnak', 'Saç', 'Cilt', 'Kaş', 'Spa'];

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final services = await _repository.getServices(includeInactive: true);
      final staff = await _repository.getStaff();
      var categories = _serviceCategories;
      try {
        categories = await _repository.getServiceCategories();
      } catch (_) {
        // Kategori listesi alınamazsa hizmet yönetimi bloklanmaz.
      }
      if (!mounted) return;
      setState(() {
        _services = services;
        _staff = staff;
        _serviceCategories = categories;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'Hizmetler yüklenemedi.');
        _isLoading = false;
      });
    }
  }

  List<BusinessServiceItem> get _visibleServices {
    Iterable<BusinessServiceItem> items = _services;
    if (_activeCat != _cats.first) {
      items = items.where((item) => _serviceMatchesCategory(item));
    }
    if (_statusFilter == 'active') {
      items = items.where((item) => item.isActive);
    } else if (_statusFilter == 'inactive') {
      items = items.where((item) => !item.isActive);
    }
    if (_assignmentFilter != 'all') {
      items = items.where((item) {
        final id = item.id;
        final assigned =
            id != null && _staff.any((staff) => staff.serviceIds.contains(id));
        return _assignmentFilter == 'assigned' ? assigned : !assigned;
      });
    }
    final list = items.toList();
    switch (_sortMode) {
      case 'price_asc':
        list.sort((a, b) => a.price.compareTo(b.price));
      case 'price_desc':
        list.sort((a, b) => b.price.compareTo(a.price));
      case 'duration_asc':
        list.sort((a, b) => a.durationMinutes.compareTo(b.durationMinutes));
      case 'duration_desc':
        list.sort((a, b) => b.durationMinutes.compareTo(a.durationMinutes));
      default:
        list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return list;
  }

  bool _serviceMatchesCategory(BusinessServiceItem item) {
    final text = '${item.category ?? ''} ${item.name}'.toLowerCase();
    switch (_activeCat) {
      case 'Tırnak':
        return text.contains('nail') ||
            text.contains('tırnak') ||
            text.contains('tirnak') ||
            text.contains('oje') ||
            text.contains('manik') ||
            text.contains('pedik');
      case 'Saç':
        return text.contains('hair') ||
            text.contains('saç') ||
            text.contains('sac');
      case 'Cilt':
        return text.contains('skin') ||
            text.contains('cilt') ||
            text.contains('lazer');
      case 'Kaş':
        return text.contains('brow') ||
            text.contains('kaş') ||
            text.contains('kas');
      case 'Spa':
        return text.contains('spa') ||
            text.contains('masaj') ||
            text.contains('pedik');
    }
    return true;
  }

  Future<void> _toggleService(BusinessServiceItem item) async {
    final busyId = '${item.id ?? item.name}';
    if (_busyServiceId != null) return;
    final desired = !item.isActive;
    final previousServices = List<BusinessServiceItem>.from(_services);
    setState(() {
      _busyServiceId = busyId;
      _services = _services
          .map(
            (s) => (s.id != null && s.id == item.id)
                ? s.copyWith(isActive: desired)
                : s,
          )
          .toList();
    });
    try {
      final saved = await _repository.saveService(
        item.copyWith(isActive: desired),
      );
      if (!mounted) return;
      setState(() {
        _services = _services
            .map((s) => (s.id != null && s.id == saved.id) ? saved : s)
            .toList();
      });
      _showMgmtSnack(context, 'Hizmet güncellendi.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _services = previousServices);
      _showMgmtSnack(
        context,
        _businessManagementError(error, 'Hizmet kaydedilemedi.'),
      );
    } finally {
      if (mounted) setState(() => _busyServiceId = null);
    }
  }

  Future<void> _openServiceCrudEditor([BusinessServiceItem? item]) async {
    final nameController = TextEditingController(text: item?.name ?? '');
    final descController = TextEditingController(text: item?.description ?? '');
    final priceController = TextEditingController(
      text: item == null ? '' : item.price.round().toString(),
    );
    var durationMinutes = _nearestServiceDuration(item?.durationMinutes ?? 60);
    int? selectedCategoryId = item?.categoryId;
    String? selectedCategoryName = item?.category;
    var isActive = item?.isActive ?? true;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        var isSaving = false;
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> save() async {
              if (isSaving) return;
              final name = nameController.text.trim();
              final price = double.tryParse(
                priceController.text.trim().replaceAll(',', '.'),
              );
              if (name.isEmpty) {
                _showMgmtSnack(sheetContext, 'Hizmet adı boş olamaz.');
                return;
              }
              if (price == null || price < 0) {
                _showMgmtSnack(sheetContext, 'Fiyat 0 veya daha büyük olmalı.');
                return;
              }
              if (!_serviceDurationOptions.contains(durationMinutes)) {
                _showMgmtSnack(sheetContext, 'Lütfen hizmet süresi seçin.');
                return;
              }

              final payload = BusinessServiceItem(
                id: item?.id,
                name: name,
                description: descController.text.trim().isEmpty
                    ? null
                    : descController.text.trim(),
                price: price,
                durationMinutes: durationMinutes,
                category: selectedCategoryName,
                categoryId: selectedCategoryId,
                isActive: isActive,
                sortOrder: item?.sortOrder ?? 0,
              );

              setSheetState(() => isSaving = true);
              try {
                await _repository.saveService(payload);
                if (!mounted) return;
                await _loadServices();
                if (sheetContext.mounted) {
                  Navigator.pop(
                    sheetContext,
                    item == null ? 'created' : 'updated',
                  );
                }
              } catch (error) {
                if (!sheetContext.mounted) return;
                _showMgmtSnack(
                  sheetContext,
                  _businessManagementError(error, 'Hizmet kaydedilemedi.'),
                );
                setSheetState(() => isSaving = false);
              }
            }

            Future<void> remove() async {
              if (isSaving) return;
              final id = item?.id;
              if (id == null) return;
              final confirmed = await _confirmMgmtDelete(
                context: sheetContext,
                title: 'Hizmet silinsin mi?',
                message: 'Bu hizmet listeden kaldırılacak.',
              );
              if (!confirmed || !sheetContext.mounted) return;

              setSheetState(() => isSaving = true);
              try {
                await _repository.deleteService(id);
                if (!mounted) return;
                await _loadServices();
                if (sheetContext.mounted) {
                  Navigator.pop(sheetContext, 'deleted');
                }
              } catch (error) {
                if (!sheetContext.mounted) return;
                _showMgmtSnack(
                  sheetContext,
                  _businessManagementError(error, 'Hizmet silinemedi.'),
                );
                setSheetState(() => isSaving = false);
              }
            }

            return _managementSheetFrame(
              context: sheetContext,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item == null ? 'Yeni hizmet' : 'Hizmeti düzenle',
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 18,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MgmtTextField(controller: nameController, label: 'Ad'),
                  const SizedBox(height: 10),
                  _MgmtTextField(
                    controller: descController,
                    label: 'Açıklama',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  _MgmtTextField(
                    controller: priceController,
                    label: 'Fiyat (TL)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 14),
                  _MgmtDurationChips(
                    value: durationMinutes,
                    onChanged: (value) =>
                        setSheetState(() => durationMinutes = value),
                  ),
                  const SizedBox(height: 10),
                  ServiceCategoryField(
                    label: 'Hizmet Kategorisi',
                    valueText: selectedCategoryName,
                    enabled: !isSaving,
                    onTap: () async {
                      final picked = await showServiceCategoryPicker(
                        sheetContext,
                        repository: _repository,
                        categories: _serviceCategories,
                        selectedId: selectedCategoryId,
                      );
                      if (picked == null) return;
                      final category = picked.category;
                      if (category != null &&
                          !_serviceCategories.any((c) => c.id == category.id)) {
                        // "Yeni kategori oluştur" ile eklenen kategori listeye girer.
                        setState(
                          () => _serviceCategories = [
                            ..._serviceCategories,
                            category,
                          ],
                        );
                      }
                      setSheetState(() {
                        selectedCategoryId = category?.id;
                        selectedCategoryName = category?.name;
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Aktif',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: isActive,
                        activeThumbColor: WebeyColors.primaryGold,
                        onChanged: isSaving
                            ? null
                            : (value) => setSheetState(() => isActive = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (item?.id != null)
                        TextButton(
                          onPressed: isSaving ? null : remove,
                          child: const Text('Sil'),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: isSaving
                            ? null
                            : () => Navigator.pop(sheetContext),
                        child: const Text('Vazgeç'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(96, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        onPressed: isSaving ? null : save,
                        child: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: WebeyColors.darkEspresso,
                                ),
                              )
                            : const Text('Kaydet'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    final message = switch (result) {
      'created' => 'Hizmet kaydedildi.',
      'updated' => 'Hizmet güncellendi.',
      'deleted' => 'Hizmet silindi.',
      _ => null,
    };
    if (message != null) _showMgmtSnack(context, message);
  }

  Future<void> _openServiceFilters() async {
    var status = _statusFilter;
    var assignment = _assignmentFilter;
    var sort = _sortMode;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return _managementSheetFrame(
            context: sheetContext,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Hizmetleri filtrele',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 18,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                _FilterChoiceGroup(
                  title: 'Durum',
                  value: status,
                  options: const [
                    ('all', 'Tümü'),
                    ('active', 'Aktif'),
                    ('inactive', 'Pasif'),
                  ],
                  onChanged: (v) => setSheetState(() => status = v),
                ),
                const SizedBox(height: 12),
                _FilterChoiceGroup(
                  title: 'Atama',
                  value: assignment,
                  options: const [
                    ('all', 'Tümü'),
                    ('assigned', 'Ataması olan'),
                    ('unassigned', 'Atama yok'),
                  ],
                  onChanged: (v) => setSheetState(() => assignment = v),
                ),
                const SizedBox(height: 12),
                _FilterChoiceGroup(
                  title: 'Sıralama',
                  value: sort,
                  options: const [
                    ('default', 'Varsayılan'),
                    ('price_asc', 'Fiyat düşük'),
                    ('price_desc', 'Fiyat yüksek'),
                    ('duration_asc', 'Süre kısa'),
                    ('duration_desc', 'Süre uzun'),
                  ],
                  onChanged: (v) => setSheetState(() => sort = v),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setSheetState(() {
                            status = 'all';
                            assignment = 'all';
                            sort = 'default';
                          });
                        },
                        child: const Text('Temizle'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: const Text('Uygula'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    if (applied != true || !mounted) return;
    setState(() {
      _statusFilter = status;
      _assignmentFilter = assignment;
      _sortMode = sort;
    });
  }

  // ignore: unused_element
  Future<void> _openServiceEditor([BusinessServiceItem? item]) async {
    final nameController = TextEditingController(text: item?.name ?? '');
    final descController = TextEditingController(text: item?.description ?? '');
    final priceController = TextEditingController(
      text: item == null ? '' : item.price.round().toString(),
    );
    var durationMinutes = _nearestServiceDuration(item?.durationMinutes ?? 60);
    final categoryController = TextEditingController(
      text: item?.category ?? '',
    );
    var isActive = item?.isActive ?? true;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return _managementSheetFrame(
              context: context,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item == null ? 'Yeni hizmet' : 'Hizmeti düzenle',
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 18,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MgmtTextField(controller: nameController, label: 'Ad'),
                  const SizedBox(height: 10),
                  _MgmtTextField(
                    controller: descController,
                    label: 'Açıklama',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  _MgmtTextField(
                    controller: priceController,
                    label: 'Fiyat (TL)',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 14),
                  _MgmtDurationChips(
                    value: durationMinutes,
                    onChanged: (value) =>
                        setSheetState(() => durationMinutes = value),
                  ),
                  const SizedBox(height: 10),
                  _MgmtTextField(
                    controller: categoryController,
                    label: 'Kategori',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Aktif',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: isActive,
                        activeThumbColor: WebeyColors.primaryGold,
                        onChanged: (value) =>
                            setSheetState(() => isActive = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (item?.id != null)
                        TextButton(
                          onPressed: () => Navigator.pop(context, 'delete'),
                          child: const Text('Sil'),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Vazgeç'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(96, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        onPressed: () => Navigator.pop(context, 'save'),
                        child: const Text('Kaydet'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;

    if (result == 'delete') {
      final id = item?.id;
      if (id == null) return;
      try {
        await _repository.deleteService(id);
        await _loadServices();
        if (mounted) _showMgmtSnack(context, 'Hizmet silindi.');
      } catch (error) {
        if (!mounted) return;
        _showMgmtSnack(
          context,
          _businessManagementError(error, 'Hizmet silinemedi.'),
        );
      }
      return;
    }

    final name = nameController.text.trim();
    final price = double.tryParse(
      priceController.text.trim().replaceAll(',', '.'),
    );
    if (name.isEmpty) {
      _showMgmtSnack(context, 'Hizmet adı boş olamaz.');
      return;
    }
    if (price == null || price < 0) {
      _showMgmtSnack(context, 'Fiyat 0 veya daha büyük olmalı.');
      return;
    }
    if (!_serviceDurationOptions.contains(durationMinutes)) {
      _showMgmtSnack(context, 'Lütfen hizmet süresi seçin.');
      return;
    }

    final payload = BusinessServiceItem(
      id: item?.id,
      name: name,
      description: descController.text.trim().isEmpty
          ? null
          : descController.text.trim(),
      price: price,
      durationMinutes: durationMinutes,
      category: categoryController.text.trim().isEmpty
          ? null
          : categoryController.text.trim(),
      isActive: isActive,
      sortOrder: item?.sortOrder ?? 0,
    );

    try {
      await _repository.saveService(payload);
      await _loadServices();
      if (mounted) _showMgmtSnack(context, 'Hizmet kaydedildi.');
    } catch (error) {
      if (!mounted) return;
      _showMgmtSnack(
        context,
        _businessManagementError(error, 'Hizmet kaydedilemedi.'),
      );
    }
  }

  _SvcItem _serviceCardItem(BusinessServiceItem item) {
    final assignedStaff = _staff
        .where(
          (member) => item.id != null && member.serviceIds.contains(item.id),
        )
        .take(3)
        .map(
          (member) => (
            initial: _initialsForName(member.name),
            colorA: _avatarColorA(member.id ?? 0),
            colorB: _avatarColorB(member.id ?? 0),
          ),
        )
        .toList();

    return _SvcItem(
      backendId: item.id,
      name: item.name.isEmpty ? 'Hizmet' : item.name,
      desc: item.description?.isNotEmpty == true
          ? item.description!
          : 'Açıklama eklenmemiş.',
      dur: '${item.durationMinutes} dk',
      price: _formatMoney(item.price),
      durationMinutes: item.durationMinutes,
      priceValue: item.price,
      category: item.category,
      staff: assignedStaff,
      isActive: item.isActive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleServices = _visibleServices;
    final averageDuration = _services.isEmpty
        ? 0
        : (_services.fold<int>(
                    0,
                    (total, item) => total + item.durationMinutes,
                  ) /
                  _services.length)
              .round();
    final startingPrice = _services.isEmpty
        ? 0
        : _services
              .map((item) => item.price)
              .reduce((a, b) => a < b ? a : b)
              .round();
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: WebeyColors.primaryGold,
                onRefresh: _loadServices,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _MgmtHeader(
                        titleBold: 'Hizmet',
                        titleItalic: 'ler',
                        onBack: () => Navigator.maybePop(context),
                        trailingWidget: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const BusinessServiceCategoriesScreen(),
                                  ),
                                );
                                if (mounted) _loadServices();
                              },
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: WebeyColors.warmCream,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: WebeyColors.borderSand,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.category_outlined,
                                  size: 16,
                                  color: WebeyColors.darkEspresso,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _openServiceFilters,
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: WebeyColors.warmCream,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: WebeyColors.borderSand,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.tune_rounded,
                                  size: 16,
                                  color: WebeyColors.darkEspresso,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 12.5,
                            ),
                            children: [
                              TextSpan(
                                text: '${_services.length} hizmet',
                                style: const TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: ' · Ortalama '),
                              TextSpan(
                                text: '$averageDuration dk',
                                style: const TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: ' · Başlangıç '),
                              TextSpan(
                                text:
                                    '${_formatMoney(startingPrice.toDouble())} TL',
                                style: const TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Category chips
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          height: 34,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _cats.length,
                            itemBuilder: (_, i) {
                              final isActive = _activeCat == _cats[i];
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _activeCat = _cats[i]),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? WebeyColors.darkEspresso
                                        : WebeyColors.softWhite,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: isActive
                                          ? WebeyColors.darkEspresso
                                          : WebeyColors.borderSand,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _cats[i],
                                      style: TextStyle(
                                        color: isActive
                                            ? Colors.white
                                            : WebeyColors.darkEspresso,
                                        fontSize: 12.5,
                                        fontWeight: isActive
                                            ? FontWeight.w500
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    // Service list
                    if (_isLoading)
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _MgmtInlineState(
                            message: 'Hizmetler yükleniyor...',
                            isLoading: true,
                          ),
                        ),
                      )
                    else if (_error != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _MgmtInlineState(
                            message: _error!,
                            onRetry: _loadServices,
                          ),
                        ),
                      )
                    else if (visibleServices.isEmpty)
                      const SliverPadding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _MgmtInlineState(
                            message: 'Henüz hizmet eklenmemiş.',
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((context, i) {
                            final item = visibleServices[i];
                            return _SvcCard(
                              item: _serviceCardItem(item),
                              onToggle: () => _toggleService(item),
                              onEdit: () => _openServiceCrudEditor(item),
                            );
                          }, childCount: visibleServices.length),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],
                ),
              ),
            ),
          ),
          _FabBar(label: 'Yeni Hizmet', onTap: () => _openServiceCrudEditor()),
        ],
      ),
    );
  }
}

class _FilterChoiceGroup extends StatelessWidget {
  const _FilterChoiceGroup({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              GestureDetector(
                onTap: () => onChanged(option.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: value == option.$1
                        ? WebeyColors.darkEspresso
                        : WebeyColors.softWhite,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: value == option.$1
                          ? WebeyColors.darkEspresso
                          : WebeyColors.borderSand,
                    ),
                  ),
                  child: Text(
                    option.$2,
                    style: TextStyle(
                      color: value == option.$1
                          ? Colors.white
                          : WebeyColors.darkEspresso,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SvcCard extends StatelessWidget {
  const _SvcCard({
    required this.item,
    required this.onToggle,
    required this.onEdit,
  });
  final _SvcItem item;
  final VoidCallback onToggle, onEdit;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: item.isActive ? 1.0 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 3,
                    child: ColoredBox(
                      color: item.isActive
                          ? WebeyColors.primaryGold
                          : WebeyColors.borderSand,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: const TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: onEdit,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: WebeyColors.warmCream,
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: WebeyColors.borderSand,
                                ),
                              ),
                              child: const Icon(
                                Icons.edit_outlined,
                                size: 12,
                                color: WebeyColors.darkEspresso,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.desc,
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          // Duration chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: WebeyColors.warmCream,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: WebeyColors.borderSand),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 10,
                                  color: WebeyColors.mutedTaupe,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  item.dur,
                                  style: TextStyle(
                                    color: WebeyColors.mutedTaupe,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Price chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: WebeyColors.goldLight,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: WebeyColors.primaryGold.withAlpha(60),
                              ),
                            ),
                            child: Text(
                              '${item.price} TL',
                              style: TextStyle(
                                color: WebeyColors.primaryGold,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Staff mini avatars
                          if (item.staff.isNotEmpty)
                            SizedBox(
                              width: 22.0 + ((item.staff.length - 1) * 16.0),
                              height: 22,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  for (
                                    var index = 0;
                                    index < item.staff.length;
                                    index += 1
                                  )
                                    Positioned(
                                      left: index * 16.0,
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            colors: [
                                              item.staff[index].colorA,
                                              item.staff[index].colorB,
                                            ],
                                          ),
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            item.staff[index].initial,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 8,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          if (item.staff.isEmpty)
                            Text(
                              'Atama yok',
                              style: TextStyle(
                                color: WebeyColors.mutedTaupe,
                                fontSize: 10.5,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Divider(height: 1, color: WebeyColors.borderSand),
                      const SizedBox(height: 9),
                      Row(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: item.isActive
                                      ? WebeyColors.successGreen
                                      : WebeyColors.mutedTaupe,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                item.isActive ? 'Aktif' : 'Pasif',
                                style: TextStyle(
                                  color: item.isActive
                                      ? WebeyColors.successGreen
                                      : WebeyColors.mutedTaupe,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: onToggle,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 42,
                              height: 24,
                              decoration: BoxDecoration(
                                color: item.isActive
                                    ? WebeyColors.primaryGold
                                    : WebeyColors.borderSand,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: AnimatedAlign(
                                  duration: const Duration(milliseconds: 200),
                                  alignment: item.isActive
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 3 — Gelir Raporu
// ─────────────────────────────────────────────────────────────────────────────

class BusinessRevenueScreen extends StatefulWidget {
  const BusinessRevenueScreen({super.key});

  @override
  State<BusinessRevenueScreen> createState() => _BusinessRevenueScreenState();
}

class _BusinessRevenueScreenState extends State<BusinessRevenueScreen> {
  static const _monthNames = [
    'Ocak',
    'Şubat',
    'Mart',
    'Nisan',
    'Mayıs',
    'Haziran',
    'Temmuz',
    'Ağustos',
    'Eylül',
    'Ekim',
    'Kasım',
    'Aralık',
  ];

  final _repository = BusinessRepository.instance;
  DateTime _selectedMonth = DateTime.now();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _report = const {};

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month);
    _load();
  }

  String get _monthKey =>
      '${_selectedMonth.year.toString().padLeft(4, '0')}-'
      '${_selectedMonth.month.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repository.getRevenueReport(month: _monthKey);
      if (!mounted) return;
      setState(() {
        _report = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'Gelir raporu alınamadı.');
        _loading = false;
      });
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
    _load();
  }

  String _formatTl(num? value) {
    final v = (value ?? 0).toDouble();
    final str = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      final fromEnd = str.length - i;
      if (i > 0 && fromEnd % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return '₺$buf';
  }

  List<Map<String, dynamic>> get _trend {
    final raw = _report['monthly_trend'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  List<Map<String, dynamic>> get _breakdown {
    final raw = _report['service_breakdown'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final totalRevenue = (_report['total_revenue'] as num?)?.toDouble() ?? 0;
    final apptCount = (_report['appointment_count'] as num?)?.toInt() ?? 0;
    final completed = (_report['completed_count'] as num?)?.toInt() ?? 0;
    final cancelled = (_report['cancelled_count'] as num?)?.toInt() ?? 0;
    final depositTotal = (_report['deposit_total'] as num?)?.toDouble() ?? 0;
    final inSalonTotal = (_report['in_salon_total'] as num?)?.toDouble() ?? 0;
    final emptyMessage = _report['empty_message']?.toString();
    final hasData = _report['has_data'] == true;
    final trend = _trend;
    final maxTrend = trend.fold<double>(0, (m, t) {
      final v = (t['revenue'] as num?)?.toDouble() ?? 0;
      return v > m ? v : m;
    });
    final breakdown = _breakdown;
    final maxBreakdown = breakdown.fold<double>(0, (m, t) {
      final v = (t['revenue'] as num?)?.toDouble() ?? 0;
      return v > m ? v : m;
    });

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _MgmtHeader(
                titleBold: 'Gelir ',
                titleItalic: 'Raporu',
                onBack: () => Navigator.maybePop(context),
                trailingWidget: GestureDetector(
                  onTap: _load,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: WebeyColors.warmCream,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: WebeyColors.borderSand),
                    ),
                    child: const Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: WebeyColors.darkEspresso,
                    ),
                  ),
                ),
              ),
            ),
            // Period pill
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: WebeyColors.softWhite,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: WebeyColors.borderSand),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => _shiftMonth(-1),
                          child: const Icon(
                            Icons.chevron_left_rounded,
                            size: 16,
                            color: WebeyColors.mutedTaupe,
                          ),
                        ),
                        const SizedBox(width: 8),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                            children: [
                              TextSpan(
                                text: _monthNames[_selectedMonth.month - 1],
                                style: const TextStyle(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              TextSpan(text: ' ${_selectedMonth.year}'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _shiftMonth(1),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: WebeyColors.mutedTaupe,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Revenue summary
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: WebeyColors.darkEspresso,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'AY · ${_monthNames[_selectedMonth.month - 1].toUpperCase()} ${_selectedMonth.year}',
                            style: TextStyle(
                              color: Colors.white.withAlpha(120),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const Spacer(),
                          if (_loading)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _formatTl(totalRevenue),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontFamily: 'Georgia',
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$apptCount randevu · $completed tamamlandı · $cancelled iptal',
                        style: TextStyle(
                          color: Colors.white.withAlpha(160),
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withAlpha(15)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        size: 11,
                                        color: Colors.white.withAlpha(120),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Kapora tahsilat',
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(120),
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _formatTl(depositTotal),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 36,
                              color: Colors.white.withAlpha(20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet_outlined,
                                        size: 11,
                                        color: Colors.white.withAlpha(120),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Salonda ödeme',
                                        style: TextStyle(
                                          color: Colors.white.withAlpha(120),
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _formatTl(inSalonTotal),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Monthly chart
            SliverToBoxAdapter(
              child: _SecH(
                eyebrow: 'SON 6 AY',
                title: 'Aylık trend',
                meta: '₺',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: WebeyColors.softWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: trend.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            'Trend verisi yok.',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : Column(
                          children: trend.map((m) {
                            final isActive =
                                m['month']?.toString() == _monthKey;
                            final rev = (m['revenue'] as num?)?.toDouble() ?? 0;
                            final width = maxTrend > 0
                                ? (rev / maxTrend).clamp(0.0, 1.0)
                                : 0.0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      m['label']?.toString() ?? '',
                                      style: TextStyle(
                                        color: isActive
                                            ? WebeyColors.primaryGold
                                            : WebeyColors.mutedTaupe,
                                        fontSize: 11.5,
                                        fontWeight: isActive
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: width,
                                        backgroundColor: WebeyColors.warmCream,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              isActive
                                                  ? WebeyColors.primaryGold
                                                  : WebeyColors.primaryGold
                                                        .withAlpha(120),
                                            ),
                                        minHeight: isActive ? 10 : 7,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 70,
                                    child: Text(
                                      _formatTl(rev),
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        color: isActive
                                            ? WebeyColors.darkEspresso
                                            : WebeyColors.mutedTaupe,
                                        fontSize: 11.5,
                                        fontWeight: isActive
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ),
            ),
            // Service revenue
            SliverToBoxAdapter(
              child: _SecH(
                eyebrow: 'HİZMET BAZLI',
                title: 'Gelir dağılımı',
                meta: 'Top 5',
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: WebeyColors.softWhite,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: breakdown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            emptyMessage ??
                                (hasData
                                    ? 'Bu ay için tamamlanmış randevu yok.'
                                    : 'Bu ay henüz tamamlanan randevu yok.'),
                            style: const TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : Column(
                          children: breakdown.map((s) {
                            final cnt = (s['count'] as num?)?.toInt() ?? 0;
                            final rev = (s['revenue'] as num?)?.toDouble() ?? 0;
                            final width = maxBreakdown > 0
                                ? (rev / maxBreakdown).clamp(0.0, 1.0)
                                : 0.0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          s['name']?.toString() ?? '-',
                                          style: const TextStyle(
                                            color: WebeyColors.darkEspresso,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '$cnt rdv',
                                        style: TextStyle(
                                          color: WebeyColors.mutedTaupe,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _formatTl(rev),
                                        style: const TextStyle(
                                          color: WebeyColors.darkEspresso,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: width,
                                      backgroundColor: WebeyColors.warmCream,
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            WebeyColors.primaryGold,
                                          ),
                                      minHeight: 5,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ),
            ),
            if (_error != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: _MgmtInlineState(message: _error!, onRetry: _load),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 4 — Kapora Politikası
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN — Çalışma Saatleri
// ─────────────────────────────────────────────────────────────────────────────

class BusinessHoursScreen extends StatefulWidget {
  const BusinessHoursScreen({super.key});

  @override
  State<BusinessHoursScreen> createState() => _BusinessHoursScreenState();
}

class _BusinessHoursScreenState extends State<BusinessHoursScreen> {
  final _repository = BusinessRepository.instance;
  var _hours = <Map<String, dynamic>>[];
  var _isLoading = true;
  var _isSaving = false;
  String? _error;

  static const _dayNames = {
    'mon': 'Pazartesi',
    'tue': 'Salı',
    'wed': 'Çarşamba',
    'thu': 'Perşembe',
    'fri': 'Cuma',
    'sat': 'Cumartesi',
    'sun': 'Pazar',
  };

  static const _allDays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  @override
  void initState() {
    super.initState();
    _loadHours();
  }

  Future<void> _loadHours() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final hours = await _repository.getBusinessHours();
      if (!mounted) return;
      final byDay = {for (final h in hours) (h['day'] ?? '').toString(): h};
      final full = _allDays
          .map(
            (d) =>
                byDay[d] ??
                {
                  'day': d,
                  'is_open': false,
                  'open_time': null,
                  'close_time': null,
                },
          )
          .toList();
      setState(() {
        _hours = full.map((h) => Map<String, dynamic>.from(h)).toList();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(
          error,
          'Çalışma saatleri yüklenemedi.',
        );
        _isLoading = false;
      });
    }
  }

  Future<void> _saveHours() async {
    if (_isSaving) return;
    for (final h in _hours) {
      final isOpen = (h['is_open'] as bool?) ?? false;
      if (!isOpen) continue;
      final open = _normalizeHhMm(h['open_time']?.toString());
      final close = _normalizeHhMm(h['close_time']?.toString());
      if (open == null || close == null) {
        _showMgmtSnack(
          context,
          'Açık günler için açılış ve kapanış saati seçin.',
        );
        return;
      }
      if (_timeToMinutes(open) >= _timeToMinutes(close)) {
        final dayName = _dayNames[h['day']] ?? '';
        _showMgmtSnack(
          context,
          '$dayName için kapanış saati açılıştan sonra olmalı.',
        );
        return;
      }
    }
    setState(() => _isSaving = true);
    try {
      final payload = _hours.map((h) {
        final copy = Map<String, dynamic>.from(h);
        copy['open_time'] = _normalizeHhMm(copy['open_time']?.toString());
        copy['close_time'] = _normalizeHhMm(copy['close_time']?.toString());
        return copy;
      }).toList();
      await _repository.saveBusinessHours(payload);
      if (!mounted) return;
      _showMgmtSnack(context, 'Çalışma saatleri güncellendi.');
    } catch (error) {
      if (!mounted) return;
      _showMgmtSnack(
        context,
        _businessManagementError(error, 'Çalışma saatleri kaydedilemedi.'),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _setDayOpen(int index, bool isOpen) {
    setState(() {
      final updated = Map<String, dynamic>.from(_hours[index]);
      updated['is_open'] = isOpen;
      if (!isOpen) {
        updated['open_time'] = null;
        updated['close_time'] = null;
      } else {
        updated['open_time'] ??= '09:00';
        updated['close_time'] ??= '18:00';
      }
      _hours[index] = updated;
    });
  }

  void _setTime(int index, String field, String? value) {
    setState(() {
      final updated = Map<String, dynamic>.from(_hours[index]);
      final normalized = _normalizeHhMm(value);
      updated[field] = normalized;
      _hours[index] = updated;
    });
  }

  static String? _normalizeHhMm(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(':');
    if (parts.length < 2) return trimmed;
    final hh = parts[0].padLeft(2, '0');
    final mm = parts[1].padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _pickTime(int index, String field, String value) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TimePickerSheet(
        title: field == 'open_time' ? 'Açılış saati' : 'Kapanış saati',
        selected: value,
      ),
    );
    if (selected == null) return;
    _setTime(index, field, selected);
  }

  Future<void> _copyHoursFrom(int sourceIndex) async {
    final source = _hours[sourceIndex];
    final open = _normalizeHhMm(source['open_time']?.toString()) ?? '09:00';
    final close = _normalizeHhMm(source['close_time']?.toString()) ?? '18:00';
    final sourceDay = source['day']?.toString() ?? '';
    final selected = <String>{
      for (final h in _hours)
        if ((h['day']?.toString() ?? '') != sourceDay &&
            ((h['is_open'] as bool?) ?? false))
          h['day'].toString(),
    };
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: WebeyColors.ivory,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Saatleri kopyala',
                      style: TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 18,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$open - $close saatlerini secilen gunlere uygula.',
                      style: const TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final h in _hours)
                          if ((h['day']?.toString() ?? '') != sourceDay)
                            FilterChip(
                              label: Text(
                                _dayNames[h['day']?.toString() ?? ''] ??
                                    h['day'].toString(),
                              ),
                              selected: selected.contains(h['day'].toString()),
                              onSelected: (value) => setSheetState(() {
                                final day = h['day'].toString();
                                value
                                    ? selected.add(day)
                                    : selected.remove(day);
                              }),
                              selectedColor: WebeyColors.primaryGold,
                              backgroundColor: WebeyColors.softWhite,
                              side: BorderSide(
                                color: selected.contains(h['day'].toString())
                                    ? WebeyColors.primaryGold
                                    : WebeyColors.borderSand,
                              ),
                              labelStyle: const TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(sheetContext, selected),
                        child: const Text('Uygula'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      for (var i = 0; i < _hours.length; i++) {
        final day = _hours[i]['day']?.toString() ?? '';
        if (!picked.contains(day)) continue;
        final updated = Map<String, dynamic>.from(_hours[i]);
        updated['open_time'] = open;
        updated['close_time'] = close;
        _hours[i] = updated;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: _MgmtHeader(
                      titleBold: 'Çalışma ',
                      titleItalic: 'Saatleri',
                      onBack: () => Navigator.maybePop(context),
                      subtitle:
                          'Haftalık açılış ve kapanış saatlerini ayarlayın.',
                    ),
                  ),
                  if (_isLoading)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: _MgmtInlineState(
                          message: 'Yükleniyor...',
                          isLoading: true,
                        ),
                      ),
                    )
                  else if (_error != null)
                    if (_error != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _MgmtInlineState(
                            message: _error!,
                            onRetry: _loadHours,
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((context, i) {
                            final hour = _hours[i];
                            final day = hour['day']?.toString() ?? '';
                            final dayName = _dayNames[day] ?? day;
                            final isOpen = (hour['is_open'] as bool?) ?? false;
                            final openTime =
                                _normalizeHhMm(hour['open_time']?.toString()) ??
                                '';
                            final closeTime =
                                _normalizeHhMm(
                                  hour['close_time']?.toString(),
                                ) ??
                                '';
                            return _HourRow(
                              dayName: dayName,
                              isOpen: isOpen,
                              openTime: openTime,
                              closeTime: closeTime,
                              onToggle: (v) => _setDayOpen(i, v),
                              onOpenTimeChanged: (v) =>
                                  _pickTime(i, 'open_time', openTime),
                              onCloseTimeChanged: (v) =>
                                  _pickTime(i, 'close_time', closeTime),
                              onCopy: () => _copyHoursFrom(i),
                            );
                          }, childCount: _hours.length),
                        ),
                      ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              10 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: WebeyColors.ivory,
              border: Border(top: BorderSide(color: WebeyColors.borderSand)),
            ),
            child: GestureDetector(
              onTap: _isSaving ? null : _saveHours,
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: _isSaving
                      ? WebeyColors.borderSand
                      : WebeyColors.primaryGold,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: _isSaving
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: WebeyColors.darkEspresso,
                          ),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.save_outlined,
                            size: 16,
                            color: WebeyColors.darkEspresso,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Değişiklikleri Kaydet',
                            style: TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HourRow extends StatelessWidget {
  const _HourRow({
    required this.dayName,
    required this.isOpen,
    required this.openTime,
    required this.closeTime,
    required this.onToggle,
    required this.onOpenTimeChanged,
    required this.onCloseTimeChanged,
    required this.onCopy,
  });

  final String dayName, openTime, closeTime;
  final bool isOpen;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onOpenTimeChanged;
  final ValueChanged<String> onCloseTimeChanged;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dayName,
                  style: TextStyle(
                    color: isOpen
                        ? WebeyColors.darkEspresso
                        : WebeyColors.mutedTaupe,
                    fontSize: 13.5,
                    fontWeight: isOpen ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              Switch(
                value: isOpen,
                activeThumbColor: WebeyColors.primaryGold,
                onChanged: onToggle,
              ),
            ],
          ),
          if (isOpen) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _TimeField(
                    label: 'Açılış',
                    value: openTime,
                    onChanged: onOpenTimeChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeField(
                    label: 'Kapanış',
                    value: closeTime,
                    onChanged: onCloseTimeChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_all_rounded, size: 16),
                label: const Text('Saatleri kopyala'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

int _timeToMinutes(String value) {
  final parts = value.split(':');
  if (parts.length < 2) return 0;
  return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label, value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value.isEmpty ? '09:00' : value,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.access_time_rounded,
              size: 16,
              color: WebeyColors.mutedTaupe,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePickerSheet extends StatelessWidget {
  const _TimePickerSheet({required this.title, required this.selected});

  final String title;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final times = [
      for (var minutes = 6 * 60; minutes <= 23 * 60; minutes += 15)
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}',
    ];
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * .7,
        ),
        decoration: const BoxDecoration(
          color: WebeyColors.ivory,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text(
                title,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 20,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Flexible(
              child: GridView.builder(
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  20 + MediaQuery.of(context).padding.bottom,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 2.2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: times.length,
                itemBuilder: (context, index) {
                  final time = times[index];
                  final active = time == selected;
                  return GestureDetector(
                    onTap: () => Navigator.of(context).pop(time),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active
                            ? WebeyColors.darkEspresso
                            : WebeyColors.softWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: Text(
                        time,
                        style: TextStyle(
                          color: active
                              ? Colors.white
                              : WebeyColors.darkEspresso,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN — Kapora Politikası
// ─────────────────────────────────────────────────────────────────────────────

class BusinessDepositPolicyScreen extends StatefulWidget {
  const BusinessDepositPolicyScreen({super.key});

  @override
  State<BusinessDepositPolicyScreen> createState() =>
      _BusinessDepositPolicyScreenState();
}

class _BusinessDepositPolicyScreenState
    extends State<BusinessDepositPolicyScreen> {
  final _repository = BusinessRepository.instance;
  String _rate = '25';
  String _depositMode = 'percent';
  final _fixedAmountCtrl = TextEditingController(text: '250');
  // Kapora ödeme sistemi ana açık/kapalı durumu (policy.deposit_required).
  bool _depositEnabled = true;
  String _cancelPolicy = 'esnek';
  bool _isLoading = true;
  bool _isSaving = false;

  // Kapora aktif ama IBAN eksik: müşteriler kaporalı randevu oluşturamaz.
  bool _ibanMissing = false;

  static const _rates = ['10', '25', '50', '100'];
  static const _cancelOptions = [
    (
      id: 'esnek',
      name: 'Esnek',
      sub: '24 saat öncesine kadar ücretsiz iptal, kapora iade.',
    ),
    (id: 'orta', name: 'Orta', sub: '48 saat öncesine kadar ücretsiz iptal.'),
    (id: 'kati', name: 'Katı', sub: 'İptal halinde kapora iade edilmez.'),
  ];

  int get _depositAmount => (1200 * int.parse(_rate) / 100).round();
  int get _fixedDepositAmount =>
      int.tryParse(_fixedAmountCtrl.text.trim()) ?? 0;
  int get _sampleDepositAmount =>
      _depositMode == 'fixed' ? _fixedDepositAmount : _depositAmount;
  int get _sampleRemainingAmount =>
      (1200 - _sampleDepositAmount).clamp(0, 1200);

  @override
  void initState() {
    super.initState();
    _loadDeposit();
  }

  @override
  void dispose() {
    _fixedAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDeposit() async {
    setState(() => _isLoading = true);
    try {
      final policy = await _repository.getDepositPolicy();
      if (!mounted) return;
      final ratePct = (policy['rate_pct'] as num?)?.toInt() ?? 25;
      final rateStr = '$ratePct';
      final mode = policy['deposit_mode']?.toString() == 'fixed'
          ? 'fixed'
          : 'percent';
      final fixedAmount = (policy['fixed_deposit_amount'] as num?)?.round();
      setState(() {
        _depositEnabled = (policy['deposit_required'] as bool?) ?? false;
        _depositMode = mode;
        _rate = _rates.contains(rateStr) ? rateStr : '25';
        _cancelPolicy = (policy['cancel_policy'] as String?) ?? 'esnek';
        if (fixedAmount != null && fixedAmount > 0) {
          _fixedAmountCtrl.text = '$fixedAmount';
        }
        _isLoading = false;
      });
      if (_depositEnabled) _checkIbanMissing(ratePct);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Kapora oranı > 0 ama salon IBAN'ı kayıtlı değilse uyarı göster.
  Future<void> _checkIbanMissing(int ratePct) async {
    if (ratePct <= 0) {
      if (mounted && _ibanMissing) setState(() => _ibanMissing = false);
      return;
    }
    try {
      final settings = await _repository.getPaymentSettings();
      if (!mounted) return;
      final hasIban =
          settings['has_iban'] == true ||
          (settings['iban']?.toString().isNotEmpty ?? false);
      setState(() => _ibanMissing = !hasIban);
    } catch (_) {
      // Bilgi alınamazsa uyarı gösterme (yanlış alarm olmasın).
    }
  }

  Future<void> _saveDeposit() async {
    if (_isSaving) return;
    // Kapora açıkken sabit tutar doğrulaması; kapalıyken kontrol yapılmaz.
    if (_depositEnabled &&
        _depositMode == 'fixed' &&
        _fixedDepositAmount <= 0) {
      _showMgmtSnack(context, 'Sabit kapora tutarı girin.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      // Kapora kapalıysa rate_pct=0 + percent gönderilir → backend deposit_required=0.
      // Hizmete özel kapora kaldırıldığı için per_service her zaman false.
      await _repository.saveDepositPolicy(
        _depositEnabled
            ? {
                'deposit_mode': _depositMode,
                'rate_pct': _depositMode == 'fixed' ? 0 : int.parse(_rate),
                'fixed_deposit_amount': _depositMode == 'fixed'
                    ? _fixedDepositAmount
                    : null,
                'per_service': false,
                'cancel_policy': _cancelPolicy,
              }
            : {
                'deposit_mode': 'percent',
                'rate_pct': 0,
                'fixed_deposit_amount': null,
                'per_service': false,
                'cancel_policy': _cancelPolicy,
              },
      );
      if (!mounted) return;
      _showMgmtSnack(context, 'Kapora ayarları güncellendi.');
    } catch (error) {
      if (!mounted) return;
      _showMgmtSnack(
        context,
        _businessManagementError(error, 'Kapora ayarları kaydedilemedi.'),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _MgmtHeader(
                      titleBold: 'Kapora ',
                      titleItalic: 'Politikası',
                      onBack: () => Navigator.maybePop(context),
                    ),
                  ),
                  // Kapora aktif ama IBAN eksik uyarısı
                  if (_depositEnabled && _ibanMissing)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: WebeyColors.errorRed.withAlpha(12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: WebeyColors.errorRed.withAlpha(70),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 17,
                                    color: WebeyColors.errorRed,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'IBAN bilgileriniz eksik',
                                      style: TextStyle(
                                        color: WebeyColors.darkEspresso,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Kapora aktif ancak IBAN bilgileriniz eksik. '
                                'Müşteriler kaporalı randevu oluşturamaz.',
                                style: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                height: 40,
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const BusinessPaymentSettingsScreen(),
                                      ),
                                    );
                                    if (mounted) _loadDeposit();
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: WebeyColors.darkEspresso,
                                    side: const BorderSide(
                                      color: WebeyColors.borderSand,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Text(
                                    'IBAN bilgilerini tamamla',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Ana kontrol: Kapora ile ödeme al / alma
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _depositEnabled
                              ? WebeyColors.successGreen.withAlpha(15)
                              : WebeyColors.softWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _depositEnabled
                                ? WebeyColors.successGreen.withAlpha(50)
                                : WebeyColors.borderSand,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: _depositEnabled
                                        ? WebeyColors.successGreen.withAlpha(20)
                                        : WebeyColors.warmCream,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.shield_outlined,
                                    size: 20,
                                    color: _depositEnabled
                                        ? WebeyColors.successGreen
                                        : WebeyColors.mutedTaupe,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _depositEnabled
                                        ? 'Kapora ile ödeme al'
                                        : 'Kapora alma',
                                    style: const TextStyle(
                                      color: WebeyColors.darkEspresso,
                                      fontSize: 14.5,
                                      fontFamily: 'Georgia',
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: _depositEnabled,
                                  activeThumbColor: WebeyColors.primaryGold,
                                  onChanged: (_isSaving || _isLoading)
                                      ? null
                                      : (v) {
                                          setState(() => _depositEnabled = v);
                                          if (v) {
                                            _checkIbanMissing(
                                              _depositMode == 'fixed'
                                                  ? 0
                                                  : int.parse(_rate),
                                            );
                                          }
                                        },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _depositEnabled
                                  ? 'Müşterileriniz kapora ödeyerek randevu saatlerini garantileyebilir.'
                                  : 'Kapora kapalıyken müşteriler kapora ödemeden randevu oluşturabilir.',
                              style: TextStyle(
                                color: WebeyColors.mutedTaupe,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_depositEnabled)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: WebeyColors.softWhite,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: WebeyColors.borderSand),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Kapora tipi',
                                style: TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontSize: 15,
                                  fontFamily: 'Georgia',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _DepositModeButton(
                                      label: 'Yüzdelik',
                                      icon: Icons.percent_rounded,
                                      selected: _depositMode == 'percent',
                                      onTap: () => setState(
                                        () => _depositMode = 'percent',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _DepositModeButton(
                                      label: 'Sabit TL',
                                      icon: Icons.payments_outlined,
                                      selected: _depositMode == 'fixed',
                                      onTap: () => setState(
                                        () => _depositMode = 'fixed',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Rate selector
                  if (_depositEnabled)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: WebeyColors.softWhite,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: WebeyColors.borderSand),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                text: const TextSpan(
                                  style: TextStyle(
                                    color: WebeyColors.darkEspresso,
                                    fontSize: 15,
                                    fontFamily: 'Georgia',
                                    fontWeight: FontWeight.w600,
                                  ),
                                  children: [
                                    TextSpan(text: 'Kapora '),
                                    TextSpan(
                                      text: 'Oranı',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Randevu bedeli üzerinden alınan kapora yüzdesi.',
                                style: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (_depositMode == 'fixed')
                                TextField(
                                  controller: _fixedAmountCtrl,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  onChanged: (_) => setState(() {}),
                                  decoration: const InputDecoration(
                                    hintText: '250',
                                    suffixText: 'TL',
                                  ),
                                )
                              else
                                Container(
                                  decoration: BoxDecoration(
                                    color: WebeyColors.warmCream,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: WebeyColors.borderSand,
                                    ),
                                  ),
                                  child: Row(
                                    children: _rates.map((r) {
                                      final isActive = _rate == r;
                                      final isLast = _rates.last == r;
                                      final isFirst = _rates.first == r;
                                      return Expanded(
                                        child: GestureDetector(
                                          onTap: () =>
                                              setState(() => _rate = r),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: isActive
                                                  ? WebeyColors.primaryGold
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.horizontal(
                                                    left: isFirst
                                                        ? const Radius.circular(
                                                            9,
                                                          )
                                                        : Radius.zero,
                                                    right: isLast
                                                        ? const Radius.circular(
                                                            9,
                                                          )
                                                        : Radius.zero,
                                                  ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '%$r',
                                                style: TextStyle(
                                                  color: isActive
                                                      ? WebeyColors.darkEspresso
                                                      : WebeyColors.mutedTaupe,
                                                  fontSize: 13.5,
                                                  fontWeight: isActive
                                                      ? FontWeight.w700
                                                      : FontWeight.w400,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Example calculation
                  if (_depositEnabled)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: WebeyColors.goldLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: WebeyColors.primaryGold.withAlpha(60),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.calculate_outlined,
                                    size: 13,
                                    color: WebeyColors.primaryGold,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Örnek Hesaplama',
                                    style: TextStyle(
                                      color: WebeyColors.primaryGold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _CalcRow(
                                label: 'Hizmet fiyatı',
                                value: '1.200 TL',
                              ),
                              const SizedBox(height: 6),
                              _CalcRow(
                                label: _depositMode == 'fixed'
                                    ? 'Kapora (sabit)'
                                    : 'Kapora (%$_rate)',
                                value: '$_sampleDepositAmount TL',
                                isGold: true,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Divider(
                                  height: 1,
                                  color: WebeyColors.primaryGold.withAlpha(30),
                                ),
                              ),
                              _CalcRow(
                                label: 'Salonda kalan',
                                value: '$_sampleRemainingAmount TL',
                                isBold: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Cancellation policy
                  if (_depositEnabled)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: WebeyColors.softWhite,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: WebeyColors.borderSand),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                text: const TextSpan(
                                  style: TextStyle(
                                    color: WebeyColors.darkEspresso,
                                    fontSize: 15,
                                    fontFamily: 'Georgia',
                                    fontWeight: FontWeight.w600,
                                  ),
                                  children: [
                                    TextSpan(text: 'İptal '),
                                    TextSpan(
                                      text: 'Politikası',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Müşteri iptallerinde kapora durumu.',
                                style: TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 14),
                              ..._cancelOptions.map((opt) {
                                final isSelected = _cancelPolicy == opt.id;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _cancelPolicy = opt.id),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(13),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? WebeyColors.goldLight
                                          : WebeyColors.warmCream,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? WebeyColors.primaryGold.withAlpha(
                                                80,
                                              )
                                            : WebeyColors.borderSand,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 18,
                                          height: 18,
                                          margin: const EdgeInsets.only(top: 1),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isSelected
                                                ? WebeyColors.primaryGold
                                                : Colors.transparent,
                                            border: Border.all(
                                              color: isSelected
                                                  ? WebeyColors.primaryGold
                                                  : WebeyColors.borderSand,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: isSelected
                                              ? const Icon(
                                                  Icons.check_rounded,
                                                  size: 11,
                                                  color:
                                                      WebeyColors.darkEspresso,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                opt.name,
                                                style: TextStyle(
                                                  color:
                                                      WebeyColors.darkEspresso,
                                                  fontSize: 13.5,
                                                  fontStyle: isSelected
                                                      ? FontStyle.italic
                                                      : FontStyle.normal,
                                                  fontWeight: isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.w400,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                opt.sub,
                                                style: TextStyle(
                                                  color: WebeyColors.mutedTaupe,
                                                  fontSize: 12,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Refund info
                  if (_depositEnabled)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: WebeyColors.warmCream,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: WebeyColors.borderSand),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 14,
                                color: WebeyColors.mutedTaupe,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: const TextSpan(
                                    style: TextStyle(
                                      color: WebeyColors.mutedTaupe,
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'Salon kaynaklı iptallerde',
                                        style: TextStyle(
                                          color: WebeyColors.darkEspresso,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      TextSpan(
                                        text:
                                            ' kapora otomatik olarak müşteriye iade edilir. Politika seçiminizden bağımsızdır.',
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Webey guarantee
                  if (_depositEnabled)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: WebeyColors.darkEspresso,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: WebeyColors.primaryGold.withAlpha(20),
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(
                                  Icons.shield_outlined,
                                  size: 20,
                                  color: WebeyColors.primaryGold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    RichText(
                                      text: const TextSpan(
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.5,
                                          fontFamily: 'Georgia',
                                          fontWeight: FontWeight.w600,
                                        ),
                                        children: [
                                          TextSpan(text: 'Webey '),
                                          TextSpan(
                                            text: 'Kapora Bilgisi',
                                            style: TextStyle(
                                              fontStyle: FontStyle.italic,
                                              color: Color(0xFFD4B574),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      'Kapora doğrudan salonun banka hesabına gönderilir. Webey ödeme tahsil etmez; iade/iptal salon politikasına tabidir.',
                                      style: TextStyle(
                                        color: Colors.white.withAlpha(160),
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                ],
              ),
            ),
          ),
          // Save button
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              10 + MediaQuery.of(context).padding.bottom,
            ),
            decoration: BoxDecoration(
              color: WebeyColors.ivory,
              border: Border(top: BorderSide(color: WebeyColors.borderSand)),
            ),
            child: GestureDetector(
              onTap: (_isSaving || _isLoading) ? null : _saveDeposit,
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: (_isSaving || _isLoading)
                      ? WebeyColors.borderSand
                      : WebeyColors.primaryGold,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: (_isSaving || _isLoading)
                    ? const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: WebeyColors.darkEspresso,
                          ),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.save_outlined,
                            size: 16,
                            color: WebeyColors.darkEspresso,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Değişiklikleri Kaydet',
                            style: TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DepositModeButton extends StatelessWidget {
  const _DepositModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 44,
        decoration: BoxDecoration(
          color: selected ? WebeyColors.primaryGold : WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? WebeyColors.primaryGold : WebeyColors.borderSand,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: WebeyColors.darkEspresso),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalcRow extends StatelessWidget {
  const _CalcRow({
    required this.label,
    required this.value,
    this.isGold = false,
    this.isBold = false,
  });
  final String label, value;
  final bool isGold, isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12.5),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: isGold ? WebeyColors.primaryGold : WebeyColors.darkEspresso,
            fontSize: isGold || isBold ? 14 : 12.5,
            fontWeight: isGold || isBold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// SCREEN - Kapora Odeme Bilgileri (IBAN)
// MVP: Webey para tahsil etmez. Musteri kaporayi dogrudan salonun IBAN'ina yollar.
// ----------------------------------------------------------------------------

class BusinessPaymentSettingsScreen extends StatefulWidget {
  const BusinessPaymentSettingsScreen({super.key});

  @override
  State<BusinessPaymentSettingsScreen> createState() =>
      _BusinessPaymentSettingsScreenState();
}

class _BusinessPaymentSettingsScreenState
    extends State<BusinessPaymentSettingsScreen> {
  final _repository = BusinessRepository.instance;
  final _ibanController = TextEditingController();
  final _holderController = TextEditingController();
  final _bankController = TextEditingController();
  final _instructionsController = TextEditingController();
  bool _depositEnabled = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _bankHint;
  bool _bankAutoFilled = false;
  bool get _showPaymentActivationSwitch => false;
  bool get _requirePaymentSettingsForActiveDeposit => false;
  bool get _showPaymentSettingsFields => true;

  @override
  void initState() {
    super.initState();
    _ibanController.addListener(_onIbanChanged);
    _load();
  }

  @override
  void dispose() {
    _ibanController.removeListener(_onIbanChanged);
    _ibanController.dispose();
    _holderController.dispose();
    _bankController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  void _onIbanChanged() {
    final iban = normalizeTrIban(_ibanController.text);
    if (!isValidTrIbanFormat(iban)) {
      if (_bankHint != null) {
        setState(() => _bankHint = null);
      }
      return;
    }
    final inferred = trBankNameFromIban(iban);
    if (inferred == null) {
      setState(
        () => _bankHint = 'Banka otomatik tanınamadı, elle yazabilirsiniz.',
      );
      return;
    }
    final current = _bankController.text.trim();
    if (current.isEmpty || _bankAutoFilled) {
      _bankController.text = inferred;
      _bankAutoFilled = true;
    }
    setState(() => _bankHint = 'Banka IBAN’dan otomatik tanındı.');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repository.getPaymentSettings();
      if (!mounted) return;
      setState(() {
        _depositEnabled = data['deposit_enabled'] == true;
        _ibanController.text = (data['iban_formatted'] ?? data['iban'] ?? '')
            .toString();
        _holderController.text = (data['account_holder'] ?? '').toString();
        _bankController.text = (data['bank_name'] ?? '').toString();
        _instructionsController.text = (data['instructions'] ?? '').toString();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'Ayarlar yüklenemedi.');
        _loading = false;
      });
    }
  }

  String _normalizeIban(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  Future<void> _save() async {
    if (_saving) return;
    final iban = _normalizeIban(_ibanController.text);
    final holder = _holderController.text.trim();

    if (iban.isNotEmpty && !RegExp(r'^TR[0-9]{24}$').hasMatch(iban)) {
      _showMgmtSnack(context, 'Geçerli bir TR IBAN girin (TR + 24 hane).');
      return;
    }
    if (_requirePaymentSettingsForActiveDeposit &&
        _depositEnabled &&
        iban.isEmpty) {
      _showMgmtSnack(context, 'Kapora ödemesini açmak için IBAN girin.');
      return;
    }
    if (_requirePaymentSettingsForActiveDeposit &&
        _depositEnabled &&
        holder.isEmpty) {
      _showMgmtSnack(
        context,
        'Kapora ödemesini açmak için hesap sahibini girin.',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await _repository.savePaymentSettings(
        depositEnabled: false,
        iban: iban,
        accountHolder: holder,
        bankName: _bankController.text.trim(),
        instructions: _instructionsController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _ibanController.text = (saved['iban_formatted'] ?? iban).toString();
        _saving = false;
      });
      _showMgmtSnack(context, 'Kapora ödeme ayarları kaydedildi.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMgmtSnack(
        context,
        _businessManagementError(error, 'Ayarlar kaydedilemedi.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: Center(
          child: CircularProgressIndicator(color: WebeyColors.primaryGold),
        ),
      );
    }
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: ListView(
                children: [
                  _MgmtHeader(
                    titleBold: 'Kapora ',
                    titleItalic: 'Ödeme Bilgileri',
                    onBack: () => Navigator.maybePop(context),
                    subtitle:
                        'Kapora doğrudan salonunuzun banka hesabına gönderilir.',
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: _MgmtInlineState(message: _error!, onRetry: _load),
                    ),
                  // Bilgi kartı (MVP hukuki metin)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: WebeyColors.warmCream,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: WebeyColors.primaryGold,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Webey kapora tahsil etmez. Müşteri kaporayı '
                              'doğrudan girdiğiniz IBAN’a gönderir. İade ve iptal '
                              'koşulları salon politikanıza tabidir.',
                              style: TextStyle(
                                color: WebeyColors.mutedTaupe,
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Aktif switch
                  if (_showPaymentActivationSwitch)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: WebeyColors.softWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: WebeyColors.borderSand),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Kapora ödemesi aktif',
                                style: TextStyle(
                                  color: WebeyColors.darkEspresso,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Switch(
                              value: _depositEnabled,
                              activeThumbColor: WebeyColors.primaryGold,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _depositEnabled = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Kapora ödemesi aktifken IBAN formu görünür; pasifken gizlenir
                  // (mevcut IBAN bilgileri silinmez, yalnızca gizlenir).
                  if (_showPaymentSettingsFields) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: _MgmtTextField(
                        controller: _ibanController,
                        label: 'IBAN (TR...)',
                        keyboardType: TextInputType.text,
                        inputFormatters: [LengthLimitingTextInputFormatter(34)],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: _MgmtTextField(
                        controller: _holderController,
                        label: 'Hesap sahibi (alıcı adı)',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: _MgmtTextField(
                        controller: _bankController,
                        label: 'Banka adı (IBAN girilince otomatik doldurulur)',
                      ),
                    ),
                    if (_bankHint != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                        child: Text(
                          _bankHint!,
                          style: const TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: _MgmtTextField(
                        controller: _instructionsController,
                        label: 'Kapora açıklama notu (opsiyonel)',
                        maxLines: 3,
                        maxLength: 2000,
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: WebeyColors.softWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: WebeyColors.borderSand),
                        ),
                        child: Text(
                          'Kapora ödemesi kapalı. Müşteriler kapora ödemeden '
                          'randevu oluşturabilir. Açtığınızda kayıtlı IBAN '
                          'bilgileriniz tekrar görünür.',
                          style: TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _FabBar(
            label: _saving ? 'Kaydediliyor...' : 'Kaydet',
            onTap: _saving ? () {} : _save,
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// SCREEN - Isletme Bildirimleri
// ----------------------------------------------------------------------------

class BusinessReviewsScreen extends StatefulWidget {
  const BusinessReviewsScreen({super.key});

  @override
  State<BusinessReviewsScreen> createState() => _BusinessReviewsScreenState();
}

class _BusinessReviewsScreenState extends State<BusinessReviewsScreen> {
  final _repository = BusinessRepository.instance;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _items = const [];
  String? _busyReviewId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _replyTo(Map<String, dynamic> item) async {
    final reviewId = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    if (reviewId <= 0) return;
    final existing = item['business_reply']?.toString() ?? '';
    final reply = await _showReplyDialog(existing);
    if (reply == null || !mounted) return;
    setState(() => _busyReviewId = item['id']?.toString());
    try {
      await _repository.replyToReview(reviewId: reviewId, reply: reply);
      if (!mounted) return;
      WebeyToast.success(
        context,
        reply.trim().isEmpty ? 'Yanıt kaldırıldı.' : 'Yanıtınız kaydedildi.',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      WebeyToast.error(
        context,
        _businessManagementError(error, 'Yanıt kaydedilemedi.'),
      );
    } finally {
      if (mounted) setState(() => _busyReviewId = null);
    }
  }

  Future<void> _toggleLike(Map<String, dynamic> item) async {
    final reviewId = int.tryParse(item['id']?.toString() ?? '') ?? 0;
    if (reviewId <= 0) return;
    final next = !(item['business_liked'] == true);
    setState(() => _busyReviewId = item['id']?.toString());
    try {
      await _repository.likeReview(reviewId: reviewId, liked: next);
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      WebeyToast.error(
        context,
        _businessManagementError(error, 'Beğeni güncellenemedi.'),
      );
    } finally {
      if (mounted) setState(() => _busyReviewId = null);
    }
  }

  Future<String?> _showReplyDialog(String existing) async {
    final controller = TextEditingController(text: existing);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WebeyColors.softWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Yoruma yanıt',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontFamily: 'Georgia',
            fontSize: 18,
          ),
        ),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(
            hintText: 'Müşteriye yanıtınızı yazın',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Vazgeç',
              style: TextStyle(color: WebeyColors.mutedTaupe),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text(
              'Kaydet',
              style: TextStyle(
                color: WebeyColors.primaryGold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repository.getBusinessReviews(limit: 50);
      final summary = data['summary'] is Map
          ? Map<String, dynamic>.from(data['summary'] as Map)
          : const <String, dynamic>{};
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'Yorumlar alınamadı.');
        _loading = false;
      });
    }
  }

  double get _rating {
    final raw = _summary['rating'];
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  int get _reviewCount {
    final raw = _summary['review_count'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? _items.length;
  }

  int get _fiveStarCount {
    final raw = _summary['five_star_count'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        child: RefreshIndicator(
          color: WebeyColors.primaryGold,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
            children: [
              _MgmtHeader(
                titleBold: 'Yorumlar ',
                titleItalic: '& Puanlar',
                subtitle:
                    'Müşteri deneyimini ve son değerlendirmeleri takip et.',
                onBack: () => Navigator.of(context).pop(),
                trailingWidget: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: WebeyColors.warmCream,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: WebeyColors.borderSand),
                  ),
                  child: const Icon(
                    Icons.rate_review_outlined,
                    color: WebeyColors.primaryGold,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: WebeyColors.primaryGold,
                    ),
                  ),
                )
              else if (_error != null)
                _MgmtInlineState(message: _error!, onRetry: _load)
              else ...[
                _BusinessReviewsSummaryCard(
                  rating: _rating,
                  reviewCount: _reviewCount,
                  fiveStarCount: _fiveStarCount,
                ),
                const SizedBox(height: 14),
                if (_items.isEmpty)
                  const _BusinessReviewsEmptyState()
                else
                  ..._items.map(
                    (item) => _BusinessReviewCard(
                      item: item,
                      busy: _busyReviewId == item['id']?.toString(),
                      onReply: () => _replyTo(item),
                      onToggleLike: () => _toggleLike(item),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessReviewsSummaryCard extends StatelessWidget {
  const _BusinessReviewsSummaryCard({
    required this.rating,
    required this.reviewCount,
    required this.fiveStarCount,
  });

  final double rating;
  final int reviewCount;
  final int fiveStarCount;

  @override
  Widget build(BuildContext context) {
    final pct = reviewCount == 0
        ? 0.0
        : (fiveStarCount / reviewCount).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: WebeyColors.primaryGold.withAlpha(24),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.star_rounded,
              color: WebeyColors.primaryGold,
              size: 32,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reviewCount == 0
                      ? 'Henüz puan yok'
                      : '${rating.toStringAsFixed(1)} ortalama puan',
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 18,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$reviewCount yorum · $fiveStarCount adet 5 yıldız',
                  style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 7,
                    backgroundColor: WebeyColors.warmCream,
                    color: WebeyColors.primaryGold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessReviewCard extends StatelessWidget {
  const _BusinessReviewCard({
    required this.item,
    this.onReply,
    this.onToggleLike,
    this.busy = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback? onReply;
  final VoidCallback? onToggleLike;
  final bool busy;

  String? get _reply {
    final r = item['business_reply']?.toString().trim() ?? '';
    return r.isEmpty ? null : r;
  }

  bool get _liked => item['business_liked'] == true;

  String get _name {
    final text = item['customer_name']?.toString().trim() ?? '';
    return text.isEmpty ? 'Müşteri' : text;
  }

  String get _initials {
    final parts = _name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  int get _rating {
    final raw = item['rating'];
    if (raw is int) return raw;
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  String get _when {
    final dt = DateTime.tryParse(item['created_at']?.toString() ?? '');
    if (dt == null) return 'Yakın zamanda';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays <= 0) return 'Bugün';
    if (diff.inDays == 1) return 'Dün';
    if (diff.inDays < 7) return '${diff.inDays} gün önce';
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final service = item['service_name']?.toString();
    final comment = item['comment']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: WebeyColors.warmCream,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    _initials.isEmpty ? 'M' : _initials,
                    style: const TextStyle(
                      color: WebeyColors.primaryGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name,
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (service != null && service.isNotEmpty) service,
                        _when,
                      ].join(' · '),
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(5, (index) {
                  return Icon(
                    index < _rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 15,
                    color: index < _rating
                        ? WebeyColors.primaryGold
                        : WebeyColors.borderSand,
                  );
                }),
              ),
            ],
          ),
          if (comment != null && comment.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              comment,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
          // İşletme cevabı (varsa).
          if (_reply != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  left: BorderSide(color: WebeyColors.primaryGold, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'İşletme yanıtı',
                    style: TextStyle(
                      color: WebeyColors.primaryGold,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _reply!,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Aksiyonlar: Cevapla/Düzenle + Beğen toggle.
          if (onReply != null || onToggleLike != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (onReply != null)
                  GestureDetector(
                    onTap: busy ? null : onReply,
                    child: Row(
                      children: [
                        Icon(
                          _reply == null
                              ? Icons.reply_rounded
                              : Icons.edit_outlined,
                          size: 15,
                          color: WebeyColors.primaryGold,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _reply == null ? 'Cevapla' : 'Cevabı düzenle',
                          style: const TextStyle(
                            color: WebeyColors.primaryGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                if (onToggleLike != null)
                  GestureDetector(
                    onTap: busy ? null : onToggleLike,
                    child: Icon(
                      _liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 19,
                      color: _liked
                          ? WebeyColors.errorRed
                          : WebeyColors.mutedTaupe,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BusinessReviewsEmptyState extends StatelessWidget {
  const _BusinessReviewsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: WebeyColors.warmCream,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(
              Icons.rate_review_outlined,
              color: WebeyColors.primaryGold,
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Henüz yorum yok',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 16,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Müşteriler randevu sonrası puan verdikçe burada görünecek.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

enum _BizNotifType { randevu, odeme, musteri, sistem }

class _BizNotif {
  const _BizNotif({
    required this.id,
    required this.type,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.when,
    required this.group,
    this.unread = false,
  });
  final String id, title, body, when, group;
  final _BizNotifType type;
  final IconData icon;
  final Color iconColor;
  final bool unread;
}

class BusinessNotificationsScreen extends StatefulWidget {
  const BusinessNotificationsScreen({
    super.key,
    BusinessRepository repository = BusinessRepository.instance,
  }) : _repository = repository;

  final BusinessRepository _repository;

  @override
  State<BusinessNotificationsScreen> createState() =>
      _BusinessNotificationsScreenState();
}

class _BusinessNotificationsScreenState
    extends State<BusinessNotificationsScreen> {
  String _filter = 'all';
  bool _isMarkingAll = false;
  bool _loading = true;
  List<_BizNotif> _notifs = const [];

  static const _filters = [
    (id: 'all', label: 'Tümü'),
    (id: 'randevu', label: 'Randevu'),
    (id: 'odeme', label: 'Ödeme'),
    (id: 'musteri', label: 'Müşteri'),
  ];

  @override
  void initState() {
    super.initState();
    _loadNotifs();
  }

  Future<void> _loadNotifs() async {
    setState(() => _loading = true);
    try {
      final data = await widget._repository.getBusinessNotifications(limit: 50);
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      if (!mounted) return;
      final mapped = _mapApiNotifs(items);
      debugPrint(
        '[BusinessNotificationsScreen] items=${items.length}, mapped=${mapped.length}',
      );
      setState(() {
        _notifs = mapped;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[BusinessNotificationsScreen] load failed: $e');
      if (!mounted) return;
      setState(() {
        _notifs = [];
        _loading = false;
      });
    }
  }

  List<_BizNotif> _mapApiNotifs(List<Map<String, dynamic>> items) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    String groupFor(DateTime? dt) {
      if (dt == null) return 'onceki';
      if (!dt.isBefore(todayStart)) return 'today';
      if (!dt.isBefore(yesterdayStart)) return 'yesterday';
      return 'onceki';
    }

    String formatWhen(DateTime? dt, String group) {
      if (dt == null) return '';
      final diff = now.difference(dt);
      if (group == 'today') {
        if (diff.inMinutes < 1) return 'az önce';
        if (diff.inHours < 1) return '${diff.inMinutes} dk önce';
        return '${diff.inHours} sa önce';
      }
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      if (group == 'yesterday') return 'Dün $hh:$mm';
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    }

    final blushDarkened = Color.lerp(
      WebeyColors.blushRose,
      WebeyColors.darkEspresso,
      0.35,
    )!;

    final result = <_BizNotif>[];
    for (var i = 0; i < items.length; i++) {
      final raw = items[i];
      final typeRaw = (raw['type'] ?? '').toString().toLowerCase();
      _BizNotifType type;
      IconData icon;
      Color color;
      switch (typeRaw) {
        case 'booking':
        case 'appointment':
        case 'randevu':
        case 'cancellation':
        case 'cancel':
          type = _BizNotifType.randevu;
          icon = Icons.event_available_outlined;
          color = WebeyColors.primaryGold;
        case 'payment':
        case 'odeme':
          type = _BizNotifType.odeme;
          icon = Icons.payments_outlined;
          color = WebeyColors.successGreen;
        case 'customer':
        case 'musteri':
        case 'review':
        case 'yorum':
          type = _BizNotifType.musteri;
          icon = typeRaw == 'review' || typeRaw == 'yorum'
              ? Icons.rate_review_outlined
              : Icons.person_outline_rounded;
          color = typeRaw == 'review' || typeRaw == 'yorum'
              ? WebeyColors.primaryGold
              : blushDarkened;
        default:
          type = _BizNotifType.sistem;
          icon = Icons.info_outline_rounded;
          color = WebeyColors.mutedTaupe;
      }

      final createdAt = DateTime.tryParse(
        (raw['created_at'] ?? raw['createdAt'] ?? '').toString(),
      );
      final group = groupFor(createdAt);
      final unread =
          raw['read'] == false ||
          raw['is_read'] == false ||
          raw['read'] == 0 ||
          raw['unread'] == true;

      result.add(
        _BizNotif(
          id: (raw['id'] ?? 'n$i').toString(),
          type: type,
          icon: icon,
          iconColor: color,
          title: (raw['title'] ?? '').toString(),
          body: (raw['body'] ?? raw['message'] ?? '').toString(),
          when: formatWhen(createdAt, group),
          group: group,
          unread: unread,
        ),
      );
    }
    return result;
  }

  List<_BizNotif> get _visible {
    if (_filter == 'all') return _notifs;
    final type = switch (_filter) {
      'randevu' => _BizNotifType.randevu,
      'odeme' => _BizNotifType.odeme,
      'musteri' => _BizNotifType.musteri,
      _ => null,
    };
    if (type == null) return _notifs;
    return _notifs.where((n) => n.type == type).toList();
  }

  int _countFor(String filterId) {
    if (filterId == 'all') return _notifs.length;
    final type = switch (filterId) {
      'randevu' => _BizNotifType.randevu,
      'odeme' => _BizNotifType.odeme,
      'musteri' => _BizNotifType.musteri,
      _ => null,
    };
    if (type == null) return _notifs.length;
    return _notifs.where((n) => n.type == type).length;
  }

  int get _unreadCount => _notifs.where((n) => n.unread).length;

  Future<void> _markAllRead() async {
    if (_isMarkingAll) return;
    setState(() => _isMarkingAll = true);
    try {
      await widget._repository.markBusinessNotificationRead(markAll: true);
      if (!mounted) return;
      setState(() {
        _notifs = _notifs
            .map(
              (n) => _BizNotif(
                id: n.id,
                type: n.type,
                icon: n.icon,
                iconColor: n.iconColor,
                title: n.title,
                body: n.body,
                when: n.when,
                group: n.group,
                unread: false,
              ),
            )
            .toList();
      });
    } catch (_) {
      // sessiz hata
    } finally {
      if (mounted) setState(() => _isMarkingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: Center(
          child: CircularProgressIndicator(color: WebeyColors.primaryGold),
        ),
      );
    }
    final visible = _visible;
    final today = visible.where((n) => n.group == 'today').toList();
    final yesterday = visible.where((n) => n.group == 'yesterday').toList();
    final previous = visible.where((n) => n.group == 'onceki').toList();

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── Header ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.maybePop(context),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: WebeyColors.warmCream,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: WebeyColors.borderSand),
                        ),
                        child: const Icon(
                          Icons.chevron_left_rounded,
                          size: 20,
                          color: WebeyColors.darkEspresso,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 20,
                                fontFamily: 'Georgia',
                                fontWeight: FontWeight.w600,
                              ),
                              children: [
                                TextSpan(text: 'Bildirim'),
                                TextSpan(
                                  text: 'ler',
                                  style: TextStyle(fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          ),
                          if (_unreadCount > 0)
                            Text(
                              '$_unreadCount okunmamış',
                              style: const TextStyle(
                                color: WebeyColors.mutedTaupe,
                                fontSize: 11.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_unreadCount > 0)
                      GestureDetector(
                        onTap: _isMarkingAll ? null : _markAllRead,
                        child: Text(
                          _isMarkingAll
                              ? 'İşleniyor…'
                              : 'Tümünü okundu işaretle',
                          style: TextStyle(
                            color: _isMarkingAll
                                ? WebeyColors.mutedTaupe
                                : WebeyColors.primaryGold,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Filter Chips ─────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  itemCount: _filters.length,
                  separatorBuilder: (_, separatorIndex) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final f = _filters[i];
                    final on = _filter == f.id;
                    final count = _countFor(f.id);
                    return GestureDetector(
                      onTap: () => setState(() => _filter = f.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: on
                              ? WebeyColors.darkEspresso
                              : WebeyColors.softWhite,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: on
                                ? WebeyColors.darkEspresso
                                : WebeyColors.borderSand,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              f.label,
                              style: TextStyle(
                                color: on
                                    ? Colors.white
                                    : WebeyColors.mutedTaupe,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: on
                                    ? Colors.white.withAlpha(46)
                                    : WebeyColors.warmCream,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  color: on
                                      ? Colors.white
                                      : WebeyColors.mutedTaupe,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── Feed veya Boş Durum ──────────────────────────────────────────
            if (visible.isEmpty)
              SliverFillRemaining(child: _BizNotifEmptyState(filter: _filter))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (today.isNotEmpty) ...[
                      _BizNotifGroup(label: 'BUGÜN', items: today),
                      const SizedBox(height: 22),
                    ],
                    if (yesterday.isNotEmpty)
                      _BizNotifGroup(label: 'DÜN', items: yesterday),
                    if (yesterday.isNotEmpty && previous.isNotEmpty)
                      const SizedBox(height: 22),
                    if (previous.isNotEmpty)
                      _BizNotifGroup(label: 'ÖNCEKİ', items: previous),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Bildirim Grubu ────────────────────────────────────────────────────────────

class _BizNotifGroup extends StatelessWidget {
  const _BizNotifGroup({required this.label, required this.items});
  final String label;
  final List<_BizNotif> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: WebeyColors.primaryGold,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(height: 1, color: WebeyColors.borderSand),
            ),
            const SizedBox(width: 8),
            Text(
              '${items.length}',
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...items.map(
          (n) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BizNotifCard(n: n),
          ),
        ),
      ],
    );
  }
}

// ── Bildirim Kartı ────────────────────────────────────────────────────────────

class _BizNotifCard extends StatelessWidget {
  const _BizNotifCard({required this.n});
  final _BizNotif n;

  @override
  Widget build(BuildContext context) {
    final isReview =
        n.icon == Icons.rate_review_outlined ||
        n.title.toLowerCase().contains('yorum');
    return GestureDetector(
      onTap: isReview
          ? () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BusinessReviewsScreen()),
            )
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            bottomLeft: Radius.circular(4),
            topRight: Radius.circular(13),
            bottomRight: Radius.circular(13),
          ),
          border: Border.all(color: WebeyColors.borderSand),
          boxShadow: WebeyShadow.subtle,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sol unread şeridi
              Container(
                width: 3,
                decoration: BoxDecoration(
                  color: n.unread
                      ? WebeyColors.primaryGold
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
              ),
              // İçerik
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // İkon kutusu
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: WebeyColors.alpha(n.iconColor, 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: WebeyColors.alpha(n.iconColor, 0.22),
                          ),
                        ),
                        child: Icon(n.icon, size: 19, color: n.iconColor),
                      ),
                      const SizedBox(width: 12),
                      // Metin
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    n.title,
                                    style: const TextStyle(
                                      color: WebeyColors.darkEspresso,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (n.unread) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 7,
                                    height: 7,
                                    margin: const EdgeInsets.only(top: 5),
                                    decoration: const BoxDecoration(
                                      color: WebeyColors.primaryGold,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              n.body,
                              style: const TextStyle(
                                color: WebeyColors.mutedTaupe,
                                fontSize: 12.5,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule_outlined,
                                  size: 12,
                                  color: WebeyColors.mutedTaupe,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  n.when,
                                  style: const TextStyle(
                                    color: WebeyColors.mutedTaupe,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Boş Durum ────────────────────────────────────────────────────────────────

class _BizNotifEmptyState extends StatelessWidget {
  const _BizNotifEmptyState({required this.filter});
  final String filter;

  @override
  Widget build(BuildContext context) {
    final label = switch (filter) {
      'randevu' => 'Randevu',
      'odeme' => 'Ödeme',
      'musteri' => 'Müşteri',
      _ => null,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: WebeyColors.goldLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.notifications_off_outlined,
                size: 28,
                color: WebeyColors.primaryGold,
              ),
            ),
            const SizedBox(height: 18),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 19,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w600,
                ),
                children: label == null
                    ? [const TextSpan(text: 'Bildirim yok')]
                    : [
                        TextSpan(text: '"$label" '),
                        const TextSpan(
                          text: 'bildirimi yok',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: WebeyColors.mutedTaupe,
                          ),
                        ),
                      ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Yeni randevu, ödeme ve müşteri hareketleri burada görünecek. Şimdilik her şey güncel.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BusinessRevenueDepositScreen extends StatefulWidget {
  const BusinessRevenueDepositScreen({
    super.key,
    BusinessRepository repository = BusinessRepository.instance,
  }) : _repository = repository;

  final BusinessRepository _repository;

  @override
  State<BusinessRevenueDepositScreen> createState() =>
      _BusinessRevenueDepositScreenState();
}

class _BusinessRevenueDepositScreenState
    extends State<BusinessRevenueDepositScreen> {
  String _segment = 'all';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _items = const [];

  static const _segments = [
    (id: 'all', label: 'Tümü'),
    (id: 'deposit', label: 'Kapora'),
    (id: 'collected', label: 'Tam Ödeme'),
    (id: 'pending', label: 'Bekleyen'),
    (id: 'refund', label: 'İade'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget._repository.getDepositHistory();
      if (!mounted) return;
      final summary = data['summary'];
      final items = data['items'];
      setState(() {
        _summary = summary is Map
            ? Map<String, dynamic>.from(summary)
            : const {};
        _items = items is List
            ? items
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : const [];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'Kapora geçmişi alınamadı.');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visibleItems {
    if (_segment == 'all') return _items;
    return _items.where((item) {
      final status = (item['status'] ?? '').toString();
      return switch (_segment) {
        'deposit' => status == 'paid',
        'collected' => status == 'paid',
        'pending' => status == 'pending' || status == 'not_received',
        'refund' => status == 'refunded',
        _ => true,
      };
    }).toList();
  }

  String _money(num? value) {
    final v = (value ?? 0).toDouble();
    final whole = v.round();
    final s = whole.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '₺$buf';
  }

  String _itemWhen(Map<String, dynamic> item) {
    final raw = (item['created_at'] ?? item['appointment_start'] ?? '')
        .toString();
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inDays <= 0) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return 'Bugün $h:$m';
    }
    if (diff.inDays == 1) return 'Dün';
    if (diff.inDays < 7) return '${diff.inDays} gün önce';
    return '${dt.day}.${dt.month}.${dt.year}';
  }

  _RevenueStatus _statusOf(Map<String, dynamic> item) {
    return switch ((item['status'] ?? '').toString()) {
      'paid' => _RevenueStatus.deposit,
      'refunded' => _RevenueStatus.refund,
      'pending' || 'not_received' => _RevenueStatus.pending,
      _ => _RevenueStatus.collected,
    };
  }

  IconData _iconOf(_RevenueStatus s) => switch (s) {
    _RevenueStatus.deposit => Icons.savings_outlined,
    _RevenueStatus.collected => Icons.payments_outlined,
    _RevenueStatus.pending => Icons.hourglass_top_rounded,
    _RevenueStatus.refund => Icons.undo_rounded,
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: WebeyColors.ivory,
        body: const Center(
          child: CircularProgressIndicator(color: WebeyColors.primaryGold),
        ),
      );
    }

    final visible = _visibleItems;
    final totalCollected =
        (_summary['month_total_collected'] as num?)?.toDouble() ?? 0.0;
    final deposit =
        (_summary['month_deposit_collected'] as num?)?.toDouble() ?? 0.0;
    final pending = (_summary['pending_amount'] as num?)?.toDouble() ?? 0.0;
    final refunded = (_summary['refunded_amount'] as num?)?.toDouble() ?? 0.0;
    final changePct = (_summary['month_change_percent'] as num?)?.toDouble();

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: WebeyColors.primaryGold,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: _MgmtHeader(
                  titleBold: 'Gelir ',
                  titleItalic: '& Kapora',
                  onBack: () => Navigator.maybePop(context),
                ),
              ),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: _MgmtInlineState(message: _error!, onRetry: _load),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: _RevenueSummaryCard(
                    amountText: _money(totalCollected),
                    changePct: changePct,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      _RevenueMiniStat(label: 'Kapora', value: _money(deposit)),
                      const SizedBox(width: 8),
                      _RevenueMiniStat(
                        label: 'Bekleyen',
                        value: _money(pending),
                      ),
                      const SizedBox(width: 8),
                      _RevenueMiniStat(label: 'İade', value: _money(refunded)),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                    itemCount: _segments.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final segment = _segments[index];
                      return _RevenueSegmentChip(
                        label: segment.label,
                        selected: _segment == segment.id,
                        onTap: () => setState(() => _segment = segment.id),
                      );
                    },
                  ),
                ),
              ),
              if (visible.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _RevenueEmptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                  sliver: SliverList.separated(
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final status = _statusOf(item);
                      final customer = (item['customer_name'] ?? '')
                          .toString()
                          .trim();
                      final service = (item['service_name'] ?? '')
                          .toString()
                          .trim();
                      final detail = [
                        if (customer.isNotEmpty) customer,
                        if (service.isNotEmpty) service,
                      ].join(' · ');
                      return _RevenueTransactionCard(
                        item: _RevenueTransaction(
                          title: (item['label'] ?? '').toString(),
                          detail: detail.isEmpty ? 'Müşteri' : detail,
                          when: _itemWhen(item),
                          amount: _money(item['amount'] as num?),
                          status: status,
                          icon: _iconOf(status),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RevenueStatus { deposit, collected, pending, refund }

class _RevenueTransaction {
  const _RevenueTransaction({
    required this.title,
    required this.detail,
    required this.when,
    required this.amount,
    required this.status,
    required this.icon,
  });

  final String title;
  final String detail;
  final String when;
  final String amount;
  final _RevenueStatus status;
  final IconData icon;
}

class _RevenueSummaryCard extends StatelessWidget {
  const _RevenueSummaryCard({required this.amountText, this.changePct});

  final String amountText;
  final double? changePct;

  @override
  Widget build(BuildContext context) {
    String? changeLabel;
    Color? changeColor;
    if (changePct != null) {
      final sign = changePct! >= 0 ? '+' : '';
      changeLabel = 'Geçen aya göre $sign%${changePct!.toStringAsFixed(0)}';
      changeColor = changePct! >= 0
          ? WebeyColors.successGreen
          : WebeyColors.errorRed;
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
        boxShadow: WebeyShadow.subtle,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bu ay tahsil edilen',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  amountText,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 31,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                if (changeLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    changeLabel,
                    style: TextStyle(
                      color: changeColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: WebeyColors.goldLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.monetization_on_outlined,
              color: WebeyColors.primaryGold,
              size: 27,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueMiniStat extends StatelessWidget {
  const _RevenueMiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 19,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueSegmentChip extends StatelessWidget {
  const _RevenueSegmentChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? WebeyColors.darkEspresso : WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? WebeyColors.darkEspresso : WebeyColors.borderSand,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : WebeyColors.mutedTaupe,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _RevenueTransactionCard extends StatelessWidget {
  const _RevenueTransactionCard({required this.item});

  final _RevenueTransaction item;

  @override
  Widget build(BuildContext context) {
    final color = _revenueStatusColor(item.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
        boxShadow: WebeyShadow.subtle,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: WebeyColors.warmCream,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: Icon(item.icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Text(
                      item.when,
                      style: const TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RevenueStatusChip(status: item.status),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            item.amount,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueStatusChip extends StatelessWidget {
  const _RevenueStatusChip({required this.status});

  final _RevenueStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _revenueStatusColor(status);
    final label = switch (status) {
      _RevenueStatus.deposit => 'Kapora',
      _RevenueStatus.collected => 'Tahsil edildi',
      _RevenueStatus.pending => 'Bekliyor',
      _RevenueStatus.refund => 'İade',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WebeyColors.alpha(color, 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WebeyColors.alpha(color, 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _revenueStatusColor(_RevenueStatus status) {
  return switch (status) {
    _RevenueStatus.deposit => WebeyColors.primaryGold,
    _RevenueStatus.collected => WebeyColors.successGreen,
    _RevenueStatus.pending => WebeyColors.warning,
    _RevenueStatus.refund => WebeyColors.errorRed,
  };
}

// ignore: unused_element
class _DepositRatioCard extends StatelessWidget {
  const _DepositRatioCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kapora oranı',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 16,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Randevuların %72’sinde kapora alınmış.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              value: 0.72,
              minHeight: 7,
              backgroundColor: WebeyColors.warmCream,
              valueColor: AlwaysStoppedAnimation<Color>(
                WebeyColors.primaryGold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueEmptyState extends StatelessWidget {
  const _RevenueEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              color: WebeyColors.primaryGold,
              size: 42,
            ),
            SizedBox(height: 14),
            Text(
              'Henüz gelir hareketi yok',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 19,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Tahsilatlar ve kaporalar burada görünecek.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _LegacyBusinessRevenueDepositScreen extends StatelessWidget {
  const _LegacyBusinessRevenueDepositScreen();

  @override
  Widget build(BuildContext context) {
    return const _LegacyBusinessScreen(
      title: 'Gelir ve Kapora',
      labels: ['1 Gün', '1 Hafta', '1 Ay', 'Kapora toplamı', 'Kalan ödeme'],
    );
  }
}

class BusinessCustomersScreen extends StatefulWidget {
  const BusinessCustomersScreen({
    super.key,
    BusinessRepository repository = BusinessRepository.instance,
  }) : _repository = repository;

  final BusinessRepository _repository;

  @override
  State<BusinessCustomersScreen> createState() =>
      _BusinessCustomersScreenState();
}

class _BusinessCustomersScreenState extends State<BusinessCustomersScreen> {
  final _searchCtrl = TextEditingController();
  String _sort = 'frequency';

  static const _sorts = [
    (id: 'frequency', label: 'En sık'),
    (id: 'recent', label: 'En son'),
    (id: 'spend', label: 'Harcama'),
  ];

  bool _loading = true;
  String? _error;
  List<BusinessCustomer> _customers = const [];
  Map<String, dynamic> _summary = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget._repository.getCustomers();
      if (!mounted) return;
      setState(() {
        _customers = result.customers;
        _summary = result.summary;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'Müşteriler alınamadı.');
        _loading = false;
      });
    }
  }

  void _showCustomerDetail(BusinessCustomer customer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomerDetailSheet(
        customerId: customer.detailKey ?? customer.id,
        fallbackName: customer.name,
        repository: widget._repository,
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<BusinessCustomer> get _visibleCustomers {
    final query = _searchCtrl.text.trim().toLowerCase();
    final items = _customers.where((customer) {
      if (query.isEmpty) return true;
      final service = customer.favoriteServices.isEmpty
          ? ''
          : customer.favoriteServices.first;
      return customer.name.toLowerCase().contains(query) ||
          customer.phoneMasked.toLowerCase().contains(query) ||
          service.toLowerCase().contains(query);
    }).toList();

    switch (_sort) {
      case 'recent':
        items.sort((a, b) => b.lastVisitDate.compareTo(a.lastVisitDate));
      case 'spend':
        items.sort((a, b) => b.totalSpent.compareTo(a.totalSpent));
      default:
        items.sort(
          (a, b) => b.totalAppointments.compareTo(a.totalAppointments),
        );
    }
    return items;
  }

  int get _totalCustomers =>
      (_summary['total_customers'] as num?)?.toInt() ?? _customers.length;

  int get _newThisMonth {
    final fromSummary = (_summary['new_this_month'] as num?)?.toInt();
    if (fromSummary != null) return fromSummary;
    final now = DateTime.now();
    return _customers
        .where(
          (customer) =>
              customer.firstVisitDate.year == now.year &&
              customer.firstVisitDate.month == now.month,
        )
        .length;
  }

  int get _repeatRate {
    final fromSummary = (_summary['repeat_rate'] as num?)?.toInt();
    if (fromSummary != null) return fromSummary;
    if (_customers.isEmpty) return 0;
    final repeat = _customers
        .where((customer) => customer.completedAppointments > 1)
        .length;
    return ((repeat / _customers.length) * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleCustomers;

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _MgmtHeader(
                titleBold: 'Müşteri',
                titleItalic: 'ler',
                onBack: () => Navigator.maybePop(context),
                trailingWidget: _CustomerIconButton(
                  icon: Icons.search_rounded,
                  onTap: () {},
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    _CustomerSummaryCard(
                      value: '$_totalCustomers',
                      label: 'Toplam müşteri',
                    ),
                    const SizedBox(width: 8),
                    _CustomerSummaryCard(
                      value: '$_newThisMonth',
                      label: 'Bu ay yeni',
                    ),
                    const SizedBox(width: 8),
                    _CustomerSummaryCard(
                      value: '$_repeatRate%',
                      label: 'Tekrar gelen',
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: _CustomerSearchField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  itemCount: _sorts.length,
                  separatorBuilder: (_, separatorIndex) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final sort = _sorts[index];
                    final selected = _sort == sort.id;
                    return GestureDetector(
                      onTap: () => setState(() => _sort = sort.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? WebeyColors.darkEspresso
                              : WebeyColors.softWhite,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? WebeyColors.darkEspresso
                                : WebeyColors.borderSand,
                          ),
                        ),
                        child: Text(
                          sort.label,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : WebeyColors.mutedTaupe,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(
                    color: WebeyColors.primaryGold,
                  ),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _MgmtInlineState(message: _error!, onRetry: _load),
              )
            else if (visible.isEmpty)
              const SliverFillRemaining(child: _CustomersEmptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                sliver: SliverList.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, separatorIndex) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) => _CustomerCard(
                    customer: visible[index],
                    onTap: () => _showCustomerDetail(visible[index]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CustomerIconButton extends StatelessWidget {
  const _CustomerIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Icon(icon, size: 17, color: WebeyColors.darkEspresso),
      ),
    );
  }
}

class _CustomerSummaryCard extends StatelessWidget {
  const _CustomerSummaryCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: WebeyColors.borderSand),
          boxShadow: WebeyShadow.subtle,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 21,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 10.5,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerSearchField extends StatelessWidget {
  const _CustomerSearchField({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            size: 18,
            color: WebeyColors.mutedTaupe,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 13.5,
              ),
              decoration: const InputDecoration(
                hintText: 'Müşteri ara...',
                hintStyle: TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 13.5,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, this.onTap});

  final BusinessCustomer customer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final service = customer.favoriteServices.isEmpty
        ? 'Hizmet geçmişi hazırlanıyor'
        : customer.favoriteServices.first;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: WebeyColors.borderSand),
          boxShadow: WebeyShadow.subtle,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    WebeyColors.primaryGold,
                    Color.lerp(
                      WebeyColors.primaryGold,
                      WebeyColors.darkEspresso,
                      0.42,
                    )!,
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  _initials(customer.name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (customer.isVip)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: WebeyColors.goldLight,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'VIP',
                            style: TextStyle(
                              color: WebeyColors.primaryGold,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    service,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _CustomerBadge(
                        icon: Icons.event_available_outlined,
                        text: '${customer.totalAppointments} randevu',
                      ),
                      const SizedBox(width: 6),
                      _CustomerBadge(
                        icon: Icons.payments_outlined,
                        text: _formatTry(customer.totalSpent),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: WebeyColors.mutedTaupe,
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  static String _formatTry(double value) {
    final rounded = value.round().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < rounded.length; i++) {
      final remaining = rounded.length - i;
      buffer.write(rounded[i]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write('.');
    }
    return '$buffer TL';
  }
}

class _CustomerBadge extends StatelessWidget {
  const _CustomerBadge({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: WebeyColors.primaryGold),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Müşteri detay sheet — gerçek veriden (customer-detail.php).
class _CustomerDetailSheet extends StatefulWidget {
  const _CustomerDetailSheet({
    required this.customerId,
    required this.fallbackName,
    required this.repository,
  });

  final String customerId;
  final String fallbackName;
  final BusinessRepository repository;

  @override
  State<_CustomerDetailSheet> createState() => _CustomerDetailSheetState();
}

class _CustomerDetailSheetState extends State<_CustomerDetailSheet> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _customer = const {};
  Map<String, dynamic> _stats = const {};
  List<Map<String, dynamic>> _appointments = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.repository.getCustomerDetail(widget.customerId);
      if (!mounted) return;
      setState(() {
        _customer = data['customer'] is Map
            ? Map<String, dynamic>.from(data['customer'] as Map)
            : const {};
        _stats = data['stats'] is Map
            ? Map<String, dynamic>.from(data['stats'] as Map)
            : const {};
        _appointments = (data['appointments'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'Müşteri detayı alınamadı.');
        _loading = false;
      });
    }
  }

  int _int(Object? v) => v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
  double _double(Object? v) =>
      v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final name = (_customer['name']?.toString().trim().isNotEmpty ?? false)
        ? _customer['name'].toString()
        : widget.fallbackName;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: WebeyColors.ivory,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: WebeyColors.borderSand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 19,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_customer['is_vip'] == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: WebeyColors.primaryGold.withAlpha(28),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'VIP',
                      style: TextStyle(
                        color: WebeyColors.primaryGold,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: WebeyColors.primaryGold,
                      ),
                    ),
                  )
                : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: _MgmtInlineState(message: _error!, onRetry: _load),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _CustomerStatChip(
                            label: 'Toplam randevu',
                            value: '${_int(_stats['total_appointments'])}',
                          ),
                          _CustomerStatChip(
                            label: 'Tamamlanan',
                            value: '${_int(_stats['completed_appointments'])}',
                          ),
                          _CustomerStatChip(
                            label: 'İptal',
                            value: '${_int(_stats['cancelled_appointments'])}',
                          ),
                          _CustomerStatChip(
                            label: 'Gelmedi',
                            value: '${_int(_stats['no_show_appointments'])}',
                          ),
                          _CustomerStatChip(
                            label: 'Toplam harcama',
                            value: _CustomerCard._formatTry(
                              _double(_stats['total_spent']),
                            ),
                          ),
                          _CustomerStatChip(
                            label: 'Ortalama',
                            value: _CustomerCard._formatTry(
                              _double(_stats['average_spent']),
                            ),
                          ),
                        ],
                      ),
                      if ((_stats['favorite_service']?.toString() ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Favori hizmet: ${_stats['favorite_service']}',
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      const Text(
                        'Randevu geçmişi',
                        style: TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_appointments.isEmpty)
                        Text(
                          'Randevu kaydı yok.',
                          style: TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 12.5,
                          ),
                        )
                      else
                        ..._appointments.map(
                          (a) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    [
                                      a['service_name']?.toString() ?? 'Hizmet',
                                      if ((a['date']?.toString() ?? '')
                                          .isNotEmpty)
                                        '${a['date']} ${a['time'] ?? ''}'
                                            .trim(),
                                    ].join(' · '),
                                    style: const TextStyle(
                                      color: WebeyColors.darkEspresso,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                                if ((a['price']) != null)
                                  Text(
                                    _CustomerCard._formatTry(
                                      _double(a['price']),
                                    ),
                                    style: const TextStyle(
                                      color: WebeyColors.mutedTaupe,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CustomerStatChip extends StatelessWidget {
  const _CustomerStatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: (MediaQuery.of(context).size.width - 56) / 2,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _CustomersEmptyState extends StatelessWidget {
  const _CustomersEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: WebeyColors.goldLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_add_alt_1_outlined,
                size: 28,
                color: WebeyColors.primaryGold,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Henüz müşteriniz yok',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 19,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'İlk randevular tamamlandığında müşteri geçmişi, hizmet tercihleri ve tekrar ziyaret bilgileri burada görünecek.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BusinessAnalyticsScreen extends StatefulWidget {
  const BusinessAnalyticsScreen({
    super.key,
    BusinessRepository repository = BusinessRepository.instance,
  }) : _repository = repository;

  final BusinessRepository _repository;

  @override
  State<BusinessAnalyticsScreen> createState() =>
      _BusinessAnalyticsScreenState();
}

class _BusinessAnalyticsScreenState extends State<BusinessAnalyticsScreen> {
  String _period = '30d';
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

  static const _periods = [
    (id: '7d', label: '7 gün'),
    (id: '30d', label: '30 gün'),
    (id: '90d', label: '90 gün'),
    (id: 'year', label: 'Bu yıl'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget._repository.getAnalytics(range: _period);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'Analitik verisi alınamadı.');
        _loading = false;
      });
    }
  }

  Future<void> _changePeriod(String id) async {
    if (_period == id) return;
    setState(() => _period = id);
    await _load();
  }

  String _money(num? value) {
    final v = (value ?? 0).toDouble();
    final whole = v.round();
    final s = whole.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '₺$buf';
  }

  String _pctLabel(num? pct) {
    if (pct == null) return '—';
    final sign = pct >= 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final periodLabel = _periods
        .firstWhere((p) => p.id == _period, orElse: () => _periods[1])
        .label;

    final summaryRaw = _data['summary'];
    final summary = summaryRaw is Map
        ? Map<String, dynamic>.from(summaryRaw)
        : const <String, dynamic>{};
    final revenue = (summary['revenue'] as num?)?.toDouble() ?? 0.0;
    final revenueChange = summary['revenue_change_percent'] as num?;
    final appointmentsCount =
        (summary['appointments_count'] as num?)?.toInt() ?? 0;
    final apptChange = summary['appointments_change_percent'] as num?;
    final newCustomers = (summary['new_customers_count'] as num?)?.toInt() ?? 0;
    final newCustChange = summary['new_customers_change_percent'] as num?;
    final occupancy = (summary['occupancy_percent'] as num?)?.toDouble() ?? 0.0;
    final occupancyChange = summary['occupancy_change_percent'] as num?;
    final avgBasket = (summary['average_basket'] as num?)?.toDouble() ?? 0.0;
    final basketChange = summary['average_basket_change_percent'] as num?;

    final chartRaw = _data['revenue_chart'];
    final chartValues = chartRaw is List
        ? chartRaw
              .whereType<Map>()
              .map((e) => (e['revenue'] as num?)?.toDouble() ?? 0.0)
              .toList()
        : <double>[];

    final topServicesRaw = _data['top_services'];
    final topServices = topServicesRaw is List
        ? topServicesRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const <Map<String, dynamic>>[];

    final weeklyRaw = _data['weekly_occupancy'];
    final weekly = weeklyRaw is List
        ? weeklyRaw
              .whereType<Map>()
              .map(
                (e) => (
                  day: (e['day'] ?? '').toString(),
                  value: ((e['occupancy_percent'] as num?)?.toDouble() ?? 0.0)
                      .round(),
                ),
              )
              .toList()
        : const <({String day, int value})>[];

    final insightsRaw = _data['insights'];
    final insights = insightsRaw is List
        ? insightsRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : const <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: WebeyColors.primaryGold,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: _MgmtHeader(
                  titleBold: 'Anal',
                  titleItalic: 'itik',
                  onBack: () => Navigator.maybePop(context),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 58,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                    itemCount: _periods.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final period = _periods[index];
                      return _AnalyticsPeriodChip(
                        label: period.label,
                        selected: _period == period.id,
                        onTap: () => _changePeriod(period.id),
                      );
                    },
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: WebeyColors.primaryGold,
                    ),
                  ),
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: _MgmtInlineState(message: _error!, onRetry: _load),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _AnalyticsPerformanceCard(
                      periodLabel: periodLabel,
                      amountText: _money(revenue),
                      changeLabel: _pctLabel(revenueChange),
                      changePositive: (revenueChange ?? 0) >= 0,
                      values: chartValues,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: _AnalyticsKpiGrid(
                      items: [
                        (
                          label: 'Randevu',
                          value: '$appointmentsCount',
                          trend: _pctLabel(apptChange),
                        ),
                        (
                          label: 'Yeni müşteri',
                          value: '$newCustomers',
                          trend: _pctLabel(newCustChange),
                        ),
                        (
                          label: 'Doluluk',
                          value: '%${occupancy.toStringAsFixed(0)}',
                          trend: _pctLabel(occupancyChange),
                        ),
                        (
                          label: 'Ortalama sepet',
                          value: _money(avgBasket),
                          trend: _pctLabel(basketChange),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _SecH(
                    eyebrow: 'HİZMETLER',
                    title: 'En iyi hizmetler',
                    meta: periodLabel,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: WebeyColors.softWhite,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: topServices.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(
                                child: Text(
                                  'Henüz veri yok',
                                  style: TextStyle(
                                    color: WebeyColors.mutedTaupe,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            )
                          : Column(
                              children: [
                                for (
                                  var i = 0;
                                  i < topServices.length;
                                  i++
                                ) ...[
                                  _TopServiceRow(
                                    name: (topServices[i]['name'] ?? '')
                                        .toString(),
                                    value: _money(
                                      topServices[i]['revenue'] as num?,
                                    ),
                                    percent:
                                        ((topServices[i]['share_percent']
                                                    as num?)
                                                ?.toDouble() ??
                                            0) /
                                        100,
                                    label:
                                        '%${((topServices[i]['share_percent'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}',
                                  ),
                                  if (i != topServices.length - 1)
                                    const SizedBox(height: 14),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: _SecH(eyebrow: 'DOLULUK', title: 'Haftalık doluluk'),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: weekly.isEmpty
                        ? const _AnalyticsEmptyMini(
                            text:
                                'Doluluk için çalışma saatleri ve randevu gerekiyor.',
                          )
                        : _WeeklyOccupancyChart(values: weekly),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: _SecH(eyebrow: 'İÇGÖRÜLER', title: 'Öneriler'),
                ),
                if (insights.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(20, 14, 20, 40),
                      child: _AnalyticsEmptyMini(
                        text: 'Şu an gösterilecek öneri yok.',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                    sliver: SliverList.separated(
                      itemCount: insights.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final ins = insights[index];
                        final key = (ins['key'] ?? '').toString();
                        final icon = switch (key) {
                          'peak_day' => Icons.trending_up_rounded,
                          'low_occupancy' => Icons.schedule_rounded,
                          'top_service' => Icons.spa_outlined,
                          'new_customers' => Icons.person_add_alt_1_outlined,
                          'data_warmup' ||
                          'no_data' => Icons.hourglass_top_rounded,
                          _ => Icons.insights_outlined,
                        };
                        return _AnalyticsInsightCard(
                          icon: icon,
                          title: (ins['title'] ?? '').toString(),
                          description: (ins['description'] ?? '').toString(),
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticsEmptyMini extends StatelessWidget {
  const _AnalyticsEmptyMini({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12.5),
        ),
      ),
    );
  }
}

class _AnalyticsPeriodChip extends StatelessWidget {
  const _AnalyticsPeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? WebeyColors.darkEspresso : WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? WebeyColors.darkEspresso : WebeyColors.borderSand,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : WebeyColors.mutedTaupe,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _AnalyticsPerformanceCard extends StatelessWidget {
  const _AnalyticsPerformanceCard({
    required this.periodLabel,
    required this.amountText,
    required this.changeLabel,
    required this.changePositive,
    required this.values,
  });

  final String periodLabel;
  final String amountText;
  final String changeLabel;
  final bool changePositive;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final color = changePositive
        ? WebeyColors.successGreen
        : WebeyColors.errorRed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
        boxShadow: WebeyShadow.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Toplam performans',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      amountText,
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 31,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Gelir · $periodLabel',
                      style: const TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: WebeyColors.alpha(color, 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: WebeyColors.alpha(color, 0.22)),
                ),
                child: Text(
                  changeLabel,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _MiniBarSparkline(values: values),
        ],
      ),
    );
  }
}

class _AnalyticsKpiGrid extends StatelessWidget {
  const _AnalyticsKpiGrid({required this.items});

  final List<({String label, String value, String trend})> items;

  @override
  Widget build(BuildContext context) {
    if (items.length < 4) return const SizedBox.shrink();

    return Column(
      children: [
        Row(
          children: [
            _AnalyticsKpiCard(
              label: items[0].label,
              value: items[0].value,
              trend: items[0].trend,
            ),
            const SizedBox(width: 8),
            _AnalyticsKpiCard(
              label: items[1].label,
              value: items[1].value,
              trend: items[1].trend,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _AnalyticsKpiCard(
              label: items[2].label,
              value: items[2].value,
              trend: items[2].trend,
            ),
            const SizedBox(width: 8),
            _AnalyticsKpiCard(
              label: items[3].label,
              value: items[3].value,
              trend: items[3].trend,
            ),
          ],
        ),
      ],
    );
  }
}

class _AnalyticsKpiCard extends StatelessWidget {
  const _AnalyticsKpiCard({
    required this.label,
    required this.value,
    required this.trend,
  });

  final String label;
  final String value;
  final String trend;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 86),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 21,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  trend,
                  style: const TextStyle(
                    color: WebeyColors.successGreen,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniBarSparkline extends StatelessWidget {
  const _MiniBarSparkline({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox(
        height: 74,
        child: Center(
          child: Text(
            'Grafik verisi yok',
            style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 11.5),
          ),
        ),
      );
    }
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final safeMax = maxValue > 0 ? maxValue : 1.0;
    return SizedBox(
      height: 74,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            Expanded(
              child: FractionallySizedBox(
                heightFactor: (values[i] / safeMax).clamp(0.02, 1.0),
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: BoxDecoration(
                    color: WebeyColors.primaryGold,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            if (i != values.length - 1) const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }
}

class _TopServiceRow extends StatelessWidget {
  const _TopServiceRow({
    required this.name,
    required this.value,
    required this.percent,
    required this.label,
  });

  final String name;
  final String value;
  final double percent;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: 7,
            backgroundColor: WebeyColors.warmCream,
            valueColor: const AlwaysStoppedAnimation<Color>(
              WebeyColors.primaryGold,
            ),
          ),
        ),
      ],
    );
  }
}

class _WeeklyOccupancyChart extends StatelessWidget {
  const _WeeklyOccupancyChart({required this.values});

  final List<({String day, int value})> values;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: SizedBox(
        height: 138,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final item in values) ...[
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: item.value / 100,
                          widthFactor: 0.72,
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            decoration: BoxDecoration(
                              color: WebeyColors.primaryGold,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.day,
                      style: const TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (item != values.last) const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnalyticsInsightCard extends StatelessWidget {
  const _AnalyticsInsightCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
        boxShadow: WebeyShadow.subtle,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: WebeyColors.warmCream,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: Icon(icon, size: 17, color: WebeyColors.primaryGold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: WebeyColors.goldLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Öneri',
                        style: TextStyle(
                          color: WebeyColors.primaryGold,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _AnalyticsEmptyState extends StatelessWidget {
  const _AnalyticsEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.analytics_outlined,
              color: WebeyColors.primaryGold,
              size: 42,
            ),
            SizedBox(height: 14),
            Text(
              'Henüz analiz verisi yok',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 19,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Randevular oluştukça performans verileri burada görünecek.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _LegacyBusinessAnalyticsScreen extends StatelessWidget {
  const _LegacyBusinessAnalyticsScreen();

  @override
  Widget build(BuildContext context) {
    return const _LegacyBusinessScreen(
      title: 'Analitik',
      labels: [
        'Tahmini gelir',
        'Doluluk oranı',
        'Personel Performansı',
        'Tamamlanan randevu',
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN — Fatura ve Ödemeler (MVP: Webey komisyon henüz aktif değil)
// ─────────────────────────────────────────────────────────────────────────────

class BusinessInvoicesScreen extends StatefulWidget {
  const BusinessInvoicesScreen({super.key});

  @override
  State<BusinessInvoicesScreen> createState() => _BusinessInvoicesScreenState();
}

class _BusinessInvoicesScreenState extends State<BusinessInvoicesScreen> {
  final _repository = BusinessRepository.instance;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _items = const [];
  String? _message;
  bool _billingActive = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repository.getInvoices();
      if (!mounted) return;
      final summary = data['summary'];
      final items = data['items'];
      setState(() {
        _summary = summary is Map
            ? Map<String, dynamic>.from(summary)
            : const {};
        _items = items is List
            ? items
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : const [];
        _message = (data['message'] as String?);
        _billingActive = data['billing_active'] == true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'Fatura bilgileri alınamadı.');
        _loading = false;
      });
    }
  }

  String _money(num? value) {
    final v = (value ?? 0).toDouble();
    final whole = v.round();
    final s = whole.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '₺$buf';
  }

  @override
  Widget build(BuildContext context) {
    final commission =
        (_summary['commission_month'] as num?)?.toDouble() ?? 0.0;
    final unpaid = (_summary['unpaid_balance'] as num?)?.toDouble() ?? 0.0;
    final lastDate = (_summary['last_invoice_date'] as String?) ?? '';

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: WebeyColors.primaryGold,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 40),
            children: [
              _MgmtHeader(
                titleBold: 'Fatura ',
                titleItalic: 've Ödemeler',
                subtitle:
                    'Webey komisyonlarınızı, fatura geçmişinizi ve ödeme durumlarınızı buradan takip edebilirsiniz.',
                onBack: () => Navigator.maybePop(context),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: WebeyColors.primaryGold,
                    ),
                  ),
                )
              else ...[
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _MgmtInlineState(message: _error!, onRetry: _load),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      _RevenueMiniStat(
                        label: 'Bu ay komisyon',
                        value: _money(commission),
                      ),
                      const SizedBox(width: 8),
                      _RevenueMiniStat(
                        label: 'Ödenmemiş',
                        value: _money(unpaid),
                      ),
                      const SizedBox(width: 8),
                      _RevenueMiniStat(
                        label: 'Son fatura',
                        value: lastDate.isEmpty
                            ? '—'
                            : lastDate.substring(
                                0,
                                lastDate.length.clamp(0, 10),
                              ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: WebeyColors.warmCream,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: WebeyColors.borderSand),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: WebeyColors.primaryGold,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Kapora ödemeleri doğrudan salon IBAN’ına yapılır. '
                            'Webey bu aşamada müşteri kaporasını tahsil etmez. '
                            'Bu sayfa ileride Webey komisyon ve abonelik ödemeleri için kullanılacaktır.',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 34,
                      ),
                      decoration: BoxDecoration(
                        color: WebeyColors.softWhite,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: WebeyColors.warmCream,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(
                              Icons.receipt_long_outlined,
                              color: WebeyColors.primaryGold,
                              size: 26,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Henüz fatura bulunmuyor.',
                            style: TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 16,
                              fontFamily: 'Georgia',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _message ??
                                'Webey komisyon/fatura sistemi aktif olduğunda faturalarınız burada görünecek.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 12.5,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Column(
                      children: [
                        for (final inv in _items)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: WebeyColors.softWhite,
                              borderRadius: BorderRadius.circular(13),
                              border: Border.all(color: WebeyColors.borderSand),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (inv['invoice_no'] ?? '').toString(),
                                        style: const TextStyle(
                                          color: WebeyColors.darkEspresso,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        (inv['issued_at'] ?? '').toString(),
                                        style: const TextStyle(
                                          color: WebeyColors.mutedTaupe,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  _money(inv['total_amount'] as num?),
                                  style: const TextStyle(
                                    color: WebeyColors.darkEspresso,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Webey destek: destek@webey.com.tr'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: WebeyColors.darkEspresso,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Center(
                        child: Text(
                          'Destek ile iletişime geç',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_billingActive)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text(
                      'Billing aktif',
                      style: TextStyle(
                        color: WebeyColors.successGreen,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard Search Sheet — gerçek backend search.
// ─────────────────────────────────────────────────────────────────────────────

class BusinessDashboardSearchSheet extends StatefulWidget {
  const BusinessDashboardSearchSheet({super.key});

  @override
  State<BusinessDashboardSearchSheet> createState() =>
      _BusinessDashboardSearchSheetState();
}

class _BusinessDashboardSearchSheetState
    extends State<BusinessDashboardSearchSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _repo = BusinessRepository.instance;
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(value));
  }

  Future<void> _run(String value) async {
    final q = value.trim();
    if (q.length < 2) {
      setState(() {
        _data = const {};
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repo.dashboardSearch(q);
      if (!mounted) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(e, 'Arama yapılamadı.');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _list(String key) {
    final v = _data[key];
    if (v is List) {
      return v
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final appointments = _list('appointments');
    final customers = _list('customers');
    final services = _list('services');
    final staff = _list('staff');
    final hasResult =
        appointments.isNotEmpty ||
        customers.isNotEmpty ||
        services.isNotEmpty ||
        staff.isNotEmpty;
    final qLen = _controller.text.trim().length;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                decoration: BoxDecoration(
                  color: WebeyColors.borderSand,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  decoration: InputDecoration(
                    hintText: 'Randevu, müşteri, hizmet veya personel ara…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _controller.clear();
                              _run('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: WebeyColors.warmCream,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Builder(
                  builder: (_) {
                    if (qLen < 2) {
                      return const _SearchHintState(
                        text: 'En az 2 harf yazarak arama başlatın.',
                      );
                    }
                    if (_loading) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: WebeyColors.primaryGold,
                        ),
                      );
                    }
                    if (_error != null) {
                      return _SearchHintState(text: _error!);
                    }
                    if (!hasResult) {
                      return const _SearchHintState(text: 'Sonuç bulunamadı.');
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        if (appointments.isNotEmpty)
                          _SearchSection(
                            title: 'Randevular',
                            items: appointments,
                            iconBuilder: (_) => Icons.event_outlined,
                            titleBuilder: (m) =>
                                (m['customer_name'] ?? '').toString(),
                            subtitleBuilder: (m) {
                              final svc = (m['service_name'] ?? '').toString();
                              final dt = (m['starts_at'] ?? '').toString();
                              return [
                                svc,
                                dt,
                              ].where((s) => s.isNotEmpty).join(' · ');
                            },
                            onTap: (_) => _comingSoon(),
                          ),
                        if (customers.isNotEmpty)
                          _SearchSection(
                            title: 'Müşteriler',
                            items: customers,
                            iconBuilder: (_) => Icons.person_outline_rounded,
                            titleBuilder: (m) =>
                                (m['customer_name'] ?? '').toString(),
                            subtitleBuilder: (m) {
                              final ph = (m['customer_phone'] ?? '').toString();
                              final vc = (m['visit_count'] ?? 0).toString();
                              return [
                                ph,
                                '$vc ziyaret',
                              ].where((s) => s.isNotEmpty).join(' · ');
                            },
                            onTap: (_) => _comingSoon(),
                          ),
                        if (services.isNotEmpty)
                          _SearchSection(
                            title: 'Hizmetler',
                            items: services,
                            iconBuilder: (_) => Icons.spa_outlined,
                            titleBuilder: (m) => (m['name'] ?? '').toString(),
                            subtitleBuilder: (m) {
                              final price = m['price'];
                              final dm = (m['duration_minutes'] ?? 0)
                                  .toString();
                              final priceTxt = price is num
                                  ? '₺${price.toInt()}'
                                  : '';
                              return [
                                priceTxt,
                                '$dm dk',
                              ].where((s) => s.isNotEmpty).join(' · ');
                            },
                            onTap: (_) => _comingSoon(),
                          ),
                        if (staff.isNotEmpty)
                          _SearchSection(
                            title: 'Personel',
                            items: staff,
                            iconBuilder: (_) => Icons.badge_outlined,
                            titleBuilder: (m) => (m['name'] ?? '').toString(),
                            subtitleBuilder: (m) {
                              final role = (m['role'] ?? '').toString();
                              final ph = (m['phone'] ?? '').toString();
                              return [
                                role,
                                ph,
                              ].where((s) => s.isNotEmpty).join(' · ');
                            },
                            onTap: (_) => _comingSoon(),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _comingSoon() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Detay ekranı yakında.')));
  }
}

class _SearchHintState extends StatelessWidget {
  const _SearchHintState({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: WebeyColors.mutedTaupe, fontSize: 13),
        ),
      ),
    );
  }
}

class _SearchSection extends StatelessWidget {
  const _SearchSection({
    required this.title,
    required this.items,
    required this.iconBuilder,
    required this.titleBuilder,
    required this.subtitleBuilder,
    required this.onTap,
  });

  final String title;
  final List<Map<String, dynamic>> items;
  final IconData Function(Map<String, dynamic>) iconBuilder;
  final String Function(Map<String, dynamic>) titleBuilder;
  final String Function(Map<String, dynamic>) subtitleBuilder;
  final void Function(Map<String, dynamic>) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            title,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        ...items.map(
          (item) => InkWell(
            onTap: () => onTap(item),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              child: Row(
                children: [
                  Icon(
                    iconBuilder(item),
                    size: 18,
                    color: WebeyColors.primaryGold,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titleBuilder(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitleBuilder(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: WebeyColors.mutedTaupe,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Webey Paketim — işletme aboneliği durumu (YALNIZCA GÖSTERİM).
// Ödeme / IBAN / "satın al" CTA YOK. Faturalama Webey ekibi tarafından yönetilir.
// ════════════════════════════════════════════════════════════════════════════
class BusinessSubscriptionScreen extends StatefulWidget {
  const BusinessSubscriptionScreen({super.key, BusinessRepository? repository})
    : _repository = repository ?? BusinessRepository.instance;

  final BusinessRepository _repository;

  @override
  State<BusinessSubscriptionScreen> createState() =>
      _BusinessSubscriptionScreenState();
}

class _BusinessSubscriptionScreenState
    extends State<BusinessSubscriptionScreen> {
  static const _supportEmail = 'destek@webey.com.tr';
  static const _supportPhone = '+908502550000';
  static const _whatsappUrl = 'https://wa.me/908502550000';

  BusinessRepository get _repository => widget._repository;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _plan = const {};
  Map<String, dynamic> _sub = const {};
  String _supportMessage =
      'Ödeme ve fatura işlemleri Webey ekibi tarafından yönetilir.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repository.getSubscription();
      if (!mounted) return;
      final plan = data['plan'];
      final sub = data['subscription'];
      setState(() {
        _plan = plan is Map ? Map<String, dynamic>.from(plan) : const {};
        _sub = sub is Map ? Map<String, dynamic>.from(sub) : const {};
        _supportMessage =
            data['support_message']?.toString() ?? _supportMessage;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'Abonelik bilgisi alınamadı.');
        _loading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return WebeyColors.successGreen;
      case 'trial':
        return WebeyColors.warning;
      case 'overdue':
      case 'suspended':
        return WebeyColors.errorRed;
      default:
        return WebeyColors.mutedTaupe;
    }
  }

  String? _alertText(String status) {
    switch (status) {
      case 'overdue':
        return 'Aboneliğinizin ödeme tarihi geçti. Görünürlüğünüz '
            'etkilenmeden önce Webey ekibiyle iletişime geçin.';
      case 'suspended':
        return 'Aboneliğiniz askıya alındı. Müşteri uygulamasında '
            'görünürlüğünüz kısıtlanmış olabilir.';
      case 'cancelled':
        return 'Aboneliğiniz iptal edildi. Tekrar yayına almak için '
            'Webey ekibiyle iletişime geçin.';
      default:
        return null;
    }
  }

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw.replaceFirst(' ', 'T'));
    if (dt == null) return raw;
    const months = [
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _money(num? v) {
    if (v == null) return '—';
    final str = v.toStringAsFixed(0).replaceAll('-', '');
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write('.');
      buf.write(str[i]);
    }
    return '₺$buf';
  }

  Future<void> _launch(String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) WebeyToast.error(context, 'Bağlantı açılamadı.');
    } catch (_) {
      if (mounted) WebeyToast.error(context, 'Bağlantı açılamadı.');
    }
  }

  void _contactWebey() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: WebeyColors.softWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Webey ile iletişime geç',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: WebeyColors.darkEspresso,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Abonelik ve fatura işlemleri için Webey ekibi.',
                style: TextStyle(fontSize: 12.5, color: WebeyColors.mutedTaupe),
              ),
              const SizedBox(height: 16),
              _SubContactRow(
                icon: Icons.chat_outlined,
                label: 'WhatsApp ile yaz',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _launch(_whatsappUrl);
                },
              ),
              _SubContactRow(
                icon: Icons.mail_outline_rounded,
                label: _supportEmail,
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _launch('mailto:$_supportEmail');
                },
              ),
              _SubContactRow(
                icon: Icons.phone_outlined,
                label: 'Webey destek hattı',
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _launch('tel:$_supportPhone');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _sub['status']?.toString() ?? 'unknown';
    final statusLabel = _sub['status_label']?.toString() ?? 'Tanımlanmadı';
    final planName = _plan['name']?.toString() ?? 'Webey İşletme Paketi';
    final monthly =
        (_sub['monthly_price'] as num?) ?? (_plan['monthly_price'] as num?);
    final trialEnds = _sub['trial_ends_at']?.toString();
    final periodEnds = _sub['current_period_end']?.toString();
    final nextDue = _sub['next_payment_due_at']?.toString();
    final alert = _alertText(status);
    final statusColor = _statusColor(status);

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _MgmtHeader(
              titleBold: 'Webey',
              titleItalic: ' Paketim',
              onBack: () => Navigator.maybePop(context),
              trailingWidget: _CustomerIconButton(
                icon: Icons.workspace_premium_outlined,
                onTap: () {},
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: WebeyColors.primaryGold,
                      ),
                    )
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: _MgmtInlineState(message: _error!, onRetry: _load),
                    )
                  : ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                      children: [
                        if (alert != null) ...[
                          _SubAlertBanner(text: alert, color: statusColor),
                          const SizedBox(height: 16),
                        ],
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: WebeyColors.softWhite,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: WebeyColors.borderSand),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: WebeyColors.goldLight,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.workspace_premium_outlined,
                                      color: WebeyColors.primaryGold,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          planName,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: WebeyColors.darkEspresso,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        const Text(
                                          'Webey işletme aboneliği',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: WebeyColors.mutedTaupe,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  _SubStatusPill(
                                    label: statusLabel,
                                    color: statusColor,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Divider(
                                color: WebeyColors.borderSand,
                                height: 1,
                              ),
                              const SizedBox(height: 14),
                              _SubInfoRow(
                                label: 'Aylık ücret',
                                value: _money(monthly),
                              ),
                              if (trialEnds != null)
                                _SubInfoRow(
                                  label: 'Deneme bitiş',
                                  value: _fmtDate(trialEnds),
                                ),
                              if (periodEnds != null)
                                _SubInfoRow(
                                  label: 'Dönem bitiş',
                                  value: _fmtDate(periodEnds),
                                ),
                              if (nextDue != null)
                                _SubInfoRow(
                                  label: 'Sonraki ödeme',
                                  value: _fmtDate(nextDue),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: WebeyColors.warmCream,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: WebeyColors.borderSand),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: WebeyColors.primaryGold,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _supportMessage,
                                  style: const TextStyle(
                                    color: WebeyColors.mutedTaupe,
                                    fontSize: 12.5,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: _contactWebey,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: WebeyColors.darkEspresso,
                              side: const BorderSide(
                                color: WebeyColors.borderSand,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(
                              Icons.headset_mic_outlined,
                              size: 18,
                            ),
                            label: const Text(
                              'Webey ile iletişime geç',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Bu ekranda satın alma veya ödeme yapılmaz.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Durum etiketi (renkli pill).
class _SubStatusPill extends StatelessWidget {
  const _SubStatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: WebeyColors.alpha(color, 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WebeyColors.alpha(color, 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SubInfoRow extends StatelessWidget {
  const _SubInfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: WebeyColors.mutedTaupe, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubAlertBanner extends StatelessWidget {
  const _SubAlertBanner({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.alpha(color, 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.alpha(color, 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubContactRow extends StatelessWidget {
  const _SubContactRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: WebeyColors.primaryGold),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: WebeyColors.darkEspresso,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: WebeyColors.mutedTaupe,
            ),
          ],
        ),
      ),
    );
  }
}

class BusinessPromotionBoostScreen extends StatefulWidget {
  const BusinessPromotionBoostScreen({
    super.key,
    BusinessRepository? repository,
  }) : _repository = repository ?? BusinessRepository.instance;

  final BusinessRepository _repository;

  @override
  State<BusinessPromotionBoostScreen> createState() =>
      _BusinessPromotionBoostScreenState();
}

class _BusinessPromotionBoostScreenState
    extends State<BusinessPromotionBoostScreen> {
  BusinessRepository get _repository => widget._repository;
  bool _loading = true;
  bool _requesting = false;
  String? _error;
  Map<String, dynamic> _current = const {};
  Map<String, dynamic> _pendingRequest = const {};
  List<Map<String, dynamic>> _packages = const [];
  List<Map<String, dynamic>> _history = const [];
  bool _eligible = true;
  List<Map<String, dynamic>> _missing = const [];
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repository.getBoostPackages();
      if (!mounted) return;
      final cur = data['current_boost'];
      final pending = data['pending_request'];
      final pkgs = (data['packages'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final hist = (data['history'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final miss = (data['missing_requirements'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      setState(() {
        _current = cur is Map ? Map<String, dynamic>.from(cur) : const {};
        _pendingRequest = pending is Map
            ? Map<String, dynamic>.from(pending)
            : const {};
        _packages = pkgs;
        _history = hist;
        _eligible = (data['eligible'] as bool?) ?? true;
        _missing = miss;
        _selectedId ??= pkgs.isNotEmpty
            ? (pkgs.first['id'] as num?)?.toInt()
            : null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'Boost paketleri alınamadı.');
        _loading = false;
      });
    }
  }

  Future<void> _request() async {
    final id = _selectedId;
    if (id == null || _requesting || !_eligible) return;
    setState(() => _requesting = true);
    try {
      final res = await _repository.requestBoostPackage(packageId: id);
      if (!mounted) return;
      WebeyToast.success(
        context,
        res['message']?.toString() ??
            'Talebiniz alındı. Webey ekibi sizinle iletişime geçecek.',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      WebeyToast.error(
        context,
        _businessManagementError(error, 'Talep oluşturulamadı.'),
      );
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  _BoostPackage _toCard(Map<String, dynamic> p) {
    final price = (p['price'] as num?)?.toDouble() ?? 0;
    final days = (p['duration_days'] as num?)?.toInt() ?? 0;
    final feats = (p['features'] as List? ?? const [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    final desc = feats.isNotEmpty
        ? '$days gün · ${feats.first}'
        : (p['description']?.toString() ?? '$days gün görünürlük');
    final weight = (p['priority_weight'] as num?)?.toInt() ?? 0;
    return _BoostPackage(
      id: '${(p['id'] as num?)?.toInt() ?? 0}',
      title: p['name']?.toString() ?? 'Boost',
      description: desc,
      price: '₺${price.toStringAsFixed(0)}',
      durationDays: days,
      features: feats,
      icon: weight >= 10
          ? Icons.workspace_premium_outlined
          : weight >= 5
          ? Icons.star_outline_rounded
          : Icons.rocket_launch_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = _current.isNotEmpty;
    final hasPending = _pendingRequest.isNotEmpty;
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _MgmtHeader(
              titleBold: 'Bo',
              titleItalic: 'ost',
              onBack: () => Navigator.maybePop(context),
              trailingWidget: _CustomerIconButton(
                icon: Icons.campaign_outlined,
                onTap: () {},
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: WebeyColors.primaryGold,
                      ),
                    )
                  : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: _MgmtInlineState(message: _error!, onRetry: _load),
                    )
                  : ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                      children: [
                        if (hasActive) ...[
                          _BoostActiveRealCard(current: _current),
                          const SizedBox(height: 18),
                        ],
                        if (hasPending) ...[
                          _BoostPendingRequestCard(request: _pendingRequest),
                          const SizedBox(height: 18),
                        ],
                        if (!_eligible && _missing.isNotEmpty) ...[
                          _BoostEligibilityCard(missing: _missing),
                          const SizedBox(height: 18),
                        ],
                        const _SecH(eyebrow: 'PAKETLER', title: 'Boost seçimi'),
                        const SizedBox(height: 12),
                        if (_packages.isEmpty)
                          Text(
                            'Şu an satın alınabilir boost paketi yok.',
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 13,
                            ),
                          )
                        else
                          ..._packages.map((p) {
                            final id = (p['id'] as num?)?.toInt() ?? 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _BoostPackageCard(
                                package: _toCard(p),
                                selected: id == _selectedId,
                                active:
                                    ((_current['package_id'] as num?)
                                            ?.toInt() ??
                                        0) ==
                                    id,
                                pending:
                                    ((_pendingRequest['package_id'] as num?)
                                            ?.toInt() ??
                                        0) ==
                                    id,
                                onTap: () => setState(() => _selectedId = id),
                              ),
                            );
                          }),
                        if (_packages.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed:
                                  (_requesting || hasPending || !_eligible)
                                  ? null
                                  : _request,
                              child: Text(
                                !_eligible
                                    ? 'Şartları tamamlayın'
                                    : hasPending
                                    ? 'Talep alindi'
                                    : _requesting
                                    ? 'Gönderiliyor...'
                                    : 'Talep Et',
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ödeme alınmaz. Talebiniz Webey ekibine iletilir.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                        if (_history.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          const _SecH(
                            eyebrow: 'GEÇMİŞ',
                            title: 'Boost işlemleri',
                          ),
                          const SizedBox(height: 10),
                          ..._history.map((h) => _BoostHistoryRow(item: h)),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Boost uygunluk eksikleri kartı (gerçek backend verisi: missing_requirements).
class _BoostEligibilityCard extends StatelessWidget {
  const _BoostEligibilityCard({required this.missing});
  final List<Map<String, dynamic>> missing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.alpha(WebeyColors.warning, 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.alpha(WebeyColors.warning, 0.40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: WebeyColors.warning,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Boost için önce şu adımları tamamlayın',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: WebeyColors.darkEspresso,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...missing.map((m) {
            final label = m['label']?.toString() ?? 'Eksik şart';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.radio_button_unchecked,
                    size: 16,
                    color: WebeyColors.mutedTaupe,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 13,
                        color: WebeyColors.darkEspresso,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          const Text(
            'Şartlar tamamlanınca boost talebi açılır. Ödeme alınmaz.',
            style: TextStyle(fontSize: 11.5, color: WebeyColors.mutedTaupe),
          ),
        ],
      ),
    );
  }
}

// Gerçek aktif boost kartı.
class _BoostActiveRealCard extends StatelessWidget {
  const _BoostActiveRealCard({required this.current});
  final Map<String, dynamic> current;

  @override
  Widget build(BuildContext context) {
    final name = current['package_name']?.toString() ?? 'Boost';
    final daysLeft = (current['days_left'] as num?)?.toInt();
    final endsAt = current['ends_at']?.toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.primaryGold.withAlpha(22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.primaryGold.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bolt_rounded,
                color: WebeyColors.primaryGold,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Aktif paket: $name',
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (daysLeft != null) '$daysLeft gün kaldı',
              if (endsAt != null && endsAt.isNotEmpty)
                'Bitiş: ${endsAt.substring(0, endsAt.length >= 10 ? 10 : endsAt.length)}',
            ].join(' · '),
            style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _BoostPendingRequestCard extends StatelessWidget {
  const _BoostPendingRequestCard({required this.request});
  final Map<String, dynamic> request;

  @override
  Widget build(BuildContext context) {
    final name = request['package_name']?.toString() ?? 'Boost paketi';
    final date = request['created_at']?.toString() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.borderSand),
        boxShadow: WebeyShadow.subtle,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.schedule_send_outlined,
            color: WebeyColors.primaryGold,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Talep alindi: $name',
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    'Webey ekibi iletisime gececek.',
                    if (date.isNotEmpty)
                      'Tarih: ${date.substring(0, date.length >= 10 ? 10 : date.length)}',
                  ].join(' '),
                  style: const TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BoostHistoryRow extends StatelessWidget {
  const _BoostHistoryRow({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = item['package_name']?.toString() ?? 'Boost';
    final date = item['date']?.toString() ?? '';
    final status = item['status']?.toString() ?? '';
    final amount = (item['amount'] as num?)?.toDouble();
    final statusLabel = switch (status) {
      'pending' => 'Beklemede',
      'contacted' => 'İletişime geçildi',
      'approved' || 'active' => 'Onaylandı',
      'rejected' => 'Reddedildi',
      'expired' => 'Süresi doldu',
      'cancelled' => 'İptal',
      _ => status,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              [
                name,
                if (date.isNotEmpty)
                  date.substring(0, date.length >= 10 ? 10 : date.length),
              ].join(' · '),
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 12.5,
              ),
            ),
          ),
          Text(
            amount != null ? '₺${amount.toStringAsFixed(0)}' : statusLabel,
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoostPackage {
  const _BoostPackage({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.durationDays,
    required this.features,
    required this.icon,
  });

  final String id;
  final String title;
  final String description;
  final String price;
  final int durationDays;
  final List<String> features;
  final IconData icon;
}

// ignore: unused_element
class _BoostHeroCard extends StatelessWidget {
  const _BoostHeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
        boxShadow: WebeyShadow.subtle,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Salonunu öne çıkar',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 21,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Yakındaki müşterilere daha görünür ol ve boş saatlerini doldur.',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Gercek boost verileri',
                  style: TextStyle(
                    color: WebeyColors.primaryGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: WebeyColors.goldLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.campaign_outlined,
              color: WebeyColors.primaryGold,
              size: 27,
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _BoostMiniStat extends StatelessWidget {
  const _BoostMiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        constraints: const BoxConstraints(minHeight: 74),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 20,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _ActiveBoostCard extends StatelessWidget {
  const _ActiveBoostCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aktif Boost',
                      style: TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 16,
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    SizedBox(height: 7),
                    Text(
                      'Cuma-Pazar arası yakın çevrede üst sıralarda görün.',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 10),
              _BoostStatusChip(label: 'Aktif'),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              value: 0.62,
              minHeight: 7,
              backgroundColor: WebeyColors.warmCream,
              valueColor: AlwaysStoppedAnimation<Color>(
                WebeyColors.primaryGold,
              ),
            ),
          ),
          const SizedBox(height: 9),
          const Row(
            children: [
              Expanded(
                child: Text(
                  '2 gün kaldı',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 11.5,
                  ),
                ),
              ),
              Text(
                'Performans entegrasyonu ayri faz',
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoostPackageCard extends StatelessWidget {
  const _BoostPackageCard({
    required this.package,
    required this.selected,
    required this.active,
    required this.pending,
    required this.onTap,
  });

  final _BoostPackage package;
  final bool selected;
  final bool active;
  final bool pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? WebeyColors.primaryGold : WebeyColors.borderSand,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected ? WebeyShadow.subtle : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: Icon(
                package.icon,
                size: 17,
                color: WebeyColors.primaryGold,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          package.title,
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: 6),
                        const _BoostStatusChip(label: 'Aktif paket'),
                      ],
                      if (pending) ...[
                        const SizedBox(width: 6),
                        const _BoostStatusChip(label: 'Talep alindi'),
                      ],
                      if (selected) ...[
                        const SizedBox(width: 6),
                        const _BoostStatusChip(label: 'Seçili'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    package.description,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12.5,
                    ),
                  ),
                  if (package.features.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...package.features
                        .take(4)
                        .map(
                          (feature) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline_rounded,
                                  color: WebeyColors.primaryGold,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    feature,
                                    style: const TextStyle(
                                      color: WebeyColors.darkEspresso,
                                      fontSize: 11.8,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                  const SizedBox(height: 9),
                  Text(
                    package.price,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.chevron_right_rounded,
              size: selected ? 19 : 22,
              color: selected
                  ? WebeyColors.primaryGold
                  : WebeyColors.mutedTaupe,
            ),
          ],
        ),
      ),
    );
  }
}

class _BoostStatusChip extends StatelessWidget {
  const _BoostStatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WebeyColors.goldLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: WebeyColors.alpha(WebeyColors.primaryGold, 0.22),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: WebeyColors.primaryGold,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ignore: unused_element
class _BoostCtaCard extends StatelessWidget {
  const _BoostCtaCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.darkEspresso,
        borderRadius: BorderRadius.circular(13),
        boxShadow: WebeyShadow.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Secili paket talebi',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Talep kaydedildikten sonra Webey ekibi iletisime gecer.',
            style: TextStyle(
              color: WebeyColors.goldLight,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: WebeyColors.primaryGold,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'Talep Et',
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _BoostInactiveState extends StatelessWidget {
  const _BoostInactiveState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.campaign_outlined,
              color: WebeyColors.primaryGold,
              size: 42,
            ),
            SizedBox(height: 14),
            Text(
              'Aktif boost yok',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 19,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Bir paket seçerek salonunu öne çıkar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore: unused_element
class _LegacyBusinessPromotionBoostScreen extends StatelessWidget {
  const _LegacyBusinessPromotionBoostScreen();

  @override
  Widget build(BuildContext context) {
    return const _LegacyBusinessScreen(
      title: 'Boost Paketleri',
      labels: ['Premium Salon Rozeti'],
    );
  }
}

class BusinessActionCenterScreen extends StatefulWidget {
  const BusinessActionCenterScreen({super.key, this.onOpenCalendar});

  /// Randevu/takvim ile ilgili görevlerde Takvim ekranını ilgili filtreyle
  /// açmak için. (Takvim ekranı başka dosyada olduğundan callback ile gelir.)
  /// filter: 'pending' | 'today' | 'outcome'
  final void Function(String filter)? onOpenCalendar;

  @override
  State<BusinessActionCenterScreen> createState() =>
      _BusinessActionCenterScreenState();
}

class _BusinessActionCenterScreenState
    extends State<BusinessActionCenterScreen> {
  final _repository = BusinessRepository.instance;
  String _filter = 'all';
  bool _isLoading = false;
  String? _error;
  List<_ActionCenterItem> _loadedActions = _actions;

  static final _actions = [
    _ActionCenterItem(
      title: 'Bekleyen kaporaları kontrol et',
      description: '2 randevuda kapora onayı bekleniyor.',
      meta: 'Ödeme',
      status: _ActionCenterStatus.urgent,
      icon: Icons.account_balance_wallet_outlined,
      target: 'calendar_pending',
    ),
    _ActionCenterItem(
      title: 'Bugünkü randevuları hazırla',
      description: 'Bugün 6 müşteri randevusu var.',
      meta: 'Bugün 09:30-18:00',
      status: _ActionCenterStatus.today,
      icon: Icons.event_available_outlined,
      target: 'calendar_today',
    ),
    _ActionCenterItem(
      title: 'Profil fotoğraflarını güncelle',
      description: 'Salon galerinize 3 yeni görsel ekleyin.',
      meta: 'Profil',
      status: _ActionCenterStatus.suggestion,
      icon: Icons.photo_library_outlined,
      target: 'gallery',
    ),
    _ActionCenterItem(
      title: 'Çalışan saatleri tamamlandı',
      description: 'Bu haftanın müsaitlikleri girildi.',
      meta: 'Takvim',
      status: _ActionCenterStatus.done,
      icon: Icons.check_circle_outline_rounded,
      target: 'hours',
    ),
  ];

  static const _filters = [
    (id: 'all', label: 'Tümü'),
    (id: 'urgent', label: 'Acil'),
    (id: 'today', label: 'Bugün'),
    (id: 'done', label: 'Tamamlandı'),
  ];

  List<_ActionCenterItem> get _visibleActions {
    final actions = _loadedActions.isEmpty && _isLoading
        ? _actions
        : _loadedActions;
    final status = switch (_filter) {
      'urgent' => _ActionCenterStatus.urgent,
      'today' => _ActionCenterStatus.today,
      'done' => _ActionCenterStatus.done,
      _ => null,
    };
    if (status == null) return actions;
    return actions.where((item) => item.status == status).toList();
  }

  int _count(_ActionCenterStatus status) =>
      _loadedActions.where((item) => item.status == status).length;

  @override
  void initState() {
    super.initState();
    _loadActions();
  }

  Future<void> _loadActions() async {
    try {
      final data = await _repository.getActionCenter();
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => _ActionCenterItem.fromJson(item))
          .toList();
      if (!mounted) return;
      setState(() {
        _loadedActions = items.isEmpty ? _actions : items;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadedActions = _actions;
        _error = null;
        _isLoading = false;
      });
    }
  }

  void _openAction(_ActionCenterItem item) {
    Widget? screen;
    switch (item.target) {
      case 'deposits':
        screen = const BusinessRevenueDepositScreen();
      case 'calendar_today':
      case 'calendar_pending':
      case 'calendar_outcome':
        final filter = switch (item.target) {
          'calendar_pending' => 'pending',
          'calendar_outcome' => 'outcome',
          _ => 'today',
        };
        if (widget.onOpenCalendar != null) {
          widget.onOpenCalendar!(filter);
        } else {
          _showMgmtSnack(
            context,
            'Takvim sekmesinden randevuları açabilirsiniz.',
          );
        }
        return;
      case 'gallery':
        screen = const BusinessGalleryScreen();
      case 'hours':
        screen = const BusinessHoursScreen();
      case 'services':
        screen = const BusinessServicesScreen();
      case 'staff':
        screen = const BusinessStaffScreen();
      case 'payment_settings':
        screen = const BusinessPaymentSettingsScreen();
      case 'deposit_policy':
        screen = const BusinessDepositPolicyScreen();
      case 'campaigns':
        screen = const BusinessCampaignsScreen();
      default:
        screen = null;
    }
    if (screen == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleActions;
    final completed = _count(_ActionCenterStatus.done);

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _MgmtHeader(
                titleBold: 'Aksiyon ',
                titleItalic: 'Merkezi',
                onBack: () => Navigator.maybePop(context),
                trailingWidget: _CustomerIconButton(
                  icon: Icons.bolt_rounded,
                  onTap: () {},
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _ActionFocusCard(total: _loadedActions.length),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    _ActionMiniStat(
                      label: 'Acil',
                      value: '${_count(_ActionCenterStatus.urgent)}',
                    ),
                    const SizedBox(width: 8),
                    _ActionMiniStat(
                      label: 'Bugün',
                      value: '${_count(_ActionCenterStatus.today)}',
                    ),
                    const SizedBox(width: 8),
                    _ActionMiniStat(label: 'Tamamlanan', value: '$completed'),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                  itemCount: _filters.length,
                  separatorBuilder: (_, separatorIndex) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    final selected = _filter == filter.id;
                    return GestureDetector(
                      onTap: () => setState(() => _filter = filter.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? WebeyColors.darkEspresso
                              : WebeyColors.softWhite,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? WebeyColors.darkEspresso
                                : WebeyColors.borderSand,
                          ),
                        ),
                        child: Text(
                          filter.label,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : WebeyColors.mutedTaupe,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: _MgmtInlineState(
                  message: _error!,
                  onRetry: _loadActions,
                ),
              )
            else if (visible.isEmpty)
              const SliverFillRemaining(child: _ActionCenterEmptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
                sliver: SliverList.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, separatorIndex) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) => _ActionCenterCard(
                    item: visible[index],
                    onTap: () => _openAction(visible[index]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LaunchReadinessScreen extends StatelessWidget {
  const LaunchReadinessScreen({super.key, this.onEditBusinessInfo});

  /// "Salon bilgileri" adımına basınca açılacak işletme bilgileri düzenleyicisi.
  /// (Düzenleyici BusinessProfileScreen'de tanımlı olduğundan callback ile gelir.)
  final VoidCallback? onEditBusinessInfo;

  static final _items = [
    _LaunchChecklistItem(
      title: 'Salon bilgileri tamamlandı',
      description: 'Adres, iletişim ve işletme açıklaması hazır.',
      completed: true,
      target: _ReadinessTarget.businessInfo,
    ),
    _LaunchChecklistItem(
      title: 'Hizmetler eklendi',
      description: 'Müşterilerin rezerve edebileceği hizmet kataloğu var.',
      completed: true,
      target: _ReadinessTarget.services,
    ),
    _LaunchChecklistItem(
      title: 'Çalışanlar eklendi',
      description: 'Ekip üyeleri ve uzmanlık alanları tanımlandı.',
      completed: true,
      target: _ReadinessTarget.staff,
    ),
    _LaunchChecklistItem(
      title: 'Çalışma saatleri girildi',
      description: 'Haftalık müsaitlik takvimi yayına hazır.',
      completed: true,
      target: _ReadinessTarget.hours,
    ),
    _LaunchChecklistItem(
      title: 'Kapora ayarı eksik',
      description: 'No-show riskini azaltmak için kapora politikasını seç.',
      completed: false,
      target: _ReadinessTarget.deposit,
    ),
    _LaunchChecklistItem(
      title: 'Galeri görselleri eksik',
      description: 'Salon atmosferini gösteren en az 3 görsel ekle.',
      completed: false,
      target: _ReadinessTarget.gallery,
    ),
    _LaunchChecklistItem(
      title: 'İlk kampanya oluşturulmadı',
      description: 'İlk keşif trafiği için kısa süreli teklif hazırlayın.',
      completed: false,
      target: _ReadinessTarget.campaign,
    ),
  ];

  /// Checklist maddesinin hedef düzenleme ekranını açar.
  void _openTarget(BuildContext context, _ReadinessTarget target) {
    Widget? screen;
    switch (target) {
      case _ReadinessTarget.businessInfo:
        onEditBusinessInfo?.call();
        return;
      case _ReadinessTarget.services:
        screen = const BusinessServicesScreen();
      case _ReadinessTarget.staff:
        screen = const BusinessStaffScreen();
      case _ReadinessTarget.hours:
        screen = const BusinessHoursScreen();
      case _ReadinessTarget.deposit:
        screen = const BusinessPaymentSettingsScreen();
      case _ReadinessTarget.gallery:
        screen = const BusinessGalleryScreen();
      case _ReadinessTarget.campaign:
        screen = const BusinessPromotionBoostScreen();
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
  }

  @override
  Widget build(BuildContext context) {
    final completed = _items.where((item) => item.completed).length;
    final percent = _items.isEmpty ? 1.0 : completed / _items.length;
    final ready = completed == _items.length;
    final firstIncomplete = _items.cast<_LaunchChecklistItem?>().firstWhere(
      (item) => item != null && !item.completed,
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _MgmtHeader(
                titleBold: 'Yayına ',
                titleItalic: 'Hazırlık',
                onBack: () => Navigator.maybePop(context),
                trailingWidget: _CustomerIconButton(
                  icon: Icons.info_outline_rounded,
                  onTap: () {},
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: ready
                    ? const _LaunchReadyStateCard()
                    : _ReadinessProgressCard(percent: percent),
              ),
            ),
            SliverToBoxAdapter(
              child: _SecH(
                eyebrow: 'CHECKLIST',
                title: 'Yayına çıkış adımları',
                meta: '$completed/${_items.length}',
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              sliver: SliverList.separated(
                itemCount: _items.length,
                separatorBuilder: (_, separatorIndex) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) => _LaunchChecklistTile(
                  item: _items[index],
                  onTap: () => _openTarget(context, _items[index].target),
                ),
              ),
            ),
            if (!ready)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
                  child: _LaunchCtaCard(
                    onTap: firstIncomplete == null
                        ? null
                        : () => _openTarget(context, firstIncomplete.target),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _ActionCenterStatus { urgent, today, suggestion, done }

class _ActionCenterItem {
  const _ActionCenterItem({
    required this.title,
    required this.description,
    required this.meta,
    required this.status,
    required this.icon,
    this.target = '',
  });

  factory _ActionCenterItem.fromJson(Map<dynamic, dynamic> json) {
    final statusRaw = json['status']?.toString() ?? 'suggestion';
    final status = switch (statusRaw) {
      'urgent' => _ActionCenterStatus.urgent,
      'today' => _ActionCenterStatus.today,
      'done' => _ActionCenterStatus.done,
      _ => _ActionCenterStatus.suggestion,
    };
    return _ActionCenterItem(
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      meta: json['meta']?.toString() ?? '',
      status: status,
      icon: _actionIcon(json['icon']?.toString()),
      target: json['target']?.toString() ?? '',
    );
  }

  final String title;
  final String description;
  final String meta;
  final _ActionCenterStatus status;
  final IconData icon;
  final String target;
}

IconData _actionIcon(String? value) {
  return switch (value) {
    'wallet' => Icons.account_balance_wallet_outlined,
    'calendar' => Icons.calendar_month_outlined,
    'event' => Icons.event_available_outlined,
    'check' => Icons.check_circle_outline_rounded,
    'services' => Icons.spa_outlined,
    'staff' => Icons.groups_2_outlined,
    'hours' => Icons.schedule_outlined,
    'gallery' => Icons.photo_library_outlined,
    'deposit' => Icons.shield_outlined,
    'bank' => Icons.account_balance_outlined,
    _ => Icons.task_alt_rounded,
  };
}

class _ActionFocusCard extends StatelessWidget {
  const _ActionFocusCard({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
        boxShadow: WebeyShadow.subtle,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bugün odaklanman gereken $total aksiyon var',
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 19,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w700,
                    fontStyle: FontStyle.italic,
                    height: 1.18,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Randevu, ödeme ve profil eksiklerini buradan takip et.',
                  style: TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: WebeyColors.goldLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.task_alt_rounded,
              color: WebeyColors.primaryGold,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionMiniStat extends StatelessWidget {
  const _ActionMiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 20,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCenterCard extends StatelessWidget {
  const _ActionCenterCard({required this.item, required this.onTap});

  final _ActionCenterItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = item.status == _ActionCenterStatus.done;
    final color = _actionStatusColor(item.status);

    return GestureDetector(
      onTap: done ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: WebeyColors.borderSand),
          boxShadow: WebeyShadow.subtle,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: WebeyColors.borderSand),
              ),
              child: Icon(item.icon, size: 17, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ActionStatusChip(status: item.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.description,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_outlined,
                        size: 13,
                        color: WebeyColors.alpha(WebeyColors.mutedTaupe, 0.85),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        item.meta,
                        style: const TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              done ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
              color: done ? WebeyColors.successGreen : WebeyColors.mutedTaupe,
              size: done ? 20 : 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionStatusChip extends StatelessWidget {
  const _ActionStatusChip({required this.status});

  final _ActionCenterStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _actionStatusColor(status);
    final label = switch (status) {
      _ActionCenterStatus.urgent => 'Acil',
      _ActionCenterStatus.today => 'Bugün',
      _ActionCenterStatus.suggestion => 'Öneri',
      _ActionCenterStatus.done => 'Tamamlandı',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WebeyColors.alpha(color, 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WebeyColors.alpha(color, 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Color _actionStatusColor(_ActionCenterStatus status) {
  return switch (status) {
    _ActionCenterStatus.urgent => WebeyColors.errorRed,
    _ActionCenterStatus.today => WebeyColors.primaryGold,
    _ActionCenterStatus.suggestion => WebeyColors.mutedTaupe,
    _ActionCenterStatus.done => WebeyColors.successGreen,
  };
}

class _ActionCenterEmptyState extends StatelessWidget {
  const _ActionCenterEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt_rounded,
              size: 42,
              color: WebeyColors.primaryGold,
            ),
            SizedBox(height: 14),
            Text(
              'Şu an aksiyon yok',
              style: TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 19,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Her şey yolunda görünüyor.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 13,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yayına Hazırlık checklist maddesinin yönlendireceği düzenleme ekranı.
enum _ReadinessTarget {
  businessInfo,
  services,
  staff,
  hours,
  deposit,
  gallery,
  campaign,
}

class _LaunchChecklistItem {
  const _LaunchChecklistItem({
    required this.title,
    required this.description,
    required this.completed,
    required this.target,
  });

  final String title;
  final String description;
  final bool completed;
  final _ReadinessTarget target;
}

class _ReadinessProgressCard extends StatelessWidget {
  const _ReadinessProgressCard({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final pct = (percent * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
        boxShadow: WebeyShadow.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profilin %$pct hazır',
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 21,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 8,
              backgroundColor: WebeyColors.warmCream,
              valueColor: const AlwaysStoppedAnimation<Color>(
                WebeyColors.primaryGold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Yayına çıkmadan önce birkaç adımı tamamla.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _LaunchChecklistTile extends StatelessWidget {
  const _LaunchChecklistTile({required this.item, this.onTap});

  final _LaunchChecklistItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = item.completed
        ? WebeyColors.successGreen
        : WebeyColors.warning;

    return Material(
      color: WebeyColors.softWhite,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: WebeyColors.borderSand),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: item.completed
                      ? WebeyColors.alpha(WebeyColors.successGreen, 0.10)
                      : WebeyColors.warmCream,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: WebeyColors.borderSand),
                ),
                child: Icon(
                  item.completed
                      ? Icons.check_rounded
                      : Icons.priority_high_rounded,
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.description,
                      style: const TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 12.5,
                        height: 1.42,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _LaunchStatusChip(completed: item.completed),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaunchStatusChip extends StatelessWidget {
  const _LaunchStatusChip({required this.completed});

  final bool completed;

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? WebeyColors.successGreen
        : WebeyColors.primaryGold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: WebeyColors.alpha(color, 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: WebeyColors.alpha(color, 0.22)),
      ),
      child: Text(
        completed ? 'Tamam' : 'Eksik',
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LaunchCtaCard extends StatelessWidget {
  const _LaunchCtaCard({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.darkEspresso,
        borderRadius: BorderRadius.circular(13),
        boxShadow: WebeyShadow.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Yayına çıkmaya çok yakınsın',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Eksik adımları tamamladığında müşteriler seni keşfetmeye başlayabilir.',
            style: TextStyle(
              color: WebeyColors.goldLight,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: WebeyColors.primaryGold,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: const SizedBox(
                height: 42,
                child: Center(
                  child: Text(
                    'Eksikleri tamamla',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LaunchReadyStateCard extends StatelessWidget {
  const _LaunchReadyStateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: WebeyColors.borderSand),
        boxShadow: WebeyShadow.subtle,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_rounded,
            color: WebeyColors.successGreen,
            size: 30,
          ),
          SizedBox(height: 12),
          Text(
            'Yayına hazırsın',
            style: TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 22,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tüm hazırlık adımları tamamlandı. İşletmen müşteriler tarafından keşfedilebilir.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _LegacyBusinessActionCenterScreen extends StatelessWidget {
  const _LegacyBusinessActionCenterScreen();

  @override
  Widget build(BuildContext context) {
    return const _LegacyBusinessScreen(
      title: 'Aksiyon Merkezi',
      labels: ['3 yoruma yanıt verin'],
    );
  }
}

// ignore: unused_element
class _LegacyLaunchReadinessScreen extends StatelessWidget {
  const _LegacyLaunchReadinessScreen();

  @override
  Widget build(BuildContext context) {
    return const _LegacyBusinessScreen(
      title: 'Canlıya Hazırlık',
      labels: ['Ürün', 'Teknik', 'Mağaza'],
    );
  }
}

class _LegacyBusinessScreen extends StatelessWidget {
  const _LegacyBusinessScreen({required this.title, required this.labels});

  final String title;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            title,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 24,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          for (final label in labels)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(label),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN — İptal Politikası
// ─────────────────────────────────────────────────────────────────────────────

class BusinessCancellationPolicyScreen extends StatefulWidget {
  const BusinessCancellationPolicyScreen({super.key});

  @override
  State<BusinessCancellationPolicyScreen> createState() =>
      _BusinessCancellationPolicyScreenState();
}

class _BusinessCancellationPolicyScreenState
    extends State<BusinessCancellationPolicyScreen> {
  final _repository = BusinessRepository.instance;
  bool _isLoading = true;
  bool _isSaving = false;
  bool get _showBackendPolicyMode => false;
  String? _error;

  String _cancelPolicy = 'esnek';
  int _freeHours = 24;
  bool _lateFeeEnabled = false;
  String _lateFeeMode = 'percent';
  int _lateFeePercent = 50;
  String _noShowMode = 'forfeit';
  final _descCtrl = TextEditingController();
  int _ratePct = 25;
  bool _perService = false;

  static const _freeHourOptions = [1, 3, 6, 12, 24];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final policy = await _repository.getDepositPolicy();
      if (!mounted) return;
      final cancel = policy['cancel_policy']?.toString() ?? 'esnek';
      setState(() {
        _cancelPolicy = cancel;
        _ratePct = (policy['rate_pct'] is num)
            ? _normalizedDepositRate((policy['rate_pct'] as num).toInt())
            : 25;
        _perService = policy['per_service'] == true;
        _freeHours =
            (policy['free_cancel_hours'] as num?)?.toInt() ??
            switch (cancel) {
              'orta' => 12,
              'kati' || 'siki' => 3,
              _ => 24,
            };
        _lateFeeEnabled =
            policy['late_cancel_enabled'] == true ||
            (cancel == 'orta' || cancel == 'kati' || cancel == 'siki');
        _lateFeePercent =
            (policy['late_cancel_rate_pct'] as num?)?.toInt() ?? 50;
        _noShowMode =
            policy['no_show_policy']?.toString() ??
            switch (cancel) {
              'esnek' => 'refund',
              _ => 'forfeit',
            };
        final cm = policy['customer_message']?.toString();
        if (cm != null && cm.isNotEmpty) _descCtrl.text = cm;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _businessManagementError(error, 'İptal politikası alınamadı.');
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_depositRateOptions.contains(_ratePct)) {
      _showMgmtSnack(context, 'Kapora oranı seçin.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _repository.saveDepositPolicy({
        'rate_pct': _ratePct,
        'per_service': _perService,
        'cancel_policy': _cancelPolicy,
        'free_cancel_hours': _freeHours,
        'late_cancel_enabled': _lateFeeEnabled,
        'late_cancel_rate_pct': _lateFeePercent,
        'no_show_policy': _noShowMode,
        'customer_message': _descCtrl.text.trim(),
      });
      if (!mounted) return;
      _showMgmtSnack(context, 'İptal politikası kaydedildi.');
    } catch (error) {
      if (!mounted) return;
      _showMgmtSnack(
        context,
        _businessManagementError(error, 'İptal politikası kaydedilemedi.'),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _MgmtHeader(
                      titleBold: 'İptal ',
                      titleItalic: 'Politikası',
                      onBack: () => Navigator.maybePop(context),
                      subtitle:
                          'Ücretsiz iptal süresi, geç iptal ücreti ve no-show kuralı.',
                    ),
                  ),
                  if (_isLoading)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
                      sliver: SliverToBoxAdapter(
                        child: _MgmtInlineState(
                          message: 'Yükleniyor...',
                          isLoading: true,
                        ),
                      ),
                    )
                  else if (_error != null)
                    if (_showBackendPolicyMode)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _MgmtInlineState(
                            message: _error!,
                            onRetry: _load,
                          ),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _PolicySection(
                            title: 'Ücretsiz iptal süresi',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final hours in _freeHourOptions)
                                  _ChoiceChip(
                                    label: '$hours saat öncesine kadar',
                                    selected: _freeHours == hours,
                                    onTap: () =>
                                        setState(() => _freeHours = hours),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _PolicySection(
                            title: 'Geç iptal ücreti',
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'Geç iptal halinde ücret kesilsin',
                                        style: TextStyle(
                                          color: WebeyColors.darkEspresso,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Switch(
                                      value: _lateFeeEnabled,
                                      activeThumbColor: WebeyColors.primaryGold,
                                      onChanged: (v) =>
                                          setState(() => _lateFeeEnabled = v),
                                    ),
                                  ],
                                ),
                                if (_lateFeeEnabled) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      for (final pct in _depositRateOptions)
                                        _ChoiceChip(
                                          label: '%$pct',
                                          selected:
                                              _lateFeeMode == 'percent' &&
                                              _lateFeePercent == pct,
                                          onTap: () => setState(() {
                                            _lateFeeMode = 'percent';
                                            _lateFeePercent = pct;
                                          }),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _PolicySection(
                            title: 'Gelmeme (no-show)',
                            child: Column(
                              children: [
                                for (final option in const [
                                  ('forfeit', 'Kapora iade edilmez.'),
                                  (
                                    'half_refund',
                                    'Kaporanın yarısı iade edilir.',
                                  ),
                                  ('refund', 'Kapora tam iade edilir.'),
                                ])
                                  _RadioRow(
                                    label: option.$2,
                                    selected: _noShowMode == option.$1,
                                    onTap: () =>
                                        setState(() => _noShowMode = option.$1),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _PolicySection(
                            title: 'Backend politika modu',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Müşteri uygulamasında özetlenecek mod.',
                                  style: TextStyle(
                                    color: WebeyColors.mutedTaupe,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    for (final mode in const [
                                      ('esnek', 'Esnek'),
                                      ('orta', 'Orta'),
                                      ('kati', 'Katı'),
                                    ])
                                      _ChoiceChip(
                                        label: mode.$2,
                                        selected: _cancelPolicy == mode.$1,
                                        onTap: () => setState(
                                          () => _cancelPolicy = mode.$1,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: _PolicySection(
                            title: 'Müşteriye gösterilecek açıklama',
                            child: TextField(
                              controller: _descCtrl,
                              maxLines: 3,
                              maxLength: 300,
                              style: const TextStyle(
                                color: WebeyColors.darkEspresso,
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Örn. Randevudan 12 saat öncesine kadar ücretsiz iptal yapabilirsiniz.',
                                hintStyle: const TextStyle(
                                  color: WebeyColors.mutedTaupe,
                                  fontSize: 12,
                                ),
                                filled: true,
                                fillColor: WebeyColors.warmCream,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: WebeyColors.borderSand,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    ],
                ],
              ),
            ),
          ),
          _BottomSaveBar(isSaving: _isSaving, label: 'Kaydet', onTap: _save),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN — Bildirim Tercihleri
// ─────────────────────────────────────────────────────────────────────────────

class BusinessNotificationPreferencesScreen extends StatefulWidget {
  const BusinessNotificationPreferencesScreen({super.key});

  @override
  State<BusinessNotificationPreferencesScreen> createState() =>
      _BusinessNotificationPreferencesScreenState();
}

class _BusinessNotificationPreferencesScreenState
    extends State<BusinessNotificationPreferencesScreen> {
  final _repository = BusinessRepository.instance;
  Map<String, dynamic> _prefs = {
    'appointment_enabled': true,
    'review_enabled': true,
    'payment_enabled': true,
    'system_enabled': true,
    'daily_summary': false,
    'channel_push': true,
    'sound': true,
    'vibration': true,
    'sound_mode': 'sound',
  };

  bool _isSaving = false;
  bool get _showLegacyNotificationToggles => false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final remote = await _repository.getNotificationPreferences();
      if (!mounted) return;
      setState(() {
        if (remote.isNotEmpty) _prefs = {..._prefs, ...remote};
      });
    } catch (_) {
      // Keep default preferences on load failure.
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _repository.saveNotificationPreferences(_prefs);
      if (!mounted) return;
      _showMgmtSnack(context, 'Bildirim tercihleri güncellendi.');
    } catch (error) {
      if (!mounted) return;
      _showMgmtSnack(
        context,
        _businessManagementError(error, 'Bildirim tercihleri kaydedilemedi.'),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _toggle(String key, String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: _prefs[key] == true,
            activeThumbColor: WebeyColors.primaryGold,
            onChanged: (v) => setState(() => _prefs[key] = v),
          ),
        ],
      ),
    );
  }

  Widget _soundModeSelector() {
    final current = (_prefs['sound_mode'] ?? 'sound').toString();
    final modes = [
      (id: 'sound', label: 'Sesli', desc: 'Webey sesi + titreşim'),
      (id: 'vibrate', label: 'Titreşim', desc: 'Ses yok'),
      (id: 'silent', label: 'Sessiz', desc: 'Ses ve titreşim yok'),
    ];
    return Column(
      children: [
        for (final mode in modes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: GestureDetector(
              onTap: () => setState(() {
                _prefs['sound_mode'] = mode.id;
                _prefs['sound'] = mode.id == 'sound';
                _prefs['vibration'] = mode.id != 'silent';
              }),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: current == mode.id
                      ? WebeyColors.primaryGold.withAlpha(18)
                      : WebeyColors.warmCream,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: current == mode.id
                        ? WebeyColors.primaryGold
                        : WebeyColors.borderSand,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      current == mode.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: current == mode.id
                          ? WebeyColors.primaryGold
                          : WebeyColors.mutedTaupe,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mode.label,
                            style: const TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            mode.desc,
                            style: TextStyle(
                              color: WebeyColors.mutedTaupe,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _MgmtHeader(
                      titleBold: 'Bildirim ',
                      titleItalic: 'Tercihleri',
                      onBack: () => Navigator.maybePop(context),
                      subtitle:
                          'Hangi olaylarda ve hangi kanaldan bildirim alacağınızı seçin.',
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _PolicySection(
                        title: 'Olay bildirimleri',
                        child: Column(
                          children: [
                            _toggle(
                              'appointment_enabled',
                              'Yeni randevu',
                              subtitle:
                                  'Müşteri yeni randevu oluşturduğunda bildir.',
                            ),
                            if (_showLegacyNotificationToggles)
                              _toggle(
                                'appointment_enabled',
                                'Randevu push bildirimleri',
                                subtitle: 'Yeni randevu ve durum pushları.',
                              ),
                            _toggle(
                              'review_enabled',
                              'Yorum bildirimleri',
                              subtitle: 'Yeni puan ve yorum geldiğinde.',
                            ),
                            _toggle(
                              'payment_enabled',
                              'Kapora / ödeme bildirimleri',
                              subtitle: 'Tahsilat ve iade uyarıları.',
                            ),
                            _toggle(
                              'system_enabled',
                              'Sistem bildirimleri',
                              subtitle: 'Genel Webey duyuruları.',
                            ),
                            if (_showLegacyNotificationToggles)
                              _toggle(
                                'appointment_status',
                                'Randevu onay/iptal',
                                subtitle:
                                    'Müşteri onay veya iptal talep ettiğinde.',
                              ),
                            if (_showLegacyNotificationToggles)
                              _toggle(
                                'deposit_payment',
                                'Kapora ödeme',
                                subtitle:
                                    'Kapora ödendiğinde veya iade edildiğinde.',
                              ),
                            if (_showLegacyNotificationToggles)
                              _toggle(
                                'customer_message',
                                'Müşteri mesajları',
                                subtitle:
                                    'Müşteri salon ile iletişime geçtiğinde.',
                              ),
                            _toggle(
                              'daily_summary',
                              'Günlük özet',
                              subtitle: 'Her gün sabah günlük rapor.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _PolicySection(
                        title: 'Kanallar',
                        child: Column(
                          children: [
                            _toggle('channel_push', 'Uygulama bildirimi'),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _PolicySection(
                        title: 'Uyarı stili',
                        child: Column(children: [_soundModeSelector()]),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            ),
          ),
          _BottomSaveBar(isSaving: _isSaving, label: 'Kaydet', onTap: _save),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: WebeyColors.darkEspresso,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? WebeyColors.primaryGold : WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? WebeyColors.primaryGold : WebeyColors.borderSand,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : WebeyColors.darkEspresso,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? WebeyColors.primaryGold
                      : WebeyColors.borderSand,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: WebeyColors.primaryGold,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomSaveBar extends StatelessWidget {
  const _BottomSaveBar({
    required this.isSaving,
    required this.label,
    required this.onTap,
  });
  final bool isSaving;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: WebeyColors.ivory,
        border: Border(top: BorderSide(color: WebeyColors.borderSand)),
      ),
      child: GestureDetector(
        onTap: isSaving ? null : onTap,
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: isSaving ? WebeyColors.borderSand : WebeyColors.primaryGold,
            borderRadius: BorderRadius.circular(13),
          ),
          child: isSaving
              ? const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: WebeyColors.darkEspresso,
                    ),
                  ),
                )
              : Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
