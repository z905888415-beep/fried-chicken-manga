import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/anime.dart';
import '../utils/anime_download_manager.dart';
import '../utils/data_cache.dart';
import '../utils/toast.dart';
import 'anime_player_page.dart';
import 'download_center_page.dart';
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
  final _downloads = AnimeDownloadManager();
  Anime? _anime;
  List<AnimeChapter> _chapters = [];
  int _chapterTotal = 0;
  bool _loadingDetail = true;
  bool _loadingChapters = true;
  bool _briefExpanded = false;
  bool _isCollected = false;
  bool _collectSubmitting = false;
  String? _error;

  // 批量下载选择
  final Set<String> _selectedUuids = {};
  bool _selectionMode = false;

  String get _cacheKey => 'anime_detail_${widget.pathWord}';

  @override
  void initState() {
    super.initState();
    _anime = widget.initialAnime;
    _loadingDetail = widget.initialAnime == null;
    _downloads.addListener(_onDownloadsChanged);
    _loadFromCache();
    _load();
  }

  @override
  void dispose() {
    _downloads.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (mounted) setState(() {});
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

  void _toggleSelection(String uuid) {
    setState(() {
      if (_selectedUuids.contains(uuid)) {
        _selectedUuids.remove(uuid);
        if (_selectedUuids.isEmpty) _selectionMode = false;
      } else {
        _selectedUuids.add(uuid);
      }
    });
  }

  void _enterSelectionMode(String uuid) {
    setState(() {
      _selectionMode = true;
      _selectedUuids.add(uuid);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedUuids.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedUuids.addAll(
        _chapters
            .where((c) =>
                !_downloads.isDownloaded(widget.pathWord, c.uuid) &&
                !_downloads.isInQueue(widget.pathWord, c.uuid))
            .map((c) => c.uuid),
      );
    });
  }

  Future<void> _batchDownload() async {
    final anime = _anime;
    if (anime == null || _selectedUuids.isEmpty) return;

    await _downloads.init();
    if (!mounted) return;

    // 用第一个选中章节的线路
    final first = _chapters.firstWhere(
      (c) => _selectedUuids.contains(c.uuid),
      orElse: () => _chapters.first,
    );
    final line = _resolveChapterLine(first);
    if (line == null || line.isEmpty) {
      showToast(context, '当前选集暂无可用线路，无法下载', isError: true);
      return;
    }

    final toDownload = _chapters
        .where((c) => _selectedUuids.contains(c.uuid))
        .toList();

    final added = await _downloads.enqueueChapters(
      pathWord: widget.pathWord,
      anime: anime,
      chapters: toDownload,
      line: line,
    );

    if (mounted) {
      showToast(context, '已添加 $added 个下载任务');
    }
    _exitSelectionMode();
  }

  Future<void> _downloadSingle(AnimeChapter chapter) async {
    final anime = _anime;
    if (anime == null) return;
    await _downloads.init();
    if (!mounted) return;

    final line = _resolveChapterLine(chapter);
    if (line == null || line.isEmpty) {
      showToast(context, '当前选集暂无可用线路，无法下载', isError: true);
      return;
    }

    if (_downloads.isDownloaded(widget.pathWord, chapter.uuid)) {
      showToast(context, '该集已下载');
      return;
    }

    if (_downloads.isInQueue(widget.pathWord, chapter.uuid)) {
      showToast(context, '该集已在下载队列中');
      return;
    }

    await _downloads.enqueueChapters(
      pathWord: widget.pathWord,
      anime: anime,
      chapters: [chapter],
      line: line,
    );
    if (mounted) showToast(context, '已添加到下载队列');
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

  Widget? _buildDownloadFab(ColorScheme cs) {
    final count = _downloads.tasks
        .where((t) => t.pathWord == widget.pathWord)
        .length;
    if (count == 0) return null;
    return FloatingActionButton.extended(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const DownloadCenterPage(initialTab: 2),
        ),
      ),
      icon: const Icon(Icons.downloading_outlined),
      label: Text('$count 个任务'),
    );
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
      floatingActionButton: _buildDownloadFab(cs),
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
                    Expanded(
                      child: Text(
                        _selectionMode
                            ? '已选 ${_selectedUuids.length} 集'
                            : '选集 ($_chapterTotal)',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_selectionMode) ...[
                      TextButton(
                        onPressed: _selectAll,
                        child: const Text('全选未下载'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.tonal(
                        onPressed:
                            _selectedUuids.isEmpty ? null : _batchDownload,
                        child: const Text('下载选中'),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: _exitSelectionMode,
                        icon: const Icon(Icons.close),
                        tooltip: '取消',
                      ),
                    ] else if (_chapters.isNotEmpty)
                      IconButton(
                        onPressed: () => setState(() => _selectionMode = true),
                        icon: const Icon(Icons.checklist),
                        tooltip: '批量选择',
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
                    (_, i) {
                      final chapter = _chapters[i];
                      final selected = _selectedUuids.contains(chapter.uuid);
                      final downloaded = _downloads.isDownloaded(
                        widget.pathWord, chapter.uuid);
                      final taskInfo = _downloads.taskInfo(
                        widget.pathWord, chapter.uuid);
                      final inQueue = taskInfo != null;

                      return _AnimeChapterCard(
                        chapter: chapter,
                        selected: selected,
                        selectionMode: _selectionMode,
                        isDownloaded: downloaded,
                        isDownloading: taskInfo?.status == DownloadTaskStatus.downloading,
                        isQueued: inQueue && taskInfo.status != DownloadTaskStatus.downloading,
                        progress: _downloads.progressOf(widget.pathWord, chapter.uuid),
                        onTap: () {
                          if (_selectionMode) {
                            _toggleSelection(chapter.uuid);
                            return;
                          }
                          _openChapter(chapter);
                        },
                        onLongPress: () => _enterSelectionMode(chapter.uuid),
                        onDownload: () => _downloadSingle(chapter),
                      );
                    },
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
  final bool selected;
  final bool selectionMode;
  final bool isDownloaded;
  final bool isDownloading;
  final bool isQueued;
  final AnimeChapterDownloadProgress? progress;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDownload;

  const _AnimeChapterCard({
    required this.chapter,
    required this.selected,
    required this.selectionMode,
    required this.isDownloaded,
    required this.isDownloading,
    required this.isQueued,
    required this.progress,
    required this.onTap,
    required this.onLongPress,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: selected
              ? BorderSide(color: cs.primary, width: 2)
              : BorderSide.none,
        ),
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
            if (selectionMode)
              Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? cs.primary : Colors.white70,
                  size: 22,
                ),
              ),
            if (isDownloading && progress != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress!.ratio,
                  backgroundColor: Colors.transparent,
                  color: cs.primary,
                ),
              ),
            Positioned(
              left: 10,
              right: selectionMode ? 10 : 36,
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
            if (!selectionMode)
              Positioned(
                right: 4,
                bottom: 4,
                child: _buildDownloadButton(cs),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadButton(ColorScheme cs) {
    if (isDownloaded) {
      return const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(Icons.download_done, color: Colors.greenAccent, size: 18),
      );
    }
    if (isDownloading) {
      return const Padding(
        padding: EdgeInsets.all(6),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
      );
    }
    if (isQueued) {
      return const Padding(
        padding: EdgeInsets.all(6),
        child: Icon(Icons.hourglass_bottom, color: Colors.orangeAccent, size: 18),
      );
    }
    return Material(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onDownload,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(Icons.download_outlined, color: Colors.white, size: 18),
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