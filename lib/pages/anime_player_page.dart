import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../models/anime.dart';
import '../models/user_manager.dart';
import '../utils/toast.dart';
import 'profile_page.dart';

class AnimePlayerPage extends StatefulWidget {
  final String pathWord;
  final String chapterUuid;
  final String chapterName;
  final String line;
  final List<AnimeChapter> chapters;

  const AnimePlayerPage({
    super.key,
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

  final _api = ApiClient();
  final _user = UserManager();
  final _hlsProxy = _HlsProxy(headers: _videoHttpHeaders);
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<String>? _errorSubscription;
  AnimePlayback? _playback;
  late String _currentChapterUuid;
  late String _currentChapterName;
  late String _line;
  String? _videoUrl;
  bool _loading = true;
  bool _buffering = false;
  bool _requiresLogin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = Player(
      configuration: const PlayerConfiguration(bufferSize: 8 * 1024 * 1024),
    );
    _controller = VideoController(_player);
    _listenPlayerState();
    _currentChapterUuid = widget.chapterUuid;
    _currentChapterName = widget.chapterName;
    _line = widget.line;
    _load();
  }

  @override
  void dispose() {
    _bufferingSubscription?.cancel();
    _errorSubscription?.cancel();
    unawaited(_hlsProxy.close());
    _player.dispose();
    super.dispose();
  }

  void _listenPlayerState() {
    _bufferingSubscription = _player.stream.buffering.listen((value) {
      if (mounted) setState(() => _buffering = value);
    });
    _errorSubscription = _player.stream.error.listen((message) {
      if (!mounted) return;
      setState(() {
        _buffering = false;
        _error = message;
      });
    });
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
    try {
      final playableUrl = await _hlsProxy.proxy(videoUrl);
      await _player.open(Media(playableUrl));
    } catch (e) {
      debugPrint('AnimePlayerPage open media error: $e');
      if (!mounted) return;
      setState(() {
        _buffering = false;
        _error = e.toString();
      });
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

  int get _currentChapterIndex {
    return _chapters.indexWhere(
      (chapter) => chapter.uuid == _currentChapterUuid,
    );
  }

  AnimeChapter? get _previousChapter {
    final index = _currentChapterIndex;
    if (index <= 0) return null;
    return _chapters[index - 1];
  }

  AnimeChapter? get _nextChapter {
    final index = _currentChapterIndex;
    if (index < 0 || index >= _chapters.length - 1) return null;
    return _chapters[index + 1];
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
    const controlButtonSize = 24.0;
    const controlButtonExtent = 40.0;
    final previousChapter = _previousChapter;
    final nextChapter = _nextChapter;
    final previousButton = _PlayerControlButton(
      tooltip: '上一集',
      icon: Icons.skip_previous,
      iconSize: controlButtonSize,
      extent: controlButtonExtent,
      onPressed: previousChapter == null
          ? null
          : () => unawaited(_openChapter(previousChapter)),
    );
    final nextButton = _PlayerControlButton(
      tooltip: '下一集',
      icon: Icons.skip_next,
      iconSize: controlButtonSize,
      extent: controlButtonExtent,
      onPressed: nextChapter == null
          ? null
          : () => unawaited(_openChapter(nextChapter)),
    );
    final skipButton = _PlayerControlButton(
      tooltip: '快进 ${UserManager().animeSkipSeconds}秒',
      icon: Icons.fast_forward,
      iconSize: controlButtonSize,
      extent: controlButtonExtent,
      onPressed: _skipForward,
    );
    final settingsButton = _PlayerControlButton(
      tooltip: '设置跳转秒数',
      icon: Icons.settings,
      iconSize: controlButtonSize,
      extent: controlButtonExtent,
      onPressed: _showSettingsPanel,
    );
    final bottomButtonBar = [
      const MaterialPositionIndicator(),
      const Spacer(),
      previousButton,
      nextButton,
      skipButton,
      settingsButton,
      const MaterialFullscreenButton(),
    ];
    return MaterialVideoControlsTheme(
      normal: MaterialVideoControlsThemeData(
        buttonBarButtonSize: controlButtonSize,
        buttonBarButtonColor: Colors.white,
        bottomButtonBar: bottomButtonBar,
      ),
      fullscreen: MaterialVideoControlsThemeData(
        buttonBarButtonSize: controlButtonSize,
        buttonBarButtonColor: Colors.white,
        bottomButtonBar: bottomButtonBar,
        bottomButtonBarMargin: const EdgeInsets.only(
          left: 16.0,
          right: 8.0,
          bottom: 42.0,
        ),
      ),
      child: Video(controller: _controller, controls: MaterialVideoControls),
    );
  }

  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      builder: (_) => _PlayerSettingsPanel(onChanged: () => setState(() {})),
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
                              requiresLogin: _requiresLogin,
                              onLogin: _goLogin,
                              onRetry: _load,
                            ),
                    ),
                    if (_showLoadingOverlay)
                      const ColoredBox(
                        color: Color(0x66000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _VideoLinkPanel(
                    videoUrl: _videoUrl,
                    lines: _playback?.chapter.lines ?? const {},
                    currentLine: _line,
                    onCopy: _copyVideoUrl,
                    onOpen: _openVideoUrl,
                    onLineSelected: _switchLine,
                  ),
                  const SizedBox(height: 24),
                  _ChapterSelector(
                    chapters: _chapters,
                    currentChapterUuid: _currentChapterUuid,
                    onSelected: _openChapter,
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

class _HlsProxy {
  static const _channel = MethodChannel('io.github.caolib.kira/hls');

  final Map<String, String> headers;
  HttpServer? _server;
  late final HttpClient _client;

  _HlsProxy({required this.headers}) {
    _client = HttpClient()..autoUncompress = false;
  }

  Future<String> proxy(String remoteUrl) async {
    final server = await _ensureServer();
    return _localUrl(server.port, remoteUrl);
  }

  Future<HttpServer> _ensureServer() async {
    final current = _server;
    if (current != null) return current;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(_serve(server));
    return server;
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final encodedUrl = request.uri.queryParameters['u'];
      if (encodedUrl == null || encodedUrl.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final remoteUrl = utf8.decode(base64Url.decode(encodedUrl));
      final remoteUri = Uri.parse(remoteUrl);

      final range = request.headers.value(HttpHeaders.rangeHeader);
      final upstreamResponse = await _fetchUpstream(remoteUri, range);
      final contentType = upstreamResponse.contentType == null
          ? null
          : ContentType.parse(upstreamResponse.contentType!);
      final isPlaylist =
          remoteUri.path.toLowerCase().endsWith('.m3u8') ||
          contentType?.mimeType.contains('mpegurl') == true;

      request.response.statusCode = upstreamResponse.statusCode;
      if (isPlaylist) {
        final text = utf8.decode(upstreamResponse.body);
        final rewritten = _rewritePlaylist(text, remoteUri);
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
          charset: 'utf-8',
        );
        request.response.write(rewritten);
        await request.response.close();
        return;
      }

      final responseContentType = contentType;
      if (responseContentType != null) {
        request.response.headers.contentType = responseContentType;
      }
      final contentLength = upstreamResponse.contentLength;
      if (contentLength >= 0) {
        request.response.contentLength = contentLength;
      }
      final acceptRanges = upstreamResponse.acceptRanges;
      if (acceptRanges != null) {
        request.response.headers.set(
          HttpHeaders.acceptRangesHeader,
          acceptRanges,
        );
      }
      final contentRange = upstreamResponse.contentRange;
      if (contentRange != null) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          contentRange,
        );
      }
      request.response.add(upstreamResponse.body);
      await request.response.close();
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write(e.toString());
        await request.response.close();
      } catch (_) {
        // The response may already be in the middle of streaming to mpv.
      }
    }
  }

  Future<_HlsProxyResponse> _fetchUpstream(Uri remoteUri, String? range) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await _fetchUpstreamOnce(remoteUri, range);
      } catch (e) {
        lastError = e;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
        }
      }
    }
    throw lastError ?? StateError('HLS fetch failed');
  }

  Future<_HlsProxyResponse> _fetchUpstreamOnce(
    Uri remoteUri,
    String? range,
  ) async {
    if (Platform.isAndroid) {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'fetch',
        {'url': remoteUri.toString(), 'headers': headers, 'range': range},
      );
      if (response == null) {
        throw StateError('Android HLS fetch returned empty response');
      }
      final body = response['body'];
      return _HlsProxyResponse(
        statusCode: response['statusCode'] as int? ?? HttpStatus.badGateway,
        contentType: response['contentType'] as String?,
        contentLength: response['contentLength'] as int? ?? -1,
        acceptRanges: response['acceptRanges'] as String?,
        contentRange: response['contentRange'] as String?,
        body: body is Uint8List ? body : Uint8List(0),
      );
    }

    final upstreamRequest = await _client.getUrl(remoteUri);
    for (final entry in headers.entries) {
      upstreamRequest.headers.set(entry.key, entry.value);
    }
    if (range != null && range.isNotEmpty) {
      upstreamRequest.headers.set(HttpHeaders.rangeHeader, range);
    }
    final upstreamResponse = await upstreamRequest.close();
    final chunks = <int>[];
    await for (final chunk in upstreamResponse) {
      chunks.addAll(chunk);
    }
    return _HlsProxyResponse(
      statusCode: upstreamResponse.statusCode,
      contentType: upstreamResponse.headers.contentType?.toString(),
      contentLength: chunks.length,
      acceptRanges: upstreamResponse.headers.value(
        HttpHeaders.acceptRangesHeader,
      ),
      contentRange: upstreamResponse.headers.value(
        HttpHeaders.contentRangeHeader,
      ),
      body: Uint8List.fromList(chunks),
    );
  }

  String _rewritePlaylist(String text, Uri playlistUri) {
    return const LineSplitter()
        .convert(text)
        .map((line) => _rewritePlaylistLine(line, playlistUri))
        .join('\n');
  }

  String _rewritePlaylistLine(String line, Uri playlistUri) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return line;
    if (trimmed.startsWith('#')) {
      return _rewriteTagUri(line, playlistUri);
    }

    final resolved = playlistUri.resolve(trimmed).toString();
    return _localUrl(_server!.port, resolved);
  }

  String _rewriteTagUri(String line, Uri playlistUri) {
    return line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (match) {
      final uri = match.group(1);
      if (uri == null || uri.isEmpty || uri.startsWith('data:')) {
        return match.group(0)!;
      }
      final resolved = playlistUri.resolve(uri).toString();
      return 'URI="${_localUrl(_server!.port, resolved)}"';
    });
  }

  String _localUrl(int port, String remoteUrl) {
    final encoded = base64Url.encode(utf8.encode(remoteUrl));
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      path: '/hls',
      queryParameters: {'u': encoded},
    ).toString();
  }

  Future<void> close() async {
    _client.close(force: true);
    await _server?.close(force: true);
    _server = null;
  }
}

class _HlsProxyResponse {
  final int statusCode;
  final String? contentType;
  final int contentLength;
  final String? acceptRanges;
  final String? contentRange;
  final Uint8List body;

  const _HlsProxyResponse({
    required this.statusCode,
    required this.contentType,
    required this.contentLength,
    required this.acceptRanges,
    required this.contentRange,
    required this.body,
  });
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
  final bool requiresLogin;
  final VoidCallback onLogin;
  final VoidCallback onRetry;

  const _ErrorPanel({
    required this.message,
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
              FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _PlayerSettingsPanel extends StatefulWidget {
  final VoidCallback onChanged;

  const _PlayerSettingsPanel({required this.onChanged});

  @override
  State<_PlayerSettingsPanel> createState() => _PlayerSettingsPanelState();
}

class _PlayerSettingsPanelState extends State<_PlayerSettingsPanel> {
  final _user = UserManager();
  late int _skipSeconds;

  @override
  void initState() {
    super.initState();
    _skipSeconds = _user.animeSkipSeconds;
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
            Text(
              '播放设置',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
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
          ],
        ),
      ),
    );
  }
}
