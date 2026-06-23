class PaginatedResponse<T> {
  const PaginatedResponse({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.hasMore,
  });

  final List<T> items;
  final int page;
  final int limit;
  final int total;
  final bool hasMore;

  factory PaginatedResponse.fromJson(
    Map<String, Object?> json,
    T Function(Map<String, Object?> item) fromJson,
  ) {
    final itemsJson = json['items'];
    final paginationJson = json['pagination'];
    final pagination = paginationJson is Map
        ? Map<String, Object?>.from(paginationJson)
        : const <String, Object?>{};

    return PaginatedResponse<T>(
      items: itemsJson is List
          ? itemsJson
                .whereType<Map>()
                .map((item) => fromJson(Map<String, Object?>.from(item)))
                .toList()
          : const [],
      page: _int(pagination['page'], fallback: 1),
      limit: _int(pagination['limit'], fallback: 20),
      total: _int(pagination['total']),
      hasMore: pagination['has_more'] == true,
    );
  }

  static int _int(Object? value, {int fallback = 0}) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}
