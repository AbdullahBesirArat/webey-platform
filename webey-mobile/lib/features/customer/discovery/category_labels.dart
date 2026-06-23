String customerCategoryLabel(String? value, {String fallback = 'Salon'}) {
  final normalized = _normalizeCategoryKey(value);
  if (normalized.isEmpty) return fallback;

  final label = _categoryLabels[normalized];
  if (label != null) return label;

  final readable = normalized
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
  return readable.isEmpty ? fallback : readable;
}

String customerCategoryLabelUpper(String? value, {String fallback = 'SALON'}) {
  return customerCategoryLabel(value, fallback: fallback).toUpperCase();
}

String _normalizeCategoryKey(String? value) {
  return (value ?? '')
      .trim()
      .replaceAll('-', '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .toLowerCase();
}

const _categoryLabels = <String, String>{
  'hair_salon': 'Kuaför',
  'hair_care': 'Saç Bakımı',
  'beauty_salon': 'Güzellik Salonu',
  'barber': 'Berber',
  'nail': 'Tırnak',
  'nail_studio': 'Tırnak',
  'manicure_pedicure': 'Manikür / Pedikür',
  'prosthetic_nail': 'Protez Tırnak',
  'skin_care': 'Cilt Bakımı',
  'massage': 'Masaj',
  'spa': 'Spa',
  'spa_massage': 'Spa & Masaj',
  'makeup_studio': 'Makyaj',
  'permanent_makeup': 'Kalıcı Makyaj',
  'lash_brow': 'Kaş & Kirpik',
  'brow_design': 'Kaş Tasarım',
  'laser_epilation': 'Lazer Epilasyon',
};
