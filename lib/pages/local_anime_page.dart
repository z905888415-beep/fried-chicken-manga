import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/anime_download_manager.dart';
import '../utils/toast.dart';
import 'anime_detail_page.dart';
import 'anime_player_page.dart';

class LocalAnimePage extends StatefulWidget {
  final bool embedded;

  const LocalAnimePage({super.key, this.embedded = false});

  @override
  State<LocalAnimePage> createState() => _LocalAnimePageState();
}

class _LocalAnimePageState extends State<LocalAnimePage> {
  final _downloads = AnimeDownloadManager();
  final Set<String> _selectedPathWords = {};
  bool _selectionMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_handleChanged);
    _initialize();
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    if (!mounted) return;
    final valid = _downloads
        .localAnimes()
        .map((item) => item.info.anime.pathWord)
        .toSet();
    _selectedPathWords.removeWhere((pathWord) => !valid.contains(pathWord));
    if (_selectedPathWords.isEmpty) _selectionMode = false;
    setState(() {});
  }

  Future<void> _initialize() async {
    await _downloads.init();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _deleteSelected() async {
    if (_selectedPathWords.isEmpty) return;
    final count = _selectedPathWords.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除本地动漫'),
        content: Text('确定删除选中的 $count 部本地动漫吗？已下载视频和封面都会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _downloads.deleteLocalAnimes(_selectedPathWords);
    if (!mounted) return;
    setState(() {
      _selectedPathWords.clear();
      _selectionMode = false;
    });
    showToast(context, '已删除 $count 部本地动漫');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final items = _downloads.localAnimes();

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : items.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.download_done_outlined,
                  size: 56,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text('还没有本地动漫', style: tt.titleMedium),
                const SizedBox(height: 6),
                Text(
                  '去动漫详情页下载剧集后，这里会显示离线内容',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          )
        : GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              childAspectRatio: 0.6,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (_, index) {
              final item = items[index];
              final pathWord = item.info.anime.pathWord;
              final selected = _selectedPathWords.contains(pathWord);
              return _LocalAnimeCard(
                entry: item,
                selected: selected,
                selectionMode: _selectionMode,
                onTap: () {
                  if (_selectionMode) {
                    setState(() {
                      if (selected) {
                        _selectedPathWords.remove(pathWord);
                      } else {
                        _selectedPathWords.add(pathWord);
                      }
                      if (_selectedPathWords.isEmpty) _selectionMode = false;
                    });
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LocalAnimeDetailPage(pathWord: pathWord),
                    ),
                  );
                },
                onLongPress: () => setState(() {
                  _selectionMode = true;
                  _selectedPathWords.add(pathWord);
                }),
              );
            },
          );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? '已选 ${_selectedPathWords.length} 部' : '本地动漫',
        ),
        actions: [
          if (!_selectionMode && items.isNotEmpty)
            IconButton(
              onPressed: () => setState(() => _selectionMode = true),
              icon: const Icon(Icons.checklist),
              tooltip: '批量管理',
            ),
          if (_selectionMode) ...[
            IconButton(
              onPressed: items.isEmpty
                  ? null
                  : () => setState(() {
                      _selectedPathWords
                        ..clear()
                        ..addAll(items.map((item) => item.info.anime.pathWord));
                    }),
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
            ),
            IconButton(
              onPressed: _selectedPathWords.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
            ),
            IconButton(
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedPathWords.clear();
              }),
              icon: const Icon(Icons.close),
              tooltip: '取消',
            ),
          ],
        ],
      ),
      body: body,
    );
  }
}

class _LocalAnimeCard extends StatelessWidget {
  final LocalAnimeEntry entry;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LocalAnimeCard({
    required this.entry,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final anime = entry.info.anime;
    final coverPath = entry.info.coverPath;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? cs.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox.expand(
                        child: coverPath != null && File(coverPath).existsSync()
                            ? Image.file(File(coverPath), fit: BoxFit.cover)
                            : ColoredBox(
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  Icons.movie_outlined,
                                  color: cs.onSurfaceVariant,
                                  size: 32,
                                ),
                              ),
                      ),
                    ),
                    if (selectionMode)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: selected ? cs.primary : Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              selected ? Icons.check : Icons.circle_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '已下载 ${entry.downloadedCount} 集',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  anime.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall,
                ),
              ),
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  anime.pathWord,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LocalAnimeDetailPage extends StatefulWidget {
  final String pathWord;

  const LocalAnimeDetailPage({super.key, required this.pathWord});

  @override
  State<LocalAnimeDetailPage> createState() => _LocalAnimeDetailPageState();
}

class _LocalAnimeDetailPageState extends State<LocalAnimeDetailPage> {
  final _downloads = AnimeDownloadManager();
  final Set<String> _selectedChapterIds = {};
  bool _selectionMode = false;
  bool _didPopAfterDeletion = false;

  @override
  void initState() {
    super.initState();
    _downloads.addListener(_handleChanged);
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    if (!mounted) return;
    final info = _downloads.getLocalAnimeInfo(widget.pathWord);
    if (info == null ||
        _downloads.downloadedChapters(widget.pathWord).isEmpty) {
      if (_didPopAfterDeletion) return;
      _didPopAfterDeletion = true;
      Navigator.pop(context);
      return;
    }
    final validIds = _downloads
        .downloadedChapters(widget.pathWord)
        .map((item) => item.chapterUuid)
        .toSet();
    _selectedChapterIds.removeWhere((id) => !validIds.contains(id));
    if (_selectedChapterIds.isEmpty) _selectionMode = false;
    setState(() {});
  }

  Future<void> _deleteSelected() async {
    if (_selectedChapterIds.isEmpty) return;
    final count = _selectedChapterIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除本地剧集'),
        content: Text('确定删除选中的 $count 个剧集吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _downloads.deleteChapters(widget.pathWord, _selectedChapterIds);
    if (!mounted) return;
    showToast(context, '已删除 $count 个剧集');
    final remain = _downloads.downloadedChapters(widget.pathWord);
    if (remain.isEmpty) return;
    setState(() {
      _selectedChapterIds.clear();
      _selectionMode = false;
    });
  }

  void _playChapter(DownloadedAnimeChapterSummary summary) {
    final videoPath = _downloads.getLocalVideoPath(
      widget.pathWord,
      summary.chapterUuid,
    );
    if (videoPath == null || !File(videoPath).existsSync()) {
      showToast(context, '视频文件不存在', isError: true);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnimePlayerPage(
          animeName:
              _downloads.getLocalAnimeInfo(widget.pathWord)?.anime.name ?? '',
          pathWord: widget.pathWord,
          chapterUuid: summary.chapterUuid,
          chapterName: summary.chapterName,
          line: '',
          localVideoPath: videoPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final info = _downloads.getLocalAnimeInfo(widget.pathWord);
    final chapters = _downloads.downloadedChapters(widget.pathWord);

    if (info == null || chapters.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final anime = info.anime;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? '已选 ${_selectedChapterIds.length} 集' : anime.name,
        ),
        actions: [
          if (!_selectionMode)
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AnimeDetailPage(
                    pathWord: widget.pathWord,
                    initialAnime: anime,
                  ),
                ),
              ),
              icon: const Icon(Icons.public),
              tooltip: '查看在线详情',
            ),
          if (!_selectionMode)
            IconButton(
              onPressed: () => setState(() => _selectionMode = true),
              icon: const Icon(Icons.checklist),
              tooltip: '管理剧集',
            ),
          if (_selectionMode) ...[
            IconButton(
              onPressed: () => setState(() {
                _selectedChapterIds
                  ..clear()
                  ..addAll(chapters.map((item) => item.chapterUuid));
              }),
              icon: const Icon(Icons.select_all),
              tooltip: '全选',
            ),
            IconButton(
              onPressed: _selectedChapterIds.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
            ),
            IconButton(
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedChapterIds.clear();
              }),
              icon: const Icon(Icons.close),
              tooltip: '取消',
            ),
          ],
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 110,
                      height: 150,
                      child:
                          info.coverPath != null &&
                              File(info.coverPath!).existsSync()
                          ? Image.file(File(info.coverPath!), fit: BoxFit.cover)
                          : ColoredBox(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                Icons.movie_outlined,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (anime.company != null)
                          Text(anime.company!.name, style: tt.bodyMedium),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (anime.category?['display'] != null)
                              _DetailChip(
                                label: anime.category!['display'].toString(),
                              ),
                            if (anime.grade?['display'] != null)
                              _DetailChip(
                                label: anime.grade!['display'].toString(),
                              ),
                            ...anime.themes.map(
                              (item) => _DetailChip(label: item.name),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '已下载 ${chapters.length} 集',
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (anime.brief != null && anime.brief!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  anime.brief!,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '本地剧集 (${chapters.length})',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 100,
                childAspectRatio: 1.8,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate((_, index) {
                final chapter = chapters[index];
                final selected = _selectedChapterIds.contains(
                  chapter.chapterUuid,
                );
                return _LocalAnimeChapterCard(
                  summary: chapter,
                  selected: selected,
                  selectionMode: _selectionMode,
                  onTap: () {
                    if (_selectionMode) {
                      setState(() {
                        if (selected) {
                          _selectedChapterIds.remove(chapter.chapterUuid);
                        } else {
                          _selectedChapterIds.add(chapter.chapterUuid);
                        }
                        if (_selectedChapterIds.isEmpty) {
                          _selectionMode = false;
                        }
                      });
                      return;
                    }
                    _playChapter(chapter);
                  },
                  onLongPress: () => setState(() {
                    _selectionMode = true;
                    _selectedChapterIds.add(chapter.chapterUuid);
                  }),
                );
              }, childCount: chapters.length),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalAnimeChapterCard extends StatelessWidget {
  final DownloadedAnimeChapterSummary summary;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LocalAnimeChapterCard({
    required this.summary,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Center(
                child: Text(
                  summary.chapterName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ),
            ),
            if (selectionMode)
              Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  size: 20,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final String label;

  const _DetailChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: cs.onSecondaryContainer),
      ),
    );
  }
}
