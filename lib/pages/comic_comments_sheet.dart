import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/comic_comment.dart';

class ComicCommentsSheet extends StatefulWidget {
  final String comicId;
  final String comicName;

  const ComicCommentsSheet({
    super.key,
    required this.comicId,
    required this.comicName,
  });

  @override
  State<ComicCommentsSheet> createState() => _ComicCommentsSheetState();
}

class _ComicCommentsSheetState extends State<ComicCommentsSheet> {
  static const _pageSize = 10;
  static const _replyPageSize = 3;
  static const _loadMoreThreshold = 240.0;
  static const _listBottomPadding = 32.0;

  final _api = ApiClient();
  final _scrollController = ScrollController();

  List<ComicComment> _comments = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  final Map<int, _ComicReplyState> _replyStates = {};

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadComments({bool loadMore = false}) async {
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
      final data = await _api.getComicComments(
        widget.comicId,
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

  _ComicReplyState _replyStateOf(int commentId) =>
      _replyStates[commentId] ?? const _ComicReplyState();

  Future<void> _toggleReplies(ComicComment comment) async {
    final currentState = _replyStateOf(comment.id);
    if (currentState.expanded) {
      setState(() {
        _replyStates[comment.id] = currentState.copyWith(
          expanded: false,
          error: null,
        );
      });
      return;
    }

    setState(() {
      _replyStates[comment.id] = currentState.copyWith(
        expanded: true,
        error: null,
      );
    });

    if (currentState.replies.isEmpty && !currentState.loading) {
      await _loadReplies(comment);
    }
  }

  Future<void> _loadReplies(
    ComicComment comment, {
    bool loadMore = false,
  }) async {
    final currentState = _replyStateOf(comment.id);
    final knownTotal = currentState.total > 0
        ? currentState.total
        : comment.replyCount;

    if (loadMore) {
      if (currentState.loading || currentState.loadingMore) return;
      if (currentState.replies.length >= knownTotal) return;
    } else if (currentState.loading) {
      return;
    }

    setState(() {
      _replyStates[comment.id] = currentState.copyWith(
        expanded: true,
        loading: !loadMore,
        loadingMore: loadMore,
        error: null,
      );
    });

    try {
      final data = await _api.getComicComments(
        widget.comicId,
        replyId: comment.id.toString(),
        limit: _replyPageSize,
        offset: loadMore ? currentState.replies.length : 0,
      );
      if (!mounted) return;

      final mergedReplies = loadMore
          ? [
              ...currentState.replies,
              ...data.list.where(
                (item) => !currentState.replies.any(
                  (existing) => existing.id == item.id,
                ),
              ),
            ]
          : data.list;
      final latestState = _replyStateOf(comment.id);

      setState(() {
        _replyStates[comment.id] = latestState.copyWith(
          loading: false,
          loadingMore: false,
          replies: mergedReplies,
          total: data.total,
          error: null,
        );
      });
    } catch (e) {
      if (!mounted) return;
      final latestState = _replyStateOf(comment.id);
      setState(() {
        _replyStates[comment.id] = latestState.copyWith(
          loading: false,
          loadingMore: false,
          error: e.toString(),
        );
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final width = MediaQuery.sizeOf(context).width;
    final height = MediaQuery.sizeOf(context).height * 0.85;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '漫画评论',
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.comicName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _total > 0
                            ? (_comments.length >= _total
                                  ? '$_total 条'
                                  : '${_comments.length}/$_total')
                            : '',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        tooltip: '关闭',
                        icon: const Icon(Icons.close),
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
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme cs, TextTheme tt) {
    if (_loading && _comments.isEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, _listBottomPadding),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, _) => const _ComicCommentSkeleton(),
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
                onPressed: _loadComments,
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
              '这部漫画暂时没人发言',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, _listBottomPadding),
        itemCount: _comments.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          if (index == _comments.length && _loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final comment = _comments[index];
          return _buildCommentCard(cs, tt, comment);
        },
      ),
    );
  }

  Widget _buildCommentCard(
    ColorScheme cs,
    TextTheme tt,
    ComicComment comment,
  ) {
    final replyState = _replyStateOf(comment.id);
    final canExpandReplies = comment.replyCount > 0;
    final bodyStyle = tt.bodyMedium?.copyWith(
      height: 1.48,
      fontWeight: FontWeight.w500,
    );
    final metaStyle = tt.titleSmall?.copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w500,
    );
    final timeStyle = tt.bodySmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.78),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ComicCommentAvatar(imageUrl: comment.userAvatar, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            comment.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: metaStyle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatRelativeTime(comment.createAt),
                          style: timeStyle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildCommentText(
                      comment,
                      cs,
                      bodyStyle: bodyStyle,
                    ),
                    if (canExpandReplies) ...[
                      const SizedBox(height: 12),
                      _buildCommentActions(cs, tt, comment, replyState),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (canExpandReplies && replyState.expanded)
            _buildReplySection(cs, tt, comment, replyState),
        ],
      ),
    );
  }

  Widget _buildCommentActions(
    ColorScheme cs,
    TextTheme tt,
    ComicComment comment,
    _ComicReplyState replyState,
  ) {
    final loadingInitial = replyState.loading && replyState.replies.isEmpty;
    final actionStyle = tt.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _toggleReplies(comment),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loadingInitial)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onSurfaceVariant,
                ),
              )
            else
              Icon(
                replyState.expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            const SizedBox(width: 2),
            Text(
              replyState.expanded ? '收起回复' : '展开 ${comment.replyCount} 条回复',
              style: actionStyle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplySection(
    ColorScheme cs,
    TextTheme tt,
    ComicComment comment,
    _ComicReplyState replyState,
  ) {
    final replies = replyState.replies;
    final totalReplies = replyState.total > 0
        ? replyState.total
        : comment.replyCount;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.65),
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyState.loading && replies.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          if (replyState.error != null && replies.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '回复加载失败',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _loadReplies(comment),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          if (!replyState.loading && replies.isEmpty && replyState.error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '暂无可显示的回复',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          for (var i = 0; i < replies.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == replies.length - 1 ? 0 : 12),
              child: _buildReplyItem(cs, tt, replies[i]),
            ),
          if (replyState.error != null && replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: replyState.loadingMore
                    ? null
                    : () => _loadReplies(comment, loadMore: true),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试加载更多回复'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 0),
                ),
              ),
            ),
          if (replyState.error == null &&
              replies.isNotEmpty &&
              replies.length < totalReplies)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: replyState.loadingMore
                    ? null
                    : () => _loadReplies(comment, loadMore: true),
                icon: replyState.loadingMore
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      )
                    : const Icon(Icons.expand_more_rounded, size: 18),
                label: Text('加载更多回复 (${replies.length}/$totalReplies)'),
                style: TextButton.styleFrom(
                  foregroundColor: cs.primary,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyItem(ColorScheme cs, TextTheme tt, ComicComment reply) {
    final metaStyle = tt.bodySmall?.copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w500,
    );
    final timeStyle = tt.labelSmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
    );
    final bodyStyle = tt.bodySmall?.copyWith(
      height: 1.5,
      fontWeight: FontWeight.w500,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ComicCommentAvatar(imageUrl: reply.userAvatar, size: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      reply.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_formatRelativeTime(reply.createAt), style: timeStyle),
                ],
              ),
              const SizedBox(height: 4),
              _buildCommentText(reply, cs, bodyStyle: bodyStyle),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommentText(
    ComicComment comment,
    ColorScheme cs, {
    required TextStyle? bodyStyle,
  }) {
    final parentUserName = comment.parentUserName?.trim() ?? '';

    return SelectableText.rich(
      TextSpan(
        children: [
          if (parentUserName.isNotEmpty)
            TextSpan(
              text: '@$parentUserName ',
              style: bodyStyle?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          TextSpan(text: comment.comment, style: bodyStyle),
        ],
      ),
    );
  }
}

class _ComicReplyState {
  static const _unset = Object();

  final bool expanded;
  final bool loading;
  final bool loadingMore;
  final List<ComicComment> replies;
  final int total;
  final String? error;

  const _ComicReplyState({
    this.expanded = false,
    this.loading = false,
    this.loadingMore = false,
    this.replies = const [],
    this.total = 0,
    this.error,
  });

  _ComicReplyState copyWith({
    bool? expanded,
    bool? loading,
    bool? loadingMore,
    List<ComicComment>? replies,
    int? total,
    Object? error = _unset,
  }) {
    return _ComicReplyState(
      expanded: expanded ?? this.expanded,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      replies: replies ?? this.replies,
      total: total ?? this.total,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}

class _ComicCommentAvatar extends StatelessWidget {
  final String imageUrl;
  final double size;

  const _ComicCommentAvatar({required this.imageUrl, required this.size});

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

class _ComicCommentSkeleton extends StatelessWidget {
  const _ComicCommentSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 12,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 14,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: MediaQuery.sizeOf(context).width * 0.55,
            height: 14,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ),
    );
  }
}
