import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';

import '../api/api_client.dart';
import '../api/dandanplay_api.dart';
import '../models/anime.dart';
import '../models/user_manager.dart';
import '../utils/chinese_converter.dart';
import '../utils/data_cache.dart';
import '../utils/toast.dart';
import 'profile_page.dart';

part 'anime_player/media_open_diagnosis.dart';
part 'anime_player/player_controls.dart';
part 'anime_player/video_link_panel.dart';
part 'anime_player/danmaku_panels.dart';
part 'anime_player/chapter_selector.dart';
part 'anime_player/error_panel.dart';
part 'anime_player/player_settings_panel.dart';

class AnimePlayerPage extends StatefulWidget {
  final String animeName;
  final String pathWord;
  final String chapterUuid;
  final String chapterName;
  final String line;
  final List<AnimeChapter> chapters;

  const AnimePlayerPage({
    super.key,
    required this.animeName,
    required this.pathWord,
    required this.chapterUuid,
    required this.chapterName,
    required this.line,
    this.chapters = const [],
  });

  @override
  State<AnimePlayerPage> createState() => _AnimePlayerPageState();
}

class _AnimePlayerPageState extends State<AnimePlayerPage> {
  static const _videoUserAgent =
      'Mozilla/5.0 (Linux; Android 12; 23117RK66C Build/V417IR; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/110.0.5481.154 Mobile Safari/537.36';
  static const _maxPlayerLogLines = 24;
  static const _videoLinkCacheTtl = Duration(hours: 6);

  final _api = ApiClient();
  final _cache = DataCache();
  final _user = UserManager();
  late final Player _player = Player(
    configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn),
  );
  late final VideoController _videoController = VideoController(_player);
  AnimePlayback? _playback;
  late String _currentChapterUuid;
  late String _currentChapterName;
  late String _line;
  String? _videoUrl;
  bool _loading = true;
  bool _buffering = false;
  bool _requiresLogin = false;
  int _openMediaSerial = 0;
  String? _error;
  String? _rawError;
  final List<String> _recentPlayerLogs = <String>[];

  DanmakuController? _danmakuController;
  Map<int, List<DanmakuContentItem>> _danmakuItems = {};
  int _lastDanmakuSec = -1;
  int _danmakuSurfaceGeneration = 0;
  bool _danmakuVisible = true;

  // 内联搜索
  List<String> _searchSegments = [];
  Set<int> _selectedSegmentIndices = {};
  final _searchController = TextEditingController();
  List<DandanplayEpisode> _inlineResults = [];
  bool _inlineSearching = false;
  bool _hasSearched = false;
  int? _selectedDanmakuEpisodeId;
  int? _loadingDanmakuEpisodeId;

  @override
  void initState() {
    super.initState();
    _currentChapterUuid = widget.chapterUuid;
    _currentChapterName = widget.chapterName;
    _line = widget.line;
    _danmakuVisible = _user.danmakuEnabled;

    _player.stream.playing.listen((playing) {
      if (!mounted) return;
      if (playing) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
      if (playing && _danmakuVisible) {
        _danmakuController?.resume();
      } else {
        _danmakuController?.pause();
      }
    });

    _player.stream.position.listen((position) {
      if (!mounted) return;
      if (_player.state.playing && _danmakuVisible) {
        final sec = position.inSeconds;
        if (sec != _lastDanmakuSec) {
          if ((sec - _lastDanmakuSec).abs() > 2) {
            _danmakuController?.clear();
          }
          _lastDanmakuSec = sec;
          if (_danmakuItems.containsKey(sec)) {
            for (final item in _danmakuItems[sec]!) {
              _danmakuController?.addDanmaku(item);
            }
          }
        }
      }
    });

    _player.stream.buffering.listen((buffering) {
      if (!mounted) return;
      setState(() => _buffering = buffering);
    });

    _player.stream.log.listen(_rememberPlayerLog);
    _player.stream.error.listen((error) {
      if (!mounted) return;
      setState(() {
        _error = _formatPlayerError(error);
        _rawError = _buildPlayerDebugReport(error);
      });
    });

    _load();
  }

  @override
  void dispose() {
    _openMediaSerial++; // 阻止正在进行的媒体加载
    _player.dispose();
    WakelockPlus.disable();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _buffering = false;
      _requiresLogin = false;
      _error = null;
      _videoUrl = null;
      _danmakuItems = {};
      _matchCandidates = [];
      _isAutoMatched = false;
      _selectedDanmakuEpisodeId = null;
      _loadingDanmakuEpisodeId = null;
    });

    if (!_user.isLoggedIn) {
      setState(() {
        _loading = false;
        _requiresLogin = true;
        _error = '登录后才能播放该视频';
      });
      return;
    }

    try {
      final playback = await _getPlayback(forceRefresh: forceRefresh);
      final videoUrl = _resolveVideoUrl(playback.chapter);
      if (videoUrl.isEmpty) {
        throw StateError('视频链接为空');
      }

      if (!mounted) return;
      setState(() {
        _playback = playback;
        _currentChapterName = playback.chapter.name.isNotEmpty
            ? playback.chapter.name
            : _currentChapterName;
        _videoUrl = videoUrl;
        _loading = false;
        _buffering = true;
      });
      unawaited(_openMedia(videoUrl));
      unawaited(_autoMatchDanmaku());
    } catch (e) {
      debugPrint('AnimePlayerPage load error: $e');
      if (!mounted) return;
      final requiresLogin = _isUnauthorized(e);
      if (requiresLogin) {
        await _user.logout();
        if (!mounted) return;
      }
      setState(() {
        _loading = false;
        _requiresLogin = requiresLogin;
        _error = requiresLogin ? '登录后才能播放该视频' : _formatLoadError(e);
        _rawError = e.toString();
      });
    }
  }

  bool _isUnauthorized(Object error) =>
      error is DioException && error.response?.statusCode == 401;

  String _formatLoadError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final message =
            data['message']?.toString() ??
            (data['results'] is Map
                ? data['results']['detail']?.toString()
                : null);
        if (message != null && message.isNotEmpty) return message;
      }
      final statusCode = error.response?.statusCode;
      if (statusCode != null) return '请求失败（$statusCode）';
      final message = error.message;
      if (message != null && message.isNotEmpty) return message;
    }
    return error.toString();
  }

  void _rememberPlayerLog(PlayerLog log) {
    final line = '[${log.level}] ${log.prefix}: ${log.text}';
    if (_recentPlayerLogs.isNotEmpty && _recentPlayerLogs.last == line) return;
    _recentPlayerLogs.add(line);
    if (_recentPlayerLogs.length > _maxPlayerLogLines) {
      _recentPlayerLogs.removeRange(
        0,
        _recentPlayerLogs.length - _maxPlayerLogLines,
      );
    }
    debugPrint('AnimePlayerPage player log: $line');
  }

  String _buildPlayerDebugReport(
    String message, {
    _MediaOpenDiagnosis? diagnosis,
  }) {
    final buffer = StringBuffer()..writeln(message);
    if (_recentPlayerLogs.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('media_kit/mpv 日志:');
      for (final line in _recentPlayerLogs) {
        buffer.writeln(line);
      }
    }
    final diagnosisText = diagnosis?.toDebugString();
    if (diagnosisText != null && diagnosisText.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('快速诊断:')
        ..writeln(diagnosisText);
    }
    return buffer.toString().trim();
  }

  String _formatPlayerError(String message, {_MediaOpenDiagnosis? diagnosis}) {
    final lower = message.toLowerCase();
    final manifestStatus = diagnosis?.manifestStatus;
    final segmentStatus = diagnosis?.segmentStatus;
    if (lower.contains('403') ||
        lower.contains('forbidden') ||
        manifestStatus == 403 ||
        segmentStatus == 403) {
      return '视频源拒绝访问（403）';
    }
    if (lower.contains('404') ||
        lower.contains('not found') ||
        manifestStatus == 404 ||
        segmentStatus == 404) {
      return '视频地址已失效（404）';
    }
    if (lower.contains('certificate') ||
        lower.contains('tls') ||
        lower.contains('ssl')) {
      return '视频证书校验失败';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return '视频连接超时';
    }
    if (diagnosis?.networkLooksHealthy == true) {
      return '视频源可访问，但播放器无法解析该视频流';
    }
    if (lower.contains('127.0.0.1') ||
        lower.contains('localhost') ||
        lower.contains('failed to open')) {
      return '视频加载失败，请开启代理后重试';
    }
    return message;
  }

  Future<_MediaOpenDiagnosis> _diagnoseMediaOpen(String videoUrl) async {
    final uri = Uri.tryParse(videoUrl);
    if (uri == null || !uri.hasScheme) {
      return const _MediaOpenDiagnosis(manifestError: '视频地址不是合法 URI');
    }

    final dio = Dio(
      BaseOptions(
        headers: _videoHttpHeaders,
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status != null && status < 600,
      ),
    );

    try {
      final manifestResponse = await dio.getUri<String>(uri);
      final manifestText = manifestResponse.data ?? '';
      final manifestLooksLikeHls = manifestText.contains('#EXTM3U');
      final firstSegment = manifestLooksLikeHls
          ? manifestText
                .split(RegExp(r'\r?\n'))
                .map((line) => line.trim())
                .firstWhere(
                  (line) => line.isNotEmpty && !line.startsWith('#'),
                  orElse: () => '',
                )
          : '';
      final segmentUri = firstSegment.isEmpty
          ? null
          : uri.resolve(firstSegment);

      int? segmentStatus;
      int? segmentBytes;
      String? segmentError;
      if (segmentUri != null) {
        try {
          final segmentResponse = await dio.getUri<List<int>>(
            segmentUri,
            options: Options(responseType: ResponseType.bytes),
          );
          segmentStatus = segmentResponse.statusCode;
          segmentBytes = segmentResponse.data?.length;
        } on DioException catch (e) {
          segmentStatus = e.response?.statusCode;
          segmentError = _formatLoadError(e);
        }
      }

      return _MediaOpenDiagnosis(
        manifestStatus: manifestResponse.statusCode,
        manifestLooksLikeHls: manifestLooksLikeHls,
        manifestError: manifestResponse.statusCode == 200
            ? null
            : '请求失败（${manifestResponse.statusCode ?? 'unknown'}）',
        firstSegmentUrl: segmentUri?.toString(),
        segmentStatus: segmentStatus,
        segmentBytes: segmentBytes,
        segmentError: segmentError ?? (segmentUri == null ? '未解析出分片地址' : null),
      );
    } on DioException catch (e) {
      return _MediaOpenDiagnosis(
        manifestStatus: e.response?.statusCode,
        manifestError: _formatLoadError(e),
      );
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _enrichOpenMediaFailure({
    required int serial,
    required String videoUrl,
    required String rawMessage,
  }) async {
    final diagnosis = await _diagnoseMediaOpen(videoUrl);
    if (!mounted || serial != _openMediaSerial) return;
    setState(() {
      _error = _formatPlayerError(rawMessage, diagnosis: diagnosis);
      _rawError = _buildPlayerDebugReport(rawMessage, diagnosis: diagnosis);
    });
  }

  Future<void> _goLogin() async {
    final loggedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (loggedIn == true && mounted) {
      await _load();
    }
  }

  String get _videoLinkCacheKey =>
      'anime_video_link_v1_${widget.pathWord}_${_currentChapterUuid}_$_line';

  Future<AnimePlayback?> _readCachedPlayback() async {
    final cached = await _cache.get(_videoLinkCacheKey);
    if (cached is! Map) return null;

    try {
      final playback = AnimePlayback.fromJson(
        Map<String, dynamic>.from(cached),
      );
      if (_resolveVideoUrl(playback.chapter).isEmpty) {
        await _cache.remove(_videoLinkCacheKey);
        return null;
      }
      return playback;
    } catch (e) {
      debugPrint('AnimePlayerPage cached playback error: $e');
      await _cache.remove(_videoLinkCacheKey);
      return null;
    }
  }

  Future<AnimePlayback> _getPlayback({required bool forceRefresh}) async {
    if (forceRefresh) {
      await _cache.remove(_videoLinkCacheKey);
    } else {
      final cachedPlayback = await _readCachedPlayback();
      if (cachedPlayback != null) return cachedPlayback;
    }

    final playback = await _api.getAnimePlayback(
      widget.pathWord,
      _currentChapterUuid,
      line: _line,
    );
    if (_resolveVideoUrl(playback.chapter).isNotEmpty) {
      await _cache.put(
        _videoLinkCacheKey,
        playback.toJson(),
        ttl: _videoLinkCacheTtl,
      );
    }
    return playback;
  }

  Future<void> _refreshPlayback() async {
    if (_loading) return;
    await _load(forceRefresh: true);
  }

  Future<void> _openMedia(String videoUrl) async {
    final serial = ++_openMediaSerial;
    _recentPlayerLogs.clear();
    if (mounted) {
      setState(() {
        _buffering = true;
        _error = null;
        _rawError = null;
      });
    }

    try {
      await _player.open(
        Media(videoUrl, httpHeaders: _videoHttpHeaders),
        play: true,
      );
      if (!mounted || serial != _openMediaSerial) return;
      setState(() {
        _buffering = false;
        _error = null;
        _rawError = null;
      });
    } catch (e) {
      debugPrint('AnimePlayerPage open media error: $e');
      final rawMessage = e.toString();
      if (!mounted || serial != _openMediaSerial) return;
      setState(() {
        _buffering = false;
        _error = _formatPlayerError(rawMessage);
        _rawError = _buildPlayerDebugReport(rawMessage);
      });
      unawaited(
        _enrichOpenMediaFailure(
          serial: serial,
          videoUrl: videoUrl,
          rawMessage: rawMessage,
        ),
      );
    }
  }

  static const _videoHttpHeaders = {
    'User-Agent': _videoUserAgent,
    'Connection': 'Keep-Alive',
    'Accept-Encoding': 'gzip',
  };

  String _resolveVideoUrl(AnimePlaybackChapter chapter) {
    if (chapter.video.isNotEmpty) return chapter.video;
    for (final url in chapter.videoList) {
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  String _removeParentheses(String text) =>
      text.replaceAll(RegExp(r'\([^)]*\)'), '').trim();

  Future<void> _switchLine(String line) async {
    if (line == _line || _loading) return;
    setState(() => _line = line);
    await _load();
  }

  Future<void> _openChapter(AnimeChapter chapter) async {
    if (chapter.uuid == _currentChapterUuid) return;
    if (_loading) {
      showToast(context, '视频加载中，请稍后再切换', isError: true);
      return;
    }
    final line = _resolveChapterLine(chapter) ?? _line;
    if (line.isEmpty) {
      showToast(context, '当前选集暂无可用线路', isError: true);
      return;
    }

    setState(() {
      _currentChapterUuid = chapter.uuid;
      _currentChapterName = chapter.name;
      _line = line;
    });
    await _load();
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

  Future<void> _copyVideoUrl() async {
    final url = _videoUrl;
    if (url == null || url.isEmpty) {
      showToast(context, '暂无可复制的视频链接', isError: true);
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    showToast(context, '视频链接已复制到剪贴板');
  }

  Future<void> _openVideoUrl() async {
    final url = _videoUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      showToast(context, '暂无可打开的视频链接', isError: true);
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      showToast(context, '无法打开视频链接', isError: true);
    }
  }

  String get _title => _playback?.chapter.name.isNotEmpty == true
      ? _playback!.chapter.name
      : _currentChapterName;

  void _skipForward() {
    final duration = _player.state.duration;
    final position = _player.state.position;
    final newPosition =
        position + Duration(seconds: UserManager().animeSkipSeconds);
    if (newPosition < duration) {
      _player.seek(newPosition);
    } else {
      _player.seek(duration);
    }
  }

  Widget _buildVideoWithControls() {
    return _buildVideoSurface(_videoController, fullscreen: false);
  }

  List<DandanplayEpisode> _matchCandidates = [];
  bool _isAutoMatched = false;

  Future<void> _autoMatchDanmaku() async {
    String animeName = widget.animeName;
    try {
      animeName = await ChineseConverter.convertToSimplifiedChinese(
        widget.animeName,
      );
    } catch (_) {}
    final chapterName = _removeParentheses(_currentChapterName);
    _setupSearchSegments(animeName, chapterName);

    if (!_user.isAutoMatchDanmaku) return;
    try {
      if (!mounted) return;
      setState(() {
        _matchCandidates = [];
        _isAutoMatched = false;
      });

      final fileName = '$animeName $chapterName';

      if (!mounted) return;
      final response = await DandanplayApi().getRawMatch(fileName);
      if (!mounted) return;

      if (response == null || response['success'] != true) return;

      final matches = (response['matches'] as List)
          .map(
            (ep) => DandanplayEpisode(
              episodeId: ep['episodeId'] as int,
              animeTitle: ep['animeTitle'] as String,
              episodeTitle: ep['episodeTitle'] as String,
            ),
          )
          .toList();

      if (!mounted) return;

      if (matches.isEmpty || response['isMatched'] != true) return;

      await _loadDanmakuForEpisode(matches.first.episodeId, silent: true);
      if (!mounted) return;
      setState(() {
        _isAutoMatched = true;
        _matchCandidates = [matches.first];
        _selectedDanmakuEpisodeId = matches.first.episodeId;
      });
    } catch (e) {
      debugPrint('AutoMatchDanmaku error: $e');
    }
  }

  void _setupSearchSegments(String animeName, String chapterName) {
    _searchSegments = animeName
        .split(RegExp(r'[\s\p{P}]+', unicode: true))
        .where((s) => s.isNotEmpty)
        .toList();
    if (chapterName.isNotEmpty) _searchSegments.add(chapterName);
    _selectedSegmentIndices = Set.from(
      List.generate(_searchSegments.length, (i) => i),
    );
    _syncSearchText();
    // 如果有缓存，直接显示
    _doInlineSearch(showLoading: false);
  }

  void _syncSearchText() {
    final parts = _selectedSegmentIndices
        .map((i) => _searchSegments[i])
        .toList();
    _searchController.text = parts.join(' ');
  }

  Future<void> _matchDanmaku() async {
    String animeName = widget.animeName;
    try {
      animeName = await ChineseConverter.convertToSimplifiedChinese(
        widget.animeName,
      );
    } catch (_) {}
    final chapterName = _removeParentheses(_currentChapterName);
    _setupSearchSegments(animeName, chapterName);
  }

  void _toggleSearchSegment(int index) {
    setState(() {
      if (_selectedSegmentIndices.contains(index)) {
        if (_selectedSegmentIndices.length > 1) {
          _selectedSegmentIndices.remove(index);
        }
      } else {
        _selectedSegmentIndices.add(index);
      }
    });
    _syncSearchText();
  }

  Future<void> _doInlineSearch({bool showLoading = true}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    if (showLoading) setState(() => _inlineSearching = true);
    try {
      final results = await DandanplayApi().search(query);
      if (mounted) {
        setState(() {
          _inlineResults = results;
          _inlineSearching = false;
          _hasSearched = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _inlineSearching = false;
          _hasSearched = true;
        });
        if (showLoading) showToast(context, '搜索失败: $e', isError: true);
      }
    }
  }

  void _forceRefreshSearch() {
    if (!DandanplayApi().clearCache()) {
      showToast(context, '不要频繁刷新！', isError: true);
      return;
    }
    _doInlineSearch();
  }

  Future<void> _loadDanmakuForEpisode(
    int episodeId, {
    bool silent = false,
  }) async {
    if (!silent && mounted) {
      setState(() => _loadingDanmakuEpisodeId = episodeId);
    }
    try {
      final comments = await DandanplayApi().getComments(episodeId);
      if (!mounted) return;
      final blocklist = _user.danmakuBlocklist;
      final items = <DanmakuContentItem>[];
      final filteredComments = <dynamic>[];
      for (final c in comments) {
        if (blocklist.any((w) => c.text.contains(w))) continue;
        DanmakuItemType mode = DanmakuItemType.scroll;
        if (c.mode == 5) mode = DanmakuItemType.top;
        if (c.mode == 4) mode = DanmakuItemType.bottom;
        final colorStr = c.color.toRadixString(16).padLeft(6, '0');
        items.add(
          DanmakuContentItem(
            c.text,
            type: mode,
            color: Color(int.parse("FF$colorStr", radix: 16)),
          ),
        );
        filteredComments.add(c);
      }
      if (!mounted) return;
      setState(() {
        _loadingDanmakuEpisodeId = null;
        _selectedDanmakuEpisodeId = episodeId;
        _danmakuItems = {};
        for (int i = 0; i < items.length; i++) {
          final time = filteredComments[i].time.toInt();
          _danmakuItems.putIfAbsent(time, () => []).add(items[i]);
        }
      });
      _lastDanmakuSec = -1;
      // if (!silent) showToast(context, '共加载了 ${items.length} 条弹幕');
    } catch (e) {
      debugPrint('LoadDanmaku error: $e');
      if (mounted && _loadingDanmakuEpisodeId == episodeId) {
        setState(() => _loadingDanmakuEpisodeId = null);
      }
      if (!silent) showToast(context, '加载弹幕失败: $e', isError: true);
    }
  }

  void _toggleDanmaku() {
    if (_danmakuVisible) {
      _danmakuController?.clear();
    }
    setState(() {
      _danmakuVisible = !_danmakuVisible;
    });
    _user.setDanmakuEnabled(_danmakuVisible);
    if (_danmakuVisible) {
      _lastDanmakuSec = -1;
    }
  }

  Widget _buildVideoSurface(
    VideoController controller, {
    required bool fullscreen,
  }) {
    Widget? danmakuView;
    if (_danmakuVisible) {
      danmakuView = DanmakuScreen(
        key: ValueKey('danmaku-$fullscreen-$_danmakuSurfaceGeneration'),
        createdController: (c) {
          _danmakuController = c;
          if (_player.state.playing && _danmakuVisible) {
            c.resume();
          } else {
            c.pause();
          }
        },
        option: DanmakuOption(
          fontSize: _user.danmakuFontSize,
          duration: 8,
          opacity: _user.danmakuOpacity,
          area: _user.danmakuArea,
          hideScroll: _user.danmakuHideScroll,
          hideTop: _user.danmakuHideTop,
          hideBottom: _user.danmakuHideBottom,
        ),
      );
    }

    return _VideoPlayerSurface(
      controller: controller,
      fullscreen: fullscreen,
      danmakuView: danmakuView,
      danmakuVisible: _danmakuVisible,
      onMatchDanmaku: _matchDanmaku,
      onToggleDanmaku: _toggleDanmaku,
      onSkipForward: _skipForward,
      onSettings: _showSettingsPanel,
      chapters: _chapters,
      currentChapterUuid: _currentChapterUuid,
      onChapterSelected: _openChapter,
      onFullscreen: fullscreen
          ? () => Navigator.maybePop(context)
          : _fullscreen,
    );
  }

  Future<void> _fullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (!mounted) return;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Center(
                child: _buildVideoSurface(_videoController, fullscreen: true),
              ),
            ),
          ),
        ),
      );
    } finally {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      if (mounted && _danmakuVisible) {
        _danmakuController = null;
        _lastDanmakuSec = -1;
        setState(() => _danmakuSurfaceGeneration++);
      }
    }
  }

  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
      ),
      builder: (_) => _PlayerSettingsPanel(
        onChanged: () => setState(() {}),
        danmakuController: _danmakuController,
        danmakuVisible: _danmakuVisible,
        onDanmakuVisibleChanged: (v) {
          setState(() => _danmakuVisible = v);
          _user.setDanmakuEnabled(v);
          if (v) _lastDanmakuSec = -1;
        },
      ),
    );
  }

  List<AnimeChapter> get _chapters {
    if (widget.chapters.isNotEmpty) return widget.chapters;
    return [
      AnimeChapter(
        name: _currentChapterName,
        uuid: _currentChapterUuid,
        vCover: '',
      ),
    ];
  }

  bool get _showLoadingOverlay => _loading || (_buffering && _error == null);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      onPopInvokedWithResult: (_, _) {
        _player.pause();
      },
      child: Scaffold(
        body: Column(
          children: [
            ColoredBox(
              color: cs.surface,
              child: SafeArea(
                bottom: false,
                child: _VideoTopBar(title: _title),
              ),
            ),
            ColoredBox(
              color: Colors.black,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: _error == null
                          ? _buildVideoWithControls()
                          : _ErrorPanel(
                              message: _error!,
                              rawError: _rawError,
                              requiresLogin: _requiresLogin,
                              onLogin: _goLogin,
                              onRetry: () => _load(),
                            ),
                    ),
                    if (_showLoadingOverlay)
                      ColoredBox(
                        color: const Color(0x66000000),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              if (_buffering && !_loading) ...[
                                const SizedBox(height: 12),
                                const Text(
                                  '正在缓冲...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '如果网络卡顿，建议开启代理访问',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshPlayback,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (_danmakuVisible) ...[
                      _DanmakuMatchPanel(
                        isAutoMatched: _isAutoMatched,
                        candidates: _matchCandidates,
                        onSelect: _loadDanmakuForEpisode,
                        danmakuVisible: _danmakuVisible,
                        hasDanmaku: _danmakuItems.isNotEmpty,
                      ),
                      const SizedBox(height: 12),
                      _InlineSearchPanel(
                        segments: _searchSegments,
                        selectedIndices: _selectedSegmentIndices,
                        searchController: _searchController,
                        results: _inlineResults,
                        searching: _inlineSearching,
                        hasSearched: _hasSearched,
                        selectedEpisodeId: _selectedDanmakuEpisodeId,
                        loadingEpisodeId: _loadingDanmakuEpisodeId,
                        onToggleSegment: _toggleSearchSegment,

                        onSearch: _doInlineSearch,
                        onRefresh: _forceRefreshSearch,
                        onSelectResult: (ep) =>
                            _loadDanmakuForEpisode(ep.episodeId),
                      ),
                      const SizedBox(height: 24),
                    ],
                    _ChapterSelector(
                      chapters: _chapters,
                      currentChapterUuid: _currentChapterUuid,
                      onSelected: _openChapter,
                    ),
                    const SizedBox(height: 24),
                    _VideoLinkPanel(
                      videoUrl: _videoUrl,
                      lines: _playback?.chapter.lines ?? const {},
                      currentLine: _line,
                      onCopy: _copyVideoUrl,
                      onOpen: _openVideoUrl,
                      onLineSelected: _switchLine,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
