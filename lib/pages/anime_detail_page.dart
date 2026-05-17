import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/dandanplay_api.dart';
import '../models/anime.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/anime_download_manager.dart';
import '../utils/anime_playback_history.dart';
import '../utils/chinese_converter.dart';
import '../utils/data_cache.dart';
import '../utils/dandanplay_binding_store.dart';
import '../utils/toast.dart';
import 'anime_player_page.dart';
import 'bangumi_comments_section.dart';
import 'download_center_page.dart';
import 'home_page.dart';

class AnimeDetailPage extends StatefulWidget {
  final String pathWord;
  final Anime? initialAnime;

  const AnimeDetailPage({super.key, required this.pathWord, this.initialAnime});

  @override
  State<AnimeDetailPage> createState() => _AnimeDetailPageState();
}

class _AnimeDetailPageState extends State<AnimeDetailPage>
    with TickerProviderStateMixin {
  static const _watchedCompleteRemainingThreshold = Duration(minutes: 3);
  static const _detailCacheTtl = Duration(days: 3);
  static const _commentsScrollToTopThreshold = 480.0;
  static const _tabIntro = 0;
  static const _tabEpisodes = 1;
  static const _tabComments = 2;

  final _api = ApiClient();
  final _cache = DataCache();
  final _downloads = AnimeDownloadManager();
  final _dandanplayBindingStore = DandanplayBindingStore();
  final _bangumiCommentsKey = GlobalKey<BangumiCommentsSectionState>();
  final _scrollController = ScrollController();
  TabController? _tabController;
  Anime? _anime;
  List<AnimeChapter> _chapters = [];
  int _chapterTotal = 0;
  int _currentTab = _tabEpisodes;
  bool _loadingDetail = false;
  bool _detailReady = false;
  bool _loadingChapters = true;
  bool _briefExpanded = false;
  bool _isCollected = false;
  bool _collectSubmitting = false;
  DateTime? _refreshedAt;
  AnimePlaybackRecord? _latestPlaybackRecord;
  DandanplayBindingRecord? _dandanplayBinding;
  DandanplayBangumi? _dandanplayBangumi;
  bool _loadingDandanplayBangumi = false;
  Map<String, int?> _danmakuEpisodeBindings = {};
  int _dandanplayBangumiSerial = 0;
  String? _detailError;
  String? _chapterError;

  // 批量下载选择
  final Set<String> _selectedUuids = {};
  bool _selectionMode = false;
  bool _showCommentsScrollToTop = false;
  StreamSubscription<String>? _errorSub;

  String get _detailCacheKey => 'anime_detail_info_v2_${widget.pathWord}';
  bool get _showCommentsTab =>
      _dandanplayBinding?.bangumiId.trim().isNotEmpty == true;
  List<int> get _tabKinds => _showCommentsTab
      ? const [_tabIntro, _tabEpisodes, _tabComments]
      : const [_tabIntro, _tabEpisodes];
  bool get _isIntroTab => _currentTab == _tabIntro;
  bool get _isCommentsTab => _currentTab == _tabComments;
  bool get _isEpisodeTab => _currentTab == _tabEpisodes;
  bool get _useDandanplayIntro => _dandanplayBangumi != null;
  _AnimeIntroViewData? get _introViewData => _useDandanplayIntro
      ? _AnimeIntroViewData.fromDandanplay(
          _dandanplayBangumi!,
          fallbackAnime: _anime ?? widget.initialAnime,
        )
      : (_anime == null ? null : _AnimeIntroViewData.fromAnime(_anime!));

  @override
  void initState() {
    super.initState();
    _syncTabController();
    _anime = widget.initialAnime;
    _scrollController.addListener(_onScrollChanged);
    _downloads.addListener(_onDownloadsChanged);
    _errorSub = _downloads.onError.listen((msg) {
      if (mounted) showToast(context, msg, isError: true);
    });
    unawaited(_initializeDetailSources());
    unawaited(_loadChapters());
  }

  Future<void> _initializeDetailSources() async {
    await _loadDandanplayBinding();
    if (_dandanplayBinding == null) {
      await _loadDetail();
    }
  }

  void _syncTabController() {
    final tabs = _tabKinds;
    final nextTab = tabs.contains(_currentTab) ? _currentTab : _tabEpisodes;
    final nextIndex = tabs.indexOf(nextTab);
    final previousController = _tabController;
    _tabController = TabController(
      length: tabs.length,
      vsync: this,
      initialIndex: nextIndex,
    )..addListener(_onTabChanged);
    _currentTab = nextTab;
    if (previousController != null) {
      previousController.removeListener(_onTabChanged);
      previousController.dispose();
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    _tabController?.dispose();
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _errorSub?.cancel();
    _downloads.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    if (mounted) setState(() {});
  }

  void _onScrollChanged() {
    _updateCommentsScrollToTopVisibility();
  }

  void _updateCommentsScrollToTopVisibility() {
    final shouldShow =
        _isCommentsTab &&
        _scrollController.hasClients &&
        _scrollController.offset >= _commentsScrollToTopThreshold;
    if (shouldShow == _showCommentsScrollToTop) return;
    if (!mounted) return;
    setState(() => _showCommentsScrollToTop = shouldShow);
  }

  void _onTabChanged() {
    final controller = _tabController;
    if (controller == null) return;
    final tabs = _tabKinds;
    if (controller.index >= tabs.length) return;
    final nextTab = tabs[controller.index];
    if (_currentTab == nextTab) return;
    _currentTab = nextTab;
    if (_currentTab == _tabIntro) {
      unawaited(_ensureDetailLoaded());
    }
    if (_currentTab != _tabEpisodes && _selectionMode) {
      _exitSelectionMode();
      return;
    }
    _updateCommentsScrollToTopVisibility();
    if (mounted) setState(() {});
  }

  Future<void> _saveDetailCache() async {
    final anime = _anime;
    if (anime == null) return;
    await _cache.put(_detailCacheKey, {
      'anime': anime.toJson(),
      'isCollected': _isCollected,
      if (_refreshedAt != null) 'refreshedAt': _refreshedAt!.toIso8601String(),
    }, ttl: _detailCacheTtl);
  }

  Future<void> _ensureDetailLoaded() async {
    if (_useDandanplayIntro || _detailReady || _loadingDetail) return;
    await _loadDetail();
  }

  Future<void> _loadDetail({bool forceRefresh = false}) async {
    if (_loadingDetail) return;
    try {
      if (!forceRefresh) {
        final cached = await _cache.get(_detailCacheKey);
        if (cached is Map) {
          final animeJson = cached['anime'];
          if (animeJson is Map) {
            if (!mounted) return;
            setState(() {
              _anime = Anime.fromJson(Map<String, dynamic>.from(animeJson));
              _isCollected = cached['isCollected'] == true;
              _refreshedAt = DateTime.tryParse(
                cached['refreshedAt']?.toString() ?? '',
              );
              _detailReady = true;
              _detailError = null;
            });
            return;
          }
        }
      }

      setState(() {
        _loadingDetail = true;
        _detailError = null;
      });
      final detail = await _api.getAnimeDetail(widget.pathWord);
      AnimeQuery? query;
      try {
        query = await _api.getAnimeQuery(widget.pathWord);
      } catch (_) {
        query = null;
      }

      if (!mounted) return;
      final refreshedAt = DateTime.now();
      setState(() {
        _anime = detail;
        _isCollected = query?.isCollected ?? _isCollected;
        _refreshedAt = refreshedAt;
        _detailReady = true;
        _loadingDetail = false;
        _detailError = null;
      });
      await _saveDetailCache();
    } catch (e) {
      debugPrint('AnimeDetailPage load detail error: $e');
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _detailError = e.toString();
      });
      if (_detailReady) {
        showToast(context, '简介刷新失败', isError: true);
      }
    }
  }

  Future<void> _loadChapters() async {
    setState(() {
      _loadingChapters = true;
      _chapterError = null;
    });
    try {
      final chapters = await _api.getAnimeChapters(widget.pathWord);
      if (!mounted) return;
      setState(() {
        _chapters = chapters.list;
        _chapterTotal = chapters.total;
        _loadingChapters = false;
        _chapterError = null;
      });
      unawaited(_loadLatestPlaybackRecord());
      _syncDandanplayBindingsAfterChaptersLoaded();
    } catch (e) {
      debugPrint('AnimeDetailPage load chapters error: $e');
      if (!mounted) return;
      setState(() {
        _loadingChapters = false;
        _chapterError = e.toString();
      });
      if (_chapters.isNotEmpty) {
        showToast(context, '选集刷新失败', isError: true);
      }
    }
  }

  Future<void> _refreshCurrentTab() async {
    _exitSelectionMode();
    if (_isIntroTab) {
      if (_useDandanplayIntro) {
        final binding = _dandanplayBinding;
        if (binding != null) {
          await DandanplayApi().clearBangumiCache(binding.animeId);
          await _loadDandanplayBangumi(binding, applySequentialIfEmpty: true);
        }
        return;
      }
      await _loadDetail(forceRefresh: true);
      return;
    }
    if (_isCommentsTab) {
      await (_bangumiCommentsKey.currentState?.reload(forceRefresh: true) ??
          Future<void>.value());
      return;
    }
    await _clearEpisodeRefreshCaches();
    await _loadChapters();
  }

  Future<void> _clearEpisodeRefreshCaches() async {
    final binding = _dandanplayBinding;
    await _api.clearAnimePlaybackCache(widget.pathWord);
    if (binding != null) {
      await DandanplayApi().clearBangumiCache(binding.animeId);
    }
    if (!mounted) return;
    setState(() {
      _dandanplayBangumi = null;
    });
  }

  String? get _refreshedAtText {
    final refreshedAt = _refreshedAt;
    if (refreshedAt == null) return null;
    return _formatRefreshTime(refreshedAt);
  }

  String _formatRefreshTime(DateTime time) {
    final local = time.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  Future<void> _loadLatestPlaybackRecord() async {
    final records = await AnimePlaybackHistory.progressRecordsForAnime(
      pathWord: widget.pathWord,
    );
    if (!mounted) return;
    final record = _selectLatestChapterPlaybackRecord(records);
    setState(() => _latestPlaybackRecord = record);
  }

  AnimePlaybackRecord? _selectLatestChapterPlaybackRecord(
    List<AnimePlaybackRecord> records,
  ) {
    if (records.isEmpty) return null;
    final byChapterUuid = {
      for (final record in records) record.chapterUuid: record,
    };
    for (var i = _chapters.length - 1; i >= 0; i--) {
      final record = byChapterUuid[_chapters[i].uuid];
      if (record != null) return record;
    }
    records.sort((a, b) {
      final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return records.first;
  }

  Future<void> _loadDandanplayBinding() async {
    final binding = await _dandanplayBindingStore.getByPathWord(
      widget.pathWord,
    );
    if (!mounted) return;
    setState(() {
      _dandanplayBinding = binding;
      _syncTabController();
    });
    if (binding != null) {
      unawaited(_loadDandanplayBangumi(binding, applySequentialIfEmpty: true));
    }
  }

  String get _currentAnimeTitle {
    final title = _anime?.name ?? widget.initialAnime?.name ?? widget.pathWord;
    return title.trim().isEmpty ? widget.pathWord : title.trim();
  }

  Future<String> _simplifiedDandanplayKeyword(String text) async {
    try {
      return await ChineseConverter.convertToSimplifiedChinese(text);
    } catch (_) {
      return text;
    }
  }

  Future<void> _showDandanplayBindingDialog() async {
    final animeTitle = _currentAnimeTitle;
    final initialKeyword = await _simplifiedDandanplayKeyword(animeTitle);
    if (!mounted) return;

    final result = await showDialog<_DandanplayBindingDialogResult>(
      context: context,
      builder: (_) => _DandanplayBindingDialog(
        initialKeyword: initialKeyword,
        currentBinding: _dandanplayBinding,
        pathWord: widget.pathWord,
        localTitle: animeTitle,
        localUuid: _anime?.uuid ?? widget.initialAnime?.uuid,
      ),
    );
    if (!mounted || result == null) return;

    if (result.clear) {
      await _dandanplayBindingStore.removeByPathWord(widget.pathWord);
      await _clearDandanplayChapterBindings();
      if (!mounted) return;
      setState(() {
        _dandanplayBinding = null;
        _dandanplayBangumi = null;
        _danmakuEpisodeBindings = {};
        _syncTabController();
      });
      showToast(context, '已清除弹弹play绑定');
      return;
    }

    final record = result.record;
    if (record == null) return;
    await _dandanplayBindingStore.save(record);
    if (!mounted) return;
    setState(() {
      _dandanplayBinding = record;
      _dandanplayBangumi = null;
      _danmakuEpisodeBindings = {};
      _syncTabController();
    });
    await _loadDandanplayBangumi(record, applySequential: true);
    if (!mounted) return;
    showToast(context, '已绑定 ${record.animeTitle}');
  }

  void _syncDandanplayBindingsAfterChaptersLoaded() {
    final binding = _dandanplayBinding;
    if (binding == null || _chapters.isEmpty) return;
    unawaited(_loadDandanplayBangumi(binding, applySequentialIfEmpty: true));
  }

  Future<void> _loadDandanplayBangumi(
    DandanplayBindingRecord binding, {
    bool applySequential = false,
    bool applySequentialIfEmpty = false,
  }) async {
    final serial = ++_dandanplayBangumiSerial;
    setState(() {
      _loadingDandanplayBangumi = true;
    });

    final bangumi = await DandanplayApi().getBangumi(binding.animeId);
    if (!mounted ||
        serial != _dandanplayBangumiSerial ||
        _dandanplayBinding?.animeId != binding.animeId) {
      return;
    }

    if (bangumi == null) {
      setState(() {
        _dandanplayBangumi = null;
        _loadingDandanplayBangumi = false;
      });
      return;
    }

    setState(() {
      _dandanplayBangumi = bangumi;
      _loadingDandanplayBangumi = false;
    });

    if (_chapters.isEmpty) return;
    if (binding.hasAlignment &&
        await _applyStoredDandanplayAlignment(binding, bangumi.episodes)) {
      return;
    }
    if (applySequential) {
      await _applySequentialDandanplayBindings(bangumi.episodes);
      return;
    }
    await _loadDandanplayEpisodeBindings(
      bangumi,
      binding: binding,
      applySequentialIfEmpty: applySequentialIfEmpty,
    );
  }

  Future<void> _loadDandanplayEpisodeBindings(
    DandanplayBangumi bangumi, {
    required DandanplayBindingRecord binding,
    bool applySequentialIfEmpty = false,
  }) async {
    if (binding.hasAlignment &&
        await _applyStoredDandanplayAlignment(binding, bangumi.episodes)) {
      return;
    }
    final bindings = await _readDandanplayEpisodeBindings();
    if (!mounted) return;
    final hasAnyBinding = bindings.values.any((episodeId) => episodeId != null);
    if (applySequentialIfEmpty &&
        !hasAnyBinding &&
        bangumi.episodes.isNotEmpty) {
      await _applySequentialDandanplayBindings(bangumi.episodes);
      return;
    }
    setState(() => _danmakuEpisodeBindings = bindings);
  }

  Future<bool> _applyStoredDandanplayAlignment(
    DandanplayBindingRecord binding,
    List<DandanplayBangumiEpisode> episodes,
  ) async {
    final chapterUuid = binding.alignmentChapterUuid;
    final episodeId = binding.alignmentEpisodeId;
    if (chapterUuid == null || episodeId == null) return false;

    final chapterStartIndex = _chapters.indexWhere(
      (chapter) => chapter.uuid == chapterUuid,
    );
    final validEpisodes = _uniqueDandanplayEpisodes(episodes);
    final episodeStartIndex = validEpisodes.indexWhere(
      (episode) => episode.episodeId == episodeId,
    );
    if (chapterStartIndex < 0 || episodeStartIndex < 0) return false;

    await _applyAlignedDandanplayBindings(
      validEpisodes,
      chapterStartIndex: chapterStartIndex,
      episodeStartIndex: episodeStartIndex,
    );
    return true;
  }

  Future<Map<String, int?>> _readDandanplayEpisodeBindings() async {
    final entries = await Future.wait(
      _chapters.map((chapter) async {
        final record = await AnimePlaybackHistory.get(
          pathWord: widget.pathWord,
          chapterUuid: chapter.uuid,
        );
        return MapEntry(chapter.uuid, record?.danmakuEpisodeId);
      }),
    );
    return Map<String, int?>.fromEntries(entries);
  }

  Future<void> _applySequentialDandanplayBindings(
    List<DandanplayBangumiEpisode> episodes,
  ) async {
    final validEpisodes = _uniqueDandanplayEpisodes(episodes);
    final nextBindings = <String, int?>{};

    await Future.wait(
      _chapters.indexed.map((entry) async {
        final index = entry.$1;
        final chapter = entry.$2;
        final episode = index < validEpisodes.length
            ? validEpisodes[index]
            : null;
        nextBindings[chapter.uuid] = episode?.episodeId;
        if (episode == null) {
          await AnimePlaybackHistory.clearDanmakuEpisode(
            pathWord: widget.pathWord,
            chapterUuid: chapter.uuid,
            chapterName: chapter.name,
          );
          return;
        }
        await AnimePlaybackHistory.saveDanmakuEpisode(
          pathWord: widget.pathWord,
          chapterUuid: chapter.uuid,
          chapterName: chapter.name,
          episodeId: episode.episodeId,
        );
      }),
    );

    if (!mounted) return;
    setState(() => _danmakuEpisodeBindings = nextBindings);
  }

  Future<void> _showDandanplayAlignmentDialog(
    List<DandanplayBangumiEpisode> episodes,
  ) async {
    final binding = _dandanplayBinding;
    if (binding == null) return;
    final validEpisodes = _uniqueDandanplayEpisodes(episodes);
    if (_chapters.isEmpty || validEpisodes.isEmpty) return;
    final result = await showDialog<_DandanplayAlignmentResult>(
      context: context,
      builder: (_) => _DandanplayAlignmentDialog(
        chapters: _chapters,
        episodes: validEpisodes,
        initialChapterIndex: _defaultAlignmentChapterIndex(binding),
        initialEpisodeIndex: _defaultAlignmentEpisodeIndex(
          validEpisodes,
          binding,
        ),
        hasExistingAlignment: binding.hasAlignment,
      ),
    );
    if (!mounted || result == null) return;

    if (result.clear) {
      final updatedBinding = binding.withoutAlignment();
      await _dandanplayBindingStore.save(updatedBinding);
      if (!mounted) return;
      setState(() => _dandanplayBinding = updatedBinding);
      await _applySequentialDandanplayBindings(validEpisodes);
      if (mounted) showToast(context, '已清除对齐');
      return;
    }

    final chapterIndex = result.chapterIndex;
    final episodeIndex = result.episodeIndex;
    if (chapterIndex == null || episodeIndex == null) return;
    final updatedBinding = binding.withAlignment(
      chapterUuid: _chapters[chapterIndex].uuid,
      episodeId: validEpisodes[episodeIndex].episodeId,
    );
    await _dandanplayBindingStore.save(updatedBinding);
    if (!mounted) return;
    setState(() => _dandanplayBinding = updatedBinding);
    await _applyAlignedDandanplayBindings(
      validEpisodes,
      chapterStartIndex: chapterIndex,
      episodeStartIndex: episodeIndex,
    );
    if (mounted) showToast(context, '已重新对齐弹幕');
  }

  int _defaultAlignmentChapterIndex(DandanplayBindingRecord binding) {
    final chapterUuid = binding.alignmentChapterUuid;
    if (chapterUuid != null) {
      final savedIndex = _chapters.indexWhere(
        (chapter) => chapter.uuid == chapterUuid,
      );
      if (savedIndex >= 0) return savedIndex;
    }
    final index = _chapters.indexWhere(
      (chapter) => RegExp(r'第\s*0*1\s*[集话話]').hasMatch(chapter.name),
    );
    return index < 0 ? 0 : index;
  }

  int _defaultAlignmentEpisodeIndex(
    List<DandanplayBangumiEpisode> episodes,
    DandanplayBindingRecord binding,
  ) {
    final episodeId = binding.alignmentEpisodeId;
    if (episodeId != null) {
      final savedIndex = episodes.indexWhere(
        (episode) => episode.episodeId == episodeId,
      );
      if (savedIndex >= 0) return savedIndex;
    }
    final index = episodes.indexWhere(
      (episode) => RegExp(
        r'第\s*0*1\s*[集话話]',
      ).hasMatch(_formatDandanplayEpisodeLabel(episode)),
    );
    return index < 0 ? 0 : index;
  }

  Future<void> _applyAlignedDandanplayBindings(
    List<DandanplayBangumiEpisode> episodes, {
    required int chapterStartIndex,
    required int episodeStartIndex,
  }) async {
    final nextBindings = <String, int?>{};

    await Future.wait(
      _chapters.indexed.map((entry) async {
        final chapterIndex = entry.$1;
        final chapter = entry.$2;
        final episodeIndex =
            episodeStartIndex + chapterIndex - chapterStartIndex;
        final episode =
            chapterIndex >= chapterStartIndex &&
                episodeIndex >= 0 &&
                episodeIndex < episodes.length
            ? episodes[episodeIndex]
            : null;
        nextBindings[chapter.uuid] = episode?.episodeId;
        if (episode == null) {
          await AnimePlaybackHistory.clearDanmakuEpisode(
            pathWord: widget.pathWord,
            chapterUuid: chapter.uuid,
            chapterName: chapter.name,
          );
          return;
        }
        await AnimePlaybackHistory.saveDanmakuEpisode(
          pathWord: widget.pathWord,
          chapterUuid: chapter.uuid,
          chapterName: chapter.name,
          episodeId: episode.episodeId,
        );
      }),
    );

    if (!mounted) return;
    setState(() => _danmakuEpisodeBindings = nextBindings);
  }

  Future<void> _clearDandanplayChapterBindings() async {
    await Future.wait(
      _chapters.map(
        (chapter) => AnimePlaybackHistory.clearDanmakuEpisode(
          pathWord: widget.pathWord,
          chapterUuid: chapter.uuid,
          chapterName: chapter.name,
        ),
      ),
    );
  }

  Future<void> _updateDandanplayEpisodeBinding(
    AnimeChapter chapter,
    int? episodeId,
  ) async {
    setState(() {
      _danmakuEpisodeBindings = {
        ..._danmakuEpisodeBindings,
        chapter.uuid: episodeId,
      };
    });
    if (episodeId == null) {
      await AnimePlaybackHistory.clearDanmakuEpisode(
        pathWord: widget.pathWord,
        chapterUuid: chapter.uuid,
        chapterName: chapter.name,
      );
      return;
    }
    await AnimePlaybackHistory.saveDanmakuEpisode(
      pathWord: widget.pathWord,
      chapterUuid: chapter.uuid,
      chapterName: chapter.name,
      episodeId: episodeId,
    );
  }

  List<DandanplayBangumiEpisode> _uniqueDandanplayEpisodes(
    List<DandanplayBangumiEpisode> episodes,
  ) {
    final seen = <int>{};
    return episodes
        .where(
          (episode) => episode.episodeId > 0 && seen.add(episode.episodeId),
        )
        .toList();
  }

  DandanplayBangumiEpisode? _findDandanplayEpisode(
    List<DandanplayBangumiEpisode> episodes,
    int? episodeId,
  ) {
    if (episodeId == null) return null;
    for (final episode in episodes) {
      if (episode.episodeId == episodeId) return episode;
    }
    return null;
  }

  AnimeChapter? get _latestPlaybackChapter {
    final record = _latestPlaybackRecord;
    if (record == null) return null;
    for (final chapter in _chapters) {
      if (chapter.uuid == record.chapterUuid) return chapter;
    }
    return null;
  }

  Future<void> _openChapter(AnimeChapter chapter) async {
    final line = _resolveChapterLine(chapter);
    if (line == null || line.isEmpty) {
      showToast(context, '当前选集暂无可用线路', isError: true);
      return;
    }

    await Navigator.push(
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
    if (!mounted) return;
    await _loadLatestPlaybackRecord();
  }

  Future<void> _continueWatching() async {
    final chapter = _latestPlaybackChapter;
    if (chapter == null) {
      showToast(context, '播放记录对应选集暂不可用', isError: true);
      return;
    }
    await _openChapter(chapter);
  }

  Future<void> _openNextPlaybackChapter() async {
    final chapter = _nextChapterAfterLatestPlayback;
    if (chapter == null) return;
    await _openChapter(chapter);
  }

  AnimeChapter? get _nextChapterAfterLatestPlayback {
    final chapter = _latestPlaybackChapter;
    if (chapter == null) return null;
    final index = _chapters.indexWhere((item) => item.uuid == chapter.uuid);
    if (index < 0 || index + 1 >= _chapters.length) return null;
    return _chapters[index + 1];
  }

  bool _isPlaybackRecordNearEnd(AnimePlaybackRecord record) {
    final duration = record.duration;
    if (duration <= Duration.zero) return false;
    return duration - record.position < _watchedCompleteRemainingThreshold;
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
            .where(
              (c) =>
                  !_downloads.isDownloaded(widget.pathWord, c.uuid) &&
                  !_downloads.isInQueue(widget.pathWord, c.uuid),
            )
            .map((c) => c.uuid),
      );
    });
  }

  Future<Anime?> _ensureAnimeForDownload() async {
    final anime = _anime;
    if (anime != null) return anime;
    await _loadDetail(forceRefresh: true);
    return _anime;
  }

  Future<void> _batchDownload() async {
    if (_selectedUuids.isEmpty) return;
    final anime = await _ensureAnimeForDownload();
    if (anime == null) {
      if (mounted) showToast(context, '动漫信息加载失败，无法下载', isError: true);
      return;
    }

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
      await _saveDetailCache();
      if (!mounted) return;
      showToast(context, nextState ? '已收藏' : '已取消收藏');
    } catch (e) {
      debugPrint('AnimeDetailPage toggleCollect error: $e');
      if (!mounted) return;
      setState(() => _isCollected = !nextState);
      await _saveDetailCache();
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
      heroTag: 'anime_download_tasks_${widget.pathWord}',
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

  Widget? _buildFloatingActions(ColorScheme cs) {
    final rows = <Widget>[];
    final availableWidth = MediaQuery.sizeOf(context).width - 32;
    final maxButtonWidth = availableWidth.clamp(112.0, 320.0).toDouble();
    final maxLabelWidth = (maxButtonWidth - 76).clamp(36.0, 240.0).toDouble();
    final downloadFab = _buildDownloadFab(cs);
    if (downloadFab != null) {
      rows.add(downloadFab);
    }

    final playbackRecord = _latestPlaybackRecord;
    if (playbackRecord != null) {
      final chapterName =
          _latestPlaybackChapter?.name ?? playbackRecord.chapterName;
      final nextChapter = _isPlaybackRecordNearEnd(playbackRecord)
          ? _nextChapterAfterLatestPlayback
          : null;
      rows.add(
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: availableWidth),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.end,
            children: [
              if (nextChapter != null)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxButtonWidth),
                  child: FloatingActionButton.extended(
                    heroTag: 'anime_next_watching_${widget.pathWord}',
                    onPressed: () => unawaited(_openNextPlaybackChapter()),
                    icon: const Icon(Icons.skip_next_rounded, size: 20),
                    label: _FabLabel(
                      text: _truncateChapterName(
                        nextChapter.name,
                        maxLength: 12,
                      ),
                      maxWidth: maxLabelWidth,
                    ),
                  ),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxButtonWidth),
                child: FloatingActionButton.extended(
                  heroTag: 'anime_continue_watching_${widget.pathWord}',
                  onPressed: () => unawaited(_continueWatching()),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: _FabLabel(
                    text: _continueWatchingLabel(chapterName, playbackRecord),
                    maxWidth: maxLabelWidth,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          rows[i],
        ],
      ],
    );
  }

  Future<void> _scrollToTop() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Widget? _buildCommentsScrollToTopFab() {
    if (!_showCommentsScrollToTop) return null;
    return FloatingActionButton.small(
      heroTag: 'anime_comments_back_to_top_${widget.pathWord}',
      onPressed: () => unawaited(_scrollToTop()),
      tooltip: '回到顶部',
      child: const Icon(Icons.arrow_upward_rounded),
    );
  }

  String _continueWatchingLabel(
    String chapterName,
    AnimePlaybackRecord record,
  ) {
    final name = _truncateChapterName(chapterName, maxLength: 12);
    final progress = record.duration > Duration.zero
        ? '${_formatDuration(record.position)} / ${_formatDuration(record.duration)}'
        : _formatDuration(record.position);
    return name.isEmpty ? progress : '$name · $progress';
  }

  String _truncateChapterName(String name, {required int maxLength}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';

    final chars = trimmed.characters;
    if (chars.length <= maxLength) return trimmed;
    return '${chars.take(maxLength).toString()}...';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '${duration.inMinutes}:$seconds';
  }

  List<Widget> _buildIntroSlivers(double hp, TextTheme tt, ColorScheme cs) {
    final intro = _introViewData;
    if (intro == null) {
      if (_loadingDetail) {
        return const [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ];
      }
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                _detailError == null ? '暂无简介信息' : '简介加载失败，下拉重试',
                style: tt.bodyMedium,
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(hp, 18, hp, 0),
          child: _AnimeInfoPanel(
            intro: intro,
            isCollected: _isCollected,
            collectSubmitting: _collectSubmitting,
            briefExpanded: _briefExpanded,
            refreshedAtText: _refreshedAtText,
            onToggleCollect: _toggleCollect,
            onToggleBrief: () {
              setState(() => _briefExpanded = !_briefExpanded);
            },
          ),
        ),
      ),
      if (_detailError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
            child: Text(
              '简介刷新失败，当前显示缓存内容',
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ),
        ),
    ];
  }

  List<Widget> _buildEpisodeSlivers(double hp, TextTheme tt, ColorScheme cs) {
    final boundEpisodes = _dandanplayBangumi == null
        ? const <DandanplayBangumiEpisode>[]
        : _uniqueDandanplayEpisodes(_dandanplayBangumi!.episodes);

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(hp, 12, hp, 12),
          child: _selectionMode
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.start,
                    children: [
                      Text(
                        '已选 ${_selectedUuids.length} 集',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      TextButton(
                        onPressed: _selectAll,
                        child: const Text('全选未下载'),
                      ),
                      FilledButton.tonal(
                        onPressed: _selectedUuids.isEmpty
                            ? null
                            : _batchDownload,
                        child: const Text('下载选中'),
                      ),
                      IconButton(
                        onPressed: _exitSelectionMode,
                        icon: const Icon(Icons.close),
                        tooltip: '取消',
                      ),
                    ],
                  ),
                )
              : _buildEpisodeActionBar(boundEpisodes),
        ),
      ),
      if (_chapterError != null && _chapters.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text('选集加载失败，下拉重试', style: tt.bodyMedium)),
          ),
        )
      else if (_loadingChapters)
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
      else if (_dandanplayBinding != null)
        ..._buildBoundEpisodeSlivers(hp, tt, cs)
      else ...[
        if (_chapterError != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(hp, 0, hp, 12),
              child: Text(
                '选集刷新失败，当前显示上次结果',
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          ),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: hp),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((_, i) {
              final chapter = _chapters[i];
              final selected = _selectedUuids.contains(chapter.uuid);
              final downloaded = _downloads.isDownloaded(
                widget.pathWord,
                chapter.uuid,
              );
              final taskInfo = _downloads.taskInfo(
                widget.pathWord,
                chapter.uuid,
              );
              final inQueue = taskInfo != null;

              return _AnimeChapterCard(
                chapter: chapter,
                selected: selected,
                selectionMode: _selectionMode,
                isDownloaded: downloaded,
                isDownloading:
                    taskInfo?.status == DownloadTaskStatus.downloading,
                isQueued:
                    inQueue &&
                    taskInfo.status != DownloadTaskStatus.downloading,
                progress: _downloads.progressOf(widget.pathWord, chapter.uuid),
                onTap: () {
                  if (_selectionMode) {
                    _toggleSelection(chapter.uuid);
                    return;
                  }
                  _openChapter(chapter);
                },
                onLongPress: () => _enterSelectionMode(chapter.uuid),
              );
            }, childCount: _chapters.length),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisExtent: 52,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildCommentsSlivers(double hp, TextTheme tt, ColorScheme cs) {
    final binding = _dandanplayBinding;
    final bangumiId = binding?.bangumiId.trim() ?? '';
    if (bangumiId.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hp, 24, hp, 0),
            child: Center(
              child: Text(
                '绑定弹弹play 后才可查看评论',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
          child: BangumiCommentsSection(
            key: _bangumiCommentsKey,
            bangumiId: bangumiId,
            animeTitle: binding?.animeTitle ?? _currentAnimeTitle,
          ),
        ),
      ),
    ];
  }

  ButtonStyle _episodeActionButtonStyle() {
    return FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildEpisodeActionBar(List<DandanplayBangumiEpisode> boundEpisodes) {
    final buttons = <({int flex, Widget child})>[
      if (_dandanplayBinding == null)
        (
          flex: 3,
          child: FilledButton.tonalIcon(
            onPressed: _showDandanplayBindingDialog,
            icon: const Icon(Icons.link_rounded, size: 18),
            label: const Text(
              '绑定弹幕',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: _episodeActionButtonStyle(),
          ),
        )
      else ...[
        (
          flex: 3,
          child: FilledButton.tonalIcon(
            onPressed: _showDandanplayBindingDialog,
            icon: const Icon(Icons.manage_search_rounded, size: 18),
            label: const Text(
              '重新绑定',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: _episodeActionButtonStyle(),
          ),
        ),
        (
          flex: 2,
          child: FilledButton.tonalIcon(
            onPressed: boundEpisodes.isEmpty
                ? null
                : () => _showDandanplayAlignmentDialog(boundEpisodes),
            icon: const Icon(Icons.align_horizontal_left_rounded, size: 18),
            label: const Text(
              '对齐',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: _episodeActionButtonStyle(),
          ),
        ),
      ],
      if (_chapters.isNotEmpty)
        (
          flex: 2,
          child: FilledButton.tonalIcon(
            onPressed: () => setState(() => _selectionMode = true),
            icon: const Icon(Icons.download_for_offline_outlined, size: 18),
            label: const Text(
              '下载',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            style: _episodeActionButtonStyle(),
          ),
        ),
    ];

    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(flex: buttons[i].flex, child: buttons[i].child),
        ],
      ],
    );
  }

  List<Widget> _buildBoundEpisodeSlivers(
    double hp,
    TextTheme tt,
    ColorScheme cs,
  ) {
    final bangumi = _dandanplayBangumi;
    final episodes = bangumi == null
        ? const <DandanplayBangumiEpisode>[]
        : _uniqueDandanplayEpisodes(bangumi.episodes);

    return [
      if (_chapterError != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hp, 0, hp, 12),
            child: Text(
              '选集刷新失败，当前显示上次结果',
              style: tt.bodySmall?.copyWith(color: cs.error),
            ),
          ),
        ),
      if (_loadingDandanplayBangumi && episodes.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: hp),
          sliver: SliverList.separated(
            itemCount: _chapters.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final chapter = _chapters[index];
              final selectedEpisodeId = _danmakuEpisodeBindings[chapter.uuid];
              final selectedEpisode = _findDandanplayEpisode(
                episodes,
                selectedEpisodeId,
              );
              return _BoundAnimeChapterRow(
                chapter: chapter,
                selected: _selectedUuids.contains(chapter.uuid),
                selectionMode: _selectionMode,
                isDownloaded: _downloads.isDownloaded(
                  widget.pathWord,
                  chapter.uuid,
                ),
                episodes: episodes,
                selectedEpisodeId: selectedEpisode?.episodeId,
                onTap: () {
                  if (_selectionMode) {
                    _toggleSelection(chapter.uuid);
                    return;
                  }
                  _openChapter(chapter);
                },
                onLongPress: () => _enterSelectionMode(chapter.uuid),
                onEpisodeChanged: (episodeId) =>
                    _updateDandanplayEpisodeBinding(chapter, episodeId),
              );
            },
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final anime = _anime;
    final intro = _introViewData;
    final tabController = _tabController;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth < 900 ? screenWidth : 900.0;
    final hp = (screenWidth - contentWidth) / 2 + 16;

    if (_loadingChapters && anime == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_chapterError != null && anime == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 64, color: cs.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('选集加载失败', style: tt.titleMedium),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: _loadChapters,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      floatingActionButton: _isCommentsTab
          ? _buildCommentsScrollToTopFab()
          : _buildFloatingActions(cs),
      body: RefreshIndicator(
        onRefresh: _refreshCurrentTab,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 280,
              foregroundColor: Colors.white,
              title: Text(
                intro?.title ?? anime?.name ?? '动漫详情',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              flexibleSpace: intro == null
                  ? null
                  : FlexibleSpaceBar(
                      background: _AnimeDetailHeader(
                        intro: intro,
                        isCollected: _isCollected,
                      ),
                    ),
            ),
            if (_loadingDetail)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(hp, 0, hp, 0),
                child: TabBar(
                  controller: tabController,
                  tabs: [
                    const Tab(text: '简介'),
                    Tab(text: '选集 ($_chapterTotal)'),
                    if (_showCommentsTab) const Tab(text: '评论'),
                  ],
                ),
              ),
            ),
            ...(_isIntroTab
                ? _buildIntroSlivers(hp, tt, cs)
                : _isCommentsTab
                ? _buildCommentsSlivers(hp, tt, cs)
                : _buildEpisodeSlivers(hp, tt, cs)),
            SliverPadding(
              padding: EdgeInsets.only(bottom: _isEpisodeTab ? 120 : 24),
            ),
          ],
        ),
      ),
    );
  }
}

class _DandanplayBindingDialogResult {
  final DandanplayBindingRecord? record;
  final bool clear;

  const _DandanplayBindingDialogResult._({this.record, this.clear = false});

  const _DandanplayBindingDialogResult.bind(DandanplayBindingRecord record)
    : this._(record: record);

  const _DandanplayBindingDialogResult.clear() : this._(clear: true);
}

class _DandanplayBindingDialog extends StatefulWidget {
  final String initialKeyword;
  final DandanplayBindingRecord? currentBinding;
  final String pathWord;
  final String localTitle;
  final String? localUuid;

  const _DandanplayBindingDialog({
    required this.initialKeyword,
    required this.currentBinding,
    required this.pathWord,
    required this.localTitle,
    this.localUuid,
  });

  @override
  State<_DandanplayBindingDialog> createState() =>
      _DandanplayBindingDialogState();
}

class _DandanplayBindingDialogState extends State<_DandanplayBindingDialog> {
  late final TextEditingController _controller;
  final _api = DandanplayApi();
  List<DandanplayAnimeSearchItem> _results = [];
  bool _searching = false;
  bool _searched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKeyword);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_search());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final rawKeyword = _controller.text.trim();
    if (rawKeyword.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _searched = true;
      _error = null;
    });

    try {
      final keyword = await ChineseConverter.convertToSimplifiedChinese(
        rawKeyword,
      );
      if (!mounted) return;
      if (keyword != rawKeyword) {
        _controller.value = TextEditingValue(
          text: keyword,
          selection: TextSelection.collapsed(offset: keyword.length),
        );
      }
      final results = await _api.searchAnime(keyword);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _searching = false;
        _error = e.toString();
      });
    }
  }

  void _bind(DandanplayAnimeSearchItem item) {
    Navigator.pop(
      context,
      _DandanplayBindingDialogResult.bind(
        DandanplayBindingRecord(
          pathWord: widget.pathWord,
          localTitle: widget.localTitle,
          localUuid: widget.localUuid,
          animeId: item.animeId,
          bangumiId: item.bangumiId,
          animeTitle: item.animeTitle,
          imageUrl: item.imageUrl,
          boundAt: DateTime.now(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogHeight = (size.height * 0.68).clamp(360.0, 620.0);

    return AlertDialog(
      title: const Text('绑定弹幕'),
      content: SizedBox(
        width: 540,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.currentBinding != null) ...[
              _CurrentDandanplayBinding(record: widget.currentBinding!),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: '搜索关键词',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  onPressed: _searching ? null : _search,
                  icon: _searching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  tooltip: '搜索',
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
      actions: [
        if (widget.currentBinding != null)
          TextButton.icon(
            onPressed: () => Navigator.pop(
              context,
              const _DandanplayBindingDialogResult.clear(),
            ),
            icon: const Icon(Icons.link_off_rounded),
            label: const Text('清除绑定'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildResults() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          '搜索失败：$_error',
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(color: cs.error),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _searched ? '未找到相关番剧' : '输入关键词后点击搜索',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        itemCount: _results.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: cs.outlineVariant),
        itemBuilder: (_, index) {
          final item = _results[index];
          final selected = widget.currentBinding?.animeId == item.animeId;
          return _DandanplayAnimeResultTile(
            item: item,
            selected: selected,
            hasBinding: widget.currentBinding != null,
            onTap: selected ? null : () => _bind(item),
          );
        },
      ),
    );
  }
}

class _CurrentDandanplayBinding extends StatelessWidget {
  final DandanplayBindingRecord record;

  const _CurrentDandanplayBinding({required this.record});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前绑定',
                  style: tt.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  record.animeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '#${record.animeId}',
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DandanplayAnimeResultTile extends StatelessWidget {
  final DandanplayAnimeSearchItem item;
  final bool selected;
  final bool hasBinding;
  final VoidCallback? onTap;

  const _DandanplayAnimeResultTile({
    required this.item,
    required this.selected,
    required this.hasBinding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final imageUrl = item.imageUrl?.trim() ?? '';
    final meta = _metaText();

    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.24)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: imageUrl.isEmpty
                    ? Container(
                        width: 52,
                        height: 72,
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.movie_outlined,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    : CoverBrightnessFilter(
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 52,
                          height: 72,
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              Container(color: cs.surfaceContainerHighest),
                          errorWidget: (_, _, _) => Container(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              Icons.broken_image,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.animeTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: onTap,
                        icon: Icon(
                          selected ? Icons.check_rounded : Icons.link_rounded,
                          size: 16,
                        ),
                        label: Text(
                          selected ? '已绑定' : (hasBinding ? '重新绑定' : '绑定'),
                        ),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metaText() {
    final parts = <String>[
      if ((item.typeDescription ?? '').isNotEmpty) item.typeDescription!,
      if (item.episodeCount > 0) '${item.episodeCount} 集',
      if (item.rating > 0) '评分 ${item.rating.toStringAsFixed(1)}',
      ?_startYear,
    ];
    return parts.join(' · ');
  }

  String? get _startYear {
    final value = item.startDate;
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value)?.year.toString();
  }
}

class _DandanplayAlignmentResult {
  final int? chapterIndex;
  final int? episodeIndex;
  final bool clear;

  const _DandanplayAlignmentResult.align({
    required int this.chapterIndex,
    required int this.episodeIndex,
  }) : clear = false;

  const _DandanplayAlignmentResult.clear()
    : chapterIndex = null,
      episodeIndex = null,
      clear = true;
}

class _DandanplayAlignmentDialog extends StatefulWidget {
  final List<AnimeChapter> chapters;
  final List<DandanplayBangumiEpisode> episodes;
  final int initialChapterIndex;
  final int initialEpisodeIndex;
  final bool hasExistingAlignment;

  const _DandanplayAlignmentDialog({
    required this.chapters,
    required this.episodes,
    required this.initialChapterIndex,
    required this.initialEpisodeIndex,
    required this.hasExistingAlignment,
  });

  @override
  State<_DandanplayAlignmentDialog> createState() =>
      _DandanplayAlignmentDialogState();
}

class _DandanplayAlignmentDialogState
    extends State<_DandanplayAlignmentDialog> {
  late int _chapterIndex;
  late int _episodeIndex;

  @override
  void initState() {
    super.initState();
    _chapterIndex = widget.initialChapterIndex.clamp(
      0,
      widget.chapters.length - 1,
    );
    _episodeIndex = widget.initialEpisodeIndex.clamp(
      0,
      widget.episodes.length - 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('对齐弹幕'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: _chapterIndex,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '视频第一集',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final entry in widget.chapters.indexed)
                  DropdownMenuItem<int>(
                    value: entry.$1,
                    child: Text(
                      entry.$2.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _chapterIndex = value);
              },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: _episodeIndex,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '弹幕第一集',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final entry in widget.episodes.indexed)
                  DropdownMenuItem<int>(
                    value: entry.$1,
                    child: Text(
                      _formatDandanplayEpisodeLabel(entry.$2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _episodeIndex = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        if (widget.hasExistingAlignment)
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              const _DandanplayAlignmentResult.clear(),
            ),
            child: const Text('清除对齐'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _DandanplayAlignmentResult.align(
              chapterIndex: _chapterIndex,
              episodeIndex: _episodeIndex,
            ),
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

String _formatDandanplayEpisodeLabel(DandanplayBangumiEpisode episode) {
  final number = episode.episodeNumber.trim();
  final title = episode.episodeTitle.trim();
  if (title.isNotEmpty) return title;
  if (number.isNotEmpty) return number;
  return '#${episode.episodeId}';
}

class _BoundAnimeChapterRow extends StatelessWidget {
  final AnimeChapter chapter;
  final bool selected;
  final bool selectionMode;
  final bool isDownloaded;
  final List<DandanplayBangumiEpisode> episodes;
  final int? selectedEpisodeId;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<int?> onEpisodeChanged;

  const _BoundAnimeChapterRow({
    required this.chapter,
    required this.selected,
    required this.selectionMode,
    required this.isDownloaded,
    required this.episodes,
    required this.selectedEpisodeId,
    required this.onTap,
    required this.onLongPress,
    required this.onEpisodeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final itemValues = <int?>[null, ...episodes.map((e) => e.episodeId)];
    final currentValue = itemValues.contains(selectedEpisodeId)
        ? selectedEpisodeId
        : null;

    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.26)
          : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final dropdownWidth = (constraints.maxWidth * 0.46)
                  .clamp(180.0, 340.0)
                  .toDouble();
              return Row(
                children: [
                  Icon(
                    selectionMode
                        ? selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked
                        : Icons.play_circle_outline_rounded,
                    color: selectionMode && selected
                        ? cs.primary
                        : cs.onSurfaceVariant,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            chapter.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isDownloaded) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.download_done_rounded,
                            color: Colors.green.shade600,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: dropdownWidth,
                    child: DropdownButtonFormField<int?>(
                      initialValue: currentValue,
                      isExpanded: true,
                      menuMaxHeight: 360,
                      decoration: const InputDecoration(
                        labelText: '弹幕',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('未绑定'),
                        ),
                        for (final episode in episodes)
                          DropdownMenuItem<int?>(
                            value: episode.episodeId,
                            child: Text(
                              _formatDandanplayEpisodeLabel(episode),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      selectedItemBuilder: (context) => [
                        const Text(
                          '未绑定',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        for (final episode in episodes)
                          Text(
                            _formatDandanplayEpisodeLabel(episode),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                      onChanged: episodes.isEmpty ? null : onEpisodeChanged,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnimeDetailHeader extends StatelessWidget {
  final _AnimeIntroViewData intro;
  final bool isCollected;

  const _AnimeDetailHeader({required this.intro, required this.isCollected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: intro.cover,
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
                child: CoverBrightnessFilter(
                  child: CachedNetworkImage(
                    imageUrl: intro.cover,
                    width: 96,
                    height: 124,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      intro.title,
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
                        if (intro.primaryStat != null)
                          _HeaderPill(
                            icon: intro.primaryStat!.icon,
                            text: intro.primaryStat!.text,
                          ),
                        if (intro.secondaryStat != null)
                          _HeaderPill(
                            icon: intro.secondaryStat!.icon,
                            text: intro.secondaryStat!.text,
                          ),
                        ...intro.headerMetadata.map(
                          (item) =>
                              _HeaderPill(icon: item.icon, text: item.text),
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

class _FabLabel extends StatelessWidget {
  final String text;
  final double maxWidth;

  const _FabLabel({required this.text, required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

class _AnimeInfoPanel extends StatelessWidget {
  final _AnimeIntroViewData intro;
  final bool isCollected;
  final bool collectSubmitting;
  final bool briefExpanded;
  final String? refreshedAtText;
  final VoidCallback onToggleCollect;
  final VoidCallback onToggleBrief;

  const _AnimeInfoPanel({
    required this.intro,
    required this.isCollected,
    required this.collectSubmitting,
    required this.briefExpanded,
    required this.refreshedAtText,
    required this.onToggleCollect,
    required this.onToggleBrief,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final chips = <Widget>[...intro.chips.map((item) => _InfoChip(text: item))];

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
        if (intro.metaLine != null && intro.metaLine!.isNotEmpty)
          Text(
            intro.metaLine!,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        if (intro.subMetaLine != null && intro.subMetaLine!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            intro.subMetaLine!,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (refreshedAtText != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.update, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '刷新于 $refreshedAtText',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
        if (intro.summary.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            '简介',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onToggleBrief,
            child: Text(
              intro.summary,
              maxLines: briefExpanded ? null : 4,
              overflow: briefExpanded ? null : TextOverflow.ellipsis,
              style: tt.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
        if (intro.extraInfoLines.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            '资料',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          for (final line in intro.extraInfoLines.take(8)) ...[
            Text(
              line,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ],
    );
  }
}

class _AnimeIntroViewData {
  final String title;
  final String cover;
  final String summary;
  final List<String> chips;
  final String? metaLine;
  final String? subMetaLine;
  final List<String> extraInfoLines;
  final ({IconData icon, String text})? primaryStat;
  final ({IconData icon, String text})? secondaryStat;
  final List<({IconData icon, String text})> headerMetadata;

  const _AnimeIntroViewData({
    required this.title,
    required this.cover,
    required this.summary,
    this.chips = const [],
    this.metaLine,
    this.subMetaLine,
    this.extraInfoLines = const [],
    this.primaryStat,
    this.secondaryStat,
    this.headerMetadata = const [],
  });

  factory _AnimeIntroViewData.fromAnime(Anime anime) => _AnimeIntroViewData(
    title: anime.name,
    cover: anime.cover,
    summary: anime.brief?.trim() ?? '',
    chips: [
      if (anime.category?['display'] != null)
        anime.category!['display'].toString(),
      if (anime.cartoonType?['display'] != null)
        anime.cartoonType!['display'].toString(),
      if (anime.grade?['display'] != null) anime.grade!['display'].toString(),
      if (anime.freeType?['display'] != null)
        anime.freeType!['display'].toString(),
      if (anime.bSubtitle) '字幕',
      ...anime.themes
          .map((e) => e.name)
          .where((item) => item.trim().isNotEmpty),
    ],
    metaLine:
        [
          if (anime.company != null) anime.company!.name,
          if (anime.years != null) anime.years!,
        ].where((item) => item.trim().isNotEmpty).join(' · ').trim().isEmpty
        ? null
        : [
            if (anime.company != null) anime.company!.name,
            if (anime.years != null) anime.years!,
          ].where((item) => item.trim().isNotEmpty).join(' · '),
    subMetaLine: anime.lastChapter?['name'] == null
        ? null
        : '最新：${anime.lastChapter!['name']}',
    primaryStat: (
      icon: Icons.local_fire_department,
      text: ComicCard.formatPopular(anime.popular),
    ),
    secondaryStat: anime.count > 0
        ? (icon: Icons.video_collection_outlined, text: '共 ${anime.count} 集')
        : null,
  );

  factory _AnimeIntroViewData.fromDandanplay(
    DandanplayBangumi bangumi, {
    Anime? fallbackAnime,
  }) {
    final metadataMap = _bangumiMetadataMap(bangumi.metadata);
    final summary = _cleanBangumiSummary(bangumi.summary, bangumi.intro);
    final title = bangumi.animeTitle.trim().isNotEmpty
        ? bangumi.animeTitle.trim()
        : fallbackAnime?.name ?? '';
    final cover = bangumi.imageUrl?.trim().isNotEmpty == true
        ? bangumi.imageUrl!.trim()
        : fallbackAnime?.cover ?? '';
    final chips = <String>[];
    void addChip(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || chips.contains(trimmed)) return;
      chips.add(trimmed);
    }

    if ((bangumi.typeDescription ?? '').trim().isNotEmpty) {
      addChip(bangumi.typeDescription!);
    }
    if (bangumi.isOnAir) addChip('连载中');
    if (bangumi.isRestricted) addChip('受限');
    for (final item
        in bangumi.metadata.where((item) => item.contains(':')).take(6)) {
      addChip(item.split(':').first);
    }
    final extraLines = <String>[
      if ((bangumi.intro ?? '').trim().isNotEmpty) bangumi.intro!.trim(),
      ...bangumi.metadata.where(
        (item) =>
            !_isHeaderMetadata(item) &&
            item.trim().isNotEmpty &&
            item.trim() != (bangumi.intro ?? '').trim(),
      ),
    ];
    final episodeCountLabel = _formatEpisodeCountLabel(metadataMap['话数'] ?? '');

    return _AnimeIntroViewData(
      title: title,
      cover: cover,
      summary: summary,
      chips: chips,
      metaLine:
          [
            if ((metadataMap['放送开始'] ?? '').isNotEmpty) metadataMap['放送开始']!,
            if ((metadataMap['原作'] ?? '').isNotEmpty) metadataMap['原作']!,
          ].join(' · ').trim().isEmpty
          ? null
          : [
              if ((metadataMap['放送开始'] ?? '').isNotEmpty) metadataMap['放送开始']!,
              if ((metadataMap['原作'] ?? '').isNotEmpty) metadataMap['原作']!,
            ].join(' · '),
      subMetaLine: (metadataMap['导演'] ?? '').isNotEmpty
          ? '导演：${metadataMap['导演']}'
          : null,
      extraInfoLines: extraLines,
      primaryStat: bangumi.rating > 0
          ? (icon: Icons.star_rounded, text: bangumi.rating.toStringAsFixed(1))
          : (fallbackAnime != null
                ? (
                    icon: Icons.local_fire_department,
                    text: ComicCard.formatPopular(fallbackAnime.popular),
                  )
                : null),
      secondaryStat: episodeCountLabel != null
          ? (icon: Icons.video_collection_outlined, text: episodeCountLabel)
          : ((metadataMap['话数'] ?? '').isNotEmpty
                ? null
                : (bangumi.episodes.isNotEmpty
                      ? (
                          icon: Icons.video_collection_outlined,
                          text: '共 ${bangumi.episodes.length} 集',
                        )
                      : (fallbackAnime != null && fallbackAnime.count > 0
                            ? (
                                icon: Icons.video_collection_outlined,
                                text: '共 ${fallbackAnime.count} 集',
                              )
                            : null))),
      headerMetadata: [
        if ((metadataMap['放送星期'] ?? '').isNotEmpty)
          (icon: Icons.calendar_today_outlined, text: metadataMap['放送星期']!),
      ],
    );
  }

  static Map<String, String> _bangumiMetadataMap(List<String> metadata) {
    final result = <String, String>{};
    for (final item in metadata) {
      final index = item.indexOf(':');
      if (index <= 0 || index >= item.length - 1) continue;
      final key = item.substring(0, index).trim();
      final value = item.substring(index + 1).trim();
      if (key.isEmpty || value.isEmpty || result.containsKey(key)) continue;
      result[key] = value;
    }
    return result;
  }

  static bool _isHeaderMetadata(String item) =>
      item.startsWith('话数:') || item.startsWith('放送星期:');

  static String? _formatEpisodeCountLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '*') return null;
    final matched = RegExp(r'\d+').firstMatch(value)?.group(0);
    if (matched != null && matched.isNotEmpty) {
      return '共 ${int.parse(matched)} 集';
    }
    return null;
  }

  static String _cleanBangumiSummary(String? summary, String? intro) {
    final raw = (summary ?? '').trim();
    if (raw.isEmpty) return (intro ?? '').trim();
    final markerIndex = raw.indexOf('[简介原文]');
    final cleaned = markerIndex >= 0 ? raw.substring(0, markerIndex) : raw;
    final normalized = cleaned
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n\n');
    return normalized.isNotEmpty ? normalized : (intro ?? '').trim();
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
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final backgroundColor = selected
        ? cs.secondaryContainer
        : cs.surfaceContainerLow;
    final foregroundColor = selected ? cs.onSecondaryContainer : cs.onSurface;
    final subtitle = isDownloaded
        ? '已下载'
        : isDownloading && progress != null
        ? '下载 ${progress!.completed}/${progress!.total}'
        : isQueued
        ? '排队中'
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? cs.primary : Colors.transparent,
          width: 1.4,
        ),
      ),
      child: Stack(
        children: [
          Material(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTap,
              onLongPress: onLongPress,
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
                          fontWeight: selected ? FontWeight.bold : null,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: tt.labelSmall?.copyWith(
                            color: selected
                                ? foregroundColor.withValues(alpha: 0.8)
                                : cs.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (selectionMode)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? cs.primary : cs.onSurfaceVariant,
                size: 16,
              ),
            )
          else if (isDownloaded)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(
                Icons.download_done_rounded,
                color: Colors.green.shade600,
                size: 16,
              ),
            ),
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
                  value: progress!.ratio,
                ),
              ),
            ),
        ],
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
