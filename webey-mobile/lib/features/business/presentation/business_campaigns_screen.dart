import 'package:flutter/material.dart';

import '../../../core/theme/webey_colors.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/widgets/webey_toast.dart';
import '../data/models/business_campaign.dart';
import '../data/models/business_service_item.dart';
import '../data/repositories/business_repository.dart';

/// İşletme → Kampanyalar yönetim ekranı.
/// Mevcut Hizmetler/Personeller liste düzenine uyumlu; ivory/altın/koyu kahve.
class BusinessCampaignsScreen extends StatefulWidget {
  const BusinessCampaignsScreen({super.key});

  @override
  State<BusinessCampaignsScreen> createState() =>
      _BusinessCampaignsScreenState();
}

class _BusinessCampaignsScreenState extends State<BusinessCampaignsScreen> {
  final _repo = BusinessRepository.instance;

  bool _loading = true;
  String? _error;
  List<BusinessCampaign> _items = const [];
  Map<String, int> _summary = const {};
  String _filter = 'published'; // published | upcoming | paused | expired

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
      final res = await _repo.getCampaigns();
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _summary = res.summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kampanyalar yüklenemedi.';
        _loading = false;
      });
    }
  }

  /// Müşteri görünürlük durumuna göre chip grubu.
  String _group(BusinessCampaign c) {
    switch (c.customerVisibilityStatus) {
      case 'visible_now':
      case 'waiting_for_condition':
        return 'published';
      case 'upcoming':
        return 'upcoming';
      case 'paused':
        return 'paused';
      default:
        return 'expired';
    }
  }

  List<BusinessCampaign> get _filtered =>
      _items.where((c) => _group(c) == _filter).toList();

  Future<void> _openForm([BusinessCampaign? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CampaignFormSheet(existing: existing),
    );
    if (saved == true) _load();
  }

  /// Kopyala: aynı koşullarla yeni kampanya formu (kaydetmeden oluşmaz).
  Future<void> _copy(BusinessCampaign c) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CampaignFormSheet(existing: c.toDuplicate(), isCopy: true),
    );
    if (saved == true) _load();
  }

  Future<void> _toggle(BusinessCampaign c) async {
    final next = !c.isActive;
    try {
      await _repo.setCampaignStatus(id: c.id!, active: next);
      if (!mounted) return;
      WebeyToast.success(
        context,
        next ? 'Kampanya yayında.' : 'Kampanya duraklatıldı.',
      );
      _load();
    } catch (_) {
      if (mounted) WebeyToast.error(context, 'Durum güncellenemedi.');
    }
  }

  Future<void> _delete(BusinessCampaign c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: WebeyColors.ivory,
        title: const Text('Kampanyayı sonlandır'),
        content: Text(
          'Bu kampanya sonlandırılacak. Mevcut randevular etkilenmez; '
          'geçmiş indirim kayıtları korunur.\n\n"${c.title}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: WebeyColors.errorRed),
            child: const Text('Sonlandır'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteCampaign(c.id!);
      if (!mounted) return;
      WebeyToast.success(context, 'Kampanya sonlandırıldı.');
      _load();
    } catch (_) {
      if (mounted) WebeyToast.error(context, 'Kampanya sonlandırılamadı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WebeyColors.ivory,
      appBar: AppBar(
        backgroundColor: WebeyColors.ivory,
        elevation: 0,
        foregroundColor: WebeyColors.darkEspresso,
        title: const Text(
          'Kampanyalar',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: WebeyColors.darkEspresso,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: WebeyColors.primaryGold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Kampanya Ekle'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: WebeyColors.primaryGold),
              )
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    color: WebeyColors.primaryGold,
                    onRefresh: _load,
                    child: _items.isEmpty
                        ? _EmptyState(onCreate: () => _openForm())
                        : _buildList(),
                  ),
      ),
    );
  }

  Widget _buildList() {
    final list = _filtered;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _summaryHeader(),
        const SizedBox(height: 12),
        _filterChips(),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 48),
            child: Center(
              child: Text(
                switch (_filter) {
                  'expired' => 'Süresi biten kampanya yok.',
                  'paused' => 'Duraklatılmış kampanya yok.',
                  'upcoming' => 'Yaklaşan kampanya yok.',
                  _ => 'Yayında kampanya yok.',
                },
                style: const TextStyle(color: WebeyColors.mutedTaupe),
              ),
            ),
          )
        else
          ...list.map(
            (c) => _CampaignCard(
              campaign: c,
              onEdit: () => _openForm(c),
              onCopy: () => _copy(c),
              onToggle: () => _toggle(c),
              onEnd: () => _delete(c),
            ),
          ),
      ],
    );
  }

  Widget _summaryHeader() {
    final eligible = _summary['now_eligible'] ?? 0;
    final upcoming = _summary['upcoming'] ?? 0;
    final bookings = _summary['campaign_booking_total'] ?? 0;
    Widget cell(String value, String label, Color color) => Expanded(
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: WebeyColors.mutedTaupe,
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(WebeyRadius.medium),
        border: Border.all(color: WebeyColors.borderSand),
        boxShadow: WebeyShadow.subtle,
      ),
      child: Column(
        children: [
          Row(
            children: [
              cell('$eligible', 'Şu an geçerli', WebeyColors.successGreen),
              Container(width: 1, height: 34, color: WebeyColors.borderSand),
              cell('$upcoming', 'Yaklaşan', WebeyColors.primaryGold),
              Container(width: 1, height: 34, color: WebeyColors.borderSand),
              cell('$bookings', 'Kampanyalı randevu',
                  WebeyColors.darkEspresso),
            ],
          ),
          if (bookings == 0) ...[
            const SizedBox(height: 10),
            const Text(
              'Henüz kampanyalı randevu oluşmadı.',
              style: TextStyle(fontSize: 12, color: WebeyColors.mutedTaupe),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChips() {
    final published = _summary['published'] ?? 0;
    final chips = [
      ('published', 'Yayında', published),
      ('upcoming', 'Yaklaşan', _summary['upcoming'] ?? 0),
      ('paused', 'Duraklatılmış', _summary['paused'] ?? 0),
      ('expired', 'Geçmiş', _summary['expired'] ?? 0),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${c.$2} (${c.$3})'),
                selected: _filter == c.$1,
                onSelected: (_) => setState(() => _filter = c.$1),
                selectedColor: WebeyColors.primaryGold,
                backgroundColor: WebeyColors.warmCream,
                labelStyle: TextStyle(
                  color: _filter == c.$1 ? Colors.white : WebeyColors.darkText,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(WebeyRadius.pill),
                  side: BorderSide(color: WebeyColors.borderSand),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  const _CampaignCard({
    required this.campaign,
    required this.onEdit,
    required this.onCopy,
    required this.onToggle,
    required this.onEnd,
  });

  final BusinessCampaign campaign;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onToggle;
  final VoidCallback onEnd;

  // Müşteri görünürlük durumuna göre rozet etiketi + renk.
  (String, Color, IconData) get _statusBadge =>
      switch (campaign.customerVisibilityStatus) {
        'visible_now' => (
            'Şu an geçerli',
            WebeyColors.successGreen,
            Icons.check_circle,
          ),
        'waiting_for_condition' => (
            'Koşul bekliyor',
            WebeyColors.primaryGold,
            Icons.schedule,
          ),
        'upcoming' => (
            'Yaklaşan',
            WebeyColors.deepChampagne,
            Icons.upcoming,
          ),
        'paused' => (
            'Duraklatıldı',
            WebeyColors.mutedTaupe,
            Icons.pause_circle_outline,
          ),
        _ => ('Sona erdi', WebeyColors.mutedTaupe, Icons.history),
      };

  bool get _isEnded => campaign.customerVisibilityStatus == 'ended';

  String _dateRange() {
    String fmt(String? d) {
      if (d == null || d.isEmpty) return '';
      final parts = d.split('-');
      if (parts.length == 3) return '${parts[2]}.${parts[1]}.${parts[0]}';
      return d;
    }

    final s = fmt(campaign.startDate);
    final e = fmt(campaign.endDate);
    if (s.isEmpty && e.isEmpty) return 'Süresiz';
    if (e.isEmpty) return '$s →';
    if (s.isEmpty) return '→ $e';
    return '$s – $e';
  }

  @override
  Widget build(BuildContext context) {
    final (badgeLabel, badgeColor, badgeIcon) = _statusBadge;
    final perf = campaign.performance;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WebeyColors.softWhite,
        borderRadius: BorderRadius.circular(WebeyRadius.medium),
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
                child: Text(
                  campaign.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: WebeyColors.darkEspresso,
                  ),
                ),
              ),
              // Gerçek müşteri görünürlük rozeti
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: WebeyColors.alpha(badgeColor, 0.13),
                  borderRadius: BorderRadius.circular(WebeyRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      badgeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: WebeyColors.goldLight,
                  borderRadius: BorderRadius.circular(WebeyRadius.pill),
                ),
                child: Text(
                  campaign.badge.isNotEmpty ? campaign.badge : 'Kampanya',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: WebeyColors.primaryGold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  campaign.scopeSummary.isNotEmpty
                      ? campaign.scopeSummary
                      : (campaign.appliesToAllServices
                          ? 'Tüm hizmetlerde'
                          : 'Seçili hizmetlerde'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: WebeyColors.darkText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.event_outlined,
                  size: 15, color: WebeyColors.mutedTaupe),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  campaign.validitySummary.isNotEmpty
                      ? '${_dateRange()} · ${campaign.validitySummary}'
                      : _dateRange(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: WebeyColors.mutedTaupe,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Müşteri görünürlük mesajı
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: WebeyColors.alpha(badgeColor, 0.07),
              borderRadius: BorderRadius.circular(WebeyRadius.small),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility_outlined, size: 14, color: badgeColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    campaign.customerVisibilityMessage.isNotEmpty
                        ? campaign.customerVisibilityMessage
                        : badgeLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: WebeyColors.darkText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Performans (varsa)
          if (perf != null && perf.hasData) ...[
            const SizedBox(height: 8),
            Text(
              '${perf.bookingCount} kampanyalı randevu · '
              '${perf.completedCount} tamamlandı · '
              'İndirim ${perf.totalDiscountAmount.toInt()} TL',
              style: const TextStyle(
                fontSize: 11.5,
                color: WebeyColors.primaryGold,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Divider(height: 22, color: WebeyColors.borderSand),
          Row(
            children: [
              Switch(
                value: campaign.isActive,
                onChanged: _isEnded ? null : (_) => onToggle(),
                activeThumbColor: WebeyColors.primaryGold,
              ),
              Text(
                campaign.isActive ? 'Yayında' : 'Duraklat',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: WebeyColors.darkText,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined,
                    size: 20, color: WebeyColors.primaryGold),
                tooltip: 'Düzenle',
              ),
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined,
                    size: 20, color: WebeyColors.mutedTaupe),
                tooltip: 'Kopyala',
              ),
              IconButton(
                onPressed: onEnd,
                icon: const Icon(Icons.stop_circle_outlined,
                    size: 20, color: WebeyColors.mutedTaupe),
                tooltip: 'Sonlandır',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.local_offer_outlined,
            size: 64, color: WebeyColors.deepChampagne),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Henüz kampanyan yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: WebeyColors.darkEspresso,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Hizmetlerini öne çıkarmak için ilk kampanyanı oluştur.',
            textAlign: TextAlign.center,
            style: TextStyle(color: WebeyColors.mutedTaupe),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Kampanya Ekle'),
            style: ElevatedButton.styleFrom(
              backgroundColor: WebeyColors.primaryGold,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WebeyRadius.pill),
              ),
            ),
          ),
        ),
      ],
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: WebeyColors.mutedTaupe)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Tekrar dene')),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
//  KAMPANYA EKLE / DÜZENLE FORMU (bottom sheet)
// ────────────────────────────────────────────────────────────────────────────
class _CampaignFormSheet extends StatefulWidget {
  const _CampaignFormSheet({this.existing, this.isCopy = false});
  final BusinessCampaign? existing;
  final bool isCopy;

  @override
  State<_CampaignFormSheet> createState() => _CampaignFormSheetState();
}

class _CampaignFormSheetState extends State<_CampaignFormSheet> {
  final _repo = BusinessRepository.instance;
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _valueCtrl = TextEditingController();

  String _conditionType = 'general'; // general | weekday | hourly
  String _discountKind = 'percent'; // percent | fixed
  String _scopeType = 'all_services'; // all_services | selected_services
  final Set<int> _serviceIds = {};
  final Set<int> _days = {1, 2, 3, 4, 5};
  DateTime? _startDate;
  DateTime? _endDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _active = true;

  List<BusinessServiceItem> _services = const [];
  bool _servicesLoading = false;
  bool _saving = false;

  bool get _isEdit => widget.existing?.id != null;

  /// Düzenlenen kampanyanın gerçek performansı (kopyalamada yok).
  CampaignPerformance? get _perf =>
      widget.isCopy ? null : widget.existing?.performance;

  @override
  void initState() {
    super.initState();
    _loadServices();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description ?? '';
      _valueCtrl.text = e.discountValue == e.discountValue.roundToDouble()
          ? e.discountValue.round().toString()
          : e.discountValue.toString();
      _conditionType = e.conditionType;
      _discountKind = e.discountKind;
      _scopeType = e.scopeType;
      _serviceIds.addAll(e.serviceIds);
      if (e.daysOfWeek.isNotEmpty) {
        _days
          ..clear()
          ..addAll(e.daysOfWeek);
      }
      _startDate = _parseDate(e.startDate);
      _endDate = _parseDate(e.endDate);
      _startTime = _parseTime(e.startTime);
      _endTime = _parseTime(e.endTime);
      _active = e.isActive;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadServices() async {
    setState(() => _servicesLoading = true);
    try {
      final items = await _repo.getServices();
      if (!mounted) return;
      setState(() {
        _services = items;
        _servicesLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _servicesLoading = false);
    }
  }

  static DateTime? _parseDate(String? d) {
    if (d == null || d.isEmpty) return null;
    return DateTime.tryParse(d);
  }

  static TimeOfDay? _parseTime(String? t) {
    if (t == null || t.isEmpty) return null;
    final p = t.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _previewBadge() {
    final v = double.tryParse(_valueCtrl.text.replaceAll(',', '.')) ?? 0;
    final money =
        v == v.roundToDouble() ? v.round().toString() : v.toString();
    final disc = _discountKind == 'fixed' ? '$money TL' : '%$money';
    if (_conditionType == 'weekday') return 'Hafta içi $disc';
    if (_conditionType == 'hourly' &&
        _startTime != null &&
        _endTime != null) {
      return '${_fmtTime(_startTime!)}–${_fmtTime(_endTime!)} $disc';
    }
    return _discountKind == 'fixed' ? '$money TL indirim' : '%$money indirim';
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String? _validate() {
    if (_titleCtrl.text.trim().isEmpty) return 'Kampanya adı zorunlu.';
    final v = double.tryParse(_valueCtrl.text.replaceAll(',', '.'));
    if (v == null || v <= 0) return 'Geçerli bir indirim değeri girin.';
    if (_discountKind == 'percent' && (v < 1 || v > 100)) {
      return 'Yüzde indirim 1–100 arasında olmalı.';
    }
    if (_scopeType == 'selected_services' && _serviceIds.isEmpty) {
      return 'En az bir hizmet seçin.';
    }
    if (_conditionType == 'weekday' && _days.isEmpty) {
      return 'En az bir gün seçin.';
    }
    if (_conditionType == 'hourly' &&
        (_startTime == null || _endTime == null)) {
      return 'Saat bazlı kampanyada başlangıç ve bitiş saati zorunlu.';
    }
    if (_startDate != null && _endDate != null && _endDate!.isBefore(_startDate!)) {
      return 'Bitiş tarihi başlangıçtan önce olamaz.';
    }
    if (_startTime != null &&
        _endTime != null &&
        (_endTime!.hour * 60 + _endTime!.minute) <=
            (_startTime!.hour * 60 + _startTime!.minute)) {
      return 'Bitiş saati başlangıçtan sonra olmalı.';
    }
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      WebeyToast.error(context, err);
      return;
    }
    setState(() => _saving = true);
    final v = double.parse(_valueCtrl.text.replaceAll(',', '.'));
    final campaign = BusinessCampaign(
      id: widget.existing?.id,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      conditionType: _conditionType,
      discountKind: _discountKind,
      discountValue: v,
      scopeType: _scopeType,
      serviceIds: _serviceIds.toList(),
      startDate: _startDate != null ? _fmtDate(_startDate!) : null,
      endDate: _endDate != null ? _fmtDate(_endDate!) : null,
      startTime: _startTime != null ? '${_fmtTime(_startTime!)}:00' : null,
      endTime: _endTime != null ? '${_fmtTime(_endTime!)}:00' : null,
      daysOfWeek: _conditionType == 'weekday'
          ? (_days.toList()..sort())
          : const [],
      status: _active ? 'active' : 'paused',
    );
    try {
      final res = await _repo.saveCampaign(campaign);
      if (!mounted) return;
      // Çakışma varsa bilgilendir (engel değil); yoksa standart başarı.
      if (res.conflictWarning != null) {
        WebeyToast.success(context, res.conflictWarning!);
      } else {
        WebeyToast.success(
          context,
          _isEdit
              ? 'Değişiklikler kaydedildi.'
              : (_active ? 'Kampanya yayınlandı.' : 'Taslak kaydedildi.'),
        );
      }
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      WebeyToast.error(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      WebeyToast.error(context, 'Kampanya kaydedilemedi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: WebeyColors.ivory,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: WebeyColors.borderSand,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    Text(
                      _isEdit ? 'Kampanyayı Düzenle' : 'Kampanya Ekle',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: WebeyColors.darkEspresso,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(20, 4, 20, viewInsets + 100),
                  children: [
                    if (_perf != null && _perf!.hasData) ...[
                      _performanceCard(_perf!),
                      const SizedBox(height: 16),
                    ],
                    _label('Kampanya adı'),
                    _textField(_titleCtrl, 'Örn. Hafta içi %15'),
                    const SizedBox(height: 16),
                    _label('Açıklama (opsiyonel)'),
                    _textField(_descCtrl, 'Kısa açıklama', maxLines: 2),
                    const SizedBox(height: 16),
                    _label('Kampanya biçimi'),
                    _segmented({
                      'general': 'Genel indirim',
                      'weekday': 'Hafta içi',
                      'hourly': 'Saat bazlı',
                    }, _conditionType, (v) {
                      setState(() {
                        _conditionType = v;
                        if (v == 'hourly') {
                          _startTime ??= const TimeOfDay(hour: 12, minute: 0);
                          _endTime ??= const TimeOfDay(hour: 17, minute: 0);
                        }
                      });
                    }),
                    const SizedBox(height: 16),
                    _label('İndirim türü'),
                    _segmented({
                      'percent': 'Yüzdelik (%)',
                      'fixed': 'Sabit (TL)',
                    }, _discountKind, (v) => setState(() => _discountKind = v)),
                    const SizedBox(height: 16),
                    _label(_discountKind == 'fixed'
                        ? 'İndirim tutarı (TL)'
                        : 'İndirim oranı (%)'),
                    _textField(
                      _valueCtrl,
                      _discountKind == 'fixed' ? 'Örn. 100' : 'Örn. 15',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    _helperText(
                      'İndirim yalnızca kampanyaya dahil hizmetlere uygulanır. '
                      'Kesin indirim, randevu günü ve saati doğrulandığında uygulanır.',
                    ),
                    const SizedBox(height: 16),
                    _label('Kapsam'),
                    _segmented({
                      'all_services': 'Tüm hizmetler',
                      'selected_services': 'Seçili hizmetler',
                    }, _scopeType, (v) => setState(() => _scopeType = v)),
                    if (_scopeType == 'selected_services') ...[
                      const SizedBox(height: 12),
                      _serviceSelector(),
                    ],
                    if (_conditionType == 'weekday') ...[
                      const SizedBox(height: 16),
                      _label('Geçerli günler'),
                      _daySelector(),
                    ],
                    const SizedBox(height: 16),
                    _label('Tarih aralığı (opsiyonel)'),
                    Row(
                      children: [
                        Expanded(
                          child: _dateButton(
                            _startDate,
                            'Başlangıç',
                            () => _pickDate(true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _dateButton(
                            _endDate,
                            'Bitiş',
                            () => _pickDate(false),
                          ),
                        ),
                      ],
                    ),
                    if (_conditionType == 'hourly' ||
                        _startTime != null ||
                        _endTime != null) ...[
                      const SizedBox(height: 16),
                      _label(_conditionType == 'hourly'
                          ? 'Saat aralığı (zorunlu)'
                          : 'Saat aralığı (opsiyonel)'),
                      Row(
                        children: [
                          Expanded(
                            child: _timeButton(
                              _startTime,
                              'Başlangıç',
                              () => _pickTime(true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _timeButton(
                              _endTime,
                              'Bitiş',
                              () => _pickTime(false),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: WebeyColors.softWhite,
                        borderRadius: BorderRadius.circular(WebeyRadius.medium),
                        border: Border.all(color: WebeyColors.borderSand),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Kampanya yayında',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: WebeyColors.darkText,
                          ),
                        ),
                        subtitle: const Text(
                          'Kapalı olduğunda müşteriler kampanyayı göremez.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: WebeyColors.mutedTaupe,
                          ),
                        ),
                        value: _active,
                        activeThumbColor: WebeyColors.primaryGold,
                        onChanged: (v) => setState(() => _active = v),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _previewCard(),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: WebeyColors.primaryGold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(WebeyRadius.medium),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(_isEdit
                              ? 'Değişiklikleri Kaydet'
                              : (_active
                                  ? 'Kampanyayı Yayınla'
                                  : 'Taslak Olarak Kaydet')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _helperText(String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 14, color: WebeyColors.mutedTaupe),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                color: WebeyColors.mutedTaupe,
                height: 1.35,
              ),
            ),
          ),
        ],
      );

  Widget _performanceCard(CampaignPerformance p) {
    Widget stat(String value, String label) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: WebeyColors.darkEspresso,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: WebeyColors.mutedTaupe,
              ),
            ),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.goldLight,
        borderRadius: BorderRadius.circular(WebeyRadius.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kampanya performansı',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: WebeyColors.primaryGold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              stat('${p.bookingCount}', 'Kampanyalı randevu'),
              stat('${p.completedCount}', 'Tamamlanan'),
              stat('${p.totalDiscountAmount.toInt()} TL', 'Toplam indirim'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Kampanya sonrası ciro: ${p.netRevenueAmount.toInt()} TL',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: WebeyColors.darkText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WebeyColors.goldLight,
        borderRadius: BorderRadius.circular(WebeyRadius.medium),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined,
              color: WebeyColors.primaryGold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Müşteride görünecek',
                  style: TextStyle(
                    fontSize: 11,
                    color: WebeyColors.mutedTaupe,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _previewBadge(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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

  Widget _serviceSelector() {
    if (_servicesLoading) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: WebeyColors.primaryGold),
          ),
        ),
      );
    }
    if (_services.isEmpty) {
      return const Text(
        'Önce hizmet eklemelisiniz.',
        style: TextStyle(color: WebeyColors.mutedTaupe),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _services.where((s) => s.id != null).map((s) {
        final selected = _serviceIds.contains(s.id);
        return FilterChip(
          label: Text(s.name),
          selected: selected,
          onSelected: (v) => setState(() {
            if (v) {
              _serviceIds.add(s.id!);
            } else {
              _serviceIds.remove(s.id);
            }
          }),
          selectedColor: WebeyColors.primaryGold,
          backgroundColor: WebeyColors.softWhite,
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(
            color: selected ? Colors.white : WebeyColors.darkText,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebeyRadius.pill),
            side: BorderSide(color: WebeyColors.borderSand),
          ),
        );
      }).toList(),
    );
  }

  Widget _daySelector() {
    const labels = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return Wrap(
      spacing: 8,
      children: List.generate(7, (i) {
        final iso = i + 1;
        final selected = _days.contains(iso);
        return FilterChip(
          label: Text(labels[i]),
          selected: selected,
          onSelected: (v) => setState(() {
            if (v) {
              _days.add(iso);
            } else {
              _days.remove(iso);
            }
          }),
          selectedColor: WebeyColors.primaryGold,
          backgroundColor: WebeyColors.softWhite,
          checkmarkColor: Colors.white,
          labelStyle: TextStyle(
            color: selected ? Colors.white : WebeyColors.darkText,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebeyRadius.pill),
            side: BorderSide(color: WebeyColors.borderSand),
          ),
        );
      }),
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final now = DateTime.now();
    final initial = (isStart ? _startDate : _endDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = (isStart ? _startTime : _endTime) ??
        const TimeOfDay(hour: 12, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: WebeyColors.darkText,
          ),
        ),
      );

  Widget _textField(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: WebeyColors.softWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebeyRadius.medium),
          borderSide: BorderSide(color: WebeyColors.borderSand),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebeyRadius.medium),
          borderSide: BorderSide(color: WebeyColors.borderSand),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(WebeyRadius.medium),
          borderSide: const BorderSide(color: WebeyColors.primaryGold),
        ),
      ),
    );
  }

  Widget _segmented(
    Map<String, String> options,
    String value,
    ValueChanged<String> onChanged,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((e) {
        final selected = value == e.key;
        return ChoiceChip(
          label: Text(e.value),
          selected: selected,
          onSelected: (_) => onChanged(e.key),
          selectedColor: WebeyColors.primaryGold,
          backgroundColor: WebeyColors.softWhite,
          labelStyle: TextStyle(
            color: selected ? Colors.white : WebeyColors.darkText,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WebeyRadius.pill),
            side: BorderSide(color: WebeyColors.borderSand),
          ),
        );
      }).toList(),
    );
  }

  Widget _dateButton(DateTime? value, String hint, VoidCallback onTap) {
    final text = value != null
        ? '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}'
        : hint;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_outlined, size: 16),
      label: Text(text, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: value != null
            ? WebeyColors.darkText
            : WebeyColors.mutedTaupe,
        side: BorderSide(color: WebeyColors.borderSand),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebeyRadius.medium),
        ),
      ),
    );
  }

  Widget _timeButton(TimeOfDay? value, String hint, VoidCallback onTap) {
    final text = value != null ? _fmtTime(value) : hint;
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.schedule, size: 16),
      label: Text(text, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: value != null
            ? WebeyColors.darkText
            : WebeyColors.mutedTaupe,
        side: BorderSide(color: WebeyColors.borderSand),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WebeyRadius.medium),
        ),
      ),
    );
  }
}
