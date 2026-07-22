import 'package:flutter/material.dart';

/// 区块标题。
///
/// 用于各页面「为你推荐 / 热门搜索 / 分类」等块的标题行，
/// 右侧可挂载操作组件（如「查看更多」）。
class SectionHeader extends StatelessWidget {
  /// 标题文本。
  final String title;

  /// 右侧操作组件（可选）。
  final Widget? action;

  /// 内边距，默认 `(16, 16, 16, 8)`。
  final EdgeInsetsGeometry padding;

  /// 字号，默认 18。
  final double fontSize;

  /// 字重，默认 [FontWeight.w700]。
  final FontWeight fontWeight;

  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 8),
    this.fontSize = 18,
    this.fontWeight = FontWeight.w700,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: tt.titleMedium?.copyWith(
                fontSize: fontSize,
                fontWeight: fontWeight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...?(action == null ? null : [action!]),
        ],
      ),
    );
  }
}
