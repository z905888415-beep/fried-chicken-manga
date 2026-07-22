import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/comic.dart' hide Theme;
import '../utils/comic_hero_tags.dart';
import '../utils/comic_card_skeleton.dart';
import '../utils/network_error.dart';
import '../widgets/comic_cover_card.dart';
import '../widgets/kira_app_bar.dart';
import '../widgets/state_views.dart';
import 'comic_detail_page.dart';

/// 漫画排行完整列表页，支持排序切换
class RankingPage extends StatefulWidget {
  const RankingPage({super.key});

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  final _api = ApiClient();
  List<Comic> _comics = [];
  bool _loading = true;
  int _offset = 0;
  int _total = 0;
  bool _loadingMore = false;
  String? _error;
  String _ordering = '-datetime_updated';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _comics = [];
      _offset = 0;
    });
    try {
      final data = await _api.getComicList(
        ordering: _ordering,
        limit: 21,
        theme: danmeiThemePathWord,
      );
      if (!mounted) return;
      setState(() {
        _comics = data.list;
        _total = data.total;
        _offset = data.list.length;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        _error = NetworkError.message(e);
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _offset >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final data = await _api.getComicList(
        ordering: _ordering,
        limit: 21,
        offset: _offset,
        theme: danmeiThemePathWord,
      );
      if (!mounted) return;
      setState(() {
        _comics.addAll(data.list);
        _offset = _comics.length;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(NetworkError.message(e)),
            action: SnackBarAction(label: '重试', onPressed: _loadMore),
          ),
        );
      }
    }
    if (mounted) {
      setState(() => _loadingMore = false);
    } else {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final contentWidth = screenWidth.clamp(0.0, 900.0);
    final hp = (screenWidth - contentWidth) / 2 + 16;

    const gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 130,
      childAspectRatio: 0.62,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
    );

    return Scaffold(
      appBar: KiraAppBar(
        titleText: '耽美更新',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: '-popular',
                  label: Text('热度'),
                  icon: Icon(Icons.whatshot, size: 16),
                ),
                ButtonSegment(
                  value: '-datetime_updated',
                  label: Text('更新'),
                  icon: Icon(Icons.schedule, size: 16),
                ),
              ],
              selected: {_ordering},
              onSelectionChanged: (v) {
                _ordering = v.first;
                _load();
              },
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? GridView.builder(
              padding: EdgeInsets.symmetric(horizontal: hp, vertical: 12),
              itemCount: 21,
              gridDelegate: gridDelegate,
              itemBuilder: (_, _) => const ComicCardSkeleton(),
            )
          : _error != null && _comics.isEmpty
          ? ErrorView(message: _error!, onRetry: _load)
          : _comics.isEmpty
          ? const EmptyView(message: '暂无排行数据')
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) {
                  _loadMore();
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(hp, 12, hp, 0),
                    sliver: SliverGrid(
                      gridDelegate: gridDelegate,
                      delegate: SliverChildBuilderDelegate((_, i) {
                        if (i >= _comics.length) {
                          return const ComicCardSkeleton();
                        }
                        final comic = _comics[i];
                        final heroTagBase = ComicHeroTags.base(
                          scope: 'ranking',
                          pathWord: comic.pathWord,
                          index: i,
                        );
                        return ComicCoverCard(
                          comic: comic,
                          heroTagBase: heroTagBase,
                          onTap: () => Navigator.push(
                            context,
                            ComicDetailPage.route(
                              pathWord: comic.pathWord,
                              initialComic: comic,
                              heroTagBase: heroTagBase,
                            ),
                          ),
                        );
                      }, childCount: _comics.length + (_loadingMore ? 6 : 0)),
                    ),
                  ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
                ],
              ),
            ),
    );
  }
}
