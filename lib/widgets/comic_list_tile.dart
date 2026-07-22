import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/comic.dart' hide Theme;
import '../utils/comic_hero_tags.dart';
import '../utils/theme_tokens.dart';

/// 漫画列表行（横向：封面缩略图 + 标题 + 副信息）。
///
/// 统一收藏列表等横向列表项，复用毛玻璃卡片风格。
class ComicListTile extends StatelessWidget {
  /// 漫画数据。
  final Comic comic;

  /// 点击回调；为 `null` 时不可点击。
  final VoidCallback? onTap;

  /// Hero 动画基串；不为 `null` 时封面套用 [ComicHeroTags.cover] 实现转场。
  final String? heroTagBase;

  /// 副标题（如「看到 第1话」）。
  final String? subtitle;

  /// 是否展示「更新」徽标。
  final bool showUpdateBadge;

  /// 右侧操作组件；不传且 [showUpdateBadge] 为 `true` 时展示「更多」图标。
  final Widget? trailing;

  /// 封面宽度，默认 64。
  final double coverWidth;

  /// 封面高度，默认 80。
  final double coverHeight;

  /// 封面圆角，默认 10。
  final double radius;

  const ComicListTile({
    super.key,
    required this.comic,
    this.onTap,
    this.heroTagBase,
    this.subtitle,
    this.showUpdateBadge = false,
    this.trailing,
    this.coverWidth = 64,
    this.coverHeight = 80,
    this.radius = 10.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: comic.cover,
        width: coverWidth,
        height: coverHeight,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, _) => Container(
          color: cs.surfaceContainerHighest,
          child: Center(
            child: Icon(Icons.image, color: cs.onSurfaceVariant, size: 24),
          ),
        ),
        errorWidget: (_, _, _) => Container(
          color: cs.surfaceContainerHighest,
          child: Center(
            child: Icon(
              Icons.broken_image,
              color: cs.onSurfaceVariant,
              size: 24,
            ),
          ),
        ),
      ),
    );

    final heroCover = heroTagBase == null
        ? cover
        : Hero(
            tag: ComicHeroTags.cover(heroTagBase!),
            createRectTween: ComicHeroTags.createRectTween,
            child: cover,
          );

    final body = GlassCard(
      radius: radius + 4,
      opacity: 0.6,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          heroCover,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  comic.name,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (showUpdateBadge) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: kAccentPink.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '更新',
                          style: tt.labelSmall?.copyWith(
                            color: kAccentPink,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      trailing ??
                          Icon(
                            Icons.more_horiz_rounded,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return body;
    return GestureDetector(onTap: onTap, child: body);
  }
}
