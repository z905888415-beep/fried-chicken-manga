import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/comic_hero_tags.dart';
import '../utils/layout.dart';
import '../utils/toast.dart';
import '../widgets/kira_app_bar.dart';
import '../widgets/state_views.dart';
import 'comic_detail_page.dart';

class BrowseHistoryPage extends StatefulWidget {
  final WidgetBuilder loginPageBuilder;

  const BrowseHistoryPage({super.key, required this.loginPageBuilder});

  @override
  State<BrowseHistoryPage> createState() => _BrowseHistoryPageState();
}

class _BrowseHistoryPageState extends State<BrowseHistoryPage> {
  final _api = ApiClient();
  final _user = UserManager();

  List<BrowseHistoryItem> _comicItems = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _showingLoginPrompt = false;
  int _offset = 0;
  int _total = 0;

  bool get _currentItemsEmpty => _comicItems.isEmpty;
  int get _currentLength => _comicItems.length;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    if (_user.isLoggedIn) {
      _load(silent: true);
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _load({bool silent = false, bool isInitial = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    if (!silent && !isInitial) {
      setState(() {});
    }

    _offset = 0;

    try {
      final data = await _api.getBrowseHistory();
      if (!mounted) return;
      setState(() {
        _comicItems = data.list;
        _total = data.total;
        _offset = data.list.length;
        _loading = false;
      });
      if (!silent && mounted) {
        showToast(context, '刷新成功');
      }
    } catch (e) {
      debugPrint('BrowseHistoryPage load error: $e');
      if (isInitial && mounted) setState(() => _loading = false);
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      } else if (!silent && mounted) {
        showToast(context, '刷新失败', isError: true);
      }
    } finally {
      _refreshing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _refreshing || _offset >= _total) return;
    _loadingMore = true;
    try {
      final data = await _api.getBrowseHistory(offset: _offset);
      if (!mounted) return;
      setState(() {
        _comicItems.addAll(data.list);
        _offset = _comicItems.length;
      });
    } catch (e) {
      debugPrint('BrowseHistoryPage loadMore error: $e');
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      }
    } finally {
      _loadingMore = false;
    }
  }

  bool _isUnauthorized(Object error) =>
      error is DioException && error.response?.statusCode == 401;

  Future<void> _handleUnauthorized() async {
    if (_showingLoginPrompt || !mounted) return;

    if (_user.autoLogin) {
      await _user.logout();
      if (mounted) {
        showToast(context, '自动登录失败，请手动重新登录', isError: true);
      }
      return;
    }

    _showingLoginPrompt = true;

    await _user.logout();
    if (!mounted) {
      _showingLoginPrompt = false;
      return;
    }

    final shouldLogin = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('登录已过期'),
        content: const Text('浏览记录需要登录后才能继续查看，是否现在重新登录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去登录'),
          ),
        ],
      ),
    );

    if (shouldLogin == true && mounted) {
      await _goLogin();
    } else if (mounted) {
      showToast(context, '登录后可继续查看浏览记录', isError: true);
    }

    _showingLoginPrompt = false;
  }

  Future<void> _goLogin() async {
    final loggedIn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: widget.loginPageBuilder),
    );
    if (loggedIn == true && mounted) {
      _load(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hp = MaxWidthCenter.hp(context);

    return Scaffold(
      appBar: KiraAppBar(titleText: '娴忚璁板綍', onBack: () => Navigator.pop(context)),
      body: !_user.isLoggedIn
          ? EmptyView(
              message: '登录后可查看浏览记录',
              action: FilledButton.icon(
                onPressed: _goLogin,
                icon: const Icon(Icons.login),
                label: const Text('去登录'),
              ),
            )
          : _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (!_currentItemsEmpty &&
                      n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
                    _loadMore();
                  }
                  return false;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (_refreshing)
                      const SliverToBoxAdapter(
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (_currentItemsEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyView(
                          message: '还没有漫画浏览记录',
                          action: FilledButton.tonalIcon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('刷新'),
                          ),
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(hp, 12, hp, 8),
                          child: Text(
                            '共 $_total 条漫画浏览记录',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(hp, 0, hp, 24),
                        sliver: SliverList.builder(
                          itemCount: _currentLength,
                          itemBuilder: (_, i) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _ComicBrowseHistoryCard(
                                item: _comicItems[i],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  static String formatPopular(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }

  static String formatRelativeTime(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
    return '${(diff.inDays / 365).floor()}年前';
  }
}

class _ComicBrowseHistoryCard extends StatelessWidget {
  final BrowseHistoryItem item;
  const _ComicBrowseHistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final comic = item.comic;
    final authors = comic.authors.map((e) => e.name).where((e) => e.isNotEmpty);
    final heroTagBase = ComicHeroTags.base(
      scope: 'browse-history',
      pathWord: comic.pathWord,
      index: item.id,
    );

    return _HistoryCardShell(
      onTap: () => Navigator.push(
        context,
        ComicDetailPage.route(
          pathWord: comic.pathWord,
          initialComic: comic,
          heroTagBase: heroTagBase,
        ),
      ),
      cover: _HistoryCover(
        imageUrl: comic.cover,
        icon: Icons.menu_book_outlined,
      ),
      title: comic.name,
      subtitle: authors.isEmpty ? null : authors.join(', '),
      lastBrowseName: item.lastBrowseName,
      lastBrowseIcon: Icons.play_circle_outline,
      latestText:
          (comic.lastChapterName != null && comic.lastChapterName!.isNotEmpty)
          ? '最新 ${comic.lastChapterName}'
          : null,
      chips: [
        _HistoryMetaChip(
          icon: Icons.local_fire_department,
          label: _BrowseHistoryPageState.formatPopular(comic.popular),
        ),
        if (comic.datetimeUpdated != null)
          _HistoryMetaChip(
            icon: Icons.schedule,
            label: _BrowseHistoryPageState.formatRelativeTime(
              comic.datetimeUpdated!,
            ),
          ),
      ],
    );
  }
}

class _HistoryCardShell extends StatelessWidget {
  final VoidCallback onTap;
  final Widget cover;
  final String title;
  final String? subtitle;
  final String? lastBrowseName;
  final IconData lastBrowseIcon;
  final String? latestText;
  final List<Widget> chips;

  const _HistoryCardShell({
    required this.onTap,
    required this.cover,
    required this.title,
    this.subtitle,
    this.lastBrowseName,
    required this.lastBrowseIcon,
    this.latestText,
    required this.chips,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                child: AspectRatio(aspectRatio: 0.72, child: cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (lastBrowseName != null &&
                        lastBrowseName!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(lastBrowseIcon, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '上次看到 $lastBrowseName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (latestText != null && latestText!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        latestText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: chips),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCover extends StatelessWidget {
  final String imageUrl;
  final IconData icon;

  const _HistoryCover({required this.imageUrl, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CoverBrightnessFilter(
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (_, _) => Container(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: Icon(icon, color: cs.onSurfaceVariant, size: 28),
            ),
          ),
          errorWidget: (_, _, _) => Container(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: Icon(
                Icons.broken_image,
                color: cs.onSurfaceVariant,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryMetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HistoryMetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
