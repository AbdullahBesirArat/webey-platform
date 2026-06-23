class SearchSuggestion {
  const SearchSuggestion({
    required this.type,
    required this.title,
    required this.subtitle,
    this.id,
    this.slug,
  });

  final String type;
  final String title;
  final String subtitle;
  final String? id;
  final String? slug;

  factory SearchSuggestion.fromJson(Map<String, Object?> json) {
    return SearchSuggestion(
      type: _string(json['type']),
      title: _string(json['title']),
      subtitle: _string(json['subtitle']),
      id: _nullableString(json['id']),
      slug: _nullableString(json['slug']),
    );
  }

  static String _string(Object? value) => value?.toString() ?? '';

  static String? _nullableString(Object? value) {
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : text;
  }
}
