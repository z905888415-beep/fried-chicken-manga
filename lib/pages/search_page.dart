import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../utils/comic_card_skeleton.dart';
import '../utils/comic_hero_tags.dart';
import '../utils/network_error.dart';
import '../widgets/comic_cover_card.dart';
import '../models/category_config.dart';
import 'category_comics_page.dart';
import 'comic_detail_page.dart';

class SearchPage extends StatefulWidget {
  final String? initialQuery;
  final String? initialTag;

  const SearchPage({super.key, this.initialQuery, this.initialTag});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _tagSpacing = 8.0;

  static const List<String> _danmeiHotKeywords = [
    '五號公寓',
    '光逝去的夏天',
    '绝对会变成BL的世界',
    '没有味觉的男人',
    '穿进妹妹的乙女游戏',
    '原来我是BL主人公',
    '野画集',
    '水边之夜',
    '勾心游戏',
    '危险便利店',
  ];

  final _api = ApiClient();
  final _searchController = TextEditingController();

  List<Comic> _comics = [];
  List<Comic> _suggestions = [];
  Timer? _debounceTimer;
  bool _showSuggestions = false;

  bool _searching = false;
  bool _loadingMore = false;
  int _offset = 0;
  int _total = 0;
  String? _searchQuery;
  String? _searchError;

  bool get _hasResults => _comics.isNotEmpty;

  @override
  void initState() {
    super.initState();

    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _searchController.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _doSearch(widget.initialQuery!);
      });
    } else if (widget.initialTag != null && widget.initialTag != 'danmei') {
      _searchController.text = widget.initialTag!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _doSearch(widget.initialTag!);
      });
    }
    // 默认不预加载列表，直接显示热门搜索+分类标签，避免闪屏
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    final keyword = value.trim();
    if (keyword.isEmpty) {
      if (mounted) {
        setState(() {
          _suggestions = [];
          _showSuggestions = false;
        });
      }
      return;
    }
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _fetchSuggestions(keyword);
    });
  }

  /// 联想搜索：在耽美范围内搜
  Future<void> _fetchSuggestions(String keyword) async {
    try {
      final result = await _api.searchComicsWithinTheme(
        keyword,
        theme: 'danmei',
        limit: 6,
      );
      if (!mounted || _searchController.text.trim() != keyword) return;
      setState(() {
        _suggestions = result.list;
        _showSuggestions = result.list.isNotEmpty;
      });
    } catch (_) {}
  }

  void _onSuggestionTap(Comic comic) {
    _searchController.text = comic.name;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: comic.name.length),
    );
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
    });
    _doSearch(comic.name);
  }

  /// 搜索：在耽美范围内搜（theme=danmei）
  Future<void> _doSearch(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _searching = true;
      _searchQuery = keyword;
      _comics = [];
      _offset = 0;
      _total = 0;
      _searchError = null;
      _showSuggestions = false;
      _suggestions = [];
    });

    try {
      final result = await _api.searchComicsWithinTheme(
        keyword,
        theme: 'danmei',
        limit: 21,
      );

      if (!mounted || _searchQuery != keyword) {
        if (mounted) setState(() => _searching = false);
        return;
      }

      setState(() {
        _comics = result.list;
        _total = result.total;
        _offset = result.list.length;
        _searching = false;
      });
    } catch (e) {
      debugPrint('SearchPage search error: $e');
      if (mounted) {
        setState(() {
          _searching = false;
          _searchError = NetworkError.message(e);
        });
      }
    }
  }

  /// 加载更多：在耽美范围内翻页
  Future<void> _loadMore() async {
    if (_loadingMore || _offset >= _total) return;
    final query = _searchQuery;
    if (query == null) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _api.searchComicsWithinTheme(
        query,
        theme: 'danmei',
        offset: _offset,
        limit: 21,
      );
      if (!mounted || _searchQuery != query) return;
      setState(() {
        _comics.addAll(result.list);
        _offset = _comics.length;
      });
    } catch (e) {
      debugPrint('SearchPage loadMore error: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      } else {
        _loadingMore = false;
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = null;
      _comics = [];
      _offset = 0;
      _total = 0;
      _searching = false;
      _searchError = null;
    });
  }

  void _onKeywordTap(String keyword) {
    _searchController.text = keyword;
    _searchAndOpenDetail(keyword);
  }

  /// 热门关键词点击 → 在耽美范围内搜一本 + 直接跳详情
  Future<void> _searchAndOpenDetail(String keyword) async {
    try {
      final result = await _api.searchComicsWithinTheme(
        keyword,
        theme: 'danmei',
        limit: 3,
      );
      if (!mounted) return;

      if (result.list.isNotEmpty) {
        // 搜到了 → 直接打开第一个
        final comic = result.list.first;
        Navigator.push(
          context,
          ComicDetailPage.route(pathWord: comic.pathWord, initialComic: comic),
        );
        return;
      }
    } catch (e) {
      debugPrint('_searchAndOpenDetail error: $e');
    }

    // 兜底：API 挂了 → 走搜索
    if (mounted) {
      _doSearch(keyword);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (_hasResults &&
              n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
            _loadMore();
          }
          return false;
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(height: MediaQuery.of(context).padding.top),
            ),
            // ── 搜索栏 ──
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp - 8, 12, hp, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: SearchBar(
                        controller: _searchController,
                        hintText: '搜索耽美漫画...',
                        leading: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.search),
                        ),
                        trailing: _searchQuery != null
                            ? [
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: _clearSearch,
                                ),
                              ]
                            : null,
                        onChanged: _onSearchChanged,
                        onSubmitted: _doSearch,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ── 联想列表 ──
            if (_showSuggestions && _suggestions.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 4, hp, 8),
                  child: _SuggestionsCard(
                    suggestions: _suggestions,
                    onTap: _onSuggestionTap,
                  ),
                ),
              ),
            // ── 搜索中 ──
            if (_searching)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
            // ── 搜索失败 ──
            if (_searchError != null && !_searching)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: cs.error),
                        const SizedBox(height: 12),
                        Text('搜索失败', style: tt.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          _searchError!,
                          textAlign: TextAlign.center,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: () {
                            if (_searchQuery != null) {
                              _doSearch(_searchQuery!);
                            }
                          },
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // ── 默认首页：热门搜索 + 耽美分类（无预加载列表，不闪屏）──
            if (_searchQuery == null &&
                !_searching &&
                _searchError == null) ...[
              // 热门搜索
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 8, hp, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.local_fire_department,
                            size: 20,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '热门搜索',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _danmeiHotKeywords.map((k) {
                          return ActionChip(
                            label: Text(k),
                            onPressed: () => _onKeywordTap(k),
                            avatar: Icon(
                              Icons.trending_up,
                              size: 16,
                              color: cs.primary,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              // 耽美分类标签
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 0, hp, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.category, size: 20, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(
                            '耽美分类',
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${CategoryConfig.categories.length} 个小类',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: _tagSpacing,
                        runSpacing: _tagSpacing,
                        children: [
                          for (final c in CategoryConfig.categories)
                            FilterChip(
                              label: Text(c.categoryName),
                              selected: false,
                              showCheckmark: false,
                              onSelected: (_) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CategoryComicsPage(
                                      categoryId: c.categoryId,
                                      categoryName: c.categoryName,
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ],
            // ── 搜索结果统计 ──
            if (_searchQuery != null && _hasResults)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 4, hp, 12),
                  child: Text(
                    '在耽美范围内搜索 "$_searchQuery" 找到 $_total 个结果',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            // ── 搜索结果网格 ──
            if (_comics.isNotEmpty)
              _ComicGrid(
                comics: _comics,
                hp: hp,
                loadingMore: _loadingMore,
                onOpen: (comic, heroTagBase) => Navigator.push(
                  context,
                  ComicDetailPage.route(
                    pathWord: comic.pathWord,
                    initialComic: comic,
                    heroTagBase: heroTagBase,
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
          ],
        ),
      ),
    );
  }
}

/// 联想列表卡片
class _SuggestionsCard extends StatelessWidget {
  final List<Comic> suggestions;
  final void Function(Comic) onTap;

  const _SuggestionsCard({required this.suggestions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHigh.withValues(alpha: 0.95),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: suggestions.map((comic) {
            return ListTile(
              dense: true,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: comic.cover,
                  width: 36,
                  height: 48,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => Container(
                    width: 36,
                    height: 48,
                    color: cs.surfaceContainerHighest,
                    child: const Icon(Icons.image_outlined, size: 18),
                  ),
                ),
              ),
              title: Text(
                comic.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium,
              ),
              subtitle: comic.authors.isNotEmpty
                  ? Text(
                      comic.authors.map((a) => a.name).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    )
                  : null,
              trailing: Icon(
                Icons.search,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              onTap: () => onTap(comic),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ComicGrid extends StatelessWidget {
  final List<Comic> comics;
  final double hp;
  final bool loadingMore;
  final void Function(Comic comic, String heroTagBase) onOpen;

  const _ComicGrid({
    required this.comics,
    required this.hp,
    required this.loadingMore,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          if (i >= comics.length) {
            return const ComicCardSkeleton();
          }
          final comic = comics[i];
          final heroTagBase = ComicHeroTags.base(
            scope: 'search',
            pathWord: comic.pathWord,
            index: i,
          );
          return ComicCoverCard(
            comic: comic,
            heroTagBase: heroTagBase,
            onTap: () => onOpen(comic, heroTagBase),
          );
        }, childCount: comics.length + (loadingMore ? 6 : 0)),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          childAspectRatio: 0.62,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
      ),
    );
  }
}
