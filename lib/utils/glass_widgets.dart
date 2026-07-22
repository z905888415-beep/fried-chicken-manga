import 'dart:ui';

import 'package:flutter/material.dart';

/// ── 苹果风设计常量 ──

/// 苹果系统蓝
const appleBlue = Color(0xFF007AFF);

/// 苹果系统粉
const applePink = Color(0xFFFF2D55);

/// 苹果系统橙
const appleOrange = Color(0xFFFF9500);

/// 苹果系统绿
const appleGreen = Color(0xFF34C759);

/// 浅色模式背景灰
const appleLightBg = Color(0xFFF2F2F7);

/// 浅色模式次级背景
const appleLightBgSecondary = Color(0xFFE5E5EA);

/// 深色模式背景黑
const appleDarkBg = Color(0xFF000000);

/// 深色模式次级背景
const appleDarkBgSecondary = Color(0xFF1C1C1E);

/// 统一大圆角
const appleCardRadius = 22.0;
const appleButtonRadius = 16.0;
const applePillRadius = 999.0;

/// ── 毛玻璃组件 ──

/// 苹果风毛玻璃卡片容器。
///
/// 使用 [BackdropFilter] 实现背景模糊，叠加半透明背景色，
/// 呈现 iOS 毛玻璃（Glassmorphism）效果。
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final double opacity;
  final EdgeInsets? padding;
  final EdgeInsets? margin;
  final Color? color;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;
  final Clip clipBehavior;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = appleCardRadius,
    this.blur = 15,
    this.opacity = 0.72,
    this.padding,
    this.margin,
    this.color,
    this.border,
    this.boxShadow,
    this.onTap,
    this.clipBehavior = Clip.antiAlias,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = color ?? (isDark ? Colors.black : Colors.white);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow:
            boxShadow ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
      ),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: clipBehavior,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: baseColor.withValues(alpha: opacity),
                borderRadius: BorderRadius.circular(radius),
                border:
                    border ??
                    Border.all(
                      color: (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.06,
                      ),
                    ),
              ),
              child: Material(color: Colors.transparent, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// 毛玻璃药丸标签（用于标签栏、分类标签等）。
class GlassPill extends StatelessWidget {
  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final Color? selectedColor;
  final EdgeInsets padding;

  const GlassPill({
    super.key,
    required this.child,
    this.selected = false,
    this.onTap,
    this.selectedColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseColor = selected
        ? (selectedColor ?? cs.primary)
        : (isDark ? Colors.white : Colors.white);

    final alpha = selected ? 0.88 : 0.55;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(applePillRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: alpha),
              borderRadius: BorderRadius.circular(applePillRadius),
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : (isDark ? Colors.white : Colors.black).withValues(
                        alpha: 0.06,
                      ),
              ),
            ),
            child: DefaultTextStyle(
              style: TextStyle(
                color: selected
                    ? (isDark ? Colors.black : Colors.white)
                    : cs.onSurface,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// 毛玻璃底部导航栏容器。
///
/// 包装在 Scaffold 的 bottomNavigationBar 位置，
/// 实现半透明模糊 + 上圆角的 iOS 风格 Tab Bar。
class GlassBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<GlassDestination> destinations;

  const GlassBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withValues(
                  alpha: 0.78,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.06,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: _GlassNavItem(
                        destination: destinations[i],
                        selected: i == selectedIndex,
                        color: cs.primary,
                        onTap: () => onDestinationSelected(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassDestination {
  final Widget icon;
  final Widget selectedIcon;
  final String label;

  const GlassDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class _GlassNavItem extends StatelessWidget {
  final GlassDestination destination;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _GlassNavItem({
    required this.destination,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = color;
    final inactiveColor = isDark
        ? const Color(0xFF8E8E93)
        : const Color(0xFF8E8E93);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: selected ? 1.08 : 1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTheme(
              data: IconThemeData(
                color: selected ? activeColor : inactiveColor,
                size: 26,
              ),
              child: selected ? destination.selectedIcon : destination.icon,
            ),
            const SizedBox(height: 2),
            Text(
              destination.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 毛玻璃悬浮顶栏（可用作 AppBar 替代品）。
class GlassTopBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;
  final double height;

  const GlassTopBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.height = 56,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      bottom: false,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.06,
              ),
            ),
          ),
        ),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withValues(
                  alpha: 0.72,
                ),
              ),
              child: NavigationToolbar(
                leading: leading,
                middle: DefaultTextStyle(
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  child: title,
                ),
                trailing: actions != null
                    ? Row(mainAxisSize: MainAxisSize.min, children: actions!)
                    : null,
                centerMiddle: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
