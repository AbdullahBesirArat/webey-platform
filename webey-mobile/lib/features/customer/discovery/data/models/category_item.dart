import 'package:flutter/material.dart';

class CategoryItem {
  const CategoryItem({
    required this.id,
    required this.slug,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.sortOrder,
    this.salonCount = 0,
    this.serviceCount = 0,
    this.isSystem = true,
  });

  final String id;
  final String slug;
  final String title;
  final String subtitle;
  final String icon;
  final int sortOrder;
  final int salonCount;
  final int serviceCount;
  final bool isSystem;

  factory CategoryItem.fromJson(Map<String, Object?> json) {
    return CategoryItem(
      id: _string(json['id']),
      slug: _string(json['slug']),
      title: _string(json['title']),
      subtitle: _string(json['subtitle']),
      icon: _string(json['icon']),
      sortOrder: _int(json['sort_order']),
      salonCount: _int(json['salon_count']),
      serviceCount: _int(json['service_count']),
      isSystem: json['is_system'] != false,
    );
  }

  IconData get iconData {
    return switch (slug) {
      'hair_salon' || 'hair_care' => Icons.content_cut_rounded,
      'nail_studio' ||
      'manicure_pedicure' ||
      'prosthetic_nail' => Icons.back_hand_outlined,
      'makeup_studio' || 'permanent_makeup' => Icons.brush_outlined,
      'skin_care' => Icons.water_drop_outlined,
      'laser_epilation' => Icons.flare_rounded,
      'lash_brow' || 'brow_design' => Icons.remove_red_eye_outlined,
      'spa_massage' => Icons.spa_outlined,
      _ => Icons.auto_awesome_outlined,
    };
  }

  static String _string(Object? value) => value?.toString() ?? '';

  static int _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
