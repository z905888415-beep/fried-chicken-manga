import 'package:flutter/material.dart';

@immutable
class AppThemeOption {
  final String id;
  final String label;
  final Color seedColor;

  const AppThemeOption({
    required this.id,
    required this.label,
    required this.seedColor,
  });
}

@immutable
class AppThemeVariantOption {
  final DynamicSchemeVariant variant;
  final String label;
  final String description;

  const AppThemeVariantOption({
    required this.variant,
    required this.label,
    required this.description,
  });

  String get id => variant.name;
}

const customThemeOptionId = 'custom';
const defaultCustomThemeColor = Color(0xFF166FF3);

const appThemeOptions = <AppThemeOption>[
  AppThemeOption(id: 'blue_grey', label: '蓝灰', seedColor: Colors.blueGrey),
  AppThemeOption(id: 'teal', label: '青绿', seedColor: Colors.teal),
  AppThemeOption(id: 'indigo', label: '靛蓝', seedColor: Colors.indigo),
  AppThemeOption(id: 'green', label: '森绿', seedColor: Colors.green),
  AppThemeOption(id: 'orange', label: '橙金', seedColor: Colors.orange),
  AppThemeOption(id: 'pink', label: '粉色', seedColor: Color(0xFFFB7299)),
  AppThemeOption(id: 'bright_blue', label: '亮蓝', seedColor: Color(0xFF166FF3)),
  AppThemeOption(id: 'violet', label: '紫罗兰', seedColor: Color(0xFF7E57C2)),
  AppThemeOption(id: 'orchid', label: '兰紫', seedColor: Color(0xFFAB47BC)),
  AppThemeOption(id: 'cyan', label: '湖青', seedColor: Color(0xFF00ACC1)),
  AppThemeOption(id: 'emerald', label: '翡翠', seedColor: Color(0xFF1F9D72)),
  AppThemeOption(id: 'lime', label: '青柠', seedColor: Color(0xFF7CB342)),
  AppThemeOption(id: 'amber', label: '琥珀', seedColor: Color(0xFFF9A825)),
  AppThemeOption(id: 'coral', label: '珊瑚', seedColor: Color(0xFFFF7043)),
];

const appThemeVariantOptions = <AppThemeVariantOption>[
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.tonalSpot,
    label: '柔和',
    description: 'Material 默认风格，低饱和、耐看。',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.vibrant,
    label: '鲜明',
    description: '提高主色饱和度，整体更醒目。',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.expressive,
    label: '表现',
    description: '会偏移主色相，风格更有个性。',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.fidelity,
    label: '准确',
    description: '尽量贴近所选主色的原始观感。',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.content,
    label: '内容',
    description: '容器颜色更贴近主色，强调层次。',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.neutral,
    label: '中性',
    description: '接近灰阶，适合更克制的界面。',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.monochrome,
    label: '黑白',
    description: '完全灰阶，只保留明暗关系。',
  ),
  AppThemeVariantOption(
    variant: DynamicSchemeVariant.rainbow,
    label: '彩虹',
    description: '跳脱主色限制，整体更活泼。',
  ),
];

AppThemeOption resolveAppThemeOption(String? id) {
  for (final option in appThemeOptions) {
    if (option.id == id) return option;
  }
  return appThemeOptions.first;
}

AppThemeVariantOption resolveAppThemeVariantOption(String? id) {
  for (final option in appThemeVariantOptions) {
    if (option.id == id) return option;
  }
  return appThemeVariantOptions.first;
}
