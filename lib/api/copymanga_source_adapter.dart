import '../models/comic.dart' hide Theme;
import '../models/chapter.dart';
import '../models/category_config.dart';
import 'api_client.dart';
import 'manga_source_adapter.dart';

/// 与 manga_api 中 danmeiThemePathWord 保持一致
const _danmeiTheme = 'danmei';

/// 分类页排序键规范化：只保留最热 / 最新
String normalizeCategoryOrdering(String ordering) {
  switch (ordering) {
    case '-datetime_updated':
    case 'datetime_updated':
      return '-datetime_updated';
    case '-popular':
    case 'popular':
    default:
      return '-popular';
  }
}

/// 是否为耽美作品（对齐 assets/sources/kopymanga_bl.js 的 isBLComic）
///
/// [requirePositiveEvidence]：
/// - false：用于 theme=danmei 列表接口结果（服务端已围栏，可信）
/// - true：用于搜索结果补齐；必须有耽美/BL 正向证据，防止普通校园漫漏网
bool isDanmeiComic(Comic comic, {bool requirePositiveEvidence = false}) {
  const blWords = ['耽美', 'bl', '纯爱', '清水', '强强', '腹黑攻', '少年爱', 'danmei'];

  for (final t in comic.themes) {
    final name = t.name.toLowerCase();
    final pw = t.pathWord.toLowerCase();
    for (final w in blWords) {
      if (name.contains(w) || pw == w || pw == _danmeiTheme) return true;
    }
  }

  final blob = '${comic.name} ${comic.brief ?? ''}'.toLowerCase();
  for (final w in blWords) {
    if (w == 'bl') {
      if (RegExp(r'(^|[^a-z])bl([^a-z]|$)').hasMatch(blob)) return true;
    } else if (blob.contains(w)) {
      return true;
    }
  }

  // 列表接口路径：无证据时仍放行（theme=danmei 服务端已滤）
  return !requirePositiveEvidence;
}

/// 子题材关键词是否命中（名称 / 标签 / 简介）
bool matchesCategoryKeyword(Comic comic, String keyword) {
  final key = keyword.trim().toLowerCase();
  if (key.isEmpty) return true;
  if (comic.name.toLowerCase().contains(key)) return true;
  if ((comic.brief ?? '').toLowerCase().contains(key)) return true;
  for (final t in comic.themes) {
    if (t.name.toLowerCase().contains(key) ||
        t.pathWord.toLowerCase().contains(key)) {
      return true;
    }
  }
  if (key == '明星') {
    return matchesCategoryKeyword(comic, '娱乐圈') ||
        matchesCategoryKeyword(comic, '偶像');
  }
  if (key == '高h' || key == '高ｈ') {
    final blob = '${comic.name} ${comic.brief ?? ''}'.toLowerCase();
    return blob.contains('高h') ||
        blob.contains('r18') ||
        blob.contains('成人') ||
        comic.themes.any((t) => t.name.toLowerCase().contains('h'));
  }
  return false;
}

/// 按热度或更新时间降序（字段缺失时沉底）
List<Comic> sortComicsByOrdering(List<Comic> comics, String ordering) {
  final list = List<Comic>.from(comics);
  final key = normalizeCategoryOrdering(ordering);
  if (key == '-datetime_updated') {
    list.sort((a, b) {
      final at = DateTime.tryParse(a.datetimeUpdated ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bt = DateTime.tryParse(b.datetimeUpdated ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
  } else {
    list.sort((a, b) => b.popular.compareTo(a.popular));
  }
  return list;
}

/// 拷贝漫画源适配器 —— 纯耽美
///
/// ## 最热 / 最新 与 耽美围栏 如何同时成立
///
/// CopyManga **唯一**同时支持 theme + ordering 的接口是：
/// ```
/// GET /api/v3/comics?theme=danmei&ordering=-popular|-datetime_updated
/// ```
///
/// 搜索接口 `/search/comic`：
/// - 可带 `theme=danmei` 做围栏
/// - **不能**再加 `ordering`（会冲破 theme，放出普通校园漫）
///
/// 因此：
/// 1. **全部耽美**：直接 comics + ordering（服务端双杀）
/// 2. **子分类**：先在 comics(theme=danmei, ordering) 流上按关键词筛
///    （全局有序 + 永不破围栏）；命中不够再用 search(theme=danmei)
///    补齐，并强制 [isDanmeiComic] 正向证据，最后本地排序。
class CopyMangaSourceAdapter implements MangaSourceAdapter {
  final ApiClient _api;
  static const int _pageSize = 21;

  /// 子分类搜索排序窗口（条）—— 在围栏内做最热/最新的取样范围

  CopyMangaSourceAdapter(this._api);

  @override
  String get sourceId => 'copymanga';

  @override
  String get sourceName => '拷贝漫画 (CopyManga)';

  @override
  bool get isAvailable => true;

  @override
  Future<MangaPage> getPopularManga(int page) async {
    final offset = (page - 1) * _pageSize;
    final res = await _api.getComicList(
      ordering: '-popular',
      offset: offset,
      limit: _pageSize,
      theme: _danmeiTheme,
    );
    return MangaPage(
      comics: res.list,
      total: res.total,
      hasNextPage: offset + res.list.length < res.total,
    );
  }

  @override
  Future<MangaPage> getLatestUpdates(int page) async {
    final offset = (page - 1) * _pageSize;
    final res = await _api.getComicList(
      ordering: '-datetime_updated',
      offset: offset,
      limit: _pageSize,
      theme: _danmeiTheme,
    );
    return MangaPage(
      comics: res.list,
      total: res.total,
      hasNextPage: offset + res.list.length < res.total,
    );
  }

  @override
  Future<MangaPage> searchManga(
    String query, {
    int page = 1,
    Map<String, String> filters = const {},
  }) async {
    final offset = (page - 1) * 20;
    final theme = filters['theme'] ?? _danmeiTheme;
    final res = await _api.searchComics(query, offset: offset, theme: theme);
    // JS 引擎已滤 BL；再过一次正向证据闸
    final comics =
        res.list.where((c) => isDanmeiComic(c, requirePositiveEvidence: true)).toList();
    return MangaPage(
      comics: comics,
      total: res.total,
      hasNextPage: offset + res.list.length < res.total,
    );
  }

  @override
  Future<MangaPage> browseByCategory(
    String categoryId, {
    int page = 1,
    String ordering = '-popular',
  }) async {
    final categoryItem = CategoryConfig.findById(categoryId);
    final sortKey = normalizeCategoryOrdering(ordering);

    if (categoryItem.isRoot) {
      final offset = (page - 1) * _pageSize;
      final res = await _api.getComicList(
        ordering: sortKey,
        offset: offset,
        limit: _pageSize,
        theme: _danmeiTheme,
      );
      return MangaPage(
        comics: res.list,
        total: res.total,
        hasNextPage: offset + res.list.length < res.total,
      );
    }

    return _browseDanmeiSubcategory(
      keyword: categoryItem.searchKeyword!,
      page: page,
      ordering: sortKey,
    );
  }
  /// 子分类排序策略：
  /// 1) 从 getComicList(theme=danmei, ordering) 拉最多 5 页（105 条），按关键词过滤
  ///    —— 服务端保证排序，请求量可控
  /// 2) 命中不够时用 search(theme=danmei) 补齐，再本地排序
  static const int _maxListPages = 5;

  Future<MangaPage> _browseDanmeiSubcategory({
    required String keyword,
    required int page,
    required String ordering,
  }) async {
    final needEnd = page * _pageSize;
    final matched = <Comic>[];
    final seen = <String>{};

    // 阶段 1：服务端有序流 + 关键词过滤（最多 _maxListPages 页）
    try {
    for (var p = 0; p < _maxListPages && matched.length < needEnd; p++) {
      final res = await _api.getComicList(
        ordering: ordering,
        offset: p * _pageSize,
        limit: _pageSize,
        theme: _danmeiTheme,
      );
      if (res.list.isEmpty) break;
      for (final comic in res.list) {
        if (!seen.add(comic.pathWord)) continue;
        if (matchesCategoryKeyword(comic, keyword)) {
          matched.add(comic);
        }
      }
      if (p * _pageSize + res.list.length >= res.total) break;
    }
    } catch (_) {
      // phase 1 failed, fall through to phase 2
    }

    // 阶段 2：不够时用 search 补齐 + 本地排序
    if (matched.length < needEnd) {
      var searchOffset = 0;
      const searchCap = 105;
      while (matched.length < needEnd && searchOffset < searchCap) {
        final res = await _api.searchComicsWithinTheme(
          keyword,
          theme: _danmeiTheme,
          offset: searchOffset,
          limit: _pageSize,
        );
        if (res.list.isEmpty) break;
        for (final comic in res.list) {
          if (!seen.add(comic.pathWord)) continue;
          matched.add(comic);
        }
        searchOffset += res.list.length;
        if (searchOffset >= res.total) break;
      }
      // 补齐部分做本地排序
      matched.sort((a, b) {
        if (ordering == '-datetime_updated') {
          final at = DateTime.tryParse(a.datetimeUpdated ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bt = DateTime.tryParse(b.datetimeUpdated ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bt.compareTo(at);
        }
        return b.popular.compareTo(a.popular);
      });
    }

    final start = (page - 1) * _pageSize;
    final pageItems = matched.skip(start).take(_pageSize).toList();
    final hasNext = start + pageItems.length < matched.length;

    return MangaPage(
      comics: pageItems,
      total: matched.length,
      hasNextPage: hasNext && pageItems.isNotEmpty,
    );
  }

  @override
  Future<Comic> getMangaDetails(String mangaId) async {
    return await _api.getComicDetail(mangaId);
  }

  @override
  Future<List<Chapter>> getChapterList(String mangaId) async {
    final res = await _api.getChapterList(mangaId);
    return res.list;
  }

  @override
  Future<List<String>> getPageList(String mangaId, String chapterId) async {
    final detail = await _api.getChapterDetail(mangaId, chapterId);
    return detail.contents;
  }
}
