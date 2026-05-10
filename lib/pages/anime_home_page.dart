import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/anime.dart';
import '../models/user_manager.dart';
import '../utils/data_cache.dart';
import 'anime_detail_page.dart';
import 'anime_list_page.dart';
import 'home_page.dart';

class AnimeHomePage extends StatefulWidget {
  const AnimeHomePage({super.key});

  @override
  State<AnimeHomePage> createState() => _AnimeHomePageState();
}

class _AnimeHomePageState extends State<AnimeHomePage> {
  static const _cacheKey = 'anime_home_v1';

  final _api = ApiClient();
  final _cache = DataCache();
  final _user = UserManager();
  final _bannerController = PageController(viewportFraction: 0.92);
  Timer? _bannerTimer;
  AnimeHome? _home;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  int _bannerPage = 0;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _load();
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  Future<void> _loadFromCache() async {
    final cached = await _cache.get(_cacheKey);
    if (!mounted || cached == null || !_loading) return;
    setState(() {
      _home = AnimeHome.fromJson(Map<String, dynamic>.from(cached));
      _loading = false;
    });
    _restartBannerTimer();
  }

  Future<void> _load() async {
    final hasData = _home != null;
    if (!hasData) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _refreshing = true);
    }

    try {
      final home = await _api.getAnimeHome();
      if (!mounted) return;
      setState(() {
        _home = home;
        _loading = false;
        _refreshing = false;
        if (_bannerPage >= home.banners.length) _bannerPage = 0;
      });
      _cache.put(_cacheKey, home.toJson());
      _restartBannerTimer();
    } catch (e) {
      debugPrint('AnimeHomePage load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e.toString();
      });
    }
  }

  void _openAnime(Anime anime) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AnimeDetailPage(pathWord: anime.pathWord, initialAnime: anime),
      ),
    );
  }

  void _openList(AnimeListType type) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AnimeListPage(type: type)),
    );
  }

  void _restartBannerTimer() {
    _bannerTimer?.cancel();
    final count = _home?.banners.length ?? 0;
    if (count <= 1 || _user.animeHomeBannerCollapsed) return;

    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      final nextPage = (_bannerPage + 1) % count;
      _bannerController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _toggleBannerCollapsed() {
    final next = !_user.animeHomeBannerCollapsed;
    _user.setAnimeHomeBannerCollapsed(next);
    setState(() {});
    if (next) {
      _bannerTimer?.cancel();
    } else {
      _restartBannerTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 900 ? screenWidth : 900.0;
    final hp = (screenWidth - contentWidth) / 2 + 16;
    final home = _home;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null && home == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('加载失败', style: tt.titleMedium),
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: MediaQuery.of(context).padding.top),
          ),
          if (_refreshing)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (home != null && home.banners.isNotEmpty)
            SliverToBoxAdapter(
              child: _AnimeBannerCarousel(
                banners: home.banners,
                controller: _bannerController,
                currentPage: _bannerPage,
                hp: hp,
                collapsed: _user.animeHomeBannerCollapsed,
                onPageChanged: (page) => setState(() => _bannerPage = page),
                onToggleCollapsed: _toggleBannerCollapsed,
                onTap: _openAnime,
              ),
            ),
          if (home != null && home.recommendations.isNotEmpty)
            _AnimeSection(
              title: '编辑推荐',
              icon: Icons.auto_awesome,
              hp: hp,
              onMore: () => _openList(AnimeListType.editor),
              child: _AnimeHorizontalList(
                items: home.recommendations,
                onTap: _openAnime,
              ),
            ),
          if (home != null && home.updates.isNotEmpty)
            _AnimeSection(
              title: '最近更新',
              icon: Icons.update,
              hp: hp,
              onMore: () => _openList(AnimeListType.updates),
              child: _AnimeUpdateGrid(items: home.updates, onTap: _openAnime),
            ),
          if (home != null && home.classics.isNotEmpty)
            _AnimeSection(
              title: '经典推荐',
              icon: Icons.workspace_premium,
              hp: hp,
              onMore: () => _openList(AnimeListType.classics),
              child: _AnimeHorizontalList(
                items: home.classics,
                onTap: _openAnime,
              ),
            ),
          if (home != null && home.hots.isNotEmpty)
            _AnimeSection(
              title: '热门动漫',
              icon: Icons.local_fire_department,
              hp: hp,
              onMore: () => _openList(AnimeListType.hots),
              child: _AnimeHorizontalList(items: home.hots, onTap: _openAnime),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}

class _AnimeBannerCarousel extends StatelessWidget {
  final List<AnimeBanner> banners;
  final PageController controller;
  final int currentPage;
  final double hp;
  final bool collapsed;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<Anime> onTap;

  const _AnimeBannerCarousel({
    required this.banners,
    required this.controller,
    required this.currentPage,
    required this.hp,
    required this.collapsed,
    required this.onPageChanged,
    required this.onToggleCollapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (collapsed) {
      return Padding(
        padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
        child: Row(
          children: [
            Icon(Icons.movie_filter_outlined, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '轮播图',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              tooltip: '展开',
              onPressed: onToggleCollapsed,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(hp, 8, hp, 0),
          child: Row(
            children: [
              const Spacer(),
              IconButton(
                tooltip: '折叠',
                onPressed: onToggleCollapsed,
                icon: const Icon(Icons.keyboard_arrow_up),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 176,
          child: PageView.builder(
            controller: controller,
            itemCount: banners.length,
            onPageChanged: onPageChanged,
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? hp - 16 : 6,
                right: i == banners.length - 1 ? hp - 16 : 6,
                bottom: 8,
              ),
              child: _AnimeBannerCard(
                banner: banners[i],
                onTap: banners[i].anime == null
                    ? null
                    : () => onTap(banners[i].anime!),
              ),
            ),
          ),
        ),
        if (banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < banners.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: i == currentPage ? 16 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == currentPage
                          ? cs.primary
                          : cs.onSurfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AnimeSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final double hp;
  final Widget child;
  final VoidCallback? onMore;

  const _AnimeSection({
    required this.title,
    required this.icon,
    required this.hp,
    required this.child,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 20, hp, 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (onMore != null)
                  TextButton(
                    onPressed: onMore,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('更多', style: TextStyle(color: cs.primary)),
                        Icon(Icons.chevron_right, size: 18, color: cs.primary),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _AnimeBannerCard extends StatelessWidget {
  final AnimeBanner banner;
  final VoidCallback? onTap;

  const _AnimeBannerCard({required this.banner, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final title = banner.anime?.name ?? banner.brief;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: banner.cover,
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, _) => _ImagePlaceholder(icon: Icons.movie),
              errorWidget: (_, _, _) =>
                  _ImagePlaceholder(icon: Icons.broken_image),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title.isNotEmpty)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  if (banner.brief.isNotEmpty && banner.brief != title) ...[
                    const SizedBox(height: 2),
                    Text(
                      banner.brief,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.surface),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimeHorizontalList extends StatelessWidget {
  final List<Anime> items;
  final ValueChanged<Anime> onTap;

  const _AnimeHorizontalList({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 900 ? screenWidth : 900.0;
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return SizedBox(
      height: 224,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: hp),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final anime = items[i];
          return _AnimeCard(anime: anime, onTap: () => onTap(anime));
        },
      ),
    );
  }
}

class _AnimeUpdateGrid extends StatelessWidget {
  final List<AnimeUpdate> items;
  final ValueChanged<Anime> onTap;

  const _AnimeUpdateGrid({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 900 ? screenWidth : 900.0;
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: hp),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 130,
        childAspectRatio: 0.5,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemBuilder: (_, i) {
        final anime = items[i].anime;
        return _AnimeCard(anime: anime, onTap: () => onTap(anime));
      },
    );
  }
}

class _AnimeCard extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;

  const _AnimeCard({required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final meta = anime.count > 0
        ? '共 ${anime.count} 集'
        : (anime.company?.name ?? anime.years ?? '');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: anime.cover,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (_, _) =>
                          _ImagePlaceholder(icon: Icons.movie_outlined),
                      errorWidget: (_, _, _) =>
                          _ImagePlaceholder(icon: Icons.broken_image),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              anime.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall,
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.local_fire_department, size: 12, color: cs.primary),
                const SizedBox(width: 2),
                Text(
                  ComicCard.formatPopular(anime.popular),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final IconData icon;

  const _ImagePlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(child: Icon(icon, color: cs.onSurfaceVariant, size: 32)),
    );
  }
}
