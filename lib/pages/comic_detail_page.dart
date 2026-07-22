import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../models/chapter.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/comic_hero_tags.dart';
import '../utils/data_cache.dart';
import '../utils/download_manager.dart';
import '../utils/local_favorites.dart';
import '../utils/reading_history.dart';
import '../utils/toast.dart';
import '../widgets/circle_icon_button.dart';
import '../widgets/kira_app_bar.dart';
import '../widgets/state_views.dart';
import 'comic_comments_sheet.dart';
import 'reader_page.dart';

class ComicDetailPage extends StatefulWidget {
  final String pathWord;
  final Comic? initialComic;
  final String? heroTagBase;
  final String? lastBrowseId;
  final String? lastBrowseName;
  const ComicDetailPage({
    super.key,
    required this.pathWord,
    this.initialComic,
    this.heroTagBase,
    this.lastBrowseId,
    this.lastBrowseName,
  });

  static Route<void> route({
    required String pathWord,
    Comic? initialComic,
    String? heroTagBase,
    String? lastBrowseId,
    String? lastBrowseName,
  }) {
    return PageRouteBuilder<void>(
      transitionDuration: ComicHeroTags.transitionDuration,
      reverseTransitionDuration: ComicHeroTags.reverseTransitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) => ComicDetailPage(
        pathWord: pathWord,
        initialComic: initialComic,
        heroTagBase: heroTagBase,
        lastBrowseId: lastBrowseId,
        lastBrowseName: lastBrowseName,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (animation.status == AnimationStatus.reverse) {
          return Opacity(opacity: 0, child: child);
        }
        return child;
      },
    );
  }

  @override
  State<ComicDetailPage> createState() => _ComicDetailPageState();
}

class _ComicDetailPageState extends State<ComicDetailPage> {
  static const _continueReadingNameMaxLength = 10;
  static const _nextChapterNameMaxLength = 10;

  final _api = ApiClient();
  final _cache = DataCache();
  final _downloads = DownloadManager();
  Comic? _comic;
  List<Chapter> _chapters = [];
  final Set<String> _selectedChapterIds = {};
  String _selectedGroup = 'default';
  bool _loadingComic = true;
  bool _loadingChapters = false;
  bool _keepShowingCachedChapters = false;
  int _chapterTotal = 0;
  int _chapterPage = 0; // 当前页码（0-based）
  static const _pageSize = 100;
  // 会话内章节分页缓存：key 为 "group:page"，离开详情页时随 State 一起销毁
  final Map<String, ({List<Chapter> list, int total})> _chapterPageCache = {};
  bool _briefExpanded = false;
  bool _reversed = false;
  bool _isCollected = false;
  bool _selectionMode = false;
  Chapter? _nextBrowseChapter;
  String? _nextBrowseChapterSourceId;
  bool _loadingNextBrowseChapter = false;
  // 本地阅读记录（优先级高于书架传入的记录）
  late final String? _officialLastBrowseId;
  late final String? _officialLastBrowseName;
  bool _usingLocalHistory = false;
  String? _lastBrowseId;
  String? _lastBrowseName;
  int _lastBrowsePage = 1;
  int _lastBrowseTotalPage = 0;

  String get _cacheKey => 'comic_detail_${widget.pathWord}';

  @override
  void initState() {
    super.initState();
    _comic = widget.initialComic;
    _loadingComic = widget.initialComic == null;
    _officialLastBrowseId = widget.lastBrowseId;
    _officialLastBrowseName = widget.lastBrowseName;
    _lastBrowseId = widget.lastBrowseId;
    _lastBrowseName = widget.lastBrowseName;
    if (_lastBrowseId != null) _reversed = true;
    _downloads.addListener(_handleDownloadChanged);
    _initializePage();
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleDownloadChanged);
    super.dispose();
  }

  Future<void> _initializePage() async {
    await Future.wait([_downloads.init(), _loadFromCache()]);
    await _loadLocalHistory();
    await _loadLocalFavoriteState();
    await _loadComic();
  }

  void _handleDownloadChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadLocalFavoriteState() async {
    final isFavorite = await LocalFavorites.contains(widget.pathWord);
    if (!mounted) return;
    setState(() => _isCollected = isFavorite || _isCollected);
  }

  Future<void> _loadLocalHistory({String? group}) async {
    final targetGroup = group ?? _selectedGroup;
    final record = await ReadingHistory.get(
      widget.pathWord,
      group: targetGroup,
    );
    if (!mounted || targetGroup != _selectedGroup) return;

    setState(() {
      _usingLocalHistory = record != null;
      _lastBrowseId = record?.chapterUuid ?? _officialLastBrowseId;
      _lastBrowseName = record?.chapterName ?? _officialLastBrowseName;
      _lastBrowsePage = record?.page ?? 1;
      _lastBrowseTotalPage = record?.totalPage ?? 0;
      if (_lastBrowseId != null) _reversed = true;
    });
    await _syncNextBrowseChapter();
  }

  Future<void> _loadFromCache() async {
    final cached = await _cache.get(_cacheKey);
    if (cached is! Map) return;
    final comicJson = cached['comic'];
    if (comicJson is! Map) return;

    final comic = Comic.fromJson(Map<String, dynamic>.from(comicJson));
    final cachedGroup = cached['selectedGroup']?.toString();
    final selectedGroup = _resolveSelectedGroup(
      comic,
      preferredGroup: cachedGroup,
    );
    final canReuseCachedChapters =
        cachedGroup == null || cachedGroup == selectedGroup;
    final cachedChapters = canReuseCachedChapters
        ? (cached['chapters'] as List?)
                  ?.map((j) => Chapter.fromJson(Map<String, dynamic>.from(j)))
                  .toList() ??
              []
        : <Chapter>[];

    if (!mounted) return;
    setState(() {
      _comic = comic;
      _selectedGroup = selectedGroup;
      _chapters = cachedChapters;
      _chapterTotal = canReuseCachedChapters ? cached['chapterTotal'] ?? 0 : 0;
      _chapterPage = canReuseCachedChapters ? cached['chapterPage'] ?? 0 : 0;
      _isCollected = cached['isCollected'] == true;
      _loadingComic = false;
    });
    await _syncNextBrowseChapter();
  }

  Future<void> _saveCache() async {
    final comic = _comic;
    if (comic == null) return;
    await _cache.put(_cacheKey, {
      'comic': comic.toJson(),
      'selectedGroup': _selectedGroup,
      'chapterPage': _chapterPage,
      'chapterTotal': _chapterTotal,
      'chapters': _chapters.map((c) => c.toJson()).toList(),
      'isCollected': _isCollected,
    });
  }

  String _resolveSelectedGroup(Comic comic, {String? preferredGroup}) {
    final groups = comic.groups;
    if (groups != null && groups.isNotEmpty) {
      if (preferredGroup != null && groups.containsKey(preferredGroup)) {
        return preferredGroup;
      }
      return groups.keys.first;
    }
    return 'default';
  }

  Future<void> _loadComic() async {
    final showRefreshNotice = _comic != null;
    if (mounted) {
      setState(() {
        if (!showRefreshNotice) {
          _loadingComic = true;
        }
      });
    }

    try {
      final comic = await _api.getComicDetail(widget.pathWord);
      if (!mounted) return;
      final selectedGroup = _resolveSelectedGroup(
        comic,
        preferredGroup: _selectedGroup,
      );

      setState(() {
        _comic = comic;
        _loadingComic = false;
        _selectedGroup = selectedGroup;
      });

      await _loadLocalHistory(group: selectedGroup);
      await _saveCache();
      await _loadChapterPageForHistory(comic: comic, group: selectedGroup);
      await _loadCollectState();
    } catch (_) {
      if (mounted) setState(() => _loadingComic = false);
    }
  }

  Future<void> _loadCollectState() async {
    final localFavorite = await LocalFavorites.contains(widget.pathWord);
    try {
      final query = await _api.getComicQuery(widget.pathWord);
      if (!mounted) return;
      setState(() => _isCollected = localFavorite || query['collect'] != null);
      await _saveCache();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCollected = localFavorite);
      await _saveCache();
    }
  }

  Future<void> _loadChapterPage(
    int page, {
    String? group,
    bool keepVisibleDuringLoad = false,
    bool forceRefresh = false,
  }) async {
    if (_loadingChapters) return;
    final targetGroup = group ?? _selectedGroup;
    final cacheKey = '$targetGroup:$page';

    // 命中会话内缓存：直接复用，避免重复请求
    if (!forceRefresh) {
      final cached = _chapterPageCache[cacheKey];
      if (cached != null) {
        setState(() {
          _chapters = cached.list;
          _chapterTotal = cached.total;
          _chapterPage = page;
          _selectedGroup = targetGroup;
          _loadingChapters = false;
          _keepShowingCachedChapters = false;
          _selectionMode = false;
          _selectedChapterIds.clear();
        });
        await _saveCache();
        await _syncNextBrowseChapter();
        return;
      }
    }

    setState(() {
      _loadingChapters = true;
      _keepShowingCachedChapters =
          keepVisibleDuringLoad &&
          _chapters.isNotEmpty &&
          targetGroup == _selectedGroup &&
          page == _chapterPage;
      _selectionMode = false;
      _selectedChapterIds.clear();
    });

    try {
      final result = await _api.getChapterList(
        widget.pathWord,
        group: targetGroup,
        limit: _pageSize,
        offset: page * _pageSize,
      );
      if (!mounted) return;
      _chapterPageCache[cacheKey] = result;
      setState(() {
        _chapters = result.list;
        _chapterTotal = result.total;
        _chapterPage = page;
        _selectedGroup = targetGroup;
        _loadingChapters = false;
        _keepShowingCachedChapters = false;
      });
      await _saveCache();
      await _syncNextBrowseChapter();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingChapters = false;
          _keepShowingCachedChapters = false;
        });
      }
    }
  }

  int get _totalPages => (_chapterTotal / _pageSize).ceil();

  /// 根据阅读记录中的章节名提取数字，自动跳到对应分页
  Future<void> _loadChapterPageForHistory({Comic? comic, String? group}) async {
    final targetGroup = group ?? _selectedGroup;
    final total =
        comic?.groups?[targetGroup]?.count ??
        _comic?.groups?[targetGroup]?.count ??
        0;
    final page = _resolveHistoryChapterPage(total);
    await _loadChapterPage(
      page,
      group: targetGroup,
      keepVisibleDuringLoad:
          targetGroup == _selectedGroup &&
          page == _chapterPage &&
          _chapters.isNotEmpty,
    );
  }

  int _resolveHistoryChapterPage(int total) {
    if (_lastBrowseName == null || total <= _pageSize) return 0;
    final match = RegExp(r'第(\d+)[话集章回卷]').firstMatch(_lastBrowseName!);
    if (match == null) return 0;

    final num = int.parse(match.group(1)!);
    final totalPages = (total / _pageSize).ceil();
    return ((num - 1) / _pageSize).floor().clamp(0, totalPages - 1);
  }

  Chapter? _chapterByUuid(String? uuid) {
    if (uuid == null || uuid.isEmpty) return null;
    for (final chapter in _chapters) {
      if (chapter.uuid == uuid) return chapter;
    }
    return null;
  }

  bool get _isLastBrowseComplete {
    if (_lastBrowseTotalPage <= 0) return false;
    final unreadThreshold = _lastBrowseTotalPage <= 1
        ? 1
        : _lastBrowseTotalPage - 1;
    return _lastBrowsePage >= unreadThreshold;
  }

  bool get _canShowLastBrowseAction {
    if (_lastBrowseId == null) return false;
    if (_usingLocalHistory) return true;
    return _chapterByUuid(_lastBrowseId) != null;
  }

  String _continueReadingLabel() {
    final name = _truncateContinueReadingName(_lastBrowseName ?? '');
    if (_lastBrowseTotalPage > 1) {
      return name.isEmpty
          ? '$_lastBrowsePage/$_lastBrowseTotalPage'
          : '$name · $_lastBrowsePage/$_lastBrowseTotalPage';
    }
    return name;
  }

  String _truncateContinueReadingName(String name) {
    return _truncateChapterName(name, maxLength: _continueReadingNameMaxLength);
  }

  String _truncateNextChapterName(String name) {
    return _truncateChapterName(name, maxLength: _nextChapterNameMaxLength);
  }

  String _truncateChapterName(String name, {required int maxLength}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';

    final chars = trimmed.characters;
    if (chars.length <= maxLength) {
      return trimmed;
    }
    return '${chars.take(maxLength).toString()}...';
  }

  Future<void> _syncNextBrowseChapter() async {
    if (!mounted) return;

    final currentChapter = _chapterByUuid(_lastBrowseId);
    final canShowNext =
        currentChapter != null &&
        _isLastBrowseComplete &&
        currentChapter.next != null;

    if (!canShowNext) {
      if (_nextBrowseChapter != null || _nextBrowseChapterSourceId != null) {
        setState(() {
          _nextBrowseChapter = null;
          _nextBrowseChapterSourceId = null;
        });
      }
      return;
    }

    final nextUuid = currentChapter.next!;
    final cachedNext = _chapterByUuid(nextUuid);
    if (cachedNext != null) {
      if (_nextBrowseChapter?.uuid != cachedNext.uuid) {
        setState(() {
          _nextBrowseChapter = cachedNext;
          _nextBrowseChapterSourceId = nextUuid;
        });
      }
      return;
    }

    if (_loadingNextBrowseChapter && _nextBrowseChapterSourceId == nextUuid) {
      return;
    }

    _loadingNextBrowseChapter = true;
    _nextBrowseChapterSourceId = nextUuid;
    try {
      final nextPage = _chapterPage < _totalPages - 1 ? _chapterPage + 1 : null;
      Chapter? nextChapter;
      if (nextPage != null) {
        final cacheKey = '$_selectedGroup:$nextPage';
        final cached = _chapterPageCache[cacheKey];
        final result =
            cached ??
            await _api.getChapterList(
              widget.pathWord,
              group: _selectedGroup,
              limit: _pageSize,
              offset: nextPage * _pageSize,
            );
        if (cached == null) {
          _chapterPageCache[cacheKey] = result;
        }
        for (final chapter in result.list) {
          if (chapter.uuid == nextUuid) {
            nextChapter = chapter;
            break;
          }
        }
      }

      if (nextChapter != null &&
          mounted &&
          _lastBrowseId == currentChapter.uuid) {
        setState(() {
          _nextBrowseChapter = nextChapter;
        });
      } else if (mounted && _lastBrowseId == currentChapter.uuid) {
        setState(() {
          _nextBrowseChapter = null;
        });
      }
    } catch (_) {
      if (mounted && _nextBrowseChapterSourceId == nextUuid) {
        setState(() {
          _nextBrowseChapter = null;
        });
      }
    } finally {
      if (_nextBrowseChapterSourceId == nextUuid) {
        _loadingNextBrowseChapter = false;
      }
    }
  }

  Future<void> _toggleCollect() async {
    final comic = _comic;
    if (comic == null) return;

    final newState = !_isCollected;
    setState(() => _isCollected = newState);
    await LocalFavorites.setFavorite(comic, newState);
    await _saveCache();

    final comicId = comic.uuid;
    if (comicId == null || comicId.isEmpty) return;
    try {
      await _api.toggleCollect(comicId, collect: newState);
    } catch (_) {
      // 本地收藏不依赖登录；账号同步失败时保留本地状态。
    }
  }

  Future<void> _showComicComments() async {
    final comic = _comic;
    final comicId = comic?.uuid;
    if (comic == null || comicId == null || comicId.isEmpty) {
      showToast(context, '当前漫画暂时无法查看评论', isError: true);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ComicCommentsSheet(comicId: comicId, comicName: comic.name),
    );
  }

  bool _isChapterDownloaded(String chapterUuid) =>
      _downloads.isDownloaded(widget.pathWord, chapterUuid);

  bool _isChapterQueued(String chapterUuid) =>
      _downloads.isQueued(widget.pathWord, chapterUuid);

  bool _isChapterSelectable(Chapter chapter) =>
      !_isChapterDownloaded(chapter.uuid) && !_isChapterQueued(chapter.uuid);

  void _enterSelectionMode([String? chapterUuid]) {
    setState(() {
      _selectionMode = true;
      if (chapterUuid != null) {
        _selectedChapterIds.add(chapterUuid);
      }
    });
  }

  void _exitSelectionMode() {
    if (!_selectionMode && _selectedChapterIds.isEmpty) return;
    setState(() {
      _selectionMode = false;
      _selectedChapterIds.clear();
    });
  }

  void _toggleDownloadSelectionMode() {
    if (_selectionMode) {
      _exitSelectionMode();
      return;
    }
    if (_displayChapters.any(_isChapterSelectable)) {
      _enterSelectionMode();
    }
  }

  void _toggleChapterSelection(Chapter chapter) {
    if (!_isChapterSelectable(chapter)) return;
    setState(() {
      _selectionMode = true;
      if (_selectedChapterIds.contains(chapter.uuid)) {
        _selectedChapterIds.remove(chapter.uuid);
      } else {
        _selectedChapterIds.add(chapter.uuid);
      }
      if (_selectedChapterIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _selectAllVisibleDownloadable() {
    final selectableIds = _displayChapters
        .where(_isChapterSelectable)
        .map((chapter) => chapter.uuid)
        .toSet();
    setState(() {
      _selectionMode = true;
      _selectedChapterIds
        ..clear()
        ..addAll(selectableIds);
    });
  }

  Future<void> _downloadSelectedChapters() async {
    final chapters = _displayChapters
        .where((chapter) => _selectedChapterIds.contains(chapter.uuid))
        .where(_isChapterSelectable)
        .toList();

    if (chapters.isEmpty) {
      showToast(context, '请选择未下载的章节', isError: true);
      return;
    }

    final added = await _downloads.enqueueChapters(
      pathWord: widget.pathWord,
      comic: _comic!,
      chapters: chapters,
    );
    if (!mounted) return;

    showToast(context, added > 0 ? '已加入下载队列：$added 章（顺序下载）' : '所选章节已下载或已在队列中');
    _exitSelectionMode();
  }

  void _openReader(Chapter chapter) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReaderPage(
          pathWord: widget.pathWord,
          comicName: _comic?.name,
          coverUrl: _comic?.cover,
          group: _selectedGroup,
          chapterUuid: chapter.uuid,
          chapterName: chapter.name,
        ),
      ),
    ).then((_) => _loadLocalHistory());
  }

  List<Chapter> get _displayChapters =>
      _reversed ? _chapters.reversed.toList() : _chapters;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: KiraAppBar(
        glass: true,
        leading: CircleIconButton(
          glass: true,
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => Navigator.pop(context),
        ),
        actions: [
          CircleIconButton(
            glass: true,
            icon: Icons.share_outlined,
            onTap: () {},
          ),
          const SizedBox(width: 4),
          CircleIconButton(
            glass: true,
            icon: Icons.more_horiz_rounded,
            onTap: () {},
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loadingComic
          ? const LoadingView()
          : _comic == null
          ? ErrorView(message: '加载失败', onRetry: _loadComic)
          : Stack(
              children: [
                _buildBody(cs, tt),
                if (_canShowLastBrowseAction)
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.end,
                      children: [
                        if (_nextBrowseChapter != null)
                          _GlassFloatingButton(
                            heroTag: 'next_chapter',
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReaderPage(
                                  pathWord: widget.pathWord,
                                  comicName: _comic?.name,
                                  coverUrl: _comic?.cover,
                                  group: _selectedGroup,
                                  chapterUuid: _nextBrowseChapter!.uuid,
                                  chapterName: _nextBrowseChapter!.name,
                                ),
                              ),
                            ).then((_) => _loadLocalHistory()),
                            icon: const Icon(Icons.skip_next, size: 20),
                            label: Text(
                              _truncateNextChapterName(
                                _nextBrowseChapter!.name,
                              ),
                            ),
                          ),
                        _GlassFloatingButton(
                          heroTag: 'continue_reading',
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ReaderPage(
                                pathWord: widget.pathWord,
                                comicName: _comic?.name,
                                coverUrl: _comic?.cover,
                                group: _selectedGroup,
                                chapterUuid: _lastBrowseId!,
                                chapterName: _lastBrowseName ?? '',
                                initialPage: _lastBrowsePage,
                              ),
                            ),
                          ).then((_) => _loadLocalHistory()),
                          icon: const Icon(Icons.play_arrow, size: 20),
                          label: Text(_continueReadingLabel()),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _refresh() async {
    _exitSelectionMode();
    _chapterPageCache.clear();
    await _loadLocalHistory();
    await _loadComic();
  }

  Widget _buildDownloadToolbar(ColorScheme cs, TextTheme tt) {
    final pendingCount = _downloads.pendingCountForComic(widget.pathWord);
    final downloadedCount = _downloads
        .downloadedChapterIds(widget.pathWord)
        .length;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: _selectionMode
            ? Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '已选 ${_selectedChapterIds.length} 章',
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  OutlinedButton.icon(
                    onPressed: _displayChapters.any(_isChapterSelectable)
                        ? _selectAllVisibleDownloadable
                        : null,
                    icon: const Icon(Icons.select_all, size: 18),
                    label: const Text('全选'),
                  ),
                  FilledButton.icon(
                    onPressed: _selectedChapterIds.isEmpty
                        ? null
                        : _downloadSelectedChapters,
                    icon: const Icon(Icons.download_for_offline, size: 18),
                    label: const Text('下载选中'),
                  ),
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (pendingCount > 0)
                    Chip(
                      avatar: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      ),
                      label: Text('顺序下载中 $pendingCount 章'),
                    ),
                  if (downloadedCount > 0)
                    Chip(
                      avatar: const Icon(
                        Icons.check_circle,
                        size: 18,
                        color: Colors.green,
                      ),
                      label: Text('已下载 $downloadedCount 章'),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildChapterCard(Chapter chapter, ColorScheme cs, TextTheme tt) {
    final isLastRead = _lastBrowseId == chapter.uuid;
    final isDownloaded = _isChapterDownloaded(chapter.uuid);
    final isQueued = _isChapterQueued(chapter.uuid);
    final isDownloading = _downloads.isDownloading(
      widget.pathWord,
      chapter.uuid,
    );
    final progress = _downloads.progressOf(widget.pathWord, chapter.uuid);
    final isSelected = _selectedChapterIds.contains(chapter.uuid);

    final backgroundColor = isSelected
        ? cs.secondaryContainer
        : isLastRead
        ? cs.primaryContainer
        : cs.surfaceContainerLow;
    final foregroundColor = isSelected
        ? cs.onSecondaryContainer
        : isLastRead
        ? cs.onPrimaryContainer
        : cs.onSurface;

    final subtitle = isDownloaded
        ? '已下载'
        : isDownloading && progress != null
        ? '下载 ${progress.completed}/${progress.total}'
        : isQueued
        ? '排队中'
        : '${chapter.size}P';

    final brightness = Theme.of(context).brightness;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? cs.primary
              : cs.outlineVariant.withValues(
                  alpha: brightness == Brightness.dark ? 0.22 : 0.45,
                ),
          width: isSelected ? 1.4 : 0.6,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: brightness == Brightness.dark ? 0.30 : 0.14,
            ),
            blurRadius: brightness == Brightness.dark ? 12 : 14,
            spreadRadius: brightness == Brightness.dark ? 0 : -1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (_selectionMode) {
                  _toggleChapterSelection(chapter);
                  return;
                }
                _openReader(chapter);
              },
              onLongPress: _selectionMode || !_isChapterSelectable(chapter)
                  ? null
                  : () => _enterSelectionMode(chapter.uuid),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chapter.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: tt.bodySmall?.copyWith(
                          color: foregroundColor,
                          fontWeight: isLastRead || isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: tt.labelSmall?.copyWith(
                          color: isSelected
                              ? foregroundColor.withValues(alpha: 0.8)
                              : cs.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isDownloaded)
            const Positioned(top: 4, right: 4, child: _DownloadedBadge()),
          if (isDownloading && progress != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(10),
                ),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: progress.ratio,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hero(String Function(String base) tagOf, Widget child) {
    final base = widget.heroTagBase;
    if (base == null) return child;
    return Hero(
      tag: tagOf(base),
      createRectTween: ComicHeroTags.createRectTween,
      placeholderBuilder: _buildHeroPlaceholder,
      child: child,
    );
  }

  Widget _buildHeroPlaceholder(
    BuildContext context,
    Size heroSize,
    Widget child,
  ) {
    return SizedBox(width: heroSize.width, height: heroSize.height);
  }

  Widget _buildDetailActions(Comic comic) {
    final buttonStyle = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );

    return Row(
      children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed:
                _selectionMode || _displayChapters.any(_isChapterSelectable)
                ? _toggleDownloadSelectionMode
                : null,
            icon: Icon(
              _selectionMode
                  ? Icons.close
                  : Icons.download_for_offline_outlined,
              size: 18,
            ),
            label: Text(_selectionMode ? '取消' : '下载'),
            style: buttonStyle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: comic.uuid == null || comic.uuid!.isEmpty
                ? null
                : _showComicComments,
            icon: const Icon(Icons.forum_outlined, size: 18),
            label: const Text('评论'),
            style: buttonStyle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: comic.uuid == null || comic.uuid!.isEmpty
                ? null
                : _toggleCollect,
            icon: Icon(
              _isCollected ? Icons.bookmark : Icons.bookmark_border,
              size: 18,
            ),
            label: Text(_isCollected ? '已收藏' : '收藏'),
            style: buttonStyle,
          ),
        ),
      ],
    );
  }

  // ── 全宽头图 + 毛玻璃信息卡（苹果风）──
  Widget _buildDetailHeader(Comic comic, ColorScheme cs, TextTheme tt) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return SizedBox(
      height: 260,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 模糊大背景（取封面）
          CachedNetworkImage(
            imageUrl: comic.cover,
            fit: BoxFit.cover,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (_, _) => Container(color: cs.surfaceContainerHighest),
            errorWidget: (_, _, _) =>
                Container(color: cs.surfaceContainerHighest),
          ),
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(color: bg.withValues(alpha: 0.1)),
              ),
            ),
          ),
          // 底部渐变淡出到背景色，保证信息可读
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bg.withValues(alpha: 0.15),
                    bg.withValues(alpha: 0.55),
                    bg,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          // 前景内容：封面缩略图 + 标题信息
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _hero(
                  ComicHeroTags.cover,
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CoverBrightnessFilter(
                        child: CachedNetworkImage(
                          imageUrl: comic.cover,
                          width: 112,
                          height: 150,
                          fit: BoxFit.cover,
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholder: (_, _) => Container(
                            width: 112,
                            height: 150,
                            color: cs.surfaceContainerHighest,
                          ),
                          errorWidget: (_, _, _) => Container(
                            width: 112,
                            height: 150,
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              Icons.broken_image,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        comic.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      if (comic.authors.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 15,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                comic.authors.map((a) => a.name).join(' / '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (comic.popular > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.local_fire_department,
                              size: 15,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatPopular(comic.popular),
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, TextTheme tt) {
    final comic = _comic!;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        slivers: [
          // ── 全宽头图 + 毛玻璃信息卡 ──
          SliverToBoxAdapter(child: _buildDetailHeader(comic, cs, tt)),
          // ── 标签 chips ──
          if (comic.status != null ||
              comic.region != null ||
              comic.themes.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (comic.status != null)
                      _InfoChip(
                        icon: Icons.timelapse,
                        label: (comic.status!['display'] ?? '').toString(),
                        color: cs.primaryContainer,
                        textColor: cs.onPrimaryContainer,
                      ),
                    if (comic.region != null)
                      _InfoChip(
                        icon: Icons.public,
                        label: (comic.region!['display'] ?? '').toString(),
                        color: cs.secondaryContainer,
                        textColor: cs.onSecondaryContainer,
                      ),
                    ...comic.themes.map(
                      (t) => _InfoChip(
                        icon: Icons.label_outline,
                        label: t.name,
                        color: cs.tertiaryContainer,
                        textColor: cs.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // ── 简介 ──
          if (comic.brief != null && comic.brief!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: GestureDetector(
                  onTap: () => setState(() => _briefExpanded = !_briefExpanded),
                  child: Text(
                    comic.brief!,
                    maxLines: _briefExpanded ? null : 3,
                    overflow: _briefExpanded ? null : TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _buildDetailActions(comic),
            ),
          ),
          // ── 分组切换 ──
          if (comic.groups != null && comic.groups!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: SegmentedButton<String>(
                  segments: comic.groups!.entries
                      .map(
                        (e) => ButtonSegment(
                          value: e.key,
                          label: Text(
                            '${e.value.name}(${e.value.count})',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  selected: {_selectedGroup},
                  onSelectionChanged: (v) async {
                    final group = v.first;
                    setState(() => _selectedGroup = group);
                    await _loadLocalHistory(group: group);
                    await _loadChapterPageForHistory(group: group);
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
          // ── 章节标题 + 排序 + 分页 ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  if (_totalPages > 1)
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(_totalPages, (i) {
                            final isSelected = i == _chapterPage;
                            final pageButtonShape = RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            );
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                              ),
                              child: isSelected
                                  ? FilledButton(
                                      onPressed: () {},
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(38, 38),
                                        maximumSize: const Size(38, 38),
                                        fixedSize: const Size(38, 38),
                                        padding: EdgeInsets.zero,
                                        backgroundColor: cs.primary,
                                        foregroundColor: cs.onPrimary,
                                        disabledBackgroundColor: cs.primary,
                                        disabledForegroundColor: cs.onPrimary,
                                        shape: pageButtonShape,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text('${i + 1}'),
                                    )
                                  : FilledButton.tonal(
                                      onPressed: () => _loadChapterPage(i),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(38, 38),
                                        maximumSize: const Size(38, 38),
                                        fixedSize: const Size(38, 38),
                                        padding: EdgeInsets.zero,
                                        backgroundColor:
                                            cs.surfaceContainerHigh,
                                        foregroundColor: cs.onSurfaceVariant,
                                        shape: pageButtonShape,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      child: Text('${i + 1}'),
                                    ),
                            );
                          }),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilledButton.tonal(
                      onPressed: () => setState(() => _reversed = !_reversed),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(38, 38),
                        maximumSize: const Size(38, 38),
                        fixedSize: const Size(38, 38),
                        padding: EdgeInsets.zero,
                        backgroundColor: cs.surfaceContainerHigh,
                        foregroundColor: cs.onSurfaceVariant,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Tooltip(
                        message: _reversed ? '逆序（新→旧）' : '正序（旧→新）',
                        child: Icon(
                          _reversed ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildDownloadToolbar(cs, tt),
          // ── 章节网格 ──
          if (_loadingChapters &&
              (!_keepShowingCachedChapters || _chapters.isEmpty))
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((_, i) {
                  final ch = _displayChapters[i];
                  return _buildChapterCard(ch, cs, tt);
                }, childCount: _displayChapters.length),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 120,
                  mainAxisExtent: 52,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                ),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  static String _formatPopular(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }
}

/// 悬浮圆形毛玻璃按钮（详情页顶部返回/分享/更多）
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadedBadge extends StatelessWidget {
  const _DownloadedBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.green,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(Icons.check, size: 12, color: Colors.white),
      ),
    );
  }
}

class _GlassFloatingButton extends StatelessWidget {
  final Widget icon;
  final Widget label;
  final VoidCallback onPressed;
  final String heroTag;

  const _GlassFloatingButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Theme.of(context).colorScheme.primary; // appleBlue
    final bgColor = isDark
        ? themeColor.withValues(alpha: 0.24)
        : themeColor.withValues(alpha: 0.12);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : themeColor.withValues(alpha: 0.18);
    final textColor = isDark ? Colors.white : themeColor;
    final iconColor = isDark ? Colors.white : themeColor;

    return Hero(
      tag: heroTag,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: bgColor,
                border: Border.all(color: borderColor, width: 1.0),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onPressed,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Theme(
                          data: Theme.of(context).copyWith(
                            iconTheme: IconThemeData(color: iconColor),
                          ),
                          child: icon,
                        ),
                        const SizedBox(width: 8),
                        DefaultTextStyle(
                          style: TextStyle(
                            color: textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          child: label,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
