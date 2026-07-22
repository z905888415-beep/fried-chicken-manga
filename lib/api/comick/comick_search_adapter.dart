import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../models/comic.dart' hide Theme;
import '../../models/chapter.dart';
import '../manga_source_adapter.dart';

/// Comick (comick.io) 搜索兜底适配器
///
/// 仅用于搜索兜底：当拷贝漫画搜索无结果时，并联查 Comick。
/// 不接入浏览/分类（章节接口被 Cloudflare 拦截，无法可靠获取）。
///
/// API: https://comick-api-proxy.notaspider.dev/api/v1.0/search?q=keyword
/// 搜索结果无需认证，CORS 代理可直接 Dio 请求。
class ComickSearchAdapter implements MangaSourceAdapter {
  static const _proxyBase = 'https://comick-api-proxy.notaspider.dev';
  static const _apiBase = '$_proxyBase/api/v1.0';

  final Dio _dio;

  ComickSearchAdapter()
    : _dio = Dio(
        BaseOptions(
          receiveTimeout: const Duration(seconds: 12),
          sendTimeout: const Duration(seconds: 8),
        ),
      );

  @override
  String get sourceId => 'comick';

  @override
  String get sourceName => 'Comick (搜索兜底)';

  @override
  bool get isAvailable => true;

  /// 搜索漫画
  ///
  /// Comick 搜索 API 返回 JSON 数组，每个元素包含 hid、title、cover 等。
  /// 封面图片 URL: https://meo.comick.pictures/{b2key}
  @override
  Future<MangaPage> searchManga(
    String query, {
    int page = 1,
    Map<String, String> filters = const {},
  }) async {
    final limit = 20;
    final offset = (page - 1) * limit;

    try {
      final resp = await _dio.get(
        '$_apiBase/search',
        queryParameters: {'q': query, 'limit': limit, 'page': page},
        options: Options(responseType: ResponseType.json),
      );

      final data = resp.data;
      if (data is! List) {
        return const MangaPage(comics: [], total: 0, hasNextPage: false);
      }

      final comics = <Comic>[];
      for (final item in data) {
        if (item is! Map) continue;
        final comic = _parseComicItem(Map<String, dynamic>.from(item));
        if (comic != null) comics.add(comic);
      }

      return MangaPage(
        comics: comics,
        total: comics.length,
        hasNextPage: comics.length >= limit && offset + comics.length < 500,
      );
    } catch (e) {
      debugPrint('[ComickSearch] 搜索失败: $e');
      // 搜索兜底失败不抛异常，返回空列表让调用方继续用拷贝源结果
      return const MangaPage(comics: [], total: 0, hasNextPage: false);
    }
  }

  Comic? _parseComicItem(Map<String, dynamic> json) {
    final title = json['title']?.toString() ?? '';
    if (title.isEmpty) return null;

    final hid = json['hid']?.toString() ?? '';
    if (hid.isEmpty) return null;

    // 封面：从 md_covers 数组取 b2key
    String cover = '';
    final covers = json['md_covers'];
    if (covers is List && covers.isNotEmpty) {
      final firstCover = covers.first;
      if (firstCover is Map) {
        final b2key = firstCover['b2key']?.toString() ?? '';
        if (b2key.isNotEmpty) {
          cover = 'https://meo.comick.pictures/$b2key';
        }
      }
    }

    // 解析别名（md_titles）
    final altNames = <String>[];
    final titles = json['md_titles'];
    if (titles is List) {
      for (final t in titles) {
        if (t is Map) {
          final tTitle = t['title']?.toString() ?? '';
          if (tTitle.isNotEmpty && tTitle != title) {
            altNames.add(tTitle);
          }
        }
      }
    }

    final desc = json['desc']?.toString() ?? '';
    final rating = json['rating'];
    final popular = rating is String
        ? double.tryParse(rating)?.toInt() ?? 0
        : (rating is num ? rating.toInt() : 0);

    // 国家（kr = 韩漫, jp = 日漫）
    final country = json['country']?.toString() ?? '';
    final isKorean = country == 'kr';

    return Comic(
      name: title,
      pathWord: hid,
      cover: cover,
      popular: popular,
      brief: desc.isNotEmpty
          ? '$desc${altNames.isNotEmpty ? '\n\n别名: ${altNames.take(3).join(', ')}' : ''}${isKorean ? '\n[韩漫]' : ''}'
          : '',
      sourceId: sourceId,
    );
  }

  // ── 以下方法不实现（搜索兜底不接入浏览/详情/章节）──

  @override
  Future<MangaPage> getPopularManga(int page) async {
    return const MangaPage(comics: [], total: 0, hasNextPage: false);
  }

  @override
  Future<MangaPage> getLatestUpdates(int page) async {
    return const MangaPage(comics: [], total: 0, hasNextPage: false);
  }

  @override
  Future<MangaPage> browseByCategory(
    String categoryId, {
    int page = 1,
    String ordering = '-popular',
  }) async {
    return const MangaPage(comics: [], total: 0, hasNextPage: false);
  }

  @override
  Future<Comic> getMangaDetails(String mangaId) async {
    throw UnsupportedError('ComickSearchAdapter 不支持获取详情');
  }

  @override
  Future<List<Chapter>> getChapterList(String mangaId) async {
    throw UnsupportedError('ComickSearchAdapter 不支持获取章节列表');
  }

  @override
  Future<List<String>> getPageList(String mangaId, String chapterId) async {
    throw UnsupportedError('ComickSearchAdapter 不支持获取图片列表');
  }
}
