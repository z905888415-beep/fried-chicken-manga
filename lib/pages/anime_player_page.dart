import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

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
  VideoPlayerController? _videoController;
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

  @override
  void initState() {
    super.initState();
    _currentChapterUuid = widget.chapterUuid;
    _currentChapterName = widget.chapterName;
    _line = widget.line;
    _load();
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoStateChanged);
    _videoController?.dispose();
    super.dispose();
  }

  void _onVideoStateChanged() {
    final controller = _videoController;
    if (!mounted || controller == null) return;
    final value = controller.value;
    final nextError = value.hasError
        ? _formatPlayerError(value.errorDescription ?? '')
        : null;
    if (_buffering == value.isBuffering && _error == nextError) {
      return;
    }
    setState(() {
      _buffering = value.isBuffering;
      _error = nextError;
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

  String _formatPlayerError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('127.0.0.1') ||
        lower.contains('localhost') ||
        lower.contains('failed to open')) {
      return '视频加载失败，请重试';
    }
    return message;
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
    _videoController?.removeListener(_onVideoStateChanged);
    final oldController = _videoController;
    _videoController = null;
    unawaited(oldController?.dispose());
    if (mounted) {
      setState(() {
        _buffering = true;
        _error = null;
      });
    }

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        httpHeaders: _videoHttpHeaders,
      );
      controller.addListener(_onVideoStateChanged);
      if (!mounted || serial != _openMediaSerial) return;
      _videoController = controller;
      await controller.initialize();
      if (!mounted || serial != _openMediaSerial) return;
      await controller.play();
      if (!mounted || serial != _openMediaSerial) return;
      setState(() {
        _buffering = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('AnimePlayerPage open media error: $e');
      if (!mounted || serial != _openMediaSerial) return;
      setState(() {
        _buffering = false;
        _error = '视频加载失败，请重试';
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
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    final position = controller.value.position;
    final newPosition =
        position + Duration(seconds: UserManager().animeSkipSeconds);
    if (newPosition < duration) {
      controller.seekTo(newPosition);
    } else {
      controller.seekTo(duration);
    }
  }

  Widget _buildVideoWithControls() {
    final controller = _videoController;
    if (controller == null) {
      return const ColoredBox(color: Colors.black);
    }
    return _buildVideoSurface(controller, fullscreen: false);
  }

  Widget _buildVideoSurface(
    VideoPlayerController controller, {
    required bool fullscreen,
  }) {
    final previousChapter = _previousChapter;
    final nextChapter = _nextChapter;
    return _VideoPlayerSurface(
      controller: controller,
      fullscreen: fullscreen,
      onPrevious: previousChapter == null
          ? null
          : () => unawaited(_openChapter(previousChapter)),
      onNext: nextChapter == null
          ? null
          : () => unawaited(_openChapter(nextChapter)),
      onSkipForward: _skipForward,
      onSettings: _showSettingsPanel,
      onFullscreen: fullscreen
          ? () => Navigator.maybePop(context)
          : _fullscreen,
    );
  }

  Future<void> _fullscreen() async {
    final controller = _videoController;
    if (controller == null) return;
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
                child: _buildVideoSurface(controller, fullscreen: true),
              ),
            ),
          ),
        ),
      );
    } finally {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
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
        _videoController?.pause();
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
  final VideoPlayerController controller;
  final bool fullscreen;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onSkipForward;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;

  const _VideoPlayerSurface({
    required this.controller,
    required this.fullscreen,
    required this.onPrevious,
    required this.onNext,
    required this.onSkipForward,
    required this.onSettings,
    required this.onFullscreen,
  });

  @override
  State<_VideoPlayerSurface> createState() => _VideoPlayerSurfaceState();
}

class _VideoPlayerSurfaceState extends State<_VideoPlayerSurface> {
  static const _controlsAutoHideDelay = Duration(seconds: 3);

  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  VideoPlayerController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_syncControlsAutoHide);
    _syncControlsAutoHide();
  }

  @override
  void didUpdateWidget(covariant _VideoPlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_syncControlsAutoHide);
    controller.addListener(_syncControlsAutoHide);
    setState(() => _controlsVisible = true);
    _syncControlsAutoHide();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    controller.removeListener(_syncControlsAutoHide);
    super.dispose();
  }

  void _syncControlsAutoHide() {
    final value = controller.value;
    if (!value.isInitialized || !value.isPlaying || !_controlsVisible) {
      _hideControlsTimer?.cancel();
      _hideControlsTimer = null;
      return;
    }
    if (_hideControlsTimer?.isActive == true) return;
    _startControlsAutoHideTimer();
  }

  void _startControlsAutoHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(_controlsAutoHideDelay, () {
      if (!mounted || !controller.value.isPlaying) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    if (!controller.value.isInitialized) return;
    setState(() => _controlsVisible = !_controlsVisible);
    if (!_controlsVisible || !controller.value.isPlaying) {
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
    if (controller.value.isPlaying) {
      _startControlsAutoHideTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    const controlButtonSize = 24.0;
    const controlButtonExtent = 40.0;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final initialized = value.isInitialized;
        final duration = initialized ? value.duration : Duration.zero;
        final position = initialized ? value.position : Duration.zero;
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
                child: initialized
                    ? AspectRatio(
                        aspectRatio: value.aspectRatio,
                        child: VideoPlayer(controller),
                      )
                    : const SizedBox.shrink(),
              ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: initialized ? _toggleControls : null,
                  onDoubleTap: initialized ? _togglePlay : null,
                ),
              ),
              if (initialized && !value.isPlaying && _controlsVisible)
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
                                  onChanged: initialized
                                      ? (v) => controller.seekTo(
                                            Duration(
                                              milliseconds:
                                                  (duration.inMilliseconds * v)
                                                      .round(),
                                            ),
                                          )
                                      : null,
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
                                  const Spacer(),
                                  _PlayerControlButton(
                                    tooltip: '上一集',
                                    icon: Icons.skip_previous,
                                    iconSize: controlButtonSize,
                                    extent: controlButtonExtent,
                                    onPressed: widget.onPrevious,
                                  ),
                                  _PlayerControlButton(
                                    tooltip: value.isPlaying ? '暂停' : '播放',
                                    icon: value.isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    iconSize: controlButtonSize,
                                    extent: controlButtonExtent,
                                    onPressed: initialized ? _togglePlay : null,
                                  ),
                                  _PlayerControlButton(
                                    tooltip: '下一集',
                                    icon: Icons.skip_next,
                                    iconSize: controlButtonSize,
                                    extent: controlButtonExtent,
                                    onPressed: widget.onNext,
                                  ),
                                  _PlayerControlButton(
                                    tooltip:
                                        '快进 ${UserManager().animeSkipSeconds}秒',
                                    icon: Icons.fast_forward,
                                    iconSize: controlButtonSize,
                                    extent: controlButtonExtent,
                                    onPressed: initialized
                                        ? widget.onSkipForward
                                        : null,
                                  ),
                                  _PlayerControlButton(
                                    tooltip: '设置跳转秒数',
                                    icon: Icons.settings,
                                    iconSize: controlButtonSize,
                                    extent: controlButtonExtent,
                                    onPressed: widget.onSettings,
                                  ),
                                  _PlayerControlButton(
                                    tooltip:
                                        widget.fullscreen ? '退出全屏' : '全屏',
                                    icon: widget.fullscreen
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                    iconSize: controlButtonSize,
                                    extent: controlButtonExtent,
                                    onPressed: widget.onFullscreen,
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
    if (controller.value.isPlaying) {
      controller.pause();
      return;
    }
    if (controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero) {
      controller.seekTo(Duration.zero);
    }
    controller.play();
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
