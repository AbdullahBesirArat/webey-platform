import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/webey_colors.dart';
import '../profile/data/models/customer_profile.dart';
import '../profile/data/repositories/customer_profile_repository.dart';

class CustomerProfileEditScreen extends StatefulWidget {
  const CustomerProfileEditScreen({super.key, required this.profile});
  final CustomerProfile profile;

  @override
  State<CustomerProfileEditScreen> createState() =>
      _CustomerProfileEditScreenState();
}

class _CustomerProfileEditScreenState extends State<CustomerProfileEditScreen> {
  late final TextEditingController _firstNameCtrl;
  late final TextEditingController _lastNameCtrl;
  late final TextEditingController _phoneCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(
      text: widget.profile.firstName ?? '',
    );
    _lastNameCtrl = TextEditingController(text: widget.profile.lastName ?? '');
    _phoneCtrl = TextEditingController(text: widget.profile.phone ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // Yalnızca kişisel bilgiler güncellenir. Adres/konum alanları bu ekrandan
      // gönderilmez; backend yalnızca gelen alanları yazdığı için "Adres ve
      // Konum" sayfasındaki mevcut adres verisi korunur (sıfırlanmaz).
      await CustomerProfileRepository.instance.updateProfile({
        'first_name': _firstNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil güncellendi')));
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Güncelleme başarısız')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      appBar: AppBar(
        backgroundColor: WebeyColors.ivory,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: WebeyColors.darkEspresso,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profili Düzenle',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: WebeyColors.primaryGold,
                    ),
                  )
                : const Text(
                    'Kaydet',
                    style: TextStyle(
                      color: WebeyColors.primaryGold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        // Alt inputların (ör. Açık adres) Android navigation bar altında
        // ezilmemesi için cihazın alt güvenli alan inset'i kadar boşluk ekle.
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          24 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildField('Ad', _firstNameCtrl),
            const SizedBox(height: 16),
            _buildField('Soyad', _lastNameCtrl),
            const SizedBox(height: 16),
            _buildField(
              'Telefon',
              _phoneCtrl,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController ctrl, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: WebeyColors.mutedTaupe,
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(color: WebeyColors.darkEspresso, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: WebeyColors.softWhite,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: WebeyColors.borderSand),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: WebeyColors.borderSand),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: WebeyColors.primaryGold),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}

