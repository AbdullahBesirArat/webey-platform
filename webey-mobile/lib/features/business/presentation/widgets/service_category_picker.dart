// lib/features/business/presentation/widgets/service_category_picker.dart
//
// Hizmet ekleme/düzenleme formlarında kullanılan kategori seçici.
// - Sistem kategorileri + işletmeye özel kategoriler listelenir.
// - "Kategorisiz" seçeneği açıkça sunulur.
// - "Yeni kategori oluştur" ile işletmeye özel kategori eklenip otomatik seçilir.

import 'package:flutter/material.dart';

import '../../../../core/theme/webey_colors.dart';
import '../../data/models/business_service_category.dart';
import '../../data/repositories/business_repository.dart';

/// Picker sonucu: `cancelled` ise kullanıcı vazgeçti; değilse `category`
/// seçilen kategoridir (null = Kategorisiz).
class ServiceCategoryPickResult {
  const ServiceCategoryPickResult({this.category});
  final BusinessServiceCategory? category;
}

/// Form içinde gösterilen tıklanabilir kategori alanı.
class ServiceCategoryField extends StatelessWidget {
  const ServiceCategoryField({
    super.key,
    required this.label,
    required this.valueText,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String? valueText;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final hasValue = valueText != null && valueText!.isNotEmpty;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WebeyColors.borderSand),
        ),
        child: Row(
          children: [
            Icon(
              Icons.category_outlined,
              size: 16,
              color: WebeyColors.mutedTaupe,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasValue ? valueText! : 'Kategorisiz',
                    style: TextStyle(
                      color: hasValue
                          ? WebeyColors.darkEspresso
                          : WebeyColors.mutedTaupe,
                      fontSize: 13,
                      fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: WebeyColors.mutedTaupe,
            ),
          ],
        ),
      ),
    );
  }
}

/// Kategori seçim bottom sheet'i. null dönerse kullanıcı vazgeçmiştir.
Future<ServiceCategoryPickResult?> showServiceCategoryPicker(
  BuildContext context, {
  required BusinessRepository repository,
  required List<BusinessServiceCategory> categories,
  int? selectedId,
}) {
  return showModalBottomSheet<ServiceCategoryPickResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoryPickerSheet(
      repository: repository,
      categories: categories,
      selectedId: selectedId,
    ),
  );
}

/// Yeni kategori oluşturma / mevcut özel kategoriyi düzenleme dialog'u.
/// Kaydedilen kategoriyi döndürür; vazgeçilirse null.
Future<BusinessServiceCategory?> showServiceCategoryEditorDialog(
  BuildContext context, {
  required BusinessRepository repository,
  BusinessServiceCategory? edit,
}) {
  return showDialog<BusinessServiceCategory>(
    context: context,
    builder: (_) => _CategoryEditorDialog(repository: repository, edit: edit),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.repository,
    required this.categories,
    this.selectedId,
  });

  final BusinessRepository repository;
  final List<BusinessServiceCategory> categories;
  final int? selectedId;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  late final List<BusinessServiceCategory> _categories = widget.categories;

  Future<void> _createNew() async {
    final created = await showServiceCategoryEditorDialog(
      context,
      repository: widget.repository,
    );
    if (created == null || !mounted) return;
    // Yeni kategori otomatik seçili olarak döner.
    Navigator.of(context).pop(ServiceCategoryPickResult(category: created));
  }

  @override
  Widget build(BuildContext context) {
    final system = _categories.where((c) => c.isSystem).toList();
    final custom = _categories.where((c) => !c.isSystem).toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Material(
          color: WebeyColors.ivory,
          borderRadius: BorderRadius.circular(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: WebeyColors.borderSand,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Hizmet Kategorisi',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 17,
                      fontFamily: 'Georgia',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _optionTile(
                    label: 'Kategorisiz',
                    selected: widget.selectedId == null,
                    muted: true,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(const ServiceCategoryPickResult()),
                  ),
                  if (system.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _sectionLabel('WEBEY KATEGORİLERİ'),
                    const SizedBox(height: 6),
                    for (final category in system)
                      _optionTile(
                        label: category.name,
                        selected: widget.selectedId == category.id,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(ServiceCategoryPickResult(category: category)),
                      ),
                  ],
                  if (custom.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _sectionLabel('SALON KATEGORİLERİM'),
                    const SizedBox(height: 6),
                    for (final category in custom)
                      _optionTile(
                        label: category.name,
                        selected: widget.selectedId == category.id,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(ServiceCategoryPickResult(category: category)),
                      ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: _createNew,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Yeni kategori oluştur'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: WebeyColors.darkEspresso,
                        side: const BorderSide(color: WebeyColors.primaryGold),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: WebeyColors.primaryGold,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _optionTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool muted = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? WebeyColors.goldLight : WebeyColors.warmCream,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? WebeyColors.primaryGold : WebeyColors.borderSand,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: muted
                      ? WebeyColors.mutedTaupe
                      : WebeyColors.darkEspresso,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                size: 17,
                color: WebeyColors.primaryGold,
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryEditorDialog extends StatefulWidget {
  const _CategoryEditorDialog({required this.repository, this.edit});

  final BusinessRepository repository;
  final BusinessServiceCategory? edit;

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.edit?.name ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Kategori adı boş olamaz.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.saveServiceCategory(
        id: widget.edit?.id,
        name: name,
        sortOrder: widget.edit?.sortOrder ?? 0,
      );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString().replaceFirst('ApiException: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: WebeyColors.ivory,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: WebeyColors.borderSand),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.edit == null ? 'Yeni kategori' : 'Kategoriyi düzenle',
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 16,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              maxLength: 80,
              decoration: const InputDecoration(
                hintText: 'Örn. Gelin Makyajı',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: const TextStyle(
                  color: WebeyColors.errorRed,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Vazgeç'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
