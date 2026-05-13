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
import '../utils/toast.dart';
import 'profile_page.dart';

class _MediaOpenDiagnosis {
  final int? manifestStatus;
  final bool manifestLooksLikeHls;
  final String? manifestError;
  final String? firstSegmentUrl;
  final int? segmentStatus;
  final int? segmentBytes;
  final String? segmentError;

  const _MediaOpenDiagnosis({
    this.manifestStatus,
    this.manifestLooksLikeHls = false,
    this.manifestError,
    this.firstSegmentUrl,
    this.segmentStatus,
    this.segmentBytes,
    this.segmentError,
  });

  bool get networkLooksHealthy =>
      manifestStatus == 200 &&
      manifestLooksLikeHls &&
      segmentStatus == 200 &&
      (segmentBytes ?? 0) > 0;

  String toDebugString() {
    final buffer = StringBuffer();
    if (manifestStatus != null) {
      buffer.writeln('m3u8 状态: $manifestStatus');
    }
    if (manifestLooksLikeHls) {
      buffer.writeln('m3u8 内容: 已识别为 HLS 清单');
    } else if (manifestStatus == 200) {
      buffer.writeln('m3u8 内容: 返回 200，但内容不像标准 HLS 清单');
    }
    if (manifestError != null && manifestError!.isNotEmpty) {
      buffer.writeln('m3u8 错误: $manifestError');
    }
    if (firstSegmentUrl != null && firstSegmentUrl!.isNotEmpty) {
      buffer.writeln('首个分片: $firstSegmentUrl');
    }
    if (segmentStatus != null) {
      buffer.writeln('首个分片状态: $segmentStatus');
    }
    if (segmentBytes != null) {
      buffer.writeln('首个分片字节数: $segmentBytes');
    }
    if (segmentError != null && segmentError!.isNotEmpty) {
      buffer.writeln('首个分片错误: $segmentError');
    }
    if (networkLooksHealthy) {
      buffer.writeln('结论: m3u8 与首个分片都可访问，更像是播放器解析或解码兼容问题');
    }
    return buffer.toString().trim();
  }
}

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

  final _api = ApiClient();
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _buffering = false;
      _requiresLogin = false;
      _error = null;
      _videoUrl = null;
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
      final playback = await _api.getAnimePlayback(
        widget.pathWord,
        _currentChapterUuid,
        line: _line,
      );
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
                              onRetry: _load,
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
              child: ListView(
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
          ],
        ),
      ),
    );
  }
}

class _PlayerControlButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final double extent;
  final VoidCallback? onPressed;

  const _PlayerControlButton({
    required this.tooltip,
    required this.icon,
    required this.iconSize,
    required this.extent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: extent,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        iconSize: iconSize,
        color: Colors.white,
        disabledColor: Colors.white38,
      ),
    );
  }
}

class _VideoPlayerSurface extends StatefulWidget {
  final VideoController controller;
  final bool fullscreen;
  final VoidCallback onSkipForward;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final VoidCallback onMatchDanmaku;
  final VoidCallback onToggleDanmaku;
  final bool danmakuVisible;
  final Widget? danmakuView;

  const _VideoPlayerSurface({
    required this.controller,
    required this.fullscreen,
    required this.onSkipForward,
    required this.onSettings,
    required this.onFullscreen,
    required this.onMatchDanmaku,
    required this.onToggleDanmaku,
    required this.danmakuVisible,
    this.danmakuView,
  });

  @override
  State<_VideoPlayerSurface> createState() => _VideoPlayerSurfaceState();
}

class _VideoPlayerSurfaceState extends State<_VideoPlayerSurface> {
  static const _controlsAutoHideDelay = Duration(seconds: 3);

  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  // 手势处理状态
  double? _dragStartX;
  Duration? _dragTargetPosition;
  bool _isDraggingProgress = false;

  double? _dragStartY;
  bool _isDraggingVolume = false;
  bool _isDraggingBrightness = false;
  double _initialVolume = 0;
  double _initialBrightness = 0;
  double? _currentVolume;
  double? _currentBrightness;

  VideoController get controller => widget.controller;
  Player get player => widget.controller.player;

  @override
  void initState() {
    super.initState();
    _hideControlsTimer = Timer(_controlsAutoHideDelay, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  @override
  void didUpdateWidget(covariant _VideoPlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    setState(() => _controlsVisible = true);
    _startControlsAutoHideTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _startControlsAutoHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(_controlsAutoHideDelay, () {
      if (!mounted || !player.state.playing) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (!_controlsVisible || !player.state.playing) {
      _hideControlsTimer?.cancel();
      _hideControlsTimer = null;
      return;
    }
    _startControlsAutoHideTimer();
  }

  void _showControls() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    if (player.state.playing) {
      _startControlsAutoHideTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    const controlButtonSize = 24.0;
    const controlButtonExtent = 40.0;

    return StreamBuilder<Object>(
      stream: player.stream.position,
      builder: (context, _) {
        final state = player.state;
        final duration = state.duration;
        final position = state.position;
        final playing = state.playing;
        final progress = duration.inMilliseconds <= 0
            ? 0.0
            : (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              );

        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Video(controller: controller, controls: NoVideoControls),
              ),
              if (widget.danmakuView != null)
                Positioned.fill(
                  child: IgnorePointer(child: widget.danmakuView),
                ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTap: _togglePlay,
                  onHorizontalDragStart: (details) {
                    _dragStartX = details.globalPosition.dx;
                    _dragTargetPosition = player.state.position;
                    _isDraggingProgress = true;
                    _showControls();
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_dragStartX == null) return;
                    final delta = details.globalPosition.dx - _dragStartX!;
                    final screenWidth = MediaQuery.sizeOf(context).width;
                    // 左右滑动控制进度，滑动全屏距离相当于视频总时长的 1/2
                    final totalDuration = player.state.duration;
                    if (totalDuration == Duration.zero) return;

                    final deltaMs =
                        (delta / screenWidth) *
                        totalDuration.inMilliseconds *
                        0.5;
                    final targetMs =
                        player.state.position.inMilliseconds + deltaMs.toInt();
                    _dragTargetPosition = Duration(
                      milliseconds: targetMs.clamp(
                        0,
                        totalDuration.inMilliseconds,
                      ),
                    );
                    setState(() {});
                  },
                  onHorizontalDragEnd: (details) {
                    if (_isDraggingProgress && _dragTargetPosition != null) {
                      player.seek(_dragTargetPosition!);
                    }
                    _isDraggingProgress = false;
                    _dragStartX = null;
                    _dragTargetPosition = null;
                  },
                  onVerticalDragStart: (details) async {
                    _dragStartY = details.globalPosition.dy;
                    final screenWidth = MediaQuery.sizeOf(context).width;
                    if (details.globalPosition.dx > screenWidth / 2) {
                      _isDraggingVolume = true;
                      _initialVolume = player.state.volume / 100.0;
                    } else {
                      _isDraggingBrightness = true;
                      try {
                        _initialBrightness =
                            await ScreenBrightness().application;
                      } catch (_) {
                        _initialBrightness = 0.5;
                      }
                    }
                  },
                  onVerticalDragUpdate: (details) async {
                    if (_dragStartY == null) return;
                    final delta = _dragStartY! - details.globalPosition.dy;
                    final screenHeight = MediaQuery.sizeOf(context).height;
                    final ratio = delta / (screenHeight * 0.8);

                    if (_isDraggingVolume) {
                      final newVolume = (_initialVolume + ratio).clamp(
                        0.0,
                        1.0,
                      );
                      player.setVolume(newVolume * 100.0);
                      setState(() => _currentVolume = newVolume);
                    } else if (_isDraggingBrightness) {
                      final newBrightness = (_initialBrightness + ratio).clamp(
                        0.0,
                        1.0,
                      );
                      try {
                        await ScreenBrightness().setApplicationScreenBrightness(
                          newBrightness,
                        );
                      } catch (_) {}
                      setState(() => _currentBrightness = newBrightness);
                    }
                  },
                  onVerticalDragEnd: (details) {
                    _isDraggingVolume = false;
                    _isDraggingBrightness = false;
                    _dragStartY = null;
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) {
                        setState(() {
                          _currentVolume = null;
                          _currentBrightness = null;
                        });
                      }
                    });
                  },
                ),
              ),
              if (_isDraggingProgress && _dragTargetPosition != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_formatDuration(_dragTargetPosition!)} / ${_formatDuration(player.state.duration)}',
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                ),
              if (_currentVolume != null || _currentBrightness != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _currentVolume != null
                              ? (_currentVolume! <= 0
                                    ? Icons.volume_mute
                                    : Icons.volume_up)
                              : Icons.brightness_6,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${((_currentVolume ?? _currentBrightness!) * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!playing && _controlsVisible)
                Center(
                  child: IconButton.filledTonal(
                    onPressed: _togglePlay,
                    icon: const Icon(Icons.play_arrow),
                    iconSize: widget.fullscreen ? 56 : 44,
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black54,
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Listener(
                      onPointerDown: (_) => _showControls(),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            8,
                            22,
                            8,
                            widget.fullscreen ? 16 : 4,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2.4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                ),
                                child: Slider(
                                  value: progress,
                                  onChanged: (v) => player.seek(
                                    Duration(
                                      milliseconds:
                                          (duration.inMilliseconds * v).round(),
                                    ),
                                  ),
                                  activeColor: Colors.red,
                                  inactiveColor: Colors.white38,
                                ),
                              ),
                              Row(
                                children: [
                                  SizedBox(
                                    width: widget.fullscreen ? 132 : 104,
                                    child: Text(
                                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: widget.fullscreen ? 14 : 12,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      reverse: true,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _PlayerControlButton(
                                            tooltip: playing ? '暂停' : '播放',
                                            icon: playing
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                            iconSize: controlButtonSize,
                                            extent: controlButtonExtent,
                                            onPressed: _togglePlay,
                                          ),
                                          _PlayerControlButton(
                                            tooltip:
                                                '快进 ${UserManager().animeSkipSeconds}秒',
                                            icon: Icons.fast_forward,
                                            iconSize: controlButtonSize,
                                            extent: controlButtonExtent,
                                            onPressed: widget.onSkipForward,
                                          ),
                                          _PlayerControlButton(
                                            tooltip: widget.danmakuVisible
                                                ? '隐藏弹幕'
                                                : '显示弹幕',
                                            icon: widget.danmakuVisible
                                                ? Icons.subtitles
                                                : Icons.subtitles_off,
                                            iconSize: controlButtonSize,
                                            extent: controlButtonExtent,
                                            onPressed: widget.onToggleDanmaku,
                                          ),
                                          _PlayerControlButton(
                                            tooltip: '设置跳转秒数',
                                            icon: Icons.settings,
                                            iconSize: controlButtonSize,
                                            extent: controlButtonExtent,
                                            onPressed: widget.onSettings,
                                          ),
                                          _PlayerControlButton(
                                            tooltip: widget.fullscreen
                                                ? '退出全屏'
                                                : '全屏',
                                            icon: widget.fullscreen
                                                ? Icons.fullscreen_exit
                                                : Icons.fullscreen,
                                            iconSize: controlButtonSize,
                                            extent: controlButtonExtent,
                                            onPressed: widget.onFullscreen,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _togglePlay() {
    _showControls();
    if (player.state.playing) {
      player.pause();
    } else {
      player.play();
    }
    setState(() {});
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '${duration.inMinutes}:$seconds';
}

class _VideoTopBar extends StatelessWidget {
  final String title;

  const _VideoTopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoLinkPanel extends StatefulWidget {
  final String? videoUrl;
  final String currentLine;
  final Map<String, AnimeChapterLine> lines;
  final VoidCallback onCopy;
  final VoidCallback onOpen;
  final ValueChanged<String> onLineSelected;

  const _VideoLinkPanel({
    required this.videoUrl,
    required this.currentLine,
    required this.lines,
    required this.onCopy,
    required this.onOpen,
    required this.onLineSelected,
  });

  @override
  State<_VideoLinkPanel> createState() => _VideoLinkPanelState();
}

class _VideoLinkPanelState extends State<_VideoLinkPanel> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final url = widget.videoUrl;
    final hasUrl = url != null && url.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _collapsed = !_collapsed),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Icon(Icons.link, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                '视频链接',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Icon(
                _collapsed ? Icons.expand_more : Icons.expand_less,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
        if (!_collapsed) ...[
          const SizedBox(height: 10),
          SelectableText(
            hasUrl ? url : '加载后显示视频链接',
            style: tt.bodySmall?.copyWith(
              color: hasUrl ? cs.onSurface : cs.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: hasUrl ? widget.onCopy : null,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('复制'),
              ),
              FilledButton.tonalIcon(
                onPressed: hasUrl ? widget.onOpen : null,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('浏览器打开'),
              ),
              if (widget.lines.values.where((l) => l.config).length > 1)
                PopupMenuButton<String>(
                  tooltip: '切换线路',
                  initialValue: widget.currentLine,
                  onSelected: widget.onLineSelected,
                  itemBuilder: (context) => [
                    for (final entry in widget.lines.entries.where(
                      (e) => e.value.config,
                    ))
                      PopupMenuItem(
                        value: entry.value.pathWord.isNotEmpty
                            ? entry.value.pathWord
                            : entry.key,
                        child: Row(
                          children: [
                            if (_isCurrent(entry))
                              const Icon(Icons.check, size: 18)
                            else
                              const SizedBox(width: 18),
                            const SizedBox(width: 8),
                            Text(
                              entry.value.name.isNotEmpty
                                  ? entry.value.name
                                  : entry.key,
                            ),
                          ],
                        ),
                      ),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.alt_route, size: 18),
                    label: Text(_currentLineLabel),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  bool _isCurrent(MapEntry<String, AnimeChapterLine> entry) {
    return entry.key == widget.currentLine ||
        entry.value.pathWord == widget.currentLine;
  }

  String get _currentLineLabel {
    for (final entry in widget.lines.entries.where((e) => e.value.config)) {
      if (_isCurrent(entry)) {
        return entry.value.name.isNotEmpty ? entry.value.name : entry.key;
      }
    }
    return widget.currentLine;
  }
}

class _DanmakuMatchPanel extends StatelessWidget {
  final bool isAutoMatched;
  final List<DandanplayEpisode> candidates;
  final ValueChanged<int> onSelect;
  final bool danmakuVisible;
  final bool hasDanmaku;

  const _DanmakuMatchPanel({
    required this.isAutoMatched,
    required this.candidates,
    required this.onSelect,
    required this.danmakuVisible,
    required this.hasDanmaku,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.subtitles_outlined, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              '弹幕搜索',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (danmakuVisible && !hasDanmaku)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '未加载弹幕，请在下方选择',
                      style: tt.labelSmall?.copyWith(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (candidates.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ep in candidates)
                ActionChip(
                  avatar: isAutoMatched && candidates.indexOf(ep) == 0
                      ? const Icon(Icons.auto_awesome, size: 16)
                      : null,
                  label: Text(
                    '${ep.animeTitle} - ${ep.episodeTitle}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isAutoMatched && candidates.indexOf(ep) == 0
                          ? cs.onPrimaryContainer
                          : null,
                    ),
                  ),
                  backgroundColor: isAutoMatched && candidates.indexOf(ep) == 0
                      ? cs.primaryContainer
                      : null,
                  onPressed: () => onSelect(ep.episodeId),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _InlineSearchPanel extends StatelessWidget {
  final List<String> segments;
  final Set<int> selectedIndices;
  final TextEditingController searchController;
  final List<DandanplayEpisode> results;
  final bool searching;
  final bool hasSearched;
  final ValueChanged<int> onToggleSegment;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;
  final ValueChanged<DandanplayEpisode> onSelectResult;

  const _InlineSearchPanel({
    required this.segments,
    required this.selectedIndices,
    required this.searchController,
    required this.results,
    required this.searching,
    required this.hasSearched,
    required this.onToggleSegment,
    required this.onSearch,
    required this.onRefresh,
    required this.onSelectResult,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasResults = results.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (segments.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (int i = 0; i < segments.length; i++)
                FilterChip(
                  label: Text(segments[i]),
                  selected: selectedIndices.contains(i),
                  onSelected: (_) => onToggleSegment(i),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: searchController,
          decoration: InputDecoration(
            hintText: '输入搜索关键词',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            isDense: true,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: searching ? null : onRefresh,
                  tooltip: '强制刷新',
                ),
                IconButton(
                  icon: searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  onPressed: searching ? null : onSearch,
                ),
              ],
            ),
          ),
          onSubmitted: (_) => onSearch(),
        ),
        const SizedBox(height: 12),
        if (searching)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (hasResults)
          _buildGroupedResults(cs, tt)
        else if (hasSearched)
          _buildEmptyResults(cs, tt)
        else
          Text(
            '请选择分段或输入搜索词后点击搜索',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _buildGroupedResults(ColorScheme cs, TextTheme tt) {
    // 按动漫名称分组
    final grouped = <String, List<DandanplayEpisode>>{};
    for (final ep in results) {
      grouped.putIfAbsent(ep.animeTitle, () => []).add(ep);
    }
    final animeTitles = grouped.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '共找到 ${results.length} 条结果',
          style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        for (final title in animeTitles) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final ep in grouped[title]!)
                      ActionChip(
                        label: Text(
                          ep.episodeTitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                        backgroundColor: cs.secondaryContainer,
                        onPressed: () => onSelectResult(ep),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildEmptyResults(ColorScheme cs, TextTheme tt) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            '未找到相关弹幕',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '减少关键词，仅搜索作品名称\n如：「Re：从零开始的异世界生活第四季丧失篇」 搜索 \n  「从零开始的异世界生活第四季」',
            textAlign: TextAlign.start,
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.6,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterSelector extends StatelessWidget {
  final List<AnimeChapter> chapters;
  final String currentChapterUuid;
  final ValueChanged<AnimeChapter> onSelected;

  const _ChapterSelector({
    required this.chapters,
    required this.currentChapterUuid,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.video_library_outlined, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              '选集 (${chapters.length})',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final chapter in chapters)
              _ChapterButton(
                chapter: chapter,
                selected: chapter.uuid == currentChapterUuid,
                onTap: () => onSelected(chapter),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChapterButton extends StatelessWidget {
  final AnimeChapter chapter;
  final bool selected;
  final VoidCallback onTap;

  const _ChapterButton({
    required this.chapter,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 92, maxWidth: 172),
      child: Material(
        color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              chapter.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;
  final String? rawError;
  final bool requiresLogin;
  final VoidCallback onLogin;
  final VoidCallback onRetry;

  const _ErrorPanel({
    required this.message,
    this.rawError,
    required this.requiresLogin,
    required this.onLogin,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              requiresLogin ? Icons.lock_outline : Icons.cloud_off,
              color: Colors.white70,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              requiresLogin ? '需要登录' : '播放失败',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            if (requiresLogin)
              FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login),
                label: const Text('去登录'),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (rawError != null) ...[
                    TextButton.icon(
                      onPressed: () => _showErrorLog(context),
                      icon: const Icon(Icons.bug_report_outlined, size: 18),
                      label: const Text('查看日志'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.tonal(
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showErrorLog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误日志'),
        content: SingleChildScrollView(
          child: SelectableText(
            rawError ?? '无日志信息',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (rawError != null) {
                await Clipboard.setData(ClipboardData(text: rawError!));
                if (context.mounted) {
                  showToast(context, '日志已复制到剪贴板');
                }
              }
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _PlayerSettingsPanel extends StatefulWidget {
  final VoidCallback onChanged;
  final DanmakuController? danmakuController;
  final bool danmakuVisible;
  final ValueChanged<bool> onDanmakuVisibleChanged;

  const _PlayerSettingsPanel({
    required this.onChanged,
    this.danmakuController,
    required this.danmakuVisible,
    required this.onDanmakuVisibleChanged,
  });

  @override
  State<_PlayerSettingsPanel> createState() => _PlayerSettingsPanelState();
}

class _PlayerSettingsPanelState extends State<_PlayerSettingsPanel> {
  final _user = UserManager();
  late int _skipSeconds;
  late double _fontSize;
  late double _area;
  late double _opacity;
  late bool _hideScroll;
  late bool _hideTop;
  late bool _hideBottom;

  @override
  void initState() {
    super.initState();
    _skipSeconds = _user.animeSkipSeconds;
    _fontSize = _user.danmakuFontSize;
    _area = _user.danmakuArea;
    _opacity = _user.danmakuOpacity;
    _hideScroll = _user.danmakuHideScroll;
    _hideTop = _user.danmakuHideTop;
    _hideBottom = _user.danmakuHideBottom;
  }

  void _updateDanmakuOption() {
    widget.danmakuController?.updateOption(
      DanmakuOption(
        fontSize: _fontSize,
        duration: 8,
        opacity: _opacity,
        area: _area,
        hideScroll: _hideScroll,
        hideTop: _hideTop,
        hideBottom: _hideBottom,
      ),
    );
    _user.setDanmakuFontSize(_fontSize);
    _user.setDanmakuArea(_area);
    _user.setDanmakuOpacity(_opacity);
    _user.setDanmakuHideScroll(_hideScroll);
    _user.setDanmakuHideTop(_hideTop);
    _user.setDanmakuHideBottom(_hideBottom);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ===== 播放设置区域 =====
            Text(
              '播放设置',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              '快进秒数',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '动漫片头一般约90秒',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: TextEditingController(text: _skipSeconds.toString()),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '秒数',
                suffixText: '秒',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                final value = int.tryParse(v);
                if (value != null && value > 0) {
                  _skipSeconds = value;
                  _user.setAnimeSkipSeconds(value);
                  widget.onChanged();
                }
              },
            ),

            const Divider(height: 32),

            // ===== 弹幕设置区域 =====
            Text(
              '弹幕设置',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 弹幕开关
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '显示弹幕',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              value: widget.danmakuVisible,
              onChanged: (v) {
                widget.onDanmakuVisibleChanged(v);
                setState(() {});
              },
            ),

            // 自动匹配弹幕
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '自动匹配弹幕',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '播放时自动通过文件名匹配弹幕',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              value: _user.isAutoMatchDanmaku,
              onChanged: (v) {
                _user.setAutoMatchDanmaku(v);
                widget.onChanged();
                setState(() {});
              },
            ),

            // 弹幕详细设置（弹幕开启时显示）
            if (widget.danmakuVisible) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '字体大小',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    _fontSize.toStringAsFixed(0),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: _fontSize,
                min: 10,
                max: 30,
                divisions: 20,
                label: _fontSize.toStringAsFixed(0),
                onChanged: (v) => setState(() => _fontSize = v),
                onChangeEnd: (v) => _updateDanmakuOption(),
              ),

              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '显示区域',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    '${(_area * 100).toStringAsFixed(0)}%',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: _area,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                label: '${(_area * 100).toStringAsFixed(0)}%',
                onChanged: (v) => setState(() => _area = v),
                onChangeEnd: (v) => _updateDanmakuOption(),
              ),

              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '透明度',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    '${(_opacity * 100).toStringAsFixed(0)}%',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: _opacity,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                label: '${(_opacity * 100).toStringAsFixed(0)}%',
                onChanged: (v) => setState(() => _opacity = v),
                onChangeEnd: (v) => _updateDanmakuOption(),
              ),

              const SizedBox(height: 4),
              Text(
                '弹幕类型',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('滚动弹幕', style: tt.bodyMedium),
                value: !_hideScroll,
                onChanged: (v) {
                  setState(() => _hideScroll = !v);
                  _updateDanmakuOption();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('顶部弹幕', style: tt.bodyMedium),
                value: !_hideTop,
                onChanged: (v) {
                  setState(() => _hideTop = !v);
                  _updateDanmakuOption();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('底部弹幕', style: tt.bodyMedium),
                value: !_hideBottom,
                onChanged: (v) {
                  setState(() => _hideBottom = !v);
                  _updateDanmakuOption();
                },
              ),

              // 屏蔽词设置
              const SizedBox(height: 8),
              _DanmakuBlocklistEditor(
                blocklist: _user.danmakuBlocklist,
                onChanged: (list) {
                  _user.setDanmakuBlocklist(list);
                  widget.onChanged();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DanmakuBlocklistEditor extends StatefulWidget {
  final List<String> blocklist;
  final ValueChanged<List<String>> onChanged;

  const _DanmakuBlocklistEditor({
    required this.blocklist,
    required this.onChanged,
  });

  @override
  State<_DanmakuBlocklistEditor> createState() =>
      _DanmakuBlocklistEditorState();
}

class _DanmakuBlocklistEditorState extends State<_DanmakuBlocklistEditor> {
  late List<String> _words;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _words = List.from(widget.blocklist);
  }

  void _addWord() {
    final text = _controller.text.trim();
    if (text.isEmpty || _words.contains(text)) return;
    setState(() {
      _words.add(text);
      _controller.clear();
    });
    widget.onChanged(List.from(_words));
  }

  Future<void> _convertSimplifiedTraditional() async {
    final text = _controller.text;
    if (text.isEmpty) return;
    try {
      final converted = await ChineseConverter.convertToSimplifiedChinese(text);
      if (converted == text) {
        _controller.text = await ChineseConverter.convertToTraditionalChinese(
          text,
        );
      } else {
        _controller.text = converted;
      }
    } catch (_) {}
  }

  void _removeWord(int index) {
    setState(() => _words.removeAt(index));
    widget.onChanged(List.from(_words));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '屏蔽词',
          style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          '包含屏蔽词的弹幕将被自动过滤',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '输入屏蔽词',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _convertSimplifiedTraditional,
                    icon: const Icon(Icons.translate, size: 20),
                    tooltip: '简繁转换',
                  ),
                ),
                onSubmitted: (_) => _addWord(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _addWord, icon: const Icon(Icons.add)),
          ],
        ),
        if (_words.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _words.length; i++)
                Chip(
                  label: Text(_words[i]),
                  onDeleted: () => _removeWord(i),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
