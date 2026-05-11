import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/anime.dart';
import '../utils/data_cache.dart';
import '../utils/toast.dart';
import 'anime_player_page.dart';
import 'home_page.dart';

class AnimeDetailPage extends StatefulWidget {
  final String pathWord;
  final Anime? initialAnime;

  const AnimeDetailPage({super.key, required this.pathWord, this.initialAnime});

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
}

class _AnimeDetailPageState extends State<AnimeDetailPage> {
  final _api = ApiClient();
  final _cache = DataCache();
  Anime? _anime;
  List<AnimeChapter> _chapters = [];
  int _chapterTotal = 0;
  bool _loadingDetail = true;
  bool _loadingChapters = true;
  bool _briefExpanded = false;
  bool _isCollected = false;
  bool _collectSubmitting = false;
  String? _error;

  String get _cacheKey => 'anime_detail_${widget.pathWord}';

  @override
  void initState() {
    super.initState();
    _anime = widget.initialAnime;
    _loadingDetail = widget.initialAnime == null;
    _loadFromCache();
    _load();
  }

  Future<void> _loadFromCache() async {
    final cached = await _cache.get(_cacheKey);
    if (!mounted || cached is! Map) return;
    final animeJson = cached['anime'];
    if (animeJson is! Map) return;

    setState(() {
      _anime = Anime.fromJson(Map<String, dynamic>.from(animeJson));
      _chapters =
          (cached['chapters'] as List?)
              ?.map((e) => AnimeChapter.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [];
      _chapterTotal = cached['chapterTotal'] as int? ?? _chapters.length;
      _isCollected = cached['isCollected'] == true;
      _loadingDetail = false;
      _loadingChapters = false;
    });
  }

  Future<void> _saveCache() async {
    final anime = _anime;
    if (anime == null) return;
    await _cache.put(_cacheKey, {
      'anime': anime.toJson(),
      'chapters': _chapters
          .map(
            (e) => {
              'name': e.name,
              'uuid': e.uuid,
              'v_cover': e.vCover,
              'lines': e.lines
                  .map(
                    (line) => {
                      'name': line.name,
                      'path_word': line.pathWord,
                      'config': line.config,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
      'chapterTotal': _chapterTotal,
      'isCollected': _isCollected,
    });
  }

  Future<void> _load() async {
    if (_anime == null) {
      setState(() {
        _loadingDetail = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _api.getAnimeDetail(widget.pathWord),
        _api.getAnimeChapters(widget.pathWord),
      ]);
      final detail = results[0] as Anime;
      final chapters = results[1] as ({List<AnimeChapter> list, int total});
      AnimeQuery? query;
      try {
        query = await _api.getAnimeQuery(widget.pathWord);
      } catch (_) {
        query = null;
      }

      if (!mounted) return;
      setState(() {
        _anime = detail;
        _chapters = chapters.list;
        _chapterTotal = chapters.total;
        _isCollected = query?.isCollected ?? false;
        _loadingDetail = false;
        _loadingChapters = false;
        _error = null;
      });
      await _saveCache();
    } catch (e) {
      debugPrint('AnimeDetailPage load error: $e');
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _loadingChapters = false;
        _error = e.toString();
      });
    }
  }

  void _openChapter(AnimeChapter chapter) {
    final line = _resolveChapterLine(chapter);
    if (line == null || line.isEmpty) {
      showToast(context, '当前选集暂无可用线路', isError: true);
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnimePlayerPage(
          animeName:
              widget.initialAnime?.name ?? _anime?.name ?? widget.pathWord,
          pathWord: widget.pathWord,
          chapterUuid: chapter.uuid,
          chapterName: chapter.name,
          line: line,
          chapters: _chapters,
        ),
      ),
    );
  }

  String? _resolveChapterLine(AnimeChapter chapter) {
    for (final line in chapter.lines) {
      if (line.config && line.pathWord.isNotEmpty) return line.pathWord;
    }
    for (final line in chapter.lines) {
      if (line.pathWord.isNotEmpty) return line.pathWord;
    }
    return null;
  }

  Future<void> _toggleCollect() async {
    final anime = _anime;
    final cartoonId = anime?.uuid;
    if (anime == null || cartoonId == null || cartoonId.isEmpty) {
      showToast(context, '当前动漫暂时无法收藏', isError: true);
      return;
    }
    if (_collectSubmitting) return;

    final nextState = !_isCollected;
    setState(() {
      _isCollected = nextState;
      _collectSubmitting = true;
    });

    try {
      await _api.toggleAnimeCollect(cartoonId, collect: nextState);
      await _saveCache();
      if (!mounted) return;
      showToast(context, nextState ? '已收藏' : '已取消收藏');
    } catch (e) {
      debugPrint('AnimeDetailPage toggleCollect error: $e');
      if (!mounted) return;
      setState(() => _isCollected = !nextState);
      await _saveCache();
      if (!mounted) return;
      showToast(context, '收藏状态修改失败', isError: true);
    } finally {
      if (mounted) setState(() => _collectSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anime = _anime;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 900 ? screenWidth : 900.0;
    final hp = (screenWidth - contentWidth) / 2 + 16;

    if (_loadingDetail && anime == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null && anime == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
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
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 280,
              title: Text(
                anime?.name ?? '动漫详情',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              flexibleSpace: anime == null
                  ? null
                  : FlexibleSpaceBar(
                      background: _AnimeDetailHeader(
                        anime: anime,
                        isCollected: _isCollected,
                      ),
                    ),
            ),
            if (_loadingDetail)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            if (anime != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(hp, 18, hp, 0),
                  child: _AnimeInfoPanel(
                    anime: anime,
                    isCollected: _isCollected,
                    collectSubmitting: _collectSubmitting,
                    briefExpanded: _briefExpanded,
                    onToggleCollect: _toggleCollect,
                    onToggleBrief: () {
                      setState(() => _briefExpanded = !_briefExpanded);
                    },
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 24, hp, 12),
                child: Row(
                  children: [
                    Icon(Icons.video_library_outlined, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      '选集 ($_chapterTotal)',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loadingChapters)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_chapters.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text('暂无选集', style: tt.bodyMedium)),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: hp),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 1.45,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _AnimeChapterCard(
                      chapter: _chapters[i],
                      onTap: () => _openChapter(_chapters[i]),
                    ),
                    childCount: _chapters.length,
                  ),
                ),
              ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
          ],
        ),
      ),
    );
  }
}

class _AnimeDetailHeader extends StatelessWidget {
  final Anime anime;
  final bool isCollected;

  const _AnimeDetailHeader({required this.anime, required this.isCollected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: anime.cover,
          fit: BoxFit.cover,
          placeholder: (_, _) => Container(color: cs.surfaceContainerHighest),
          errorWidget: (_, _, _) => Container(
            color: cs.surfaceContainerHighest,
            child: Icon(Icons.broken_image, color: cs.onSurfaceVariant),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.78),
              ],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: CachedNetworkImage(
                  imageUrl: anime.cover,
                  width: 96,
                  height: 124,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      anime.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _HeaderPill(
                          icon: Icons.local_fire_department,
                          text: ComicCard.formatPopular(anime.popular),
                        ),
                        if (anime.count > 0)
                          _HeaderPill(
                            icon: Icons.video_collection_outlined,
                            text: '共 ${anime.count} 集',
                          ),
                        if (isCollected)
                          const _HeaderPill(icon: Icons.bookmark, text: '已收藏'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnimeInfoPanel extends StatelessWidget {
  final Anime anime;
  final bool isCollected;
  final bool collectSubmitting;
  final bool briefExpanded;
  final VoidCallback onToggleCollect;
  final VoidCallback onToggleBrief;

  const _AnimeInfoPanel({
    required this.anime,
    required this.isCollected,
    required this.collectSubmitting,
    required this.briefExpanded,
    required this.onToggleCollect,
    required this.onToggleBrief,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final chips = <Widget>[
      if (anime.category?['display'] != null)
        _InfoChip(text: anime.category!['display'].toString()),
      if (anime.cartoonType?['display'] != null)
        _InfoChip(text: anime.cartoonType!['display'].toString()),
      if (anime.grade?['display'] != null)
        _InfoChip(text: anime.grade!['display'].toString()),
      if (anime.freeType?['display'] != null)
        _InfoChip(text: anime.freeType!['display'].toString()),
      if (anime.bSubtitle) const _InfoChip(text: '字幕'),
      ...anime.themes.map((e) => _InfoChip(text: e.name)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: collectSubmitting ? null : onToggleCollect,
              icon: Icon(isCollected ? Icons.bookmark : Icons.bookmark_border),
              label: Text(
                collectSubmitting ? '处理中' : (isCollected ? '已收藏' : '收藏'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (anime.company != null || anime.years != null)
          Text(
            [
              if (anime.company != null) anime.company!.name,
              if (anime.years != null) anime.years!,
            ].join(' · '),
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        if (anime.lastChapter?['name'] != null) ...[
          const SizedBox(height: 6),
          Text(
            '最新：${anime.lastChapter!['name']}',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (anime.brief != null && anime.brief!.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            '简介',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onToggleBrief,
            child: Text(
              anime.brief!,
              maxLines: briefExpanded ? null : 4,
              overflow: briefExpanded ? null : TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ],
    );
  }
}

class _AnimeChapterCard extends StatelessWidget {
  final AnimeChapter chapter;
  final VoidCallback onTap;

  const _AnimeChapterCard({required this.chapter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: chapter.vCover,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                color: cs.surfaceContainerHighest,
                child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant),
              ),
              errorWidget: (_, _, _) => Container(
                color: cs.surfaceContainerHighest,
                child: Icon(Icons.broken_image, color: cs.onSurfaceVariant),
              ),
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
              left: 10,
              right: 10,
              bottom: 8,
              child: Text(
                chapter.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String text;

  const _InfoChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeaderPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
