// lib/features/business/presentation/business_service_categories_screen.dart
//
// İşletme > Hizmetler > Kategoriler
// Sistem kategorileri salt-okunur ("Varsayılan" rozeti), işletmeye özel
// kategoriler oluşturulup düzenlenebilir/silinebilir. Hizmet bağlı kategori
// silinmek istenirse backend 409 döner ve net mesaj gösterilir.

import 'package:flutter/material.dart';

import '../../../core/theme/webey_colors.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/widgets/webey_toast.dart';
import '../data/models/business_service_category.dart';
import '../data/repositories/business_repository.dart';
import 'widgets/service_category_picker.dart';

class BusinessServiceCategoriesScreen extends StatefulWidget {
  const BusinessServiceCategoriesScreen({super.key, this.repository});

  final BusinessRepository? repository;

  @override
  State<BusinessServiceCategoriesScreen> createState() =>
      _BusinessServiceCategoriesScreenState();
}

class _BusinessServiceCategoriesScreenState
    extends State<BusinessServiceCategoriesScreen> {
  BusinessRepository get _repository =>
      widget.repository ?? BusinessRepository.instance;

  bool _loading = true;
  String? _error;
  List<BusinessServiceCategory> _categories = const [];
  int? _busyId;

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
      final categories = await _repository.getServiceCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException
            ? error.message
            : 'Kategoriler yüklenemedi.';
        _loading = false;
      });
    }
  }

  Future<void> _createOrEdit([BusinessServiceCategory? edit]) async {
    final saved = await showServiceCategoryEditorDialog(
      context,
      repository: _repository,
      edit: edit,
    );
    if (saved == null || !mounted) return;
    WebeyToast.success(
      context,
      edit == null ? 'Kategori oluşturuldu.' : 'Kategori güncellendi.',
    );
    _load();
  }

  Future<void> _delete(BusinessServiceCategory category) async {
    if (_busyId != null) return;
    if (category.serviceCount > 0) {
      WebeyToast.info(
        context,
        'Bu kategoriye bağlı ${category.serviceCount} hizmet var. '
        'Önce hizmetleri farklı bir kategoriye taşıyın.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WebeyColors.ivory,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: WebeyColors.borderSand),
        ),
        title: const Text(
          'Bu kategoriyi silmek istiyor musunuz?',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 16,
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          '"${category.name}" kategorisi kaldırılacak.',
          style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Sil',
              style: TextStyle(color: WebeyColors.errorRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = category.id);
    try {
      await _repository.deleteServiceCategory(category.id);
      if (!mounted) return;
      WebeyToast.success(context, 'Kategori silindi.');
      _load();
    } catch (error) {
      if (!mounted) return;
      WebeyToast.error(
        context,
        error is ApiException ? error.message : 'Kategori silinemedi.',
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final system = _categories.where((c) => c.isSystem).toList();
    final custom = _categories.where((c) => !c.isSystem).toList();

    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      appBar: AppBar(
        backgroundColor: WebeyColors.ivory,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.chevron_left_rounded,
            color: WebeyColors.darkEspresso,
          ),
        ),
        title: const Text(
          'Hizmet Kategorileri',
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 17,
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createOrEdit(),
        backgroundColor: WebeyColors.primaryGold,
        foregroundColor: WebeyColors.darkEspresso,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Yeni kategori',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                children: [
                  Text(
                    'Hizmetlerinizi kategorilere ayırarak müşterilerin daha '
                    'kolay seçim yapmasını sağlayın.',
                    style: TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _sectionLabel('WEBEY KATEGORİLERİ'),
                  const SizedBox(height: 8),
                  for (final category in system)
                    _CategoryCard(
                      category: category,
                      busy: false,
                      onEdit: null,
                      onDelete: null,
                    ),
                  const SizedBox(height: 18),
                  _sectionLabel('SALON KATEGORİLERİM'),
                  const SizedBox(height: 8),
                  if (custom.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: WebeyColors.warmCream,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: Text(
                        'Henüz size özel kategori yok. "Yeni kategori" ile '
                        'kendi kategorinizi oluşturabilirsiniz.',
                        style: TextStyle(
                          color: WebeyColors.mutedTaupe,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    )
                  else
                    for (final category in custom)
                      _CategoryCard(
                        category: category,
                        busy: _busyId == category.id,
                        onEdit: () => _createOrEdit(category),
                        onDelete: () => _delete(category),
                      ),
                ],
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
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.busy,
    this.onEdit,
    this.onDelete,
  });

  final BusinessServiceCategory category;
  final bool busy;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.borderSand),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: WebeyColors.warmCream,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WebeyColors.borderSand),
            ),
            child: Icon(
              category.isSystem
                  ? Icons.auto_awesome_outlined
                  : Icons.category_outlined,
              size: 17,
              color: WebeyColors.primaryGold,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (category.isSystem) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: WebeyColors.goldLight,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          'Varsayılan',
                          style: TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${category.serviceCount} hizmet',
                  style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 11),
                ),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (!category.isSystem) ...[
            IconButton(
              onPressed: onEdit,
              icon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: WebeyColors.mutedTaupe,
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: WebeyColors.errorRed,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: WebeyColors.mutedTaupe, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}
