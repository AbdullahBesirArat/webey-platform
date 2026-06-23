import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/webey_colors.dart';
import '../../../shared/widgets/webey_toast.dart';
import '../../../shared/services/api_client.dart';
import '../data/models/business_service_item.dart';
import '../data/models/business_staff_item.dart';
import '../data/models/business_gallery_item.dart';
import '../data/models/business_gallery_summary.dart';
import '../data/repositories/business_repository.dart';
import '../data/repositories/business_gallery_repository.dart';
import 'business_management_screens.dart';

class BusinessGalleryScreen extends StatefulWidget {
  const BusinessGalleryScreen({
    super.key,
    this.repository = BusinessGalleryRepository.instance,
    this.businessRepository = BusinessRepository.instance,
  });

  final BusinessGalleryRepository repository;
  final BusinessRepository businessRepository;

  @override
  State<BusinessGalleryScreen> createState() => _BusinessGalleryScreenState();
}

class _BusinessGalleryScreenState extends State<BusinessGalleryScreen> {
  static const _quotaLimit = 20;
  var _selectedCategory = '';
  var _sortMode = 'newest';
  var _loading = true;
  String? _error;
  BusinessGallerySummary? _summary;

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  Future<void> _loadGallery() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await widget.repository.getGallery(includeHidden: true);
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyGalleryError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_GalleryCategory> get _categories {
    final summary = _summary;
    if (summary == null) {
      return const [_GalleryCategory(key: '', label: 'Tümü', count: 0)];
    }
    return [
      _GalleryCategory(key: '', label: 'Tümü', count: summary.items.length),
      for (final category in summary.categories)
        _GalleryCategory(
          key: category.key,
          label: category.label,
          count: category.count,
          limit: category.limit,
        ),
    ];
  }

  List<BusinessGalleryItem> get _visiblePhotos {
    final items = _summary?.items ?? const <BusinessGalleryItem>[];
    final filtered = _selectedCategory.isEmpty
        ? items
        : items.where((photo) => photo.category == _selectedCategory);
    final list = filtered.toList(growable: false);
    switch (_sortMode) {
      case 'oldest':
        list.sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
      case 'cover':
        list.sort(
          (a, b) => b.isCover.toString().compareTo(a.isCover.toString()),
        );
      case 'category':
        list.sort((a, b) => a.categoryLabel.compareTo(b.categoryLabel));
      default:
        list.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    }
    return list;
  }

  List<_BeforeAfterGroup> get _beforeAfterGroups {
    final grouped =
        <String, ({BusinessGalleryItem? before, BusinessGalleryItem? after})>{};
    for (final item in _summary?.items ?? const <BusinessGalleryItem>[]) {
      if (item.category != 'before_after') continue;
      final groupId = item.pairGroupId?.trim();
      final role = item.pairRole?.trim().toLowerCase();
      if (groupId == null || groupId.isEmpty) continue;
      if (role != 'before' && role != 'after') continue;
      final current = grouped[groupId] ?? (before: null, after: null);
      grouped[groupId] = role == 'before'
          ? (before: item, after: current.after)
          : (before: current.before, after: item);
    }
    return [
      for (final entry in grouped.values)
        if (entry.before != null && entry.after != null)
          _BeforeAfterGroup(before: entry.before!, after: entry.after!),
    ];
  }

  int get _usedQuota => _summary?.quotaUsed ?? 0;
  int get _quota => _summary?.quotaLimit ?? _quotaLimit;

  String _selectedCategoryLabel() {
    for (final item in _categories) {
      if (item.key == _selectedCategory) return item.label;
    }
    return 'Tümü';
  }

  @override
  Widget build(BuildContext context) {
    final visiblePhotos = _visiblePhotos;
    final beforeAfterGroups = _beforeAfterGroups;
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _GalleryHeader(onBack: _pop, onMenu: _showGalleryMenu),
            ),
            SliverToBoxAdapter(
              child: _CoverSummaryCard(
                used: _usedQuota,
                limit: _quota,
                coverItem: _summary?.coverItem,
                onChangeCover: _showAddSheet,
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: _GalleryErrorState(
                  message: _error!,
                  onRetry: _loadGallery,
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: _CategoryStrip(
                  categories: _categories,
                  selected: _selectedCategory,
                  onChanged: (value) =>
                      setState(() => _selectedCategory = value),
                ),
              ),
              SliverToBoxAdapter(
                child: _SectionHeader(
                  eyebrow: _selectedCategory.isEmpty
                      ? 'TÜM FOTOĞRAFLAR'
                      : _selectedCategoryLabel().toUpperCase(),
                  title: visiblePhotos.isEmpty
                      ? 'Galeri boş'
                      : '${visiblePhotos.length} görsel',
                  actionLabel: 'Sırala',
                  actionIcon: Icons.sort_rounded,
                  onAction: _showSortSheet,
                ),
              ),
              if (visiblePhotos.isEmpty)
                SliverToBoxAdapter(
                  child: _GalleryEmptyState(onAdd: _showAddSheet),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                  sliver: SliverGrid.builder(
                    itemCount: visiblePhotos.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 7,
                          crossAxisSpacing: 7,
                          childAspectRatio: 0.8,
                        ),
                    itemBuilder: (context, index) => _PhotoTile(
                      photo: visiblePhotos[index],
                      onTap: _showEditSheet,
                    ),
                  ),
                ),
              if (beforeAfterGroups.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: _SectionHeader(
                    eyebrow: 'ÖNCESİ-SONRASI',
                    title: 'Dönüşüm fotoğrafları',
                  ),
                ),
                SliverToBoxAdapter(
                  child: _BeforeAfterPair(
                    group: beforeAfterGroups.first,
                    onTap: _showEditSheet,
                  ),
                ),
              ],
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 118)),
          ],
        ),
      ),
      bottomNavigationBar: _GalleryActionBar(
        onAdd: _showAddSheet,
        onMultiSelect: _showSortSheet,
      ),
    );
  }

  void _pop() => Navigator.of(context).pop();

  Future<void> _showGalleryMenu() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _GalleryMenuSheet(hasCover: _summary?.coverItem != null),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case 'refresh':
        await _loadGallery();
      case 'cover':
        await _showAddSheet();
      case 'sort':
        await _showSortSheet();
      case 'info':
        _showSnack('Galeri: $_usedQuota / $_quota fotoğraf kullanılıyor.');
    }
  }

  Future<void> _showSortSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _GallerySortSheet(selected: _sortMode),
    );
    if (!mounted || result == null) return;
    setState(() => _sortMode = result);
  }

  Future<void> _showAddSheet() async {
    final changed = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GalleryAddSheet(
        repository: widget.repository,
        businessRepository: widget.businessRepository,
      ),
    );
    if (changed == true || changed is String) {
      await _loadGallery();
      if (!mounted) return;
      _showSnack(changed is String ? changed : 'Galeri güncellendi.');
    }
  }

  Future<void> _showEditSheet(BusinessGalleryItem item) async {
    final changed = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GalleryEditSheet(
        item: item,
        repository: widget.repository,
        businessRepository: widget.businessRepository,
      ),
    );
    if (changed == true || changed is String) {
      await _loadGallery();
      if (!mounted) return;
      _showSnack(changed is String ? changed : 'Galeri güncellendi.');
    }
  }

  void _showSnack(String message) {
    final lower = message.toLowerCase();
    if (['yüklendi', 'güncellendi', 'eklendi', 'silindi'].any(lower.contains)) {
      WebeyToast.success(context, message);
    } else if (['yüklenemedi', 'hata', 'başarısız'].any(lower.contains)) {
      WebeyToast.error(context, message);
    } else {
      WebeyToast.info(context, message);
    }
  }
}

class _GalleryCategory {
  const _GalleryCategory({
    required this.key,
    required this.label,
    required this.count,
    this.limit,
  });

  final String key;
  final String label;
  final int count;
  final int? limit;
}

String _friendlyGalleryError(Object error) {
  if (error is ApiException) {
    if (error.code == 'migration_required') {
      return 'Galeri altyapısı henüz hazırlanıyor. Lütfen daha sonra tekrar deneyin.';
    }
    if (error.isUnauthorized) {
      return 'Oturum süreniz dolmuş. Lütfen tekrar giriş yapın.';
    }
    if (error.code == 'service_not_ready') {
      return 'Galeri servisi sunucuda hazır değil.';
    }
    if (error.code == 'invalid_json') {
      return 'Sunucu galeri isteğine geçersiz yanıt döndürdü.';
    }
    if (error.message.trim().isNotEmpty) return error.message;
  }
  if (error is FormatException) {
    return 'Sunucu geçersiz yanıt döndürdü. Lütfen tekrar deneyin.';
  }
  return 'Galeri yüklenemedi. Lütfen tekrar deneyin.';
}

BusinessServiceItem? _findService(int? id, List<BusinessServiceItem> services) {
  if (id == null) return null;
  for (final item in services) {
    if (item.id == id) return item;
  }
  return null;
}

BusinessStaffItem? _findStaff(int? id, List<BusinessStaffItem> staff) {
  if (id == null) return null;
  for (final item in staff) {
    if (item.id == id) return item;
  }
  return null;
}

Future<_SelectionResult<BusinessServiceItem>?> _showServicePicker(
  BuildContext context, {
  required List<BusinessServiceItem> services,
  required int? selectedId,
}) {
  return showModalBottomSheet<_SelectionResult<BusinessServiceItem>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _SelectionSheet<BusinessServiceItem>(
      title: 'Hizmete bağla',
      description:
          'Bu fotoğrafı ilgili hizmet sayfasında da göstermek için bir hizmet seç.',
      emptyTitle: 'Henüz hizmet eklenmemiş',
      emptyText: 'Fotoğrafları hizmetlere bağlamak için önce hizmet oluştur.',
      emptyIcon: Icons.spa_outlined,
      emptyActionLabel: 'Hizmet ekle',
      onEmptyAction: () {
        final navigator = Navigator.of(context);
        navigator.pop();
        navigator.push(
          MaterialPageRoute(builder: (_) => const BusinessServicesScreen()),
        );
      },
      items: services,
      selectedId: selectedId,
      idOf: (item) => item.id,
      itemBuilder: (context, item, selected, onTap) =>
          _ServiceSelectionCard(item: item, selected: selected, onTap: onTap),
    ),
  );
}

Future<_SelectionResult<BusinessStaffItem>?> _showStaffPicker(
  BuildContext context, {
  required List<BusinessStaffItem> staff,
  required int? selectedId,
}) {
  return showModalBottomSheet<_SelectionResult<BusinessStaffItem>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _SelectionSheet<BusinessStaffItem>(
      title: 'Personele bağla',
      description:
          'Bu fotoğrafı ekibindeki doğru kişiyle ilişkilendir. Seçim opsiyoneldir.',
      emptyTitle: 'Henüz personel eklenmemiş',
      emptyText:
          'Fotoğrafları bir personele bağlamak için önce işletme panelinden personel ekleyebilirsin.',
      emptyIcon: Icons.groups_2_outlined,
      emptyActionLabel: 'Personel ekle',
      onEmptyAction: () {
        final navigator = Navigator.of(context);
        navigator.pop();
        navigator.push(
          MaterialPageRoute(builder: (_) => const BusinessStaffScreen()),
        );
      },
      items: staff,
      selectedId: selectedId,
      idOf: (item) => item.id,
      itemBuilder: (context, item, selected, onTap) =>
          _StaffSelectionCard(item: item, selected: selected, onTap: onTap),
    ),
  );
}

class _GalleryMenuSheet extends StatelessWidget {
  const _GalleryMenuSheet({required this.hasCover});

  final bool hasCover;

  @override
  Widget build(BuildContext context) {
    return _SimpleActionSheet(
      title: 'Galeri seçenekleri',
      children: [
        _SimpleActionTile(
          icon: Icons.refresh_rounded,
          title: 'Galeriyi yenile',
          onTap: () => Navigator.of(context).pop('refresh'),
        ),
        _SimpleActionTile(
          icon: Icons.workspace_premium_outlined,
          title: hasCover ? 'Kapak görselini değiştir' : 'Kapak görseli ekle',
          onTap: () => Navigator.of(context).pop('cover'),
        ),
        _SimpleActionTile(
          icon: Icons.sort_rounded,
          title: 'Fotoğrafları sırala',
          onTap: () => Navigator.of(context).pop('sort'),
        ),
        _SimpleActionTile(
          icon: Icons.info_outline_rounded,
          title: 'Galeri bilgisi',
          onTap: () => Navigator.of(context).pop('info'),
        ),
      ],
    );
  }
}

class _GallerySortSheet extends StatelessWidget {
  const _GallerySortSheet({required this.selected});

  final String selected;

  @override
  Widget build(BuildContext context) {
    const options = [
      ('newest', Icons.schedule_rounded, 'En yeni'),
      ('oldest', Icons.history_rounded, 'En eski'),
      ('cover', Icons.workspace_premium_outlined, 'Kapak önce'),
      ('category', Icons.category_outlined, 'Kategoriye göre'),
    ];
    return _SimpleActionSheet(
      title: 'Sıralama',
      children: [
        for (final option in options)
          _SimpleActionTile(
            icon: option.$2,
            title: option.$3,
            trailing: selected == option.$1
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF8C6F38),
                  )
                : null,
            onTap: () => Navigator.of(context).pop(option.$1),
          ),
      ],
    );
  }
}

class _SimpleActionSheet extends StatelessWidget {
  const _SimpleActionSheet({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          20 + MediaQuery.of(context).padding.bottom,
        ),
        decoration: const BoxDecoration(
          color: WebeyColors.ivory,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
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
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 20,
                fontFamily: 'Georgia',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SimpleActionTile extends StatelessWidget {
  const _SimpleActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: WebeyColors.softWhite,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE7DCCB)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF8C6F38)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: WebeyColors.mutedTaupe,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryHeader extends StatelessWidget {
  const _GalleryHeader({required this.onBack, required this.onMenu});

  final VoidCallback onBack;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Column(
        children: [
          Row(
            children: [
              _RoundIconButton(icon: Icons.chevron_left_rounded, onTap: onBack),
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      'SALON · GALERİ',
                      style: TextStyle(
                        color: Color(0xFF8C6F38),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.45,
                      ),
                    ),
                    const SizedBox(height: 3),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 19,
                          fontFamily: 'Georgia',
                          fontWeight: FontWeight.w500,
                          height: 1,
                        ),
                        children: [
                          TextSpan(text: 'Fotoğraf '),
                          TextSpan(
                            text: 'Galerisi',
                            style: TextStyle(
                              color: Color(0xFF8C6F38),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _RoundIconButton(icon: Icons.more_horiz_rounded, onTap: onMenu),
            ],
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              "Salonunu ve çalışmalarını Webey Beauty'de sergile.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverSummaryCard extends StatelessWidget {
  const _CoverSummaryCard({
    required this.used,
    required this.limit,
    required this.coverItem,
    required this.onChangeCover,
  });

  final int used;
  final int limit;
  final BusinessGalleryItem? coverItem;
  final VoidCallback onChangeCover;

  @override
  Widget build(BuildContext context) {
    final ratio = limit == 0 ? 0.0 : used / limit;
    final hasCover = coverItem != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE7DCCB)),
          boxShadow: WebeyShadow.subtle,
        ),
        child: Column(
          children: [
            Row(
              children: [
                _CoverThumbnail(
                  hasCover: hasCover,
                  imageUrl: coverItem?.bestThumbUrl ?? '',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'KAPAK GÖRSELİ',
                        style: TextStyle(
                          color: Color(0xFF8C6F38),
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasCover
                            ? (coverItem?.title?.trim().isNotEmpty == true
                                  ? coverItem!.title!.trim()
                                  : 'Kapak görseli')
                            : 'Kapak görseli eksik',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasCover
                              ? WebeyColors.darkEspresso
                              : const Color(0xFFB3541E),
                          fontSize: 17,
                          fontFamily: 'Georgia',
                          fontWeight: FontWeight.w500,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _CoverStatus(hasCover: hasCover),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _CoverAction(onTap: onChangeCover, hasCover: hasCover),
              ],
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0x1A1C1209))),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    const Text(
                      'FOTO KOTASI',
                      style: TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: ratio.clamp(0, 1),
                          minHeight: 4,
                          backgroundColor: const Color(0xFFEADFCF),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            WebeyColors.primaryGold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontSize: 13,
                          fontFamily: 'Georgia',
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          TextSpan(text: '$used'),
                          const TextSpan(
                            text: '/',
                            style: TextStyle(
                              color: Color(0xFF8C6F38),
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          TextSpan(text: '$limit'),
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
    );
  }
}

class _CoverThumbnail extends StatelessWidget {
  const _CoverThumbnail({required this.hasCover, required this.imageUrl});

  final bool hasCover;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7DCCB)),
        gradient: hasCover
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF3A2716),
                  WebeyColors.darkEspresso,
                  WebeyColors.primaryGold,
                ],
              )
            : null,
        color: hasCover ? null : const Color(0xFFEFE5D2),
      ),
      child: Stack(
        children: [
          if (imageUrl.isNotEmpty)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (hasCover)
            Positioned(
              left: 5,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFD4B574),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Kapak',
                  style: TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          else
            const Center(
              child: Icon(
                Icons.add_photo_alternate_outlined,
                color: Color(0xFF8C6F38),
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverStatus extends StatelessWidget {
  const _CoverStatus({required this.hasCover});

  final bool hasCover;

  @override
  Widget build(BuildContext context) {
    // Kapak yokken "Aktif kapak · Webey'de görünür" gibi yanlış mesaj
    // gösterilmez; net uyarı verilir.
    final color = hasCover ? const Color(0xFF1F8A5B) : const Color(0xFFB3541E);
    final text = hasCover
        ? "Aktif kapak · Webey'de görünür"
        : 'Salon detay sayfanızın iyi görünmesi için kapak görseli ekleyin.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(
            hasCover ? Icons.circle : Icons.error_outline_rounded,
            color: color,
            size: hasCover ? 7 : 12,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color, fontSize: 11, height: 1.3),
          ),
        ),
      ],
    );
  }
}

class _CoverAction extends StatelessWidget {
  const _CoverAction({required this.onTap, required this.hasCover});

  final VoidCallback onTap;
  final bool hasCover;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: WebeyColors.primaryGold.withAlpha(hasCover ? 28 : 60),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WebeyColors.primaryGold.withAlpha(76)),
        ),
        child: Text(
          hasCover ? 'Değiştir' : 'Kapak Ekle',
          style: const TextStyle(
            color: Color(0xFF8C6F38),
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: .45,
          ),
        ),
      ),
    );
  }
}

class _CategoryStrip extends StatelessWidget {
  const _CategoryStrip({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  final List<_GalleryCategory> categories;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final item = categories[index];
          final isSelected = selected == item.key;
          return GestureDetector(
            onTap: () => onChanged(item.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? WebeyColors.primaryGold
                    : const Color(0xFFFBF8F2),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected
                      ? WebeyColors.primaryGold
                      : const Color(0xFFE7DCCB),
                ),
                boxShadow: isSelected ? WebeyShadow.subtle : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.label,
                    style: TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 11.5,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${item.count}',
                    style: TextStyle(
                      color: WebeyColors.darkEspresso.withAlpha(
                        isSelected ? 165 : 105,
                      ),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .4,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo, required this.onTap});

  final BusinessGalleryItem photo;
  final ValueChanged<BusinessGalleryItem> onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(photo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE7DCCB)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _photoPalette(photo.category),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (photo.bestThumbUrl.isNotEmpty)
                Image.network(
                  photo.bestThumbUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-.55, -.65),
                    radius: 1.2,
                    colors: [Colors.white.withAlpha(44), Colors.transparent],
                  ),
                ),
              ),
              Positioned(
                top: 6,
                left: 6,
                child: _PhotoBadge(
                  label: photo.categoryLabel,
                  isCover: photo.isCover,
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: WebeyColors.darkEspresso.withAlpha(140),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.more_vert_rounded,
                    color: Color(0xFFF4ECDC),
                    size: 13,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 20, 8, 7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        WebeyColors.darkEspresso.withAlpha(205),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    photo.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFF4ECDC),
                      fontSize: 12,
                      fontFamily: 'Georgia',
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500,
                    ),
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

List<Color> _photoPalette(String category) {
  switch (category) {
    case 'cover':
    case 'interior':
      return const [
        Color(0xFF3A2716),
        WebeyColors.darkEspresso,
        WebeyColors.primaryGold,
      ];
    case 'hair_work':
    case 'hair_color':
      return const [
        Color(0xFFE8C988),
        WebeyColors.primaryGold,
        Color(0xFF3A2412),
      ];
    case 'nail_work':
    case 'makeup':
      return const [Color(0xFFD4C2B0), Color(0xFF8C7350), Color(0xFF3A2412)];
    default:
      return const [
        Color(0xFF5D4A2C),
        Color(0xFF2C1B0F),
        WebeyColors.darkEspresso,
      ];
  }
}

class _PhotoBadge extends StatelessWidget {
  const _PhotoBadge({required this.label, required this.isCover});

  final String label;
  final bool isCover;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isCover
            ? WebeyColors.primaryGold
            : WebeyColors.darkEspresso.withAlpha(140),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCover) ...[
            const Icon(
              Icons.star_rounded,
              size: 9,
              color: WebeyColors.darkEspresso,
            ),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: isCover
                  ? WebeyColors.darkEspresso
                  : const Color(0xFFF4ECDC),
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .45,
            ),
          ),
        ],
      ),
    );
  }
}

class _BeforeAfterGroup {
  const _BeforeAfterGroup({required this.before, required this.after});

  final BusinessGalleryItem before;
  final BusinessGalleryItem after;
}

class _BeforeAfterPair extends StatelessWidget {
  const _BeforeAfterPair({required this.group, required this.onTap});

  final _BeforeAfterGroup group;
  final ValueChanged<BusinessGalleryItem> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _BeforeAfterPane(
                  item: group.before,
                  label: 'Önce',
                  onTap: () => onTap(group.before),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BeforeAfterPane(
                  item: group.after,
                  label: 'Sonra',
                  onTap: () => onTap(group.after),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 11,
                    ),
                    children: [
                      TextSpan(
                        text: group.after.displayTitle,
                        style: const TextStyle(
                          color: WebeyColors.darkEspresso,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(text: ' · Öncesi-Sonrası'),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BeforeAfterPane extends StatelessWidget {
  const _BeforeAfterPane({
    required this.item,
    required this.label,
    required this.onTap,
  });

  final BusinessGalleryItem item;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.bestThumbUrl;
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: WebeyColors.softWhite,
              border: Border.all(color: const Color(0xFFE7DCCB)),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isNotEmpty)
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _ImageFallback(),
                  )
                else
                  const _ImageFallback(),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black54],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: _PhotoBadge(label: label, isCover: label == 'Sonra'),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 9,
                  child: Text(
                    item.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: const Color(0xFFF4ECDC).withAlpha(220),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD4C2B0), Color(0xFF8C7350), Color(0xFF3A2412)],
        ),
      ),
      child: Center(
        child: Icon(Icons.image_outlined, color: Color(0xFFF4ECDC), size: 24),
      ),
    );
  }
}

class _GalleryEmptyState extends StatelessWidget {
  const _GalleryEmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE7DCCB)),
          boxShadow: WebeyShadow.subtle,
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE7DCCB)),
              ),
              child: const Icon(
                Icons.photo_camera_outlined,
                color: Color(0xFF8C6F38),
                size: 30,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'GALERİ BOŞ',
              style: TextStyle(
                color: Color(0xFF8C6F38),
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text.rich(
              TextSpan(
                style: TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 24,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
                children: [
                  TextSpan(text: 'Henüz fotoğraf '),
                  TextSpan(
                    text: 'yok',
                    style: TextStyle(
                      color: Color(0xFF8C6F38),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Salonunu, çalışmalarını ve ekibini gösteren fotoğrafları yükle.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WebeyColors.mutedTaupe,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            _GoldCtaButton(
              icon: Icons.add_rounded,
              label: 'Fotoğraf Ekle',
              onTap: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryErrorState extends StatelessWidget {
  const _GalleryErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: WebeyColors.errorRed.withAlpha(70)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: WebeyColors.errorRed),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ),
      ),
    );
  }
}

class _GalleryActionBar extends StatelessWidget {
  const _GalleryActionBar({required this.onAdd, required this.onMultiSelect});

  final VoidCallback onAdd;
  final VoidCallback onMultiSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        14,
        22,
        14 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: WebeyColors.ivory.withAlpha(245),
        border: Border(
          top: BorderSide(color: WebeyColors.darkEspresso.withAlpha(22)),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onMultiSelect,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: WebeyColors.softWhite,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: WebeyColors.darkEspresso.withAlpha(26),
                ),
                boxShadow: WebeyShadow.subtle,
              ),
              child: const Icon(
                Icons.photo_library_outlined,
                color: WebeyColors.darkEspresso,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _GoldCtaButton(
              icon: Icons.add_rounded,
              label: 'Fotoğraf Ekle',
              onTap: onAdd,
              height: 48,
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryAddSheet extends StatefulWidget {
  const _GalleryAddSheet({
    required this.repository,
    required this.businessRepository,
  });

  final BusinessGalleryRepository repository;
  final BusinessRepository businessRepository;

  @override
  State<_GalleryAddSheet> createState() => _GalleryAddSheetState();
}

class _GalleryAddSheetState extends State<_GalleryAddSheet> {
  final _picker = ImagePicker();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  var _source = 'gallery';
  var _category = 'interior';
  var _pairRole = 'before';
  var _makeCover = false;
  var _saving = false;
  var _uploadProgress = 0;
  var _linksLoading = true;
  String? _selectedFileName;
  List<String> _selectedPaths = const [];
  List<BusinessServiceItem> _services = const [];
  List<BusinessStaffItem> _staff = const [];
  BusinessServiceItem? _selectedService;
  BusinessStaffItem? _selectedStaff;
  String? _error;

  static const _sources = [
    (key: 'camera', icon: Icons.photo_camera_outlined, label: 'Kameradan çek'),
    (
      key: 'gallery',
      icon: Icons.photo_library_outlined,
      label: 'Galeriden seç',
    ),
    (key: 'multi', icon: Icons.collections_outlined, label: 'Çoklu seç'),
  ];

  static const _sheetCategories = [
    (key: 'interior', label: 'İç Mekan'),
    (key: 'exterior', label: 'Dış Mekan'),
    (key: 'hair_work', label: 'Saç Çalışmaları'),
    (key: 'hair_color', label: 'Saç Renk'),
    (key: 'nail_work', label: 'Tırnak'),
    (key: 'makeup', label: 'Makyaj'),
    (key: 'before_after', label: 'Öncesi-Sonrası'),
    (key: 'team', label: 'Ekip'),
    (key: 'campaign', label: 'Kampanya'),
  ];

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadLinks() async {
    try {
      final services = await widget.businessRepository.getServices();
      final staff = await widget.businessRepository.getStaff();
      if (!mounted) return;
      setState(() {
        _services = services.where((item) => item.isActive).toList();
        _staff = staff.where((item) => item.isActive).toList();
        _linksLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _linksLoading = false;
        _error = _friendlyGalleryError(error);
      });
    }
  }

  Future<void> _pick(String source) async {
    try {
      if (source == 'multi') {
        final files = await _picker.pickMultiImage(imageQuality: 92);
        if (files.isEmpty) return;
        setState(() {
          _source = source;
          _selectedPaths = files.map((file) => file.path).toList();
          _selectedFileName = '${files.length} fotoğraf seçildi';
          _error = null;
        });
        return;
      }

      final file = await _picker.pickImage(
        source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 92,
      );
      if (file == null) return;
      setState(() {
        _source = source;
        _selectedPaths = [file.path];
        _selectedFileName = file.name;
        _error = null;
      });
    } catch (error) {
      setState(() => _error = _friendlyGalleryError(error));
    }
  }

  Future<void> _save() async {
    if (_selectedPaths.isEmpty) {
      setState(() => _error = 'Lütfen yüklenecek bir fotoğraf seçin.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _uploadProgress = 0;
    });
    var uploaded = 0;
    var failed = 0;
    String? lastError;
    final total = _selectedPaths.length;
    final pairGroupId = _category == 'before_after' ? _newPairGroupId() : null;
    for (var i = 0; i < _selectedPaths.length; i += 1) {
      try {
        await widget.repository.uploadGalleryPhoto(
          filePath: _selectedPaths[i],
          category: _category,
          title: _titleController.text,
          description: _descriptionController.text,
          serviceId: _selectedService?.id,
          staffId: _selectedStaff?.id,
          pairGroupId: pairGroupId,
          pairRole: _pairRoleForIndex(i),
          isCover: _makeCover && i == 0,
        );
        uploaded += 1;
      } catch (error) {
        failed += 1;
        lastError = _friendlyGalleryError(error);
      }
      // Gerçek ilerleme: tamamlanan dosya / toplam. Son dosyada 100.
      if (mounted) {
        setState(() => _uploadProgress = ((i + 1) / total * 100).round());
      }
    }
    try {
      if (!mounted) return;
      if (uploaded > 0) {
        final message = failed == 0
            ? '$uploaded fotoğraf yüklendi.'
            : '$uploaded fotoğraf yüklendi, $failed fotoğraf yüklenemedi.';
        Navigator.of(context).pop(message);
      } else {
        setState(() => _error = lastError ?? 'Fotoğraf yüklenemedi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _newPairGroupId() {
    return 'mobile_${DateTime.now().microsecondsSinceEpoch}';
  }

  String? _pairRoleForIndex(int index) {
    if (_category != 'before_after') return null;
    if (_selectedPaths.length == 2) return index == 0 ? 'before' : 'after';
    return _pairRole;
  }

  Future<void> _pickService() async {
    final result = await _showServicePicker(
      context,
      services: _services,
      selectedId: _selectedService?.id,
    );
    if (!mounted || result == null) return;
    setState(() => _selectedService = result.clear ? null : result.item);
  }

  Future<void> _pickStaff() async {
    final result = await _showStaffPicker(
      context,
      staff: _staff,
      selectedId: _selectedStaff?.id,
    );
    if (!mounted || result == null) return;
    setState(() => _selectedStaff = result.clear ? null : result.item);
  }

  @override
  Widget build(BuildContext context) {
    return _GallerySheetFrame(
      titleFirst: 'Fotoğraf',
      titleEmphasis: 'Ekle',
      subtitle: 'Salon görselini yükle, kategori ve detayları seç.',
      footerNote: 'Görseller güvenli saklanır · 120 fotoğraf limiti',
      primaryLabel: _saving ? 'Yükleniyor...' : 'Kaydet',
      secondaryLabel: 'Vazgeç',
      onPrimary: _saving || _selectedPaths.isEmpty ? null : _save,
      children: [
        if (_error != null) _SheetError(message: _error!),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: .92,
          children: [
            for (final source in _sources)
              _SourceCard(
                icon: source.icon,
                label: source.label,
                selected: _source == source.key,
                onTap: () => _pick(source.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_selectedFileName != null)
          _UploadProgressCard(
            fileName: _selectedFileName!,
            isSaving: _saving,
            count: _selectedPaths.length,
            progress: _uploadProgress,
          ),
        const _FieldLabel('Kategori'),
        Wrap(
          spacing: 6,
          runSpacing: 7,
          children: [
            for (final category in _sheetCategories)
              _MiniChip(
                label: category.label,
                selected: _category == category.key,
                onTap: () => setState(() => _category = category.key),
              ),
          ],
        ),
        if (_category == 'before_after') ...[
          const _FieldLabel('Öncesi-Sonrası'),
          _SegmentedChoice(
            value: _pairRole,
            options: const [('before', 'Önce'), ('after', 'Sonra')],
            onChanged: (value) => setState(() => _pairRole = value),
          ),
          const SizedBox(height: 8),
          const Text(
            'İki fotoğraf seçersen ilk fotoğraf Önce, ikinci fotoğraf Sonra olarak eşleşir. Tek fotoğrafta rolü sen seçebilirsin.',
            style: TextStyle(
              color: WebeyColors.mutedTaupe,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
        const _FieldLabel('Detaylar'),
        _SheetTextField(
          controller: _titleController,
          hintText: 'Örn. Karamel balyaj',
        ),
        const SizedBox(height: 8),
        _SheetTextField(
          controller: _descriptionController,
          hintText: 'Kısa açıklama',
          maxLines: 3,
        ),
        const _FieldLabel('Bağlantılar'),
        _PickerRow(
          icon: Icons.content_cut_rounded,
          title: _selectedService?.name ?? 'Hizmet seçilmedi',
          subtitle: _linksLoading
              ? 'Hizmetler yükleniyor'
              : _services.isEmpty
              ? 'Henüz hizmet eklenmemiş'
              : 'Fotoğrafı hizmetle ilişkilendir',
          onTap: _pickService,
        ),
        const SizedBox(height: 8),
        _PickerRow(
          avatar: 'LD',
          title: _selectedStaff?.name ?? 'Personel seçilmedi',
          subtitle: _linksLoading
              ? 'Personel yükleniyor'
              : _staff.isEmpty
              ? 'Henüz personel eklenmemiş'
              : 'Fotoğrafı personele bağla',
          onTap: _pickStaff,
        ),
        const _FieldLabel('Vitrin'),
        _SheetSwitchRow(
          title: 'Kapak yap',
          subtitle: 'Bu fotoğraf Webey vitrinde en üstte görünür.',
          value: _makeCover,
          onChanged: (value) => setState(() => _makeCover = value),
        ),
      ],
    );
  }
}

class _GalleryEditSheet extends StatefulWidget {
  const _GalleryEditSheet({
    required this.item,
    required this.repository,
    required this.businessRepository,
  });

  final BusinessGalleryItem item;
  final BusinessGalleryRepository repository;
  final BusinessRepository businessRepository;

  @override
  State<_GalleryEditSheet> createState() => _GalleryEditSheetState();
}

class _GalleryEditSheetState extends State<_GalleryEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late String _category;
  late bool _hidden;
  late bool _makeCover;
  var _saving = false;
  var _linksLoading = true;
  List<BusinessServiceItem> _services = const [];
  List<BusinessStaffItem> _staff = const [];
  BusinessServiceItem? _selectedService;
  BusinessStaffItem? _selectedStaff;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
    _descriptionController = TextEditingController(
      text: widget.item.description,
    );
    _category = widget.item.category;
    _hidden = !widget.item.isVisible || widget.item.status == 'hidden';
    _makeCover = widget.item.isCover;
    _loadLinks();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadLinks() async {
    try {
      final services = await widget.businessRepository.getServices();
      final staff = await widget.businessRepository.getStaff();
      if (!mounted) return;
      setState(() {
        _services = services.where((item) => item.isActive).toList();
        _staff = staff.where((item) => item.isActive).toList();
        _selectedService = _findService(widget.item.serviceId, _services);
        _selectedStaff = _findStaff(widget.item.staffId, _staff);
        _linksLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _linksLoading = false;
        _error = _friendlyGalleryError(error);
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.updateGalleryPhoto(
        id: widget.item.id,
        title: _titleController.text,
        description: _descriptionController.text,
        category: _category,
        serviceId: _selectedService?.id,
        staffId: _selectedStaff?.id,
        updateService: true,
        updateStaff: true,
        isVisible: !_hidden,
        status: _hidden ? 'hidden' : 'active',
      );
      if (_makeCover && !widget.item.isCover) {
        await widget.repository.setCover(widget.item.id);
      }
      if (!mounted) return;
      Navigator.of(context).pop('Fotoğraf güncellendi.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyGalleryError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setCoverNow() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.setCover(widget.item.id);
      if (!mounted) return;
      Navigator.of(context).pop('Kapak fotoğrafı güncellendi.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyGalleryError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fotoğraf silinsin mi?'),
        content: const Text(
          'Fotoğraf vitrinden kaldırılacak. Dosya fiziksel olarak silinmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.deleteGalleryPhoto(widget.item.id);
      if (!mounted) return;
      Navigator.of(context).pop('Fotoğraf silindi.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyGalleryError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickService() async {
    final result = await _showServicePicker(
      context,
      services: _services,
      selectedId: _selectedService?.id,
    );
    if (!mounted || result == null) return;
    setState(() => _selectedService = result.clear ? null : result.item);
  }

  Future<void> _pickStaff() async {
    final result = await _showStaffPicker(
      context,
      staff: _staff,
      selectedId: _selectedStaff?.id,
    );
    if (!mounted || result == null) return;
    setState(() => _selectedStaff = result.clear ? null : result.item);
  }

  @override
  Widget build(BuildContext context) {
    return _GallerySheetFrame(
      titleFirst: 'Fotoğrafi',
      titleEmphasis: 'Düzenle',
      subtitle: 'Detayları güncelle veya kapağa al.',
      footerNote: 'Değişiklikler Webey vitrinde güncellenecek.',
      primaryLabel: _saving ? 'Kaydediliyor...' : 'Kaydet',
      secondaryLabel: 'Vazgeç',
      onPrimary: _saving ? null : _save,
      children: [
        if (_error != null) _SheetError(message: _error!),
        _EditPreview(item: widget.item),
        const _FieldLabel('Başlık'),
        _SheetTextField(controller: _titleController),
        const SizedBox(height: 8),
        _SheetTextField(
          controller: _descriptionController,
          hintText: 'Açıklama',
          maxLines: 3,
        ),
        const _FieldLabel('Kategori'),
        Wrap(
          spacing: 6,
          runSpacing: 7,
          children: [
            for (final category in _GalleryAddSheetState._sheetCategories)
              _MiniChip(
                label: category.label,
                selected: _category == category.key,
                onTap: () => setState(() => _category = category.key),
              ),
          ],
        ),
        const _FieldLabel('Eylemler'),
        _PickerRow(
          icon: Icons.content_cut_rounded,
          title: _selectedService?.name ?? 'Hizmet seçilmedi',
          subtitle: _linksLoading
              ? 'Hizmetler yükleniyor'
              : _services.isEmpty
              ? 'Henüz hizmet eklenmemiş'
              : 'Hizmet bağlantısını güncelle',
          onTap: _pickService,
        ),
        const SizedBox(height: 8),
        _PickerRow(
          avatar: 'WB',
          title: _selectedStaff?.name ?? 'Personel seçilmedi',
          subtitle: _linksLoading
              ? 'Personel yükleniyor'
              : _staff.isEmpty
              ? 'Henüz personel eklenmemiş'
              : 'Personel bağlantısını güncelle',
          onTap: _pickStaff,
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.55,
          children: [
            _EditActionTile(
              icon: Icons.workspace_premium_outlined,
              title: 'Kapak yap',
              subtitle: _makeCover ? 'Vitrinde aktif' : 'Vitrine al',
              highlighted: true,
              onTap: _saving ? () {} : _setCoverNow,
            ),
            _EditActionTile(
              icon: _hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              title: _hidden ? 'Gizli' : 'Görünür',
              subtitle: _hidden ? 'Sadece sen' : "Webey'de aktif",
              onTap: () => setState(() => _hidden = !_hidden),
            ),
            _EditActionTile(
              icon: Icons.person_outline_rounded,
              title: 'Bağlantı',
              subtitle: _selectedService != null || _selectedStaff != null
                  ? 'Seçimler kaydedilecek'
                  : 'Bağlı değil',
              onTap: _pickStaff,
            ),
            _EditActionTile(
              icon: Icons.delete_outline_rounded,
              title: 'Sil',
              subtitle: 'Vitrinden kaldır',
              danger: true,
              onTap: _saving ? () {} : _delete,
            ),
          ],
        ),
      ],
    );
  }
}

class _SelectionResult<T> {
  const _SelectionResult.item(this.item) : clear = false;
  const _SelectionResult.clear() : item = null, clear = true;

  final T? item;
  final bool clear;
}

class _SelectionSheet<T> extends StatelessWidget {
  const _SelectionSheet({
    required this.title,
    required this.description,
    required this.emptyTitle,
    required this.emptyText,
    required this.emptyIcon,
    required this.emptyActionLabel,
    required this.onEmptyAction,
    required this.items,
    required this.selectedId,
    required this.idOf,
    required this.itemBuilder,
  });

  final String title;
  final String description;
  final String emptyTitle;
  final String emptyText;
  final IconData emptyIcon;
  final String emptyActionLabel;
  final VoidCallback onEmptyAction;
  final List<T> items;
  final int? selectedId;
  final int? Function(T item) idOf;
  final Widget Function(
    BuildContext context,
    T item,
    bool selected,
    VoidCallback onTap,
  )
  itemBuilder;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * .72;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: WebeyColors.ivory,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: WebeyColors.darkEspresso.withAlpha(46),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: WebeyColors.darkEspresso,
                            fontSize: 20,
                            fontFamily: 'Georgia',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(_SelectionResult<T>.clear()),
                        child: const Text('Temizle'),
                      ),
                    ],
                  ),
                  Text(
                    description,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: items.isEmpty
                  ? _SelectionEmptyState(
                      icon: emptyIcon,
                      title: emptyTitle,
                      message: emptyText,
                      actionLabel: emptyActionLabel,
                      onAction: onEmptyAction,
                    )
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16 + MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final id = idOf(item);
                        final selected = id != null && id == selectedId;
                        return itemBuilder(
                          context,
                          item,
                          selected,
                          () => Navigator.of(
                            context,
                          ).pop(_SelectionResult<T>.item(item)),
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

class _SelectionEmptyState extends StatelessWidget {
  const _SelectionEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
          decoration: BoxDecoration(
            color: WebeyColors.softWhite,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE7DCCB)),
            boxShadow: WebeyShadow.subtle,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: WebeyColors.warmCream,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE7DCCB)),
                ),
                child: Icon(icon, color: const Color(0xFF8C6F38), size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 18,
                  fontFamily: 'Georgia',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WebeyColors.mutedTaupe,
                  fontSize: 12.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _GoldCtaButton(
                icon: Icons.add_rounded,
                label: actionLabel,
                onTap: onAction,
                height: 42,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceSelectionCard extends StatelessWidget {
  const _ServiceSelectionCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final BusinessServiceItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = _serviceCategoryLabel(item.category);
    return _PremiumSelectionCard(
      selected: selected,
      onTap: onTap,
      leading: Icons.spa_outlined,
      title: item.name.isEmpty ? 'Hizmet' : item.name,
      subtitle: category,
      meta: [
        '${item.durationMinutes} dk',
        '${item.price.toStringAsFixed(0)} TL',
        item.isActive ? 'Aktif' : 'Pasif',
      ],
    );
  }
}

class _StaffSelectionCard extends StatelessWidget {
  const _StaffSelectionCard({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final BusinessStaffItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PremiumSelectionCard(
      selected: selected,
      onTap: onTap,
      leading: Icons.person_outline_rounded,
      title: item.name.isEmpty ? 'Personel' : item.name,
      subtitle: item.role?.trim().isNotEmpty == true ? item.role! : 'Personel',
      meta: [
        item.isActive ? 'Aktif' : 'Pasif',
        if (item.serviceIds.isNotEmpty) '${item.serviceIds.length} hizmet',
      ],
    );
  }
}

class _PremiumSelectionCard extends StatelessWidget {
  const _PremiumSelectionCard({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.meta,
  });

  final bool selected;
  final VoidCallback onTap;
  final IconData leading;
  final String title;
  final String subtitle;
  final List<String> meta;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? WebeyColors.warmCream : WebeyColors.softWhite,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? WebeyColors.primaryGold
                  : const Color(0xFFE7DCCB),
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected ? WebeyShadow.subtle : null,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? WebeyColors.primaryGold.withAlpha(42)
                      : WebeyColors.warmCream,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE7DCCB)),
                ),
                child: Icon(leading, color: const Color(0xFF8C6F38), size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        for (final label in meta)
                          _TinyMetaChip(
                            label: label,
                            selected: selected && label == 'Aktif',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.chevron_right_rounded,
                color: selected
                    ? const Color(0xFF8C6F38)
                    : WebeyColors.mutedTaupe,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TinyMetaChip extends StatelessWidget {
  const _TinyMetaChip({required this.label, this.selected = false});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? WebeyColors.primaryGold : WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE7DCCB)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: WebeyColors.darkEspresso,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _serviceCategoryLabel(String? value) {
  return switch ((value ?? '').trim()) {
    'hair' => 'Saç',
    'nail' => 'Tırnak',
    'skin' => 'Cilt bakımı',
    'spa' => 'Bakım',
    'makeup' => 'Makyaj',
    '' => 'Kategori yok',
    final other => other,
  };
}

class _GallerySheetFrame extends StatelessWidget {
  const _GallerySheetFrame({
    required this.titleFirst,
    required this.titleEmphasis,
    required this.subtitle,
    required this.children,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.onPrimary,
    required this.footerNote,
  });

  final String titleFirst;
  final String titleEmphasis;
  final String subtitle;
  final List<Widget> children;
  final String primaryLabel;
  final String secondaryLabel;
  final VoidCallback? onPrimary;
  final String footerNote;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * .9;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: WebeyColors.ivory,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: WebeyColors.darkEspresso.withAlpha(46),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              color: WebeyColors.darkEspresso,
                              fontSize: 22,
                              fontFamily: 'Georgia',
                              fontWeight: FontWeight.w500,
                              height: 1,
                            ),
                            children: [
                              TextSpan(text: '$titleFirst '),
                              TextSpan(
                                text: titleEmphasis,
                                style: const TextStyle(
                                  color: Color(0xFF8C6F38),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: WebeyColors.mutedTaupe,
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _RoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                    size: 34,
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [...children, const SizedBox(height: 18)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(secondaryLabel),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: onPrimary,
                      child: Text(primaryLabel),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                22,
                10,
                22,
                12 + MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 12,
                    color: Color(0xFF8C6F38),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      footerNote,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 10.5,
                        height: 1.35,
                      ),
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

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? WebeyColors.warmCream : WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? WebeyColors.primaryGold : const Color(0xFFE7DCCB),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? WebeyColors.primaryGold.withAlpha(36)
                    : const Color(0xFFFBF8F2),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFFE7DCCB)),
              ),
              child: Icon(icon, color: const Color(0xFF8C6F38), size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WebeyColors.darkEspresso,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadProgressCard extends StatelessWidget {
  const _UploadProgressCard({
    required this.fileName,
    required this.isSaving,
    required this.count,
    this.progress = 0,
  });

  final String fileName;
  final bool isSaving;
  final int count;

  /// Gerçek upload ilerlemesi (0–100).
  final int progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: WebeyColors.warmCream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: WebeyColors.primaryGold.withAlpha(70)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFFE8C988),
                      WebeyColors.primaryGold,
                      Color(0xFF5D4A2C),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WebeyColors.darkEspresso,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count > 1 ? '$count dosya hazır' : 'Yükleme için hazır',
                      style: const TextStyle(
                        color: WebeyColors.mutedTaupe,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: Color(0xFF8C6F38),
                    fontSize: 18,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(text: '$progress'),
                    const TextSpan(
                      text: '%',
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (progress.clamp(0, 100)) / 100,
              minHeight: 4,
              backgroundColor: const Color(0x1A1C1209),
              valueColor: const AlwaysStoppedAnimation<Color>(
                WebeyColors.primaryGold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        children: [
          Container(width: 12, height: 1, color: WebeyColors.primaryGold),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF8C6F38),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetError extends StatelessWidget {
  const _SheetError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebeyColors.errorRed.withAlpha(18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WebeyColors.errorRed.withAlpha(80)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: WebeyColors.errorRed,
          fontSize: 12,
          height: 1.35,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? WebeyColors.primaryGold : const Color(0xFFFBF8F2),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? WebeyColors.primaryGold : const Color(0xFFE7DCCB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: WebeyColors.darkEspresso,
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  const _SheetTextField({
    required this.controller,
    this.hintText,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String? hintText;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(hintText: hintText),
    );
  }
}

class _SegmentedChoice extends StatelessWidget {
  const _SegmentedChoice({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7DCCB)),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(option.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: value == option.$1
                        ? WebeyColors.primaryGold
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    option.$2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
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

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
    this.avatar,
  });

  final IconData? icon;
  final String? avatar;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE7DCCB)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(avatar == null ? 8 : 999),
                gradient: const LinearGradient(
                  colors: [Color(0xFFD4B574), Color(0xFF8C6F38)],
                ),
              ),
              child: Center(
                child: avatar == null
                    ? Icon(icon, color: Colors.white, size: 15)
                    : Text(
                        avatar!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
            const Icon(
              Icons.chevron_right_rounded,
              color: WebeyColors.mutedTaupe,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetSwitchRow extends StatelessWidget {
  const _SheetSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7DCCB)),
      ),
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
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: WebeyColors.mutedTaupe,
                    fontSize: 10.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: WebeyColors.darkEspresso,
            activeTrackColor: WebeyColors.primaryGold,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _EditPreview extends StatelessWidget {
  const _EditPreview({required this.item});

  final BusinessGalleryItem item;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _photoPalette(item.category),
            ),
          ),
          child: Stack(
            children: [
              if (item.bestUrl.isNotEmpty)
                Positioned.fill(
                  child: Image.network(
                    item.bestUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(-.55, -.65),
                      radius: 1.1,
                      colors: [Colors.white.withAlpha(52), Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: WebeyColors.primaryGold,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.categoryLabel.toUpperCase(),
                    style: const TextStyle(
                      color: WebeyColors.darkEspresso,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: WebeyColors.darkEspresso.withAlpha(140),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    item.isCover
                        ? Icons.star_rounded
                        : Icons.auto_awesome_outlined,
                    color: const Color(0xFFF4ECDC),
                    size: 17,
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

class _EditActionTile extends StatelessWidget {
  const _EditActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlighted;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? WebeyColors.errorRed : WebeyColors.darkEspresso;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: highlighted ? WebeyColors.warmCream : WebeyColors.softWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: danger
                ? WebeyColors.errorRed.withAlpha(100)
                : highlighted
                ? WebeyColors.primaryGold.withAlpha(80)
                : const Color(0xFFE7DCCB),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: danger
                    ? WebeyColors.errorRed.withAlpha(24)
                    : WebeyColors.warmCream,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                icon,
                size: 16,
                color: danger ? WebeyColors.errorRed : const Color(0xFF8C6F38),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WebeyColors.mutedTaupe,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final String eyebrow;
  final String title;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 1,
                      color: WebeyColors.primaryGold,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        eyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8C6F38),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebeyColors.darkEspresso,
                    fontSize: 19,
                    fontFamily: 'Georgia',
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && actionIcon != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Row(
                children: [
                  Icon(actionIcon, size: 14, color: const Color(0xFF8C6F38)),
                  const SizedBox(width: 4),
                  Text(
                    actionLabel!,
                    style: const TextStyle(
                      color: Color(0xFF8C6F38),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
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

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.size = 38,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: WebeyColors.warmCream,
          shape: BoxShape.circle,
          border: Border.all(color: WebeyColors.darkEspresso.withAlpha(26)),
        ),
        child: Icon(icon, size: 20, color: WebeyColors.darkEspresso),
      ),
    );
  }
}

class _GoldCtaButton extends StatelessWidget {
  const _GoldCtaButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.height = 42,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: WebeyColors.primaryGold,
          borderRadius: BorderRadius.circular(14),
          boxShadow: WebeyShadow.subtle,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: WebeyColors.darkEspresso, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: WebeyColors.darkEspresso,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
