import 'package:flutter/foundation.dart';
import '../api_helpers.dart';

import '../../models/comic.dart' hide Theme;
import '../../models/chapter.dart';
import '../manga_source_adapter.dart';
import 'comix_cloudflare_service.dart';

/// Comix.to 漫画源适配器
///
/// 所有 API 请求通过持久 HeadlessInAppWebView 内的 JS fetch 执行，
/// 自动携带 Cloudflare Cookie + 客户端 Token。
///
/// 接口：
/// - 热门：GET /manga?order[score]=desc&limit=28&page=N
/// - 更新：GET /manga?order[chapter_updated_at]=desc&limit=28&page=N
/// - 搜索：GET /manga?keyword={}&order[relevance]=desc&limit=28&page=N
/// - 详情：GET /manga/{hash_id}
/// - 章节：GET /manga/{hash_id}/chapters?order[number]=desc&limit=100&page=N
class ComixSourceAdapter implements MangaSourceAdapter {
  static const _pageSize = 28;

  final ComixWebViewService _wvService;

  ComixSourceAdapter() : _wvService = ComixWebViewService();

  @override
  String get sourceId => 'comix';

  @override
  String get sourceName => 'Comix.to (English)';

  @override
  bool get isAvailable => true;

  // ── MangaSourceAdapter 实现 ──

  @override
  Future<MangaPage> getPopularManga(int page) async {
    final data = await _wvService.fetchApi(
      '/manga',
      params: {'order[score]': 'desc', 'limit': '$_pageSize', 'page': '$page'},
    );
    return _parseMangaPage(data, page);
  }

  @override
  Future<MangaPage> getLatestUpdates(int page) async {
    final data = await _wvService.fetchApi(
      '/manga',
      params: {
        'order[chapter_updated_at]': 'desc',
        'limit': '$_pageSize',
        'page': '$page',
      },
    );
    return _parseMangaPage(data, page);
  }

  @override
  Future<MangaPage> searchManga(
    String query, {
    int page = 1,
    Map<String, String> filters = const {},
  }) async {
    final data = await _wvService.fetchApi(
      '/manga',
      params: {
        'keyword': query,
        'order[relevance]': 'desc',
        'limit': '$_pageSize',
        'page': '$page',
      },
    );
    return _parseMangaPage(data, page);
  }

  /// 按分类浏览
  ///
  /// Comix 是英文站，没有耽美概念。子分类通过搜索关键词实现。
  /// categoryId 映射到英文搜索关键词，在 Comix 内搜索。
  /// 如果 categoryId 是 'danmei'（根分类），返回热门列表。
  @override
  Future<MangaPage> browseByCategory(
    String categoryId, {
    int page = 1,
    String ordering = '-popular',
  }) async {
    // 根分类：按最热 / 最新切换
    if (categoryId == 'danmei') {
      if (ordering == '-datetime_updated' || ordering == 'datetime_updated') {
        return getLatestUpdates(page);
      }
      return getPopularManga(page);
    }

    // 子分类：用英文关键词搜索，映射排序字段
    final keyword = _categoryToComickKeyword(categoryId);
    if (keyword.isEmpty) {
      if (ordering == '-datetime_updated' || ordering == 'datetime_updated') {
        return getLatestUpdates(page);
      }
      return getPopularManga(page);
    }

    final orderParam = (ordering == '-datetime_updated' ||
            ordering == 'datetime_updated')
        ? 'order[chapter_updated_at]'
        : 'order[user_follow_count]';
    final data = await _wvService.fetchApi(
      '/manga',
      params: {
        'keyword': keyword,
        orderParam: 'desc',
        'limit': '$_pageSize',
        'page': '$page',
      },
    );
    return _parseMangaPage(data, page);
  }

  /// 将耽美子分类 ID 映射到 Comix 搜索关键词
  String _categoryToComickKeyword(String categoryId) {
    switch (categoryId) {
      case 'danmei_school':
        return 'school';
      case 'danmei_ancient':
        return 'historical';
      case 'danmei_fantasy':
        return 'fantasy';
      case 'danmei_city':
        return 'urban';
      case 'danmei_entertainment':
        return 'idol';
      case 'danmei_abo':
        return 'abo';
      case 'danmei_beast':
        return 'beast';
      case 'danmei_rebirth':
        return 'rebirth';
      case 'danmei_isekai':
        return 'isekai';
      case 'danmei_healing':
        return 'healing';
      case 'danmei_mystery':
        return 'mystery';
      case 'danmei_workplace':
        return 'office';
      case 'danmei_underworld':
        return 'mafia';
      default:
        return '';
    }
  }

  @override
  Future<Comic> getMangaDetails(String mangaId) async {
    final data = await _wvService.fetchApi('/manga/$mangaId');
    return _parseComicDetail(data);
  }

  @override
  Future<List<Chapter>> getChapterList(String mangaId) async {
    final data = await _wvService.fetchApi(
      '/manga/$mangaId/chapters',
      params: {'order[number]': 'desc', 'limit': '100', 'page': '1'},
    );
    return _parseChapters(data);
  }

  @override
  Future<List<String>> getPageList(String mangaId, String chapterId) async {
    final data = await _wvService.fetchApi(
      '/manga/$mangaId/chapters/$chapterId',
    );
    if (data is Map && data['data'] != null) {
      final chapterData = data['data'];
      if (chapterData is Map && chapterData['images'] != null) {
        final images = safeRawList<dynamic>(
          chapterData['images'],
          required: false,
        );
        return images
            .map(
              (img) =>
                  img is Map ? (img['url'] ?? '').toString() : img.toString(),
            )
            .where((url) => url.isNotEmpty)
            .toList();
      }
    }
    return [];
  }

  // ── 解析方法 ──

  MangaPage _parseMangaPage(dynamic data, int page) {
    if (data is! Map) {
      debugPrint('[Comix] 解析失败，data 类型: ${data.runtimeType}');
      return const MangaPage(comics: [], total: 0, hasNextPage: false);
    }

    // 检查错误响应
    if (data['message'] != null && data['data'] == null) {
      throw Exception('API 错误: ${data['message']}');
    }

    final payload = data['data'] ?? data;
    List<dynamic> items = [];
    int total = 0;

    if (payload is Map) {
      items = safeRawList<Map>(
        payload['data'] ?? payload['list'] ?? payload['items'] ?? const [],
        required: false,
      );
      total =
          payload['total'] as int? ??
          payload['meta']?['total'] as int? ??
          items.length;
    } else if (payload is List) {
      items = payload;
      total = items.length;
    }

    final comics = items
        .whereType<Map>()
        .map((e) => _parseComicItem(Map<String, dynamic>.from(e)))
        .toList();

    return MangaPage(
      comics: comics,
      total: total,
      hasNextPage: page * _pageSize < total,
    );
  }

  Comic _parseComicItem(Map<String, dynamic> json) {
    final title =
        json['title']?.toString() ?? json['name']?.toString() ?? 'Unknown';
    final hashId =
        json['hash_id']?.toString() ??
        json['hid']?.toString() ??
        json['id']?.toString() ??
        json['slug']?.toString() ??
        '';
    // 封面：优先 poster.medium
    String cover = '';
    if (json['poster'] is Map) {
      final poster = json['poster'] as Map?;
      cover =
          poster?['medium']?.toString() ?? poster?['large']?.toString() ?? '';
    }
    cover = cover.isNotEmpty
        ? cover
        : (json['cover']?.toString() ??
              json['thumbnail']?.toString() ??
              json['image']?.toString() ??
              '');

    final description =
        json['synopsis']?.toString() ??
        json['description']?.toString() ??
        json['summary']?.toString() ??
        '';

    // 解析作者
    final authorsList = <Author>[];
    if (json['author'] != null) {
      authorsList.add(Author(name: json['author'].toString(), pathWord: ''));
    } else if (json['authors'] is List) {
      for (final a in safeRawList<dynamic>(json['authors'], required: false)) {
        if (a is Map) {
          authorsList.add(
            Author(
              name: a['name']?.toString() ?? '',
              pathWord: a['slug']?.toString() ?? '',
            ),
          );
        } else if (a is String) {
          authorsList.add(Author(name: a, pathWord: ''));
        }
      }
    }

    return Comic(
      name: title,
      pathWord: hashId,
      cover: cover,
      popular: json['score'] is num ? (json['score'] as num).toInt() : 0,
      authors: authorsList,
      brief: description,
      sourceId: sourceId,
    );
  }

  Comic _parseComicDetail(dynamic data) {
    if (data is Map && data['data'] != null) {
      return _parseComicItem(Map<String, dynamic>.from(data['data']));
    }
    if (data is Map) {
      return _parseComicItem(Map<String, dynamic>.from(data));
    }
    return Comic(name: 'Unknown', pathWord: '', cover: '', sourceId: sourceId);
  }

  List<Chapter> _parseChapters(dynamic data) {
    if (data is! Map) return [];
    final payload = data['data'] ?? data;
    List<dynamic> items = [];
    if (payload is Map) {
      items = safeRawList<Map>(
        payload['data'] ?? payload['list'] ?? payload['items'] ?? const [],
        required: false,
      );
    } else if (payload is List) {
      items = payload;
    }

    return items.whereType<Map>().map((e) {
      final map = Map<String, dynamic>.from(e);
      return Chapter(
        uuid:
            map['hash_id']?.toString() ??
            map['hid']?.toString() ??
            map['id']?.toString() ??
            '',
        index: map['number'] is num ? (map['number'] as num).toInt() : 0,
        name: map['title']?.toString() ?? map['name']?.toString() ?? 'Chapter',
        datetimeCreated:
            map['published_at']?.toString() ?? map['created_at']?.toString(),
      );
    }).toList();
  }
}
