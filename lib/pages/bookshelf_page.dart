import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../api/api_client.dart';
import '../models/anime.dart';
import '../models/comic.dart' hide Theme;
import '../models/user_manager.dart';
import '../utils/cover_brightness_filter.dart';
import '../utils/comic_hero_tags.dart';
import '../utils/comic_card_skeleton.dart';
import '../utils/toast.dart';
import 'anime_detail_page.dart';
import 'comic_detail_page.dart';
import 'home_page.dart';
import 'profile_page.dart';

enum _BookshelfType { comic, anime }

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({super.key});

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  final _api = ApiClient();
  final _user = UserManager();
  List<BookshelfItem> _items = [];
  List<AnimeBookshelfItem> _animeItems = [];
  bool _loading = true;
  int _offset = 0;
  int _total = 0;
  bool _loadingMore = false;
  bool _refreshing = false;
  bool _showingLoginPrompt = false;
  _BookshelfType _type = _BookshelfType.comic;
  late String _ordering = _user.bookshelfOrdering;
  late bool _showUpdateOnly = _user.bookshelfShowUpdateOnly;

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
    if (!_animeFeatureEnabled && _type == _BookshelfType.anime) {
      setState(() {
        _type = _BookshelfType.comic;
        _animeItems = [];
        _total = 0;
        _offset = 0;
        _loadingMore = false;
      });
    }
    if (_user.isLoggedIn) {
      _load(silent: true, force: true);
    } else {
      setState(() {
        _items = [];
        _animeItems = [];
        _total = 0;
        _loading = false;
      });
    }
  }

  Future<void> _load({bool silent = false, bool force = false}) async {
    if (_refreshing && !force) return;
    final requestType = _type;
    _refreshing = true;
    final isInitial = _currentItemsEmpty;
    if (isInitial) {
      setState(() => _loading = true);
    } else {
      setState(() {}); // 触发 UI 显示刷新指示器
    }
    _offset = 0;
    try {
      if (requestType == _BookshelfType.comic) {
        final data = await _api.getBookshelf(ordering: _ordering);
        if (!mounted || requestType != _type) return;
        setState(() {
          _items = data.list;
          _total = data.total;
          _offset = data.list.length;
          _loading = false;
        });
      } else {
        final data = await _api.getAnimeBookshelf(ordering: _ordering);
        if (!mounted || requestType != _type) return;
        setState(() {
          _animeItems = data.list;
          _total = data.total;
          _offset = data.list.length;
          _loading = false;
        });
      }
      if (!silent && mounted) {
        showToast(context, '刷新成功');
      }
    } catch (e) {
      debugPrint('BookshelfPage load error: $e');
      if (isInitial && mounted) setState(() => _loading = false);
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      } else if (!silent && mounted) {
        showToast(context, '刷新失败', isError: true);
      }
    } finally {
      if (requestType == _type) {
        _refreshing = false;
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _refreshing || _offset >= _total) return;
    final requestType = _type;
    setState(() => _loadingMore = true);
    try {
      if (requestType == _BookshelfType.comic) {
        final data = await _api.getBookshelf(
          offset: _offset,
          ordering: _ordering,
        );
        if (!mounted || requestType != _type) return;
        setState(() {
          _items.addAll(data.list);
          _offset = _items.length;
        });
      } else {
        final data = await _api.getAnimeBookshelf(
          offset: _offset,
          ordering: _ordering,
        );
        if (!mounted || requestType != _type) return;
        setState(() {
          _animeItems.addAll(data.list);
          _offset = _animeItems.length;
        });
      }
    } catch (e) {
      debugPrint('BookshelfPage loadMore error: $e');
      if (_isUnauthorized(e)) {
        await _handleUnauthorized();
      }
    } finally {
      if (mounted && requestType == _type) {
        setState(() => _loadingMore = false);
      } else if (requestType == _type) {
        _loadingMore = false;
      }
    }
  }

  bool _isUnauthorized(Object error) =>
      error is DioException && error.response?.statusCode == 401;

  Future<void> _handleUnauthorized() async {
    if (_showingLoginPrompt || !mounted) return;

    // 自动登录开启时，拦截器已尝试自动登录但失败了，静默提示即可
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
        content: const Text('书架需要登录后才能继续使用，是否现在重新登录？'),
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
      final loggedIn = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      if (loggedIn == true && mounted) {
        _load(silent: true);
      }
    } else if (mounted) {
      showToast(context, '登录后可继续查看书架', isError: true);
    }

    _showingLoginPrompt = false;
  }

  static String _orderingLabel(String ordering) {
    switch (ordering) {
      case '-datetime_updated':
        return '按更新';
      case '-datetime_modifier':
        return '按收藏';
      case '-datetime_browse':
        return '按阅读';
      default:
        return '排序';
    }
  }

  void _setOrdering(BuildContext context, String ordering) {
    Navigator.pop(context);
    setState(() => _ordering = ordering);
    _user.setBookshelfOrdering(ordering);
    _load(silent: true);
  }

  bool get _currentItemsEmpty =>
      _type == _BookshelfType.comic ? _items.isEmpty : _animeItems.isEmpty;

  String get _typeLabel => _type == _BookshelfType.comic ? '漫画' : '动漫';
  bool get _animeFeatureEnabled => _user.animeFeatureEnabled;

  void _setType(_BookshelfType type) {
    if (type == _BookshelfType.anime && !_animeFeatureEnabled) return;
    if (type == _type) return;
    setState(() {
      _type = type;
      _total = 0;
      _offset = 0;
      _loading = true;
      _loadingMore = false;
    });
    _load(silent: true, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (!_loading &&
                n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
              _loadMore();
            }
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.top + 12,
                ),
              ),
              if (_refreshing)
                const SliverToBoxAdapter(
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              SliverToBoxAdapter(child: _buildToolbar(context, hp)),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_currentItemsEmpty)
                SliverFillRemaining(child: _buildEmptyState(context))
              else if (_type == _BookshelfType.comic &&
                  _showUpdateOnly &&
                  _items.every((e) => !e.hasUpdate))
                SliverFillRemaining(child: _buildNoUpdates(context))
              else if (_type == _BookshelfType.comic)
                _buildComicGrid(context, hp)
              else
                _buildAnimeGrid(context, hp),
              const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, double hp) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 4, hp, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_animeFeatureEnabled) ...[
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_BookshelfType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _BookshelfType.comic,
                    icon: Icon(Icons.menu_book),
                    label: Text('漫画'),
                  ),
                  ButtonSegment(
                    value: _BookshelfType.anime,
                    icon: Icon(Icons.movie_outlined),
                    label: Text('动漫'),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (v) => _setType(v.first),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              if (_type == _BookshelfType.comic)
                FilterChip(
                  label: const Text('看更新'),
                  selected: _showUpdateOnly,
                  onSelected: (v) {
                    setState(() => _showUpdateOnly = v);
                    _user.setBookshelfShowUpdateOnly(v);
                  },
                ),
              const SizedBox(width: 8),
              Text(
                '共 $_total 部收藏',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              ActionChip(
                avatar: const Icon(Icons.sort, size: 18),
                label: Text(_orderingLabel(_ordering)),
                onPressed: () => _showOrderingSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showOrderingSheet(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('排序方式', style: tt.titleMedium),
            ),
            _OrderingTile(
              icon: Icons.update,
              title: '作品更新时间',
              subtitle: '按$_typeLabel最新章节的更新时间排序',
              selected: _ordering == '-datetime_updated',
              onTap: () => _setOrdering(context, '-datetime_updated'),
            ),
            _OrderingTile(
              icon: Icons.bookmark_added,
              title: '收藏时间',
              subtitle: '按加入书架的时间排序',
              selected: _ordering == '-datetime_modifier',
              onTap: () => _setOrdering(context, '-datetime_modifier'),
            ),
            _OrderingTile(
              icon: Icons.history,
              title: '浏览时间',
              subtitle: '按最近浏览的时间排序',
              selected: _ordering == '-datetime_browse',
              onTap: () => _setOrdering(context, '-datetime_browse'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            '书架空空如也',
            style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            '去找点好看的$_typeLabel吧',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('刷新'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoUpdates(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '没有漫画更新',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildComicGrid(BuildContext context, double hp) {
    final filtered = _showUpdateOnly
        ? _items.where((e) => e.hasUpdate).toList()
        : _items;
    final skeletonCount = _loadingMore ? 6 : 0;
    final totalCount = filtered.length + skeletonCount;
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          if (i >= filtered.length) {
            return const ComicCardSkeleton();
          }
          final item = filtered[i];
          final heroTagBase = ComicHeroTags.base(
            scope: _showUpdateOnly ? 'bookshelf-updates' : 'bookshelf',
            pathWord: item.comic.pathWord,
            index: i,
          );
          return Stack(
            children: [
              ComicCard(
                comic: item.comic,
                heroTagBase: heroTagBase,
                onTap: () => Navigator.push(
                  context,
                  ComicDetailPage.route(
                    pathWord: item.comic.pathWord,
                    initialComic: item.comic,
                    heroTagBase: heroTagBase,
                    lastBrowseId: item.lastBrowseId,
                    lastBrowseName: item.lastBrowseName,
                  ),
                ).then((_) => _load(silent: true)),
              ),
              if (item.hasUpdate) const _UpdateBadge(),
            ],
          );
        }, childCount: totalCount),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          childAspectRatio: 0.55,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
      ),
    );
  }

  Widget _buildAnimeGrid(BuildContext context, double hp) {
    final skeletonCount = _loadingMore ? 6 : 0;
    final totalCount = _animeItems.length + skeletonCount;
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: hp),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((_, i) {
          if (i >= _animeItems.length) {
            return const ComicCardSkeleton();
          }
          final item = _animeItems[i];
          return _AnimeBookshelfCard(
            anime: item.anime,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AnimeDetailPage(
                  pathWord: item.anime.pathWord,
                  initialAnime: item.anime,
                ),
              ),
            ).then((_) => _load(silent: true)),
          );
        }, childCount: totalCount),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          childAspectRatio: 0.55,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
      ),
    );
  }
}

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(
          color: Color(0xFFBA1A1A),
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(10),
          ),
        ),
        child: const Text(
          '更新',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _AnimeBookshelfCard extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;

  const _AnimeBookshelfCard({required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final meta = anime.count > 0
        ? '共 ${anime.count} 集'
        : (anime.company?.name ?? anime.years ?? '');

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: CoverBrightnessFilter(
                child: CachedNetworkImage(
                  imageUrl: anime.cover,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, _) => _ImagePlaceholder(
                    icon: Icons.movie_outlined,
                    color: cs.surfaceContainerHighest,
                    iconColor: cs.onSurfaceVariant,
                  ),
                  errorWidget: (_, _, _) => _ImagePlaceholder(
                    icon: Icons.broken_image,
                    color: cs.surfaceContainerHighest,
                    iconColor: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            anime.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 12, color: cs.primary),
              const SizedBox(width: 2),
              Text(
                ComicCard.formatPopular(anime.popular),
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;

  const _ImagePlaceholder({
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: Center(child: Icon(icon, color: iconColor, size: 32)),
    );
  }
}

class _OrderingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _OrderingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? cs.primary : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected ? Icon(Icons.check, color: cs.primary) : null,
      selected: selected,
      onTap: onTap,
    );
  }
}
