import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/copymanga_source_adapter.dart';
import '../models/comic.dart' hide Theme;
import '../utils/comic_hero_tags.dart';
import '../utils/data_cache.dart';
import '../widgets/comic_cover_card.dart';
import '../models/category_config.dart';
import 'comic_detail_page.dart';
import 'search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _cacheKey = 'danmei_home_v3';
  static const _sortPopular = '-popular';
  static const _sortUpdated = '-datetime_updated';

  final _api = ApiClient();
  late final CopyMangaSourceAdapter _source;
  final _cache = DataCache();

  String _selectedCategoryId = CategoryConfig.rootCategoryId;
  String _sortType = _sortPopular;

  List<Comic> _comics = [];
  int _page = 1;
  bool _hasNextPage = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _refreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _source = CopyMangaSourceAdapter(_api);
    _loadFromCache();
    _loadCategory(reset: true);
  }

  Future<void> _loadFromCache() async {
    final cached = await _cache.get(_cacheKey);
    if (!mounted || cached == null || !_loading) return;
    final key = '${_selectedCategoryId}_${_sortType}';
    final list = (cached[key] as List?)
        ?.map((j) => Comic.fromJson(j))
        .toList();
    if (list != null && list.isNotEmpty) {
      setState(() {
        _comics = list;
        _loading = false;
      });
    }
  }

  Future<void> _loadCategory({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _comics = [];
      });
    } else {
      setState(() => _refreshing = true);
    }

    try {
      final result = await _source.browseByCategory(
        _selectedCategoryId,
        page: _page,
        ordering: _sortType,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _comics = [];
        _comics.addAll(result.comics);
        _hasNextPage = result.hasNextPage;
        _loading = false;
        _refreshing = false;
      });
      if (_page == 1) {
        final key = '${_selectedCategoryId}_${_sortType}';
        final cached = await _cache.get(_cacheKey) ?? {};
        cached[key] = result.comics.map((c) => c.toJson()).toList();
        _cache.put(_cacheKey, cached);
      }
    } catch (e) {
      debugPrint('HomePage category load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = e.toString();
      });
    }
  }

  void _selectCategory(String categoryId) {
    if (categoryId == _selectedCategoryId) return;
    setState(() => _selectedCategoryId = categoryId);
    _loadCategory(reset: true);
  }

  void _changeSort(String sort) {
    if (sort == _sortType) return;
    setState(() => _sortType = sort);
    _loadCategory(reset: true);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || !_hasNextPage) return;
    setState(() {
      _loadingMore = true;
      _page++;
    });
    try {
      await _loadCategory(reset: false);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openComic(Comic comic, String heroTagBase) {
    Navigator.push(
      context,
      ComicDetailPage.route(
        pathWord: comic.pathWord,
        initialComic: comic,
        heroTagBase: heroTagBase,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (sn) {
          if (sn.metrics.pixels >= sn.metrics.maxScrollExtent - 300) {
            _loadMore();
          }
          return false;
        },
        child: RefreshIndicator(
          onRefresh: () => _loadCategory(reset: true),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.of(context).padding.top + 8),
              ),

              // 毛玻璃搜索框
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 4, hp, 10),
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SearchPage()),
                    ),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.08),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 16),
                          Icon(Icons.search_rounded,
                              size: 20, color: cs.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Text(
                            '搜索漫画...',
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 分类药丸 Wrap
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: hp),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: CategoryConfig.categories.map((c) {
                      final selected = c.categoryId == _selectedCategoryId;
                      return _CategoryPill(
                        label: c.categoryName,
                        selected: selected,
                        onTap: () => _selectCategory(c.categoryId),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // 最热/最新
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 10, hp, 4),
                  child: Row(
                    children: [
                      _SortChip(
                        icon: Icons.whatshot,
                        label: '最热',
                        selected: _sortType == _sortPopular,
                        onTap: () => _changeSort(_sortPopular),
                      ),
                      const SizedBox(width: 8),
                      _SortChip(
                        icon: Icons.schedule,
                        label: '最新',
                        selected: _sortType == _sortUpdated,
                        onTap: () => _changeSort(_sortUpdated),
                      ),
                      const Spacer(),
                      if (_refreshing)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              // 漫画网格
              if (_loading && _comics.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _comics.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_off,
                            size: 48, color: cs.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text('加载失败', style: tt.titleMedium),
                        const SizedBox(height: 8),
                        FilledButton.tonal(
                          onPressed: () => _loadCategory(reset: true),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_comics.isEmpty)
                SliverFillRemaining(
                  child: Center(
                    child: Text('暂无漫画',
                        style: tt.bodyLarge
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: hp),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        if (i >= _comics.length) {
                          return const Center(
                              child: Padding(
                            padding: EdgeInsets.all(16),
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          ));
                        }
                        final comic = _comics[i];
                        final heroTagBase = ComicHeroTags.base(
                          scope: 'home-$_selectedCategoryId',
                          pathWord: comic.pathWord,
                          index: i,
                        );
                        return ComicCoverCard(
                          comic: comic,
                          heroTagBase: heroTagBase,
                          showMeta: false,
                          radius: 10,
                          onTap: () => _openComic(comic, heroTagBase),
                        );
                      },
                      childCount:
                          _comics.length + (_loadingMore ? 1 : 0),
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.52,
                    ),
                  ),
                ),

              const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 分类药丸 ──

class _CategoryPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary
              : (isDark ? Colors.white : cs.primary)
                  .withValues(alpha: isDark ? 0.10 : 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? cs.primary
                : (isDark ? Colors.white : cs.primary)
                    .withValues(alpha: isDark ? 0.20 : 0.30),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? cs.onPrimary
                : isDark
                    ? Colors.white.withValues(alpha: 0.85)
                    : cs.primary,
          ),
        ),
      ),
    );
  }
}

// ── 排序切换 ──

class _SortChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: selected ? cs.onPrimary : cs.onSurfaceVariant),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
