import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/copymanga_source_adapter.dart';
import '../models/comic.dart' hide Theme;
import '../utils/comic_card_skeleton.dart';
import '../utils/comic_hero_tags.dart';
import '../utils/glass_widgets.dart';
import '../utils/network_error.dart';
import '../widgets/comic_cover_card.dart';
import '../widgets/kira_app_bar.dart';
import '../widgets/state_views.dart';
import 'comic_detail_page.dart';

class CategoryComicsPage extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  final String sourceId;
  final String sortType;

  const CategoryComicsPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
    this.sourceId = 'kopymanga',
    this.sortType = '-popular',
  });

  @override
  State<CategoryComicsPage> createState() => _CategoryComicsPageState();
}

class _CategoryComicsPageState extends State<CategoryComicsPage> {
  final _api = ApiClient();
  late final CopyMangaSourceAdapter _source;
  final List<Comic> _comics = [];
  int _total = 0;
  int _page = 1;
  bool _hasNextPage = false;
  late String _currentSortType;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  static const _sortPopular = '-popular';
  static const _sortUpdated = '-datetime_updated';

  @override
  void initState() {
    super.initState();
    _source = CopyMangaSourceAdapter(_api);
    _currentSortType = widget.sortType == _sortUpdated
        ? _sortUpdated
        : _sortPopular;
    _loadData(reset: true);
  }

  Future<void> _changeSort(String next) async {
    if (next == _currentSortType) return;
    setState(() => _currentSortType = next);
    await _loadData(reset: true);
  }

  Future<void> _loadData({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _comics.clear();
      });
    }

    try {
      final result = await _source.browseByCategory(
        widget.categoryId,
        page: _page,
        ordering: _currentSortType,
      );

      if (!mounted) return;
      setState(() {
        if (reset) _comics.clear();
        _comics.addAll(result.comics);
        _total = result.total;
        _hasNextPage = result.hasNextPage;
        _loading = false;
      });
    } catch (e) {
      debugPrint('CategoryComicsPage load error for ${widget.categoryId}: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = NetworkError.message(e);
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || !_hasNextPage) return;
    setState(() {
      _loadingMore = true;
      _page++;
    });
    try {
      await _loadData(reset: false);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Widget _buildHeader(ColorScheme cs, TextTheme tt, double hp) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 16, hp, 12),
      child: GlassCard(
        radius: 16,
        opacity: 0.75,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.categoryName,
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${widget.categoryId} | 找到 $_total 部作品',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _SortPill(
              icon: Icons.whatshot,
              label: '最热',
              selected: _currentSortType == _sortPopular,
              onTap: () => _changeSort(_sortPopular),
            ),
            const SizedBox(width: 6),
            _SortPill(
              icon: Icons.schedule,
              label: '最新',
              selected: _currentSortType == _sortUpdated,
              onTap: () => _changeSort(_sortUpdated),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return Scaffold(
      appBar: KiraAppBar(
        titleText: '${widget.categoryName} 耽美漫',
        onBack: () => Navigator.pop(context),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadData(reset: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (sn) {
            if (sn.metrics.pixels >= sn.metrics.maxScrollExtent - 300) {
              _loadMore();
            }
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(cs, tt, hp)),
              if (_loading)
                const SliverFillRemaining(child: LoadingView())
              else if (_error != null && _comics.isEmpty)
                SliverFillRemaining(
                  child: ErrorView(
                    message: '加载失败：$_error',
                    onRetry: () => _loadData(reset: true),
                  ),
                )
              else if (_comics.isEmpty)
                SliverFillRemaining(
                  child: EmptyView(
                    message: '暂无 ${widget.categoryName} 漫画',
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: hp),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        if (i >= _comics.length) {
                          return const ComicCardSkeleton();
                        }
                        final comic = _comics[i];
                        final heroTagBase = ComicHeroTags.base(
                          scope: 'cat-${widget.categoryId}',
                          pathWord: comic.pathWord,
                          index: i,
                        );
                        return ComicCoverCard(
                          comic: comic,
                          heroTagBase: heroTagBase,
                          onTap: () => Navigator.push(
                            context,
                            ComicDetailPage.route(
                              pathWord: comic.pathWord,
                              initialComic: comic,
                              heroTagBase: heroTagBase,
                            ),
                          ),
                        );
                      },
                      childCount: _comics.length + (_loadingMore ? 2 : 0),
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.64,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SortPill({
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            Icon(
              icon,
              size: 14,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
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