import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../api/api_client.dart';
import '../api/zhipu_api.dart';
import '../models/chapter_comment.dart';
import '../models/user_manager.dart';
import '../utils/chapter_summary_cache.dart';
import '../utils/toast.dart';
import 'chapter_comment_display.dart';

class ChapterCommentsSheet extends StatefulWidget {
  final String chapterUuid;
  final String? comicName;
  final String chapterName;
  final List<ChapterComment>? initialComments;
  final int? initialTotal;
  final void Function(List<ChapterComment> comments, int total)?
  onCommentsUpdated;
  final bool hasNextChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback? onBackToCatalog;

  const ChapterCommentsSheet({
    super.key,
    required this.chapterUuid,
    this.comicName,
    required this.chapterName,
    this.initialComments,
    this.initialTotal,
    this.onCommentsUpdated,
    this.hasNextChapter = false,
    this.onNextChapter,
    this.onBackToCatalog,
  });

  @override
  State<ChapterCommentsSheet> createState() => _ChapterCommentsSheetState();
}

class _ChapterCommentsSheetState extends State<ChapterCommentsSheet> {
  static const _pageSize = 100;
  static const _commentRowSpacing = 8.0;
  static const _loadMoreThreshold = 240.0;
  static const _commentListBottomPadding = 124.0;
  static const _sheetMaxHeightFactor = 0.85;

  final _api = ApiClient();
  final _user = UserManager();
  final _zhipuSettings = ZhipuSettings();
  final _zhipuApi = ZhipuApi();
  final _scrollController = ScrollController();

  List<ChapterComment> _comments = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingAll = false;
  String? _error;
  int _total = 0;
  bool _useCompactLayout = true;
  bool _showUserAvatar = true;
  bool _showUserName = true;
  bool _showCommentTime = true;
  double _commentFontScale = 1.0;
  bool _showFloatingButtons = true;
  double _lastScrollOffset = 0;

  String _aiSummary = '';
  bool _summarizing = false;
  bool _summaryExpanded = true;
  String? _summaryError;
  CancelToken? _summaryCancelToken;
  Set<int> _spoilerIds = const {};
  List<ChapterCommentDisplayEntry> _lastSnippetEntries = const [];

  @override
  void initState() {
    super.initState();
    _useCompactLayout = _user.commentCompactLayout;
    _showUserAvatar = _user.commentShowAvatar;
    _showUserName = _user.commentShowUserName;
    _showCommentTime = _user.commentShowTime;
    _commentFontScale = _user.commentFontScale;
    _scrollController.addListener(_handleScrollDirection);
    _zhipuSettings.addListener(_onZhipuChanged);
    _zhipuSettings.load().then((_) {
      _loadCachedSummary().then((_) => _maybeAutoSummary());
    });
    if (widget.initialComments != null) {
      _comments = List<ChapterComment>.from(widget.initialComments!);
      _total = widget.initialTotal ?? _comments.length;
      _loading = false;
      if (_user.commentAutoLoadAll && _comments.length < _total) {
        _loadAllComments();
      }
      return;
    }
    _loadComments().then((_) {
      if (_user.commentAutoLoadAll && _comments.length < _total) {
        _loadAllComments();
      }
    });
  }

  @override
  void dispose() {
    _summaryCancelToken?.cancel();
    _zhipuSettings.removeListener(_onZhipuChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onZhipuChanged() {
    if (mounted) setState(() {});
  }

  void _maybeAutoSummary() {
    if (!_zhipuSettings.hasApiKey ||
        !_zhipuSettings.summaryEnabled ||
        !_zhipuSettings.autoSummary) {
      return;
    }
    if (_zhipuSettings.autoSummaryTiming != ZhipuAutoSummaryTiming.onOpen) {
      return;
    }
    if (_aiSummary.isNotEmpty || _summarizing || _comments.isEmpty) return;
    if (_comments.length < _zhipuSettings.autoSummaryMin) return;
    _summarizeComments();
  }

  Future<void> _loadCachedSummary() async {
    final cached = await ChapterSummaryCache.get(widget.chapterUuid);
    if (!mounted || cached == null || cached.isEmpty) return;
    setState(() {
      _aiSummary = cached;
      _spoilerIds = _parseSpoilerIds(cached);
    });
  }

  void _handleScrollDirection() {
    final offset = _scrollController.offset;
    if (offset > _lastScrollOffset + 2 && _showFloatingButtons) {
      setState(() => _showFloatingButtons = false);
    } else if (offset < _lastScrollOffset - 2 && !_showFloatingButtons) {
      setState(() => _showFloatingButtons = true);
    }
    _lastScrollOffset = offset;
  }

  void _notifyCommentsUpdated() {
    final callback = widget.onCommentsUpdated;
    if (callback == null) return;
    callback(
      List<ChapterComment>.from(_comments),
      _total < _comments.length ? _comments.length : _total,
    );
  }

  Future<void> _loadComments({bool loadMore = false}) async {
    if (!loadMore && widget.initialComments != null && _comments.isNotEmpty) {
      return;
    }
    if (loadMore) {
      if (_loading || _loadingMore || _comments.length >= _total) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await _api.getChapterComments(
        widget.chapterUuid,
        limit: _pageSize,
        offset: loadMore ? _comments.length : 0,
      );
      if (!mounted) return;

      final mergedComments = loadMore
          ? [
              ..._comments,
              ...data.list.where(
                (item) => !_comments.any((existing) => existing.id == item.id),
              ),
            ]
          : data.list;

      setState(() {
        _comments = mergedComments;
        _total = data.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      _notifyCommentsUpdated();
      if (!loadMore) {
        _maybeAutoSummary();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tryLoadMoreWhenNearBottom();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    _tryLoadMoreWhenNearBottom(metrics: notification.metrics);
    return false;
  }

  void _tryLoadMoreWhenNearBottom({ScrollMetrics? metrics}) {
    if (_loading || _loadingMore || _comments.length >= _total) return;
    final currentMetrics =
        metrics ??
        (_scrollController.hasClients ? _scrollController.position : null);
    if (currentMetrics == null) return;
    if (currentMetrics.extentAfter <= _loadMoreThreshold) {
      _loadComments(loadMore: true);
    }
  }

  Future<void> _loadAllComments() async {
    if (_loadingAll) return;
    setState(() => _loadingAll = true);

    try {
      while (mounted && _comments.length < _total) {
        final data = await _api.getChapterComments(
          widget.chapterUuid,
          limit: _pageSize,
          offset: _comments.length,
        );
        if (!mounted) return;

        final newComments = data.list
            .where((item) => !_comments.any((e) => e.id == item.id))
            .toList();
        if (newComments.isEmpty) break;

        setState(() {
          _comments = [..._comments, ...newComments];
          _total = data.total;
        });
        _notifyCommentsUpdated();

        if (_comments.length < _total) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } finally {
      if (mounted) setState(() => _loadingAll = false);
    }
  }

  bool get _allCommentsLoaded => _total > 0 && _comments.length >= _total;

  Future<void> _summarizeComments() async {
    if (_summarizing) return;
    if (_comments.isEmpty) {
      showToast(context, '当前没有可总结的评论', isError: true);
      return;
    }
    if (!_zhipuSettings.hasApiKey || !_zhipuSettings.summaryEnabled) {
      showToast(context, '请先在评论区设置中启用 AI 总结', isError: true);
      return;
    }

    final cancelToken = CancelToken();
    _summaryCancelToken = cancelToken;
    setState(() {
      _summarizing = true;
      _summaryError = null;
      _aiSummary = '';
      _spoilerIds = const {};
      _summaryExpanded = true;
    });

    final snippets = _buildCommentSnippets();
    final comicLine = widget.comicName?.trim().isNotEmpty == true
        ? '漫画：${widget.comicName!.trim()}\n'
        : '';
    final messages = <ZhipuMessage>[
      ZhipuMessage(role: 'system', content: _zhipuSettings.summaryPrompt),
      ZhipuMessage(
        role: 'user',
        content:
            '$comicLine章节：${widget.chapterName}\n共 ${_lastSnippetEntries.length} 条不同评论（相同内容已合并）。每条行首数字为该评论的 id：\n\n$snippets',
      ),
    ];

    final buffer = StringBuffer();
    try {
      final stream = _zhipuApi.streamChat(
        apiKey: _zhipuSettings.apiKey!,
        model: _zhipuSettings.model,
        messages: messages,
        cancelToken: cancelToken,
      );
      await for (final delta in stream) {
        if (!mounted) return;
        buffer.write(delta);
        setState(() => _aiSummary = buffer.toString());
      }
      if (mounted && buffer.isNotEmpty) {
        final full = buffer.toString();
        setState(() => _spoilerIds = _parseSpoilerIds(full));
        await ChapterSummaryCache.set(widget.chapterUuid, full);
      }
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && CancelToken.isCancel(e)) {
        return;
      }
      setState(() => _summaryError = _extractSummaryError(e));
    } finally {
      if (mounted) {
        setState(() => _summarizing = false);
      }
      _summaryCancelToken = null;
    }
  }

  String _buildCommentSnippets() {
    const maxChars = 64 * 1024;
    final buffer = StringBuffer();
    final entries = groupChapterComments(_comments);
    _lastSnippetEntries = entries;
    var truncated = false;
    for (final entry in entries) {
      final text = entry.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      final id = entry.primaryComment.id;
      final line = entry.isMerged
          ? '$id. [${entry.count}人] $text\n'
          : '$id. ${entry.primaryComment.userName}: $text\n';
      if (buffer.length + line.length > maxChars) {
        truncated = true;
        break;
      }
      buffer.write(line);
    }
    if (truncated) {
      buffer.write('…（已截断，共 ${entries.length} 条不同评论）');
    }
    return buffer.toString();
  }

  static final _codeBlockRegex = RegExp(
    r'```[^`\r\n]*\r?\n([\s\S]*?)\r?\n\s*```',
  );
  static final _arrayRegex = RegExp(r'\[\s*([\d,\s]*)\s*\]');
  static final _spoilerLegacyRegex = RegExp(r'<!--\s*SPOILERS\s*:([^>]*)-->');

  /// 解析模型输出的剧透 id，兼容旧版 HTML 注释标记。
  /// 策略：先找最后一个 fenced code block，从中提取 [id, id, ...]；
  /// 若无代码块则找文本中最后一个数组模式；最后兜底旧版注释。
  Set<int> _parseSpoilerIds(String text) {
    // 1) 最后一个 fenced code block
    Match? lastBlock;
    for (final m in _codeBlockRegex.allMatches(text)) {
      lastBlock = m;
    }
    if (lastBlock != null) {
      final content = lastBlock.group(1) ?? '';
      final arr = _arrayRegex.firstMatch(content);
      if (arr != null) return _splitIds(arr.group(1) ?? '');
    }
    // 2) 无代码块，找文本中最后一个 [id, id, ...]
    Match? lastArr;
    for (final m in _arrayRegex.allMatches(text)) {
      lastArr = m;
    }
    if (lastArr != null) return _splitIds(lastArr.group(1) ?? '');
    // 3) 兜底旧版 HTML 注释
    final legacy = _spoilerLegacyRegex.firstMatch(text);
    if (legacy != null) return _splitIds(legacy.group(1) ?? '');
    return const {};
  }

  Set<int> _splitIds(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return const {};
    final result = <int>{};
    for (final part in s.split(',')) {
      final n = int.tryParse(part.trim());
      if (n != null && n > 0) result.add(n);
    }
    return result;
  }

  /// 从展示文本里剥离机读标记，避免暴露给用户。只剥离最后一个代码块。
  String _stripSpoilersMarker(String text) {
    Match? lastBlock;
    for (final m in _codeBlockRegex.allMatches(text)) {
      lastBlock = m;
    }
    if (lastBlock != null) {
      text = text.substring(0, lastBlock.start) + text.substring(lastBlock.end);
    }
    return text.replaceAll(_spoilerLegacyRegex, '').trimRight();
  }

  String _extractSummaryError(Object e) {
    if (e is DioException) {
      if (e.response?.statusCode == 429) {
        return '请求过于频繁，已被限速，请稍后再试';
      }
      final data = e.response?.data;
      if (data is Map) {
        final err = data['error'];
        if (err is Map && err['message'] is String) return err['message'];
        if (data['message'] is String) return data['message'];
      }
      return e.message ?? e.toString();
    }
    return e.toString();
  }

  void _stopSummarize() {
    _summaryCancelToken?.cancel('user_stop');
  }

  Future<void> _clearSummary() async {
    await ChapterSummaryCache.remove(widget.chapterUuid);
    if (!mounted) return;
    setState(() {
      _aiSummary = '';
      _summaryError = null;
      _spoilerIds = const {};
    });
  }

  String _formatRelativeTime(String raw) {
    if (raw.isEmpty) return '';

    final normalized = raw.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return raw;

    final now = DateTime.now();
    final localTime = parsed.isUtc ? parsed.toLocal() : parsed;
    final diff = now.difference(localTime);

    if (diff.isNegative) return '刚刚';
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
    return '${(diff.inDays / 365).floor()}年前';
  }

  void _showCommentSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * _sheetMaxHeightFactor,
      ),
      builder: (sheetContext) {
        final sheetSize = MediaQuery.sizeOf(sheetContext);
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: sheetSize.width,
            height: sheetSize.height * _sheetMaxHeightFactor,
            child: _CommentSettingsPanel(
              useCompactLayout: _useCompactLayout,
              showUserAvatar: _showUserAvatar,
              showUserName: _showUserName,
              showCommentTime: _showCommentTime,
              commentFontScale: _commentFontScale,
              commentPreload: _user.commentPreload,
              commentAutoLoadAll: _user.commentAutoLoadAll,
              onLayoutChanged: (compact) {
                if (!mounted) return;
                setState(() => _useCompactLayout = compact);
                _user.setCommentCompactLayout(compact);
              },
              onShowAvatarChanged: (enabled) {
                if (!mounted) return;
                setState(() => _showUserAvatar = enabled);
                _user.setCommentShowAvatar(enabled);
              },
              onShowUserNameChanged: (enabled) {
                if (!mounted) return;
                setState(() => _showUserName = enabled);
                _user.setCommentShowUserName(enabled);
              },
              onShowCommentTimeChanged: (enabled) {
                if (!mounted) return;
                setState(() => _showCommentTime = enabled);
                _user.setCommentShowTime(enabled);
              },
              onFontScaleChanged: (scale) {
                if (!mounted) return;
                setState(() => _commentFontScale = scale);
                _user.setCommentFontScale(scale);
              },
              onPreloadChanged: (enabled) {
                _user.setCommentPreload(enabled);
                if (!enabled &&
                    _zhipuSettings.autoSummaryTiming ==
                        ZhipuAutoSummaryTiming.afterPreload) {
                  _zhipuSettings.setAutoSummaryTiming(
                    ZhipuAutoSummaryTiming.onOpen,
                  );
                }
              },
              onAutoLoadAllChanged: (enabled) {
                _user.setCommentAutoLoadAll(enabled);
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final sheetWidth = MediaQuery.of(context).size.width;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: sheetWidth,
        height: MediaQuery.of(context).size.height * _sheetMaxHeightFactor,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '章节评论',
                                  style: tt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.chapterName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!_allCommentsLoaded)
                            _loadingAll
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Padding(
                                      padding: EdgeInsets.all(2),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    tooltip: '加载全部评论',
                                    onPressed: _loadAllComments,
                                    icon: const Icon(Icons.refresh),
                                  ),
                          if (_zhipuSettings.hasApiKey &&
                              _zhipuSettings.summaryEnabled) ...[
                            IconButton(
                              tooltip: _aiSummary.isEmpty
                                  ? 'AI 总结评论'
                                  : '重新生成 AI 总结',
                              onPressed: _summarizing
                                  ? null
                                  : _summarizeComments,
                              icon: Icon(
                                Icons.smart_toy_outlined,
                                color: _summarizing
                                    ? cs.onSurfaceVariant
                                    : cs.primary,
                              ),
                            ),
                          ],
                          IconButton(
                            tooltip: _useCompactLayout ? '切换为列表布局' : '切换为紧凑布局',
                            onPressed: () {
                              setState(
                                () => _useCompactLayout = !_useCompactLayout,
                              );
                              _user.setCommentCompactLayout(_useCompactLayout);
                            },
                            icon: Icon(
                              _useCompactLayout
                                  ? Icons.view_agenda_outlined
                                  : Icons.dashboard_outlined,
                            ),
                          ),
                          IconButton(
                            tooltip: '评论区设置',
                            onPressed: _showCommentSettings,
                            icon: const Icon(Icons.tune),
                          ),
                          Text(
                            _total > 0
                                ? (_allCommentsLoaded
                                      ? '$_total 条'
                                      : '${_comments.length}/$_total')
                                : '',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: cs.outlineVariant),
                    Expanded(child: _buildBody(context, cs, tt)),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: AnimatedSlide(
                offset: _showFloatingButtons
                    ? Offset.zero
                    : const Offset(0, 1.2),
                curve: Curves.easeInOutCubic,
                duration: const Duration(milliseconds: 260),
                child: AnimatedOpacity(
                  opacity: _showFloatingButtons ? 1.0 : 0.0,
                  curve: Curves.easeInOutCubic,
                  duration: const Duration(milliseconds: 260),
                  child: SafeArea(
                    top: false,
                    child: Builder(
                      builder: (context) {
                        final buttonBackgroundColor = cs.primaryContainer;
                        final buttonForegroundColor = cs.onPrimaryContainer;
                        final buttonStyle = FilledButton.styleFrom(
                          backgroundColor: buttonBackgroundColor,
                          foregroundColor: buttonForegroundColor,
                          elevation: 6,
                          shadowColor: Colors.black.withValues(alpha: 0.22),
                          minimumSize: const Size(0, 52),
                          maximumSize: const Size.fromHeight(52),
                          fixedSize: const Size.fromHeight(52),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );

                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton.icon(
                              style: buttonStyle,
                              onPressed: () {
                                widget.onBackToCatalog?.call();
                                Navigator.of(context).pop('back_to_catalog');
                              },
                              icon: const Icon(Icons.list_rounded),
                              label: const Text('返回目录'),
                            ),
                            if (widget.hasNextChapter) ...[
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                style: buttonStyle,
                                onPressed: widget.onNextChapter,
                                icon: const Icon(Icons.skip_next_rounded),
                                label: const Text('下一话'),
                              ),
                            ],
                            const SizedBox(width: 8),
                            SizedBox.square(
                              dimension: 52,
                              child: FilledButton(
                                style: buttonStyle.copyWith(
                                  padding: const WidgetStatePropertyAll(
                                    EdgeInsets.zero,
                                  ),
                                  minimumSize: const WidgetStatePropertyAll(
                                    Size.square(52),
                                  ),
                                  maximumSize: const WidgetStatePropertyAll(
                                    Size.square(52),
                                  ),
                                ),
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                child: const Center(
                                  child: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme tt) {
    if (_loading && _comments.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          _commentListBottomPadding,
        ),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _CommentSkeleton(compact: _useCompactLayout),
      );
    }

    if (_error != null && _comments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 40, color: cs.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                '评论加载失败',
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => _loadComments(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              '还没有评论',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              '这个章节暂时没人发言',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final entries = groupChapterComments(_comments);
    final hasSummary = _hasSummaryPanel;
    final summaryOffset = hasSummary ? 1 : 0;

    if (!_useCompactLayout) {
      return NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            16,
            12,
            16,
            _commentListBottomPadding,
          ),
          itemCount: summaryOffset + entries.length + (_loadingMore ? 1 : 0),
          separatorBuilder: (_, index) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            if (hasSummary && index == 0) {
              return _buildSummaryPanel(cs, tt);
            }
            final dataIndex = index - summaryOffset;
            if (dataIndex == entries.length && _loadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final entry = entries[dataIndex];
            return _CommentCard(
              entry: entry,
              relativeTime: _formatRelativeTime(entry.createAt),
              compact: false,
              showAvatar: _showUserAvatar,
              showUserName: _showUserName,
              showCommentTime: _showCommentTime,
              fontScale: _commentFontScale,
              spoilerIds: _zhipuSettings.spoilerAnalysis
                  ? _spoilerIds
                  : const {},
            );
          },
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = _buildCommentRows(
          context,
          constraints.maxWidth - 32,
          entries,
        );

        return NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(
              16,
              12,
              16,
              _commentListBottomPadding,
            ),
            itemCount: summaryOffset + rows.length + (_loadingMore ? 1 : 0),
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              if (hasSummary && index == 0) {
                return _buildSummaryPanel(cs, tt);
              }
              final dataIndex = index - summaryOffset;
              if (dataIndex == rows.length && _loadingMore) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final row = rows[dataIndex];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < row.items.length; i++) ...[
                    SizedBox(
                      width: row.items[i].width,
                      child: _CommentCard(
                        entry: row.items[i].entry,
                        relativeTime: _formatRelativeTime(
                          row.items[i].entry.createAt,
                        ),
                        compact: true,
                        showAvatar: _showUserAvatar,
                        showUserName: _showUserName,
                        showCommentTime: _showCommentTime,
                        fontScale: _commentFontScale,
                        spoilerIds: _zhipuSettings.spoilerAnalysis
                            ? _spoilerIds
                            : const {},
                      ),
                    ),
                    if (i != row.items.length - 1)
                      const SizedBox(width: _commentRowSpacing),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  bool get _hasSummaryPanel =>
      _zhipuSettings.hasApiKey &&
      _zhipuSettings.summaryEnabled &&
      (_aiSummary.isNotEmpty || _summarizing || _summaryError != null);

  Widget _buildModelNameButton(ColorScheme cs, TextTheme tt) {
    final canSwitch = !_summarizing;
    return Tooltip(
      message: canSwitch ? '切换模型' : '生成中无法切换模型',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: canSwitch ? _showModelPickerSheet : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  _zhipuSettings.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelSmall?.copyWith(
                    color: canSwitch ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_up,
                size: 14,
                color: canSwitch ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showModelPickerSheet() async {
    if (_summarizing || _zhipuSettings.customModels.isEmpty) return;

    final selectedModel = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        final tt = Theme.of(sheetContext).textTheme;
        final models = _zhipuSettings.customModels;
        final currentModel = _zhipuSettings.model;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '切换模型',
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  '当前模型：$currentModel',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.5,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: models.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final model = models[index];
                      final selected = model == currentModel;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        title: Text(
                          model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: selected
                            ? Icon(Icons.check, color: cs.primary)
                            : null,
                        onTap: () => Navigator.of(sheetContext).pop(model),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted ||
        selectedModel == null ||
        selectedModel == _zhipuSettings.model) {
      return;
    }

    _zhipuSettings.setModel(selectedModel);
  }

  Widget _buildSummaryPanel(ColorScheme cs, TextTheme tt) {
    final hasContent = _aiSummary.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'AI 总结',
                style: tt.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              if (_zhipuSettings.customModels.isNotEmpty)
                _buildModelNameButton(cs, tt),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _summaryExpanded ? '收起' : '展开',
                onPressed: () =>
                    setState(() => _summaryExpanded = !_summaryExpanded),
                icon: Icon(
                  _summaryExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
              ),
            ],
          ),
          if (_summaryExpanded) ...[
            if (_summaryError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                child: Text(
                  '生成失败：${_summaryError!}',
                  style: tt.bodySmall?.copyWith(color: cs.error),
                ),
              )
            else if (hasContent)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
                child: MarkdownBody(
                  data: _stripSpoilersMarker(_aiSummary),
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                      .copyWith(
                        p: tt.bodyMedium?.copyWith(height: 1.5),
                        h1: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        h2: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        h3: tt.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                        strong: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                        listBullet: tt.bodyMedium,
                      ),
                ),
              )
            else if (_summarizing)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                child: Text(
                  '正在生成中…',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: _summarizing ? '停止' : '重新生成',
                  onPressed: _summarizing ? _stopSummarize : _summarizeComments,
                  icon: Icon(
                    _summarizing ? Icons.stop : Icons.refresh,
                    size: 18,
                  ),
                ),
                if (hasContent && !_summarizing) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '复制',
                    onPressed: () async {
                      final text = _stripSpoilersMarker(_aiSummary);
                      await Clipboard.setData(ClipboardData(text: text));
                      if (mounted) showToast(context, '已复制');
                    },
                    icon: const Icon(Icons.copy, size: 18),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '清除总结',
                    onPressed: _clearSummary,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<_CommentRow> _buildCommentRows(
    BuildContext context,
    double maxWidth,
    List<ChapterCommentDisplayEntry> entries,
  ) {
    if (entries.isEmpty || maxWidth <= 0) return const [];

    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);
    const minWidth = 108.0;
    final preferredMaxWidth = maxWidth * 0.8;

    final estimatedWidths = entries.map((entry) {
      final compactBodyStyle = _buildCommentBodyStyle(
        textTheme,
        compact: true,
        fontScale: _commentFontScale,
      );
      final bodyWidth = _measureTextWidth(
        entry.content,
        compactBodyStyle,
        textScaler,
        preferredMaxWidth,
      );

      final headerWidth = _estimateCompactHeaderWidth(
        context,
        entry,
        preferredMaxWidth,
      );

      var contentWidth = bodyWidth > headerWidth ? bodyWidth : headerWidth;
      final mergedInlineWidth = _estimateCompactMergedInlineWidth(
        context,
        entry,
        bodyWidth: bodyWidth,
        maxWidth: preferredMaxWidth,
      );
      if (mergedInlineWidth > contentWidth) {
        contentWidth = mergedInlineWidth;
      }

      final cardWidth = (contentWidth + 24).clamp(minWidth, preferredMaxWidth);
      return _CommentLayoutItem(entry: entry, width: cardWidth);
    }).toList();

    final rows = <_CommentRow>[];
    var currentItems = <_CommentLayoutItem>[];
    var occupiedWidth = 0.0;

    void pushRow() {
      if (currentItems.isEmpty) return;

      final spacingWidth =
          _commentRowSpacing *
          (currentItems.length > 1 ? currentItems.length - 1 : 0);
      final cardsWidth = currentItems.fold<double>(
        0,
        (sum, item) => sum + item.width,
      );
      final remainder = maxWidth - spacingWidth - cardsWidth;
      if (remainder > 0) {
        final last = currentItems.removeLast();
        currentItems.add(
          _CommentLayoutItem(entry: last.entry, width: last.width + remainder),
        );
      }
      rows.add(_CommentRow(items: List<_CommentLayoutItem>.from(currentItems)));
      currentItems = <_CommentLayoutItem>[];
      occupiedWidth = 0.0;
    }

    for (final item in estimatedWidths) {
      final spacing = currentItems.isEmpty ? 0.0 : _commentRowSpacing;
      final nextWidth = occupiedWidth + spacing + item.width;

      if (currentItems.isNotEmpty && nextWidth > maxWidth) {
        pushRow();
      }

      if (item.width >= maxWidth) {
        rows.add(
          _CommentRow(
            items: [_CommentLayoutItem(entry: item.entry, width: maxWidth)],
          ),
        );
        continue;
      }

      final rowSpacing = currentItems.isEmpty ? 0.0 : _commentRowSpacing;
      occupiedWidth += rowSpacing + item.width;
      currentItems.add(item);
    }

    pushRow();
    return rows;
  }

  double _estimateCompactHeaderWidth(
    BuildContext context,
    ChapterCommentDisplayEntry entry,
    double maxWidth,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final textScaler = MediaQuery.textScalerOf(context);
    final showCountTag = _shouldShowMergedCountTag(entry.count);

    if (entry.isMerged) {
      final countTagWidth = showCountTag
          ? _estimateMergedCountTagWidth(
              context,
              entry.count,
              maxWidth,
              compact: true,
            )
          : 0.0;

      if (!_showUserAvatar) {
        return countTagWidth;
      }

      final avatarCount = entry.avatarComments().length;
      final avatarWidth = _avatarStackWidth(
        avatarCount,
        avatarSize: 22,
        overlap: 8,
      );
      if (!showCountTag) {
        return avatarWidth;
      }

      return avatarWidth + 8 + countTagWidth;
    }

    var width = 0.0;
    var visibleSegments = 0;

    if (_showUserAvatar) {
      width += 20;
      visibleSegments++;
    }

    if (_showUserName) {
      width += _measureTextWidth(
        entry.primaryComment.userName,
        textTheme.labelSmall,
        textScaler,
        maxWidth,
      );
      visibleSegments++;
    }

    if (_showCommentTime) {
      width += _measureTextWidth(
        _formatRelativeTime(entry.createAt),
        textTheme.labelSmall,
        textScaler,
        maxWidth,
      );
      visibleSegments++;
    }

    if (visibleSegments > 1) {
      width += (visibleSegments - 1) * 6;
    }

    return width;
  }

  double _estimateCompactMergedInlineWidth(
    BuildContext context,
    ChapterCommentDisplayEntry entry, {
    required double bodyWidth,
    required double maxWidth,
  }) {
    if (!entry.isMerged ||
        _showUserAvatar ||
        !_shouldShowMergedCountTag(entry.count)) {
      return bodyWidth;
    }

    return bodyWidth +
        8 +
        _estimateMergedCountTagWidth(
          context,
          entry.count,
          maxWidth,
          compact: true,
        );
  }
}

double _measureTextWidth(
  String text,
  TextStyle? style,
  TextScaler textScaler,
  double maxWidth,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
    maxLines: 1,
  )..layout(minWidth: 0, maxWidth: maxWidth);
  return painter.size.width;
}

double _estimateMergedCountTagWidth(
  BuildContext context,
  int count,
  double maxWidth, {
  required bool compact,
}) {
  final textTheme = Theme.of(context).textTheme;
  final textScaler = MediaQuery.textScalerOf(context);
  final isHot = _isHotMergedComment(count);
  final label = _formatMergedCount(count);
  final labelWidth = _measureTextWidth(
    label,
    textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
    textScaler,
    maxWidth,
  );
  final minWidth = _mergedCountTagMinWidth(compact: compact, isHot: isHot);
  final horizontalPadding = _mergedCountTagHorizontalPadding(compact: compact);
  final iconWidth = isHot ? _hotCommentTagIconSize(compact: compact) + 4 : 0.0;
  final intrinsicWidth = labelWidth + horizontalPadding + iconWidth;
  return intrinsicWidth < minWidth ? minWidth : intrinsicWidth;
}

class _CommentSkeleton extends StatefulWidget {
  final bool compact;
  const _CommentSkeleton({required this.compact});

  @override
  State<_CommentSkeleton> createState() => _CommentSkeletonState();
}

class _CommentSkeletonState extends State<_CommentSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final horizontalPadding = widget.compact ? 10.0 : 12.0;
    final topPadding = widget.compact ? 8.0 : 12.0;
    final bottomPadding = widget.compact ? 4.0 : 12.0;
    final avatarSize = widget.compact ? 20.0 : 28.0;

    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.3,
        end: 0.7,
      ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut)),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          topPadding,
          horizontalPadding,
          bottomPadding,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(_commentCardCornerRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 100,
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: widget.compact ? 14 : 16,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: MediaQuery.sizeOf(context).width * 0.6,
              height: widget.compact ? 14 : 16,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _CommentCard extends StatefulWidget {
  final ChapterCommentDisplayEntry entry;
  final String relativeTime;
  final bool compact;
  final bool showAvatar;
  final bool showUserName;
  final bool showCommentTime;
  final double fontScale;
  final Set<int> spoilerIds;

  const _CommentCard({
    required this.entry,
    required this.relativeTime,
    this.compact = false,
    this.showAvatar = true,
    this.showUserName = true,
    this.showCommentTime = true,
    this.fontScale = 1.0,
    this.spoilerIds = const {},
  });

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  bool _revealed = false;

  bool get _isSpoiler {
    // 合并评论：只要其中任一评论 id 在集合中就视为剧透
    if (_revealed) return false;
    for (final c in widget.entry.comments) {
      if (widget.spoilerIds.contains(c.id)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final entry = widget.entry;
    final compact = widget.compact;
    final showAvatar = widget.showAvatar;
    final showUserName = widget.showUserName;
    final showCommentTime = widget.showCommentTime;
    final fontScale = widget.fontScale;
    final relativeTime = widget.relativeTime;
    final horizontalPadding = compact ? 10.0 : 12.0;
    final topPadding = compact ? 8.0 : 12.0;
    final bottomPadding = compact ? 4.0 : 12.0;
    final avatarSize = compact ? 20.0 : 28.0;
    final contentSpacing = compact ? 9.0 : 8.0;
    final userStyle = _buildCommentUserStyle(tt, cs, compact: compact);
    final timeStyle = _buildCommentTimeStyle(tt, cs);
    final bodyStyle = _buildCommentBodyStyle(
      tt,
      compact: compact,
      fontScale: fontScale,
    );
    final showMetaRow = showAvatar || showUserName || showCommentTime;
    final isHotMergedComment =
        entry.isMerged && _isHotMergedComment(entry.count);

    return Container(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        bottomPadding,
      ),
      decoration: _buildCommentCardDecoration(
        cs,
        brightness: brightness,
        highlightAsHot: isHotMergedComment,
      ),
      child: entry.isMerged
          ? _MergedCommentContent(
              entry: entry,
              compact: compact,
              contentSpacing: contentSpacing,
              bodyStyle: bodyStyle,
              showAvatar: showAvatar,
              spoilerIds: widget.spoilerIds,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showMetaRow) ...[
                  Row(
                    children: [
                      if (showAvatar) ...[
                        _CommentAvatar(
                          imageUrl: entry.primaryComment.userAvatar,
                          size: avatarSize,
                        ),
                        SizedBox(width: compact ? 6 : 8),
                      ],
                      if (showUserName)
                        Expanded(
                          child: Text(
                            entry.primaryComment.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: userStyle,
                          ),
                        ),
                      if (showUserName && showCommentTime)
                        SizedBox(width: compact ? 6 : 8),
                      if (showCommentTime) Text(relativeTime, style: timeStyle),
                    ],
                  ),
                  SizedBox(height: contentSpacing),
                ],
                Stack(
                  children: [
                    SelectableText(
                      entry.content,
                      minLines: compact ? 1 : null,
                      style: bodyStyle,
                    ),
                    if (_isSpoiler)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () async {
                            final settings = ZhipuSettings();
                            if (!settings.spoilerWarn) {
                              setState(() => _revealed = true);
                              return;
                            }
                            var noRemind = false;
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => StatefulBuilder(
                                builder: (ctx, setLocal) => AlertDialog(
                                  title: const Text('剧透警告'),
                                  content: const Text('真的要打开吗？前方是地狱啊！'),
                                  actions: [
                                    SizedBox(
                                      height: 32,
                                      child: GestureDetector(
                                        onTap: () => setLocal(
                                          () => noRemind = !noRemind,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: Checkbox(
                                                value: noRemind,
                                                onChanged: (v) => setLocal(
                                                  () => noRemind = v ?? false,
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '不再提醒',
                                              style: Theme.of(
                                                ctx,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('算了'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('打开'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            if (ok == true) {
                              if (noRemind) {
                                await settings.setSpoilerWarn(false);
                              }
                              setState(() => _revealed = true);
                            }
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                              child: Container(
                                color: cs.surface.withValues(alpha: 0.5),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.visibility_off_outlined,
                                        size: compact ? 16 : 20,
                                        color: cs.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '这是一条高度剧透嫌疑的评论',
                                        style: tt.labelSmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
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
              ],
            ),
    );
  }
}

class _CommentRow {
  final List<_CommentLayoutItem> items;

  const _CommentRow({required this.items});
}

class _CommentLayoutItem {
  final ChapterCommentDisplayEntry entry;
  final double width;

  const _CommentLayoutItem({required this.entry, required this.width});
}

class _MergedCommentContent extends StatefulWidget {
  final ChapterCommentDisplayEntry entry;
  final bool compact;
  final double contentSpacing;
  final TextStyle? bodyStyle;
  final bool showAvatar;
  final Set<int> spoilerIds;

  const _MergedCommentContent({
    required this.entry,
    required this.compact,
    required this.contentSpacing,
    required this.bodyStyle,
    this.showAvatar = true,
    this.spoilerIds = const {},
  });

  @override
  State<_MergedCommentContent> createState() => _MergedCommentContentState();
}

class _MergedCommentContentState extends State<_MergedCommentContent> {
  bool _revealed = false;

  bool get _isSpoiler {
    if (_revealed) return false;
    for (final c in widget.entry.comments) {
      if (widget.spoilerIds.contains(c.id)) return true;
    }
    return false;
  }

  Widget _buildSpoilerOverlay(ColorScheme cs, TextTheme tt) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () async {
          final settings = ZhipuSettings();
          if (!settings.spoilerWarn) {
            setState(() => _revealed = true);
            return;
          }
          var noRemind = false;
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => StatefulBuilder(
              builder: (ctx, setLocal) => AlertDialog(
                title: const Text('剧透警告'),
                content: const Text('真的要打开吗？前方是地狱啊！'),
                actions: [
                  SizedBox(
                    height: 32,
                    child: GestureDetector(
                      onTap: () => setLocal(() => noRemind = !noRemind),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: Checkbox(
                              value: noRemind,
                              onChanged: (v) =>
                                  setLocal(() => noRemind = v ?? false),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '不再提醒',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('算了'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('打开'),
                  ),
                ],
              ),
            ),
          );
          if (ok == true) {
            if (noRemind) await settings.setSpoilerWarn(false);
            setState(() => _revealed = true);
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              color: cs.surface.withValues(alpha: 0.5),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      size: widget.compact ? 16 : 20,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '含剧透，点击查看',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final entry = widget.entry;
    final compact = widget.compact;
    final showAvatar = widget.showAvatar;
    final showCountTag = _shouldShowMergedCountTag(entry.count);

    Widget spoilerWrap(Widget child) {
      if (!_isSpoiler) return child;
      return Stack(children: [child, _buildSpoilerOverlay(cs, tt)]);
    }

    if (!showAvatar) {
      if (!showCountTag) {
        return spoilerWrap(
          SelectableText(
            entry.content,
            minLines: compact ? 1 : null,
            style: widget.bodyStyle,
          ),
        );
      }
      return spoilerWrap(
        Row(
          crossAxisAlignment: compact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                entry.content,
                maxLines: compact ? 3 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
                style: widget.bodyStyle,
              ),
            ),
            const SizedBox(width: 8),
            Align(
              alignment: compact ? Alignment.center : Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: compact ? 0 : 2),
                child: _MergedCommentCountTag(
                  count: entry.count,
                  compact: compact,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _CommentAvatarStack(
              comments: entry.avatarComments(),
              avatarSize: compact ? 22.0 : 26.0,
              overlap: compact ? 8.0 : 10.0,
            ),
            const Spacer(),
            if (showCountTag) ...[
              const SizedBox(width: 8),
              _MergedCommentCountTag(count: entry.count, compact: compact),
            ],
          ],
        ),
        SizedBox(height: widget.contentSpacing + (compact ? 1 : 2)),
        spoilerWrap(
          SelectableText(
            entry.content,
            minLines: compact ? 1 : null,
            style: widget.bodyStyle,
          ),
        ),
      ],
    );
  }
}

class _MergedCommentCountTag extends StatelessWidget {
  final int count;
  final bool compact;

  const _MergedCommentCountTag({required this.count, required this.compact});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isHot = _isHotMergedComment(count);
    final tagHeight = _mergedCountTagHeight(compact: compact);
    final minWidth = _mergedCountTagMinWidth(compact: compact, isHot: isHot);
    final horizontalPadding = _mergedCountTagHorizontalPadding(
      compact: compact,
    );
    final colors = _mergedCountTagColors(cs, isHot: isHot);
    final decoration = _buildMergedCountTagDecoration(cs, isHot: isHot);
    final label = _formatMergedCount(count);
    final iconSize = _hotCommentTagIconSize(compact: compact);

    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: tagHeight),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding / 2),
      alignment: Alignment.center,
      decoration: decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isHot) ...[
            Icon(
              Icons.local_fire_department_rounded,
              size: iconSize,
              color: colors.foreground,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            textAlign: TextAlign.center,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            strutStyle: const StrutStyle(height: 1, forceStrutHeight: true),
            style: tt.labelSmall?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentAvatarStack extends StatelessWidget {
  final List<ChapterComment> comments;
  final double avatarSize;
  final double overlap;

  const _CommentAvatarStack({
    required this.comments,
    required this.avatarSize,
    required this.overlap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = comments.isEmpty
        ? const <ChapterComment>[]
        : comments.take(5).toList(growable: false);

    if (items.isEmpty) {
      return _CommentAvatar(imageUrl: '', size: avatarSize);
    }

    final width = _avatarStackWidth(
      items.length,
      avatarSize: avatarSize,
      overlap: overlap,
    );
    final inset = _avatarInset(avatarSize);

    return SizedBox(
      width: width,
      height: avatarSize,
      child: Stack(
        children: [
          for (var i = 0; i < items.length; i++)
            Positioned(
              left: i * (avatarSize - overlap),
              child: Container(
                width: avatarSize,
                height: avatarSize,
                padding: EdgeInsets.all(inset),
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                ),
                child: _CommentAvatar(
                  imageUrl: items[i].userAvatar,
                  size: avatarSize - inset * 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentAvatar extends StatelessWidget {
  final String imageUrl;
  final double size;

  const _CommentAvatar({required this.imageUrl, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl.isEmpty
            ? ColoredBox(
                color: cs.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: size * 0.5,
                  color: cs.onSurfaceVariant,
                ),
              )
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.person,
                    size: size * 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                errorWidget: (_, _, _) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.person,
                    size: size * 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}

class _CommentSettingsPanel extends StatefulWidget {
  final bool useCompactLayout;
  final bool showUserAvatar;
  final bool showUserName;
  final bool showCommentTime;
  final double commentFontScale;
  final bool commentPreload;
  final bool commentAutoLoadAll;
  final ValueChanged<bool> onLayoutChanged;
  final ValueChanged<bool> onShowAvatarChanged;
  final ValueChanged<bool> onShowUserNameChanged;
  final ValueChanged<bool> onShowCommentTimeChanged;
  final ValueChanged<double> onFontScaleChanged;
  final ValueChanged<bool> onPreloadChanged;
  final ValueChanged<bool> onAutoLoadAllChanged;

  const _CommentSettingsPanel({
    required this.useCompactLayout,
    required this.showUserAvatar,
    required this.showUserName,
    required this.showCommentTime,
    required this.commentFontScale,
    required this.commentPreload,
    required this.commentAutoLoadAll,
    required this.onLayoutChanged,
    required this.onShowAvatarChanged,
    required this.onShowUserNameChanged,
    required this.onShowCommentTimeChanged,
    required this.onFontScaleChanged,
    required this.onPreloadChanged,
    required this.onAutoLoadAllChanged,
  });

  @override
  State<_CommentSettingsPanel> createState() => _CommentSettingsPanelState();
}

class _CommentSettingsPanelState extends State<_CommentSettingsPanel> {
  late bool _useCompactLayout;
  late bool _showUserAvatar;
  late bool _showUserName;
  late bool _showCommentTime;
  late double _commentFontScale;
  late bool _commentPreload;
  late bool _commentAutoLoadAll;

  @override
  void initState() {
    super.initState();
    _useCompactLayout = widget.useCompactLayout;
    _showUserAvatar = widget.showUserAvatar;
    _showUserName = widget.showUserName;
    _showCommentTime = widget.showCommentTime;
    _commentFontScale = widget.commentFontScale;
    _commentPreload = widget.commentPreload;
    _commentAutoLoadAll = widget.commentAutoLoadAll;
  }

  Future<void> _editPreset(
    BuildContext context, {
    required PromptPreset preset,
    required bool isBuiltIn,
  }) async {
    final settings = ZhipuSettings();
    final nameCtrl = TextEditingController(text: preset.name);
    final promptCtrl = TextEditingController(text: preset.prompt);
    final result = await showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isBuiltIn ? '编辑内置提示词' : '编辑提示词'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptCtrl,
                minLines: 6,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: '提示词',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!isBuiltIn)
            TextButton(
              onPressed: () => Navigator.pop(ctx, {'action': 'delete'}),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('删除'),
            ),
          if (isBuiltIn)
            TextButton(
              onPressed: () {
                final builtIn = ZhipuSettings.builtInPresets
                    .where((p) => p.id == preset.id)
                    .firstOrNull;
                if (builtIn != null) {
                  nameCtrl.text = builtIn.name;
                  promptCtrl.text = builtIn.prompt;
                }
              },
              child: const Text('还原默认'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, {
              'name': nameCtrl.text,
              'prompt': promptCtrl.text,
            }),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final action = result['action'];
    if (action == 'delete') {
      await settings.removePreset(preset.id);
    } else {
      await settings.updatePreset(
        preset.id,
        name: result['name']!.trim(),
        prompt: result['prompt']!.trim(),
      );
    }
  }

  Future<void> _addPreset(BuildContext context) async {
    final settings = ZhipuSettings();
    final nameCtrl = TextEditingController();
    final promptCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加提示词'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptCtrl,
                minLines: 6,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: '提示词',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty ||
                  promptCtrl.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(ctx, {
                'name': nameCtrl.text,
                'prompt': promptCtrl.text,
              });
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != null) {
      await settings.addPreset(
        result['name']!.trim(),
        result['prompt']!.trim(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final defaultFontSizePx = _defaultCommentFontSizePx(
      tt,
      compact: _useCompactLayout,
    );
    final minFontSizePx = _commentFontMinPx(defaultFontSizePx);
    final maxFontSizePx = _commentFontMaxPx(defaultFontSizePx);
    final currentFontSizePx = _commentFontScaleToPx(
      defaultFontSizePx,
      _commentFontScale,
    ).clamp(minFontSizePx, maxFontSizePx);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
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
                '评论区设置',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              Text('布局', style: tt.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.dashboard_outlined),
                      label: Text('紧凑布局'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.view_agenda_outlined),
                      label: Text('列表布局'),
                    ),
                  ],
                  selected: {_useCompactLayout},
                  onSelectionChanged: (values) {
                    final value = values.first;
                    setState(() => _useCompactLayout = value);
                    widget.onLayoutChanged(value);
                  },
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示头像'),
                value: _showUserAvatar,
                onChanged: (value) {
                  setState(() => _showUserAvatar = value);
                  widget.onShowAvatarChanged(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示用户名'),
                value: _showUserName,
                onChanged: (value) {
                  setState(() => _showUserName = value);
                  widget.onShowUserNameChanged(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示评论时间'),
                value: _showCommentTime,
                onChanged: (value) {
                  setState(() => _showCommentTime = value);
                  widget.onShowCommentTimeChanged(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('预加载评论'),
                subtitle: const Text('进入章节时提前加载评论并显示数量'),
                value: _commentPreload,
                onChanged: (value) {
                  setState(() => _commentPreload = value);
                  widget.onPreloadChanged(value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动加载全部评论'),
                subtitle: const Text('打开评论区时自动加载所有评论'),
                value: _commentAutoLoadAll,
                onChanged: (value) {
                  setState(() => _commentAutoLoadAll = value);
                  widget.onAutoLoadAllChanged(value);
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text('评论内容字体大小', style: tt.bodyMedium),
                  const Spacer(),
                  Text(
                    '${currentFontSizePx.round()} px',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              Slider(
                value: currentFontSizePx,
                min: minFontSizePx,
                max: maxFontSizePx,
                divisions: ((maxFontSizePx - minFontSizePx) / 1).round(),
                label: '${currentFontSizePx.round()} px',
                onChanged: (value) {
                  final nextScale = _commentFontPxToScale(
                    defaultFontSizePx,
                    value,
                  );
                  setState(() => _commentFontScale = nextScale);
                  widget.onFontScaleChanged(nextScale);
                },
              ),
              const Divider(height: 24),
              // AI 总结设置
              ListenableBuilder(
                listenable: ZhipuSettings(),
                builder: (context, _) {
                  final zhipu = ZhipuSettings();
                  final hasKey = zhipu.hasApiKey;
                  final enabled = zhipu.summaryEnabled;
                  final spoiler = zhipu.spoilerAnalysis;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI 总结', style: tt.bodyMedium),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用 AI 总结'),
                        subtitle: Text(
                          hasKey
                              ? (enabled ? '评论顶部显示 AI 总结按钮' : '未启用')
                              : '请先在「我的 → 智谱清言」中配置 API 密钥',
                          style: tt.bodySmall?.copyWith(
                            color: hasKey ? null : cs.error,
                          ),
                        ),
                        value: enabled && hasKey,
                        onChanged: hasKey
                            ? (v) => zhipu.setSummaryEnabled(v)
                            : null,
                      ),
                      if (enabled && hasKey) ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('自动 AI 总结'),
                          subtitle: Text(
                            '评论数 ≥ ${zhipu.autoSummaryMin} 条时自动生成',
                          ),
                          value: zhipu.autoSummary,
                          onChanged: (v) => zhipu.setAutoSummary(v),
                        ),
                        if (zhipu.autoSummary)
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text('最少评论数', style: tt.bodySmall),
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      width: 64,
                                      child: TextFormField(
                                        initialValue: zhipu.autoSummaryMin
                                            .toString(),
                                        keyboardType: TextInputType.number,
                                        style: tt.bodySmall,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          ),
                                          border: OutlineInputBorder(),
                                        ),
                                        onFieldSubmitted: (v) {
                                          final n = int.tryParse(v);
                                          if (n != null && n > 0) {
                                            zhipu.setAutoSummaryMin(n);
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text('调用时机', style: tt.bodySmall),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: double.infinity,
                                  child:
                                      SegmentedButton<ZhipuAutoSummaryTiming>(
                                        segments: [
                                          const ButtonSegment(
                                            value:
                                                ZhipuAutoSummaryTiming.onOpen,
                                            label: Text('打开评论区时'),
                                          ),
                                          ButtonSegment(
                                            value: ZhipuAutoSummaryTiming
                                                .afterPreload,
                                            label: const Text('预加载完成后'),
                                            enabled: _commentPreload,
                                          ),
                                        ],
                                        selected: {
                                          _commentPreload
                                              ? zhipu.autoSummaryTiming
                                              : ZhipuAutoSummaryTiming.onOpen,
                                        },
                                        onSelectionChanged: (values) {
                                          zhipu.setAutoSummaryTiming(
                                            values.first,
                                          );
                                        },
                                      ),
                                ),
                                if (!_commentPreload) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '选择“预加载完成后”需要先开启预加载评论。',
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('剧透分析'),
                          subtitle: const Text('识别剧透评论并自动遮罩（需要搭配特定提示词）'),
                          value: spoiler,
                          onChanged: (v) => zhipu.setSpoilerAnalysis(v),
                        ),
                        if (spoiler)
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('打开剧透评论弹出提醒'),
                            value: zhipu.spoilerWarn,
                            onChanged: (v) => zhipu.setSpoilerWarn(v),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          '提示词预设',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        RadioGroup<String>(
                          groupValue: zhipu.activePresetId,
                          onChanged: (v) {
                            if (v != null) zhipu.setActivePreset(v);
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final p in zhipu.presets)
                                ListTile(
                                  contentPadding: const EdgeInsets.only(
                                    left: 0,
                                    right: 8,
                                  ),
                                  leading: Radio<String>(value: p.id),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          p.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (p.isBuiltIn &&
                                          zhipu.isPresetModified(p.id))
                                        Icon(
                                          Icons.edit_note,
                                          size: 16,
                                          color: cs.primary,
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    p.prompt,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                    ),
                                    tooltip: '编辑',
                                    onPressed: () => _editPreset(
                                      context,
                                      preset: p,
                                      isBuiltIn: p.isBuiltIn,
                                    ),
                                  ),
                                  onTap: () => zhipu.setActivePreset(p.id),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('添加提示词'),
                            onPressed: () => _addPreset(context),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatMergedCount(int count) => '$count';

bool _shouldShowMergedCountTag(int count) => count > 1;

bool _isHotMergedComment(int count) => count >= 10;

const _commentCardCornerRadius = 10.0;
const _hotCommentAccentColor = Color(0xFFFF7A2F);

double _hotCommentTagIconSize({required bool compact}) => compact ? 14.0 : 16.0;

double _mergedCountTagHeight({required bool compact}) => compact ? 24.0 : 28.0;

double _mergedCountTagMinWidth({required bool compact, required bool isHot}) {
  if (!isHot) return compact ? 24.0 : 28.0;
  return compact ? 34.0 : 40.0;
}

double _mergedCountTagHorizontalPadding({required bool compact}) =>
    compact ? 12.0 : 16.0;

class _MergedCountTagColors {
  final Color foreground;

  const _MergedCountTagColors({required this.foreground});
}

_MergedCountTagColors _mergedCountTagColors(
  ColorScheme colorScheme, {
  required bool isHot,
}) {
  if (!isHot) {
    return _MergedCountTagColors(foreground: colorScheme.onPrimary);
  }
  return const _MergedCountTagColors(foreground: _hotCommentAccentColor);
}

BoxDecoration _buildMergedCountTagDecoration(
  ColorScheme colorScheme, {
  required bool isHot,
}) {
  if (!isHot) {
    return BoxDecoration(
      color: colorScheme.primary,
      borderRadius: BorderRadius.circular(999),
    );
  }

  return BoxDecoration(
    color: Color.lerp(
      colorScheme.surfaceContainerLow,
      _hotCommentAccentColor,
      0.08,
    ),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: _hotCommentAccentColor.withValues(alpha: 0.58)),
  );
}

BoxDecoration _buildCommentCardDecoration(
  ColorScheme colorScheme, {
  required Brightness brightness,
  required bool highlightAsHot,
}) {
  final borderRadius = BorderRadius.circular(_commentCardCornerRadius);
  if (!highlightAsHot) {
    return BoxDecoration(
      color: colorScheme.surfaceContainerLow,
      borderRadius: borderRadius,
    );
  }

  final surface = colorScheme.surfaceContainerLow;
  return BoxDecoration(
    color: surface,
    borderRadius: borderRadius,
    border: Border.all(
      color: _hotCommentAccentColor.withValues(
        alpha: brightness == Brightness.dark ? 0.48 : 0.56,
      ),
    ),
  );
}

TextStyle? _buildCommentUserStyle(
  TextTheme textTheme,
  ColorScheme colorScheme, {
  required bool compact,
}) {
  final metaColor = colorScheme.onSurfaceVariant.withValues(
    alpha: compact ? 0.72 : 0.78,
  );
  return (compact ? textTheme.labelSmall : textTheme.labelMedium)?.copyWith(
    color: metaColor,
    fontWeight: FontWeight.w500,
  );
}

TextStyle? _buildCommentTimeStyle(
  TextTheme textTheme,
  ColorScheme colorScheme,
) {
  return textTheme.labelSmall?.copyWith(
    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
    fontWeight: FontWeight.w400,
  );
}

TextStyle? _buildCommentBodyStyle(
  TextTheme textTheme, {
  required bool compact,
  required double fontScale,
}) {
  final baseStyle = compact
      ? textTheme.bodyMedium
      : (textTheme.bodyLarge ?? textTheme.bodyMedium);
  final defaultFontSize = _defaultCommentFontSizePx(
    textTheme,
    compact: compact,
  );

  return baseStyle?.copyWith(
        fontSize: defaultFontSize * fontScale,
        height: compact ? 1.35 : 1.55,
        fontWeight: FontWeight.w500,
      ) ??
      TextStyle(
        fontSize: defaultFontSize * fontScale,
        height: compact ? 1.35 : 1.55,
        fontWeight: FontWeight.w500,
      );
}

double _defaultCommentFontSizePx(TextTheme textTheme, {required bool compact}) {
  final baseStyle = compact
      ? textTheme.bodyMedium
      : (textTheme.bodyLarge ?? textTheme.bodyMedium);
  final fontSize = baseStyle?.fontSize;
  return fontSize != null && fontSize >= 16 ? fontSize : 16.0;
}

double _commentFontMinPx(double defaultFontSizePx) {
  final minPx = defaultFontSizePx - 5;
  return minPx < 10 ? 10 : minPx;
}

double _commentFontMaxPx(double defaultFontSizePx) => defaultFontSizePx + 14;

double _commentFontScaleToPx(double defaultFontSizePx, double scale) =>
    defaultFontSizePx * scale;

double _commentFontPxToScale(double defaultFontSizePx, double fontSizePx) =>
    fontSizePx / defaultFontSizePx;

double _avatarStackWidth(
  int count, {
  required double avatarSize,
  required double overlap,
}) {
  if (count <= 0) return avatarSize;
  return avatarSize + (count - 1) * (avatarSize - overlap);
}

double _avatarInset(double avatarSize) => avatarSize <= 22 ? 1.5 : 2;
