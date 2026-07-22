import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../utils/comic_hero_tags.dart';
import '../utils/theme_tokens.dart';
import '../utils/layout.dart';
import '../utils/local_favorites.dart';
import '../utils/reading_history.dart';
import '../utils/toast.dart';
import '../widgets/comic_list_tile.dart';
import '../widgets/section_header.dart';
import 'comic_detail_page.dart';
import 'local_comics_page.dart';
import 'reader_page.dart';
import 'search_page.dart';

class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<Comic> _favorites = [];
  List<LastReadRecord> _recentReads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    LocalFavorites.changes.addListener(_loadFavorites);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    LocalFavorites.changes.removeListener(_loadFavorites);
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    _loadRecentReads();
    _loadFavorites();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadFavorites(), _loadRecentReads()]);
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadFavorites() async {
    final items = await LocalFavorites.list();
    if (!mounted) return;
    setState(() => _favorites = items);
  }

  Future<void> _loadRecentReads() async {
    final reads = await ReadingHistory.getRecentReads();
    await ReadingHistory.getLastRead();
    if (!mounted) return;
    setState(() {
      _recentReads = reads;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hp = MaxWidthCenter.hp(context);

    if (_loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 8),
          Padding(
            padding: EdgeInsets.fromLTRB(hp, 4, hp, 12),
            child: Row(
              children: [
                Text(
                  '书架',
                  style: tt.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                _IconBtn(
                  icon: Icons.search_rounded,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchPage()),
                  ),
                ),
                const SizedBox(width: 8),
                _IconBtn(icon: Icons.more_horiz_rounded, onTap: () {}),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: hp),
            child: _TabBar(controller: _tabController),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _RecentReadsTab(
                  records: _recentReads,
                  onRefresh: _loadRecentReads,
                ),
                _FavoritesTab(
                  favorites: _favorites,
                  hp: hp,
                ),
                const LocalComicsPage(embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab 0: 最近阅读 ──

class _RecentReadsTab extends StatelessWidget {
  final List<LastReadRecord> records;
  final VoidCallback onRefresh;

  const _RecentReadsTab({required this.records, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hp = MaxWidthCenter.hp(context);

    if (records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('暂无阅读记录', style: tt.titleMedium),
            const SizedBox(height: 6),
            Text(
              '阅读漫画后会显示在这里',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(hp, 12, hp, 100),
        itemCount: records.length,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ContinueReadingCard(record: records.first),
            );
          }
          final record = records[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RecentReadTile(record: record),
          );
        },
      ),
    );
  }
}

class _RecentReadTile extends StatelessWidget {
  final LastReadRecord record;

  const _RecentReadTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ComicDetailPage(
                pathWord: record.pathWord,
                heroTagBase: ComicHeroTags.base(
                  scope: 'recent-read',
                  pathWord: record.pathWord,
                  index: 0,
                ),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: record.cover.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: record.cover,
                        width: 56,
                        height: 74,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 56,
                        height: 74,
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.menu_book,
                          color: cs.onSurfaceVariant,
                          size: 24,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '看到 ${record.chapterName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (record.totalPage > 0) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (record.page / record.totalPage).clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: cs.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(kAccentPink),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tab 1: 收藏 ──

class _FavoritesTab extends StatefulWidget {
  final List<Comic> favorites;
  final double hp;

  const _FavoritesTab({
    required this.favorites,
    required this.hp,
  });

  @override
  State<_FavoritesTab> createState() => _FavoritesTabState();
}

class _FavoritesTabState extends State<_FavoritesTab> {
  final Map<String, ReadingRecord> _readingRecords = {};

  @override
  void initState() {
    super.initState();
    _loadReadingRecords();
  }

  @override
  void didUpdateWidget(_FavoritesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.favorites != widget.favorites) {
      _loadReadingRecords();
    }
  }

  Future<void> _loadReadingRecords() async {
    final records = <String, ReadingRecord>{};
    for (final comic in widget.favorites) {
      final record = await ReadingHistory.get(comic.pathWord);
      if (record != null) {
        records[comic.pathWord] = record;
      }
    }
    if (mounted) {
      setState(() {
        _readingRecords.clear();
        _readingRecords.addAll(records);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hp = widget.hp;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SectionHeader(
            title: '我的收藏',
            padding: EdgeInsets.fromLTRB(hp, 16, hp, 8),
            action: Text(
              '管理',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        if (widget.favorites.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_border, size: 48, color: cs.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('还没有收藏', style: tt.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    '在漫画详情页点收藏后，会显示在这里',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hp),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((_, i) {
                final comic = widget.favorites[i];
                final record = _readingRecords[comic.pathWord];
                final subtitle = record != null
                    ? '看到 ${record.chapterName}'
                    : null;
                final heroTagBase = ComicHeroTags.base(
                  scope: 'bookshelf',
                  pathWord: comic.pathWord,
                  index: i,
                );
                return ComicListTile(
                  comic: comic,
                  heroTagBase: heroTagBase,
                  subtitle: subtitle,
                  showUpdateBadge: true,
                  onTap: () {
                    Navigator.push(
                      context,
                      ComicDetailPage.route(
                        pathWord: comic.pathWord,
                        initialComic: comic,
                        heroTagBase: heroTagBase,
                      ),
                    ).then((_) => _loadReadingRecords());
                  },
                );
              }, childCount: widget.favorites.length),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.2,
              ),
            ),
          ),
        if (widget.favorites.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  '共 ${widget.favorites.length} 部收藏',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }
}

// ── Tab 栏 ──

class _TabBar extends StatelessWidget {
  final TabController controller;

  const _TabBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const tabs = ['最近阅读', '收藏', '下载'];
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: kAccentPink,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
        tabs: tabs.map((t) => Tab(text: t)).toList(),
      ),
    );
  }
}

// ── 继续阅读卡片 ──

class _ContinueReadingCard extends StatefulWidget {
  final LastReadRecord record;

  const _ContinueReadingCard({required this.record});

  @override
  State<_ContinueReadingCard> createState() => _ContinueReadingCardState();
}

class _ContinueReadingCardState extends State<_ContinueReadingCard> {
  ReadingRecord? _readingRecord;
  bool _fetchingFirstChapter = false;

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  @override
  void didUpdateWidget(_ContinueReadingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.pathWord != widget.record.pathWord) {
      _loadRecord();
    }
  }

  Future<void> _loadRecord() async {
    try {
      final record = await ReadingHistory.get(widget.record.pathWord);
      if (!mounted) return;
      setState(() => _readingRecord = record);
    } catch (_) {}
  }

  Future<void> _handleContinueReading() async {
    if (_readingRecord != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderPage(
            pathWord: widget.record.pathWord,
            comicName: widget.record.name,
            coverUrl: widget.record.cover.isNotEmpty ? widget.record.cover : null,
            group: _readingRecord!.group,
            chapterUuid: _readingRecord!.chapterUuid,
            chapterName: _readingRecord!.chapterName,
            initialPage: _readingRecord!.page,
          ),
        ),
      ).then((_) => _loadRecord());
    } else {
      setState(() => _fetchingFirstChapter = true);
      try {
        final chaptersData = await ApiClient().getChapterList(
          widget.record.pathWord,
        );
        if (!mounted) return;
        if (chaptersData.list.isEmpty) {
          showToast(context, '该漫画暂无章节', isError: true);
          return;
        }
        final firstChapter = chaptersData.list.first;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReaderPage(
              pathWord: widget.record.pathWord,
              comicName: widget.record.name,
              coverUrl: widget.record.cover.isNotEmpty ? widget.record.cover : null,
              group: 'default',
              chapterUuid: firstChapter.uuid,
              chapterName: firstChapter.name,
              initialPage: 1,
            ),
          ),
        ).then((_) => _loadRecord());
      } catch (e) {
        if (mounted) {
          showToast(context, '获取章节失败：$e', isError: true);
        }
      } finally {
        if (mounted) {
          setState(() => _fetchingFirstChapter = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final value = _readingRecord != null && _readingRecord!.totalPage > 0
        ? (_readingRecord!.page / _readingRecord!.totalPage).clamp(0.0, 1.0)
        : 0.0;
    final progressText = _readingRecord != null && _readingRecord!.totalPage > 0
        ? '${(value * 100).round()}%'
        : '0%';
    final statusText = _readingRecord != null
        ? '上次看到 ${_readingRecord!.chapterName}'
        : '未开始阅读';

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '继续阅读',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: widget.record.cover.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: widget.record.cover,
                        width: 100,
                        height: 130,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 100,
                        height: 130,
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.menu_book,
                          color: cs.onSurfaceVariant,
                          size: 36,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.record.name,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      statusText,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 6,
                              backgroundColor: cs.surfaceContainerHighest,
                              valueColor: const AlwaysStoppedAnimation(
                                kAccentPink,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          progressText,
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _fetchingFirstChapter
                          ? null
                          : _handleContinueReading,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: kAccentPink),
                        foregroundColor: kAccentPink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: _fetchingFirstChapter
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(kAccentPink),
                              ),
                            )
                          : Text(_readingRecord != null ? '继续阅读' : '开始阅读'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 圆形图标按钮 ──

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color:
              (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black)
                  .withValues(alpha: 0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: cs.onSurface),
      ),
    );
  }
}
