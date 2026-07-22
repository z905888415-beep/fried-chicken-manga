import 'package:flutter/material.dart';

/// 圆形图标按钮。
///
/// 统一样式：38×38 圆形，浅色背景（深色 5% 白 / 浅色 5% 黑）。
/// [glass] 为 `true` 时使用半透明毛玻璃风格，用于详情页封面浮层。
class CircleIconButton extends StatelessWidget {
  /// 图标。
  final IconData icon;

  /// 点击回调；为 `null` 时仅展示不可点击图标。
  final VoidCallback? onTap;

  /// 按钮直径，默认 38。
  final double size;

  /// 图标颜色；不传则跟随主题 [ColorScheme.onSurface]。
  final Color? color;

  /// 是否使用毛玻璃风格。
  final bool glass;

  /// 图标尺寸，默认 20。
  final double iconSize;

  const CircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 38.0,
    this.color,
    this.glass = false,
    this.iconSize = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconColor = color ?? cs.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final child = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: glass
            ? cs.surface.withValues(alpha: 0.5)
            : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
        shape: BoxShape.circle,
        border: glass
            ? Border.all(color: cs.onSurface.withValues(alpha: 0.12))
            : null,
      ),
      child: Icon(icon, size: iconSize, color: iconColor),
    );

    if (onTap == null) return child;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}
