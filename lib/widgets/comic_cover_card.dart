import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/comic.dart' hide Theme;
import '../utils/comic_hero_tags.dart';
import '../utils/format.dart';
import '../utils/theme_tokens.dart';

/// 漫画封面卡片（网格风格）。
///
/// 统一「封面图 + 标题 + 题材 + 人气」的展示，供首页 / 搜索 / 分类 /
/// 扩展源等网格列表复用。
class ComicCoverCard extends StatelessWidget {
  /// 漫画数据。
  final Comic comic;

  /// 点击回调；为 `null` 时不可点击。
  final VoidCallback? onTap;

  /// Hero 动画基串；不为 `null` 时封面套用 [ComicHeroTags.cover] 实现转场。
  final String? heroTagBase;

  /// 是否展示题材行。
  final bool showMeta;

  /// 是否展示人气（星标 + 数值）。
  final bool showPopular;

  /// 封面圆角，默认 16。
  final double radius;

  const ComicCoverCard({
    super.key,
    required this.comic,
    this.onTap,
    this.heroTagBase,
    this.showMeta = true,
    this.showPopular = true,
    this.radius = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final themes = comic.themes.take(2).map((t) => t.name).join(' · ');

    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: CachedNetworkImage(
        imageUrl: comic.cover,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        fadeInDuration: Duration.zero,
        fadeOutDuration: Duration.zero,
        placeholder: (_, _) => Container(
          color: cs.surfaceContainerHighest,
          child: Center(
            child: Icon(Icons.image, color: cs.onSurfaceVariant, size: 32),
          ),
        ),
        errorWidget: (_, _, _) => Container(
          color: cs.surfaceContainerHighest,
          child: Center(
            child: Icon(
              Icons.broken_image,
              color: cs.onSurfaceVariant,
              size: 32,
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

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: heroCover),
        const SizedBox(height: 8),
        Text(
          comic.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (showMeta ? tt.bodyMedium : tt.bodySmall)?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (showMeta && themes.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            themes,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (showPopular) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.star_rounded, size: 14, color: kAccentPink),
              const SizedBox(width: 2),
              Text(
                Format.formatPopular(comic.popular),
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );

    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}
