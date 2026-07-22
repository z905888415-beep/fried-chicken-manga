import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/copymanga_source_adapter.dart';
import '../api/comix/comix_source_adapter.dart';
import '../api/manga_source_adapter.dart';
import '../models/comic.dart' hide Theme;
import '../utils/comic_card_skeleton.dart';
import '../utils/comic_hero_tags.dart';
import '../utils/glass_widgets.dart';
import '../utils/network_error.dart';
import '../widgets/comic_cover_card.dart';
import '../widgets/kira_app_bar.dart';
import '../widgets/state_views.dart';
import 'comic_detail_page.dart';
import 'extension_sources_page.dart';

class ExtensionBrowsePage extends StatefulWidget {
  const ExtensionBrowsePage({super.key});

  @override
  State<ExtensionBrowsePage> createState() => _ExtensionBrowsePageState();
}

class _ExtensionBrowsePageState extends State<ExtensionBrowsePage> {
  final _api = ApiClient();
  late final CopyMangaSourceAdapter _copymangaSource;
  late final ComixSourceAdapter _comixSource;
  late MangaSourceAdapter _source;
  final List<Comic> _comics = [];

  String _browseMode = 'popular'; // 'popular' | 'latest'
  int _page = 1;
  int _total = 0;
  bool _hasNextPage = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _copymangaSource = CopyMangaSourceAdapter(_api);
    _comixSource = ComixSourceAdapter();
    _source = _copymangaSource;
    _loadSourceComics(reset: true);
  }

  void _switchSource(String sourceId) {
    final newSource = sourceId == 'comix' ? _comixSource : _copymangaSource;
    if (_source == newSource) return;
    setState(() => _source = newSource);
    _loadSourceComics(reset: true);
  }

  Future<void> _loadSourceComics({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _comics.clear();
      });
    }

    try {
      final MangaPage result;
      if (_browseMode == 'latest') {
        result = await _source.getLatestUpdates(_page);
      } else {
        result = await _source.getPopularManga(_page);
      }

      if (!mounted) return;
      setState(() {
        if (reset) _comics.clear();
        _comics.addAll(result.comics);
        _total = result.total;
        _hasNextPage = result.hasNextPage;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Extension source error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              '数据源 [${_source.sourceName}] 请求失败: ${NetworkError.message(e)}';
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
      await _loadSourceComics(reset: false);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _switchBrowseMode(String mode) {
    if (_browseMode == mode) return;
    setState(() => _browseMode = mode);
    _loadSourceComics(reset: true);
  }

  Future<void> _openSourceManager() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExtensionSourcesPage()),
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
        titleText: '数据扩展中心',
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_suggest_rounded),
            onPressed: _openSourceManager,
            tooltip: '数据源管理',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadSourceComics(reset: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (sn) {
            if (sn.metrics.pixels >= sn.metrics.maxScrollExtent - 300) {
              _loadMore();
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              // ── 层级 1: 数据源信息卡片 ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 16, hp, 16),
                  child: GlassCard(
                    radius: 20,
                    opacity: 0.85,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.dns_rounded,
                                color: cs.onPrimaryContainer,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _source.sourceName,
                                    style: tt.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'sourceId: ${_source.sourceId} · 内置源适配器',
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '已连接',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              'API: ${_source.sourceId == 'comix' ? 'comix.to/api/v1' : 'mapi.hotmangasg.com'}',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                            const Spacer(),
                            PopupMenuButton<String>(
                              onSelected: _switchSource,
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'copymanga',
                                  child: Text('拷贝漫画 (CopyManga)'),
                                ),
                                const PopupMenuItem(
                                  value: 'comix',
                                  child: Text('Comix.to (English)'),
                                ),
                              ],
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                              child: const Text('切换源'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── 热门/更新切换 + 统计 ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 0, hp, 12),
                  child: Row(
                    children: [
                      SegmentedButton<String>(
                        selected: {_browseMode},
                        onSelectionChanged: (v) => _switchBrowseMode(v.first),
                        segments: const [
                          ButtonSegment(
                            value: 'popular',
                            label: Text('热门'),
                            icon: Icon(Icons.whatshot, size: 16),
                          ),
                          ButtonSegment(
                            value: 'latest',
                            label: Text('更新'),
                            icon: Icon(Icons.schedule, size: 16),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (_total > 0)
                        Text(
                          '共 $_total 部',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── 层级 2: 状态展示 (加载中 / 加载失败 / 空数据 / 正常列表) ──
              if (_loading)
                const SliverFillRemaining(child: LoadingView())
              else if (_error != null && _comics.isEmpty)
                SliverFillRemaining(
                  child: ErrorView(
                    message: _error!,
                    onRetry: () => _loadSourceComics(reset: true),
                  ),
                )
              else if (_comics.isEmpty)
                SliverFillRemaining(
                  child: EmptyView(
                    message: '当前数据源 [${_source.sourceName}] 暂无漫画数据',
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: hp),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate((_, i) {
                      if (i >= _comics.length) {
                        return const ComicCardSkeleton();
                      }
                      final comic = _comics[i];
                      final heroTagBase = ComicHeroTags.base(
                        scope: 'src-${_source.sourceId}',
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
                    }, childCount: _comics.length + (_loadingMore ? 2 : 0)),
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
