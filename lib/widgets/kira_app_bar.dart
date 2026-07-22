import 'dart:ui';

import 'package:flutter/material.dart';

/// 统一顶部栏。
///
/// 默认毛玻璃风格（与 [GlassTopBar] 视觉一致）。
/// [glass] 为 `true` 时进一步降低背景不透明度，适配封面图浮层。
///
/// 提供 [onBack] 便捷参数自动生成统一的返回按钮（[_BackButton]）。
class KiraAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// 标题组件。
  final Widget? title;

  /// 标题文本（与 [title] 二选一，优先 [title]）。
  final String? titleText;

  /// 右侧操作区。
  final List<Widget>? actions;

  /// 左侧组件；不传且 [onBack] 不为 `null` 时自动生成返回按钮。
  final Widget? leading;

  /// 返回回调；传入后自动在左侧渲染返回按钮。
  final VoidCallback? onBack;

  /// 高度，默认 56。
  final double height;

  /// 是否使用毛玻璃浮层风格。
  final bool glass;

  const KiraAppBar({
    super.key,
    this.title,
    this.titleText,
    this.actions,
    this.leading,
    this.onBack,
    this.height = 56.0,
    this.glass = false,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  Widget get _titleWidget => title ?? Text(titleText ?? '');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgAlpha = glass ? 0.4 : 0.72;

    final leadingWidget =
        leading ?? (onBack != null ? _BackButton(onPressed: onBack) : null);

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
                  alpha: bgAlpha,
                ),
              ),
              child: NavigationToolbar(
                leading: leadingWidget,
                middle: DefaultTextStyle(
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  child: _titleWidget,
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

/// 统一的返回按钮，常用于 [KiraAppBar.leading]。
class _BackButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const _BackButton({this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_ios_new_rounded),
      onPressed: onPressed ?? () => Navigator.maybePop(context),
    );
  }
}
