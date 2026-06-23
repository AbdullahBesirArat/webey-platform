import '../../../../../core/config/api_config.dart';
import '../../../../../shared/services/api_client.dart';
import '../models/business_gallery_item.dart';
import '../models/business_gallery_summary.dart';

class BusinessGalleryRepository {
  const BusinessGalleryRepository({ApiClient? apiClient})
    : _apiClient = apiClient ?? const ApiClient();

  static const instance = BusinessGalleryRepository();

  final ApiClient _apiClient;

  Future<BusinessGallerySummary> getGallery({
    String? category,
    bool includeHidden = false,
  }) async {
    if (ApiConfig.useMockBusiness) return _mockSummary();
    final query = <String, String>{
      if (category != null && category.isNotEmpty) 'category': category,
      if (includeHidden) 'include_hidden': '1',
    };
    final path = Uri(
      path: '/business/gallery.php',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    final data = await _apiClient.getData(path);
    return BusinessGallerySummary.fromJson(data);
  }

  Future<BusinessGalleryItem> uploadGalleryPhoto({
    required String filePath,
    required String category,
    String? title,
    String? description,
    int? serviceId,
    int? staffId,
    String? pairGroupId,
    String? pairRole,
    bool isCover = false,
  }) async {
    final data = await _apiClient.multipartData(
      '/business/gallery-upload.php',
      fileField: 'file',
      filePath: filePath,
      fields: {
        'category': category,
        'is_cover': isCover ? '1' : '0',
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        if (serviceId != null) 'service_id': '$serviceId',
        if (staffId != null) 'staff_id': '$staffId',
        if (pairGroupId != null && pairGroupId.trim().isNotEmpty)
          'pair_group_id': pairGroupId.trim(),
        if (pairRole != null && pairRole.trim().isNotEmpty)
          'pair_role': pairRole.trim(),
      },
    );
    return _itemFromData(data);
  }

  Future<BusinessGalleryItem> updateGalleryPhoto({
    required String id,
    String? title,
    String? description,
    String? category,
    int? serviceId,
    int? staffId,
    bool updateService = false,
    bool updateStaff = false,
    bool? isVisible,
    String? status,
  }) async {
    final body = <String, Object?>{'id': id};
    if (title != null) {
      body['title'] = title;
    }
    if (description != null) {
      body['description'] = description;
    }
    if (category != null) {
      body['category'] = category;
    }
    if (serviceId != null || updateService) {
      body['service_id'] = serviceId;
    }
    if (staffId != null || updateStaff) {
      body['staff_id'] = staffId;
    }
    if (isVisible != null) {
      body['is_visible'] = isVisible;
    }
    if (status != null) {
      body['status'] = status;
    }
    final data = await _apiClient.postData(
      '/business/gallery-update.php',
      body: body,
    );
    return _itemFromData(data);
  }

  Future<void> deleteGalleryPhoto(String id) async {
    await _apiClient.postData('/business/gallery-delete.php', body: {'id': id});
  }

  Future<void> reorderGalleryPhotos(String category, List<String> ids) async {
    await _apiClient.postData(
      '/business/gallery-reorder.php',
      body: {'category': category, 'order': ids},
    );
  }

  Future<BusinessGalleryItem> setCover(String id) async {
    final data = await _apiClient.postData(
      '/business/gallery-set-cover.php',
      body: {'id': id},
    );
    return _itemFromData(data);
  }

  BusinessGalleryItem _itemFromData(Map<String, Object?> data) {
    final item = data['item'];
    if (item is Map) {
      return BusinessGalleryItem.fromJson(Map<String, Object?>.from(item));
    }
    throw const FormatException('Sunucu yanıtında item alanı yok.');
  }

  BusinessGallerySummary _mockSummary() {
    const cats = [
      BusinessGalleryCategory(key: 'cover', label: 'Kapak', count: 1, limit: 1),
      BusinessGalleryCategory(
        key: 'interior',
        label: 'İç Mekan',
        count: 0,
        limit: 12,
      ),
      BusinessGalleryCategory(
        key: 'nail_work',
        label: 'Tırnak',
        count: 0,
        limit: 24,
      ),
    ];
    const item = BusinessGalleryItem(
      id: 'mock-cover',
      category: 'cover',
      categoryLabel: 'Kapak',
      title: 'Demo kapak',
      isCover: true,
    );
    return const BusinessGallerySummary(
      items: [item],
      categories: cats,
      quotaUsed: 1,
      quotaLimit: 20,
      coverItem: item,
    );
  }
}
