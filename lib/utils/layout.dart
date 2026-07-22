import 'dart:math' show min;

import 'package:flutter/material.dart';

/// 居中布局容器。
///
/// 将子组件约束在 [maxWidth] 以内，并在两侧保留与页面一致的视觉边距
/// （[horizontalPadding]），从而在大屏 / 横屏下仍然保持居中且不过宽。
///
/// 用法：
/// ```dart
/// MaxWidthCenter(
///   child: ListView(...),
/// )
/// ```
class MaxWidthCenter extends StatelessWidget {
  /// 被约束的子组件。
  final Widget child;

  /// 内容最大宽度，默认 900。
  final double maxWidth;

  /// 内容两侧额外内边距，默认 16。
  final double horizontalPadding;

  const MaxWidthCenter({
    super.key,
    required this.child,
    this.maxWidth = 900.0,
    this.horizontalPadding = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final hp = computeHorizontalPadding(context, maxWidth, horizontalPadding);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hp),
          child: child,
        ),
      ),
    );
  }

  /// 计算与页面一致的左右内边距。
  ///
  /// 公式： `(屏幕宽度 - min(屏幕宽度, maxWidth)) / 2 + horizontalPadding`。
  /// 供已有的 `CustomScrollView` / `Sliver` 列表复用，保持边距一致。
  static double computeHorizontalPadding(
    BuildContext context, [
    double maxWidth = 900.0,
    double horizontalPadding = 16.0,
  ]) {
    final width = MediaQuery.of(context).size.width;
    return (width - min(width, maxWidth)) / 2 + horizontalPadding;
  }

  /// [computeHorizontalPadding] 的简写，使用默认 [horizontalPadding]。
  static double hp(BuildContext context, [double maxWidth = 900.0]) =>
      computeHorizontalPadding(context, maxWidth, 16.0);
}
