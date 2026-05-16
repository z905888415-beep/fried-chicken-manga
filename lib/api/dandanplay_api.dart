import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../utils/data_cache.dart';

class _CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  _CacheEntry(this.data, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class DandanplayEpisode {
  final int episodeId;
  final String animeTitle;
  final String episodeTitle;

  DandanplayEpisode({
    required this.episodeId,
    required this.animeTitle,
    required this.episodeTitle,
  });
}

class DandanplayComment {
  final double time;
  final int mode;
  final int color;
  final String text;

  DandanplayComment({
    required this.time,
    required this.mode,
    required this.color,
    required this.text,
  });
}

class DandanplayAnimeSearchItem {
  final int animeId;
  final String bangumiId;
  final String animeTitle;
  final String? typeDescription;
  final String? imageUrl;
  final int episodeCount;
  final double rating;
  final String? startDate;

  DandanplayAnimeSearchItem({
    required this.animeId,
    required this.bangumiId,
    required this.animeTitle,
    this.typeDescription,
    this.imageUrl,
    this.episodeCount = 0,
    this.rating = 0,
    this.startDate,
  });

  factory DandanplayAnimeSearchItem.fromJson(Map<String, dynamic> json) =>
      DandanplayAnimeSearchItem(
        animeId: json['animeId'] as int? ?? 0,
        bangumiId: json['bangumiId']?.toString() ?? '',
        animeTitle: json['animeTitle']?.toString() ?? '',
        typeDescription: json['typeDescription']?.toString(),
        imageUrl: json['imageUrl']?.toString(),
        episodeCount: json['episodeCount'] as int? ?? 0,
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        startDate: json['startDate']?.toString(),
      );
}

class DandanplayBangumiEpisode {
  final int episodeId;
  final String episodeTitle;
  final String episodeNumber;

  DandanplayBangumiEpisode({
    required this.episodeId,
    required this.episodeTitle,
    required this.episodeNumber,
  });

  factory DandanplayBangumiEpisode.fromJson(Map<String, dynamic> json) =>
      DandanplayBangumiEpisode(
        episodeId: json['episodeId'] as int? ?? 0,
        episodeTitle: json['episodeTitle']?.toString() ?? '',
        episodeNumber: json['episodeNumber']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
    'episodeId': episodeId,
    'episodeTitle': episodeTitle,
    'episodeNumber': episodeNumber,
  };
}

class DandanplayBangumi {
  final int animeId;
  final String bangumiId;
  final String animeTitle;
  final String? imageUrl;
  final List<DandanplayBangumiEpisode> episodes;

  DandanplayBangumi({
    required this.animeId,
    required this.bangumiId,
    required this.animeTitle,
    this.imageUrl,
    this.episodes = const [],
  });

  factory DandanplayBangumi.fromJson(Map<String, dynamic> json) {
    final episodes =
        (json['episodes'] as List?)
            ?.map(
              (e) => DandanplayBangumiEpisode.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList() ??
        const <DandanplayBangumiEpisode>[];
    return DandanplayBangumi(
      animeId: json['animeId'] as int? ?? 0,
      bangumiId: json['bangumiId']?.toString() ?? '',
      animeTitle: json['animeTitle']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString(),
      episodes: episodes,
    );
  }

  Map<String, dynamic> toJson() => {
    'animeId': animeId,
    'bangumiId': bangumiId,
    'animeTitle': animeTitle,
    if (imageUrl != null) 'imageUrl': imageUrl,
    'episodes': episodes.map((e) => e.toJson()).toList(),
  };
}

class DandanplayApi {
  static const _baseUrl = 'https://api.dandanplay.net';

  // 从环境变量中读取
  static const String appId = String.fromEnvironment('DANDANPLAY_APP_ID');
  static const String appSecret = String.fromEnvironment(
    'DANDANPLAY_APP_SECRET',
  );

  static final DandanplayApi _instance = DandanplayApi._();
  factory DandanplayApi() => _instance;

  late final Dio _dio;
  final DataCache _dataCache = DataCache();
  final Map<String, _CacheEntry> _cache = {};
  final Map<int, Future<DandanplayBangumi?>> _bangumiInFlight = {};
  DateTime? _lastClearTime;

  // 缓存时长：根据弹弹play官方建议
  static const _ttlSearch = Duration(hours: 6); // 搜索结果 6小时
  static const _ttlComments = Duration(hours: 1); // 弹幕 1小时（较活跃）

  String _cacheKey(String endpoint, [Map<String, dynamic>? params]) {
    final sorted = params?.entries.toList()
      ?..sort((a, b) => a.key.compareTo(b.key));
    return '$endpoint${sorted != null ? jsonEncode(sorted.map((e) => [e.key, e.value]).toList()) : ''}';
  }

  T? _getCache<T>(String key) {
    final entry = _cache[key];
    if (entry != null && !entry.isExpired) return entry.data as T;
    _cache.remove(key);
    return null;
  }

  void _setCache(String key, dynamic data, Duration ttl) {
    _cache[key] = _CacheEntry(data, DateTime.now().add(ttl));
  }

  DandanplayApi._() {
    _dio = Dio(BaseOptions(baseUrl: _baseUrl));
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (appId.isNotEmpty && appSecret.isNotEmpty) {
            final path = options.path.split('?').first;
            final timestamp =
                (DateTime.now().toUtc().millisecondsSinceEpoch / 1000)
                    .floor()
                    .toString();

            final data = appId + timestamp + path + appSecret;
            final signature = base64Encode(
              sha256.convert(utf8.encode(data)).bytes,
            );

            options.headers['X-AppId'] = appId;
            options.headers['X-Timestamp'] = timestamp;
            options.headers['X-Signature'] = signature;
          }
          handler.next(options);
        },
      ),
    );
  }

  Future<List<DandanplayEpisode>> search(String animeName) async {
    final key = _cacheKey('/api/v2/search/episodes', {'anime': animeName});
    final cached = _getCache<List<DandanplayEpisode>>(key);
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        '/api/v2/search/episodes',
        queryParameters: {'anime': animeName},
      );
      if (response.data['success'] == true) {
        final animes = response.data['animes'] as List;
        final results = <DandanplayEpisode>[];
        for (var anime in animes) {
          final animeTitle = anime['animeTitle'] as String;
          final episodes = anime['episodes'] as List;
          for (var ep in episodes) {
            results.add(
              DandanplayEpisode(
                episodeId: ep['episodeId'] as int,
                animeTitle: animeTitle,
                episodeTitle: ep['episodeTitle'] as String,
              ),
            );
          }
        }
        _setCache(key, results, _ttlSearch);
        return results;
      }
    } catch (e) {
      debugPrint('Dandanplay search error: $e');
    }
    return [];
  }

  /// 按关键词搜索动漫列表（不含 episodes，仅返回动漫基本信息）
  Future<List<DandanplayAnimeSearchItem>> searchAnime(String keyword) async {
    final key = _cacheKey('/api/v2/search/anime', {'keyword': keyword});
    final cached = _getCache<List<DandanplayAnimeSearchItem>>(key);
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        '/api/v2/search/anime',
        queryParameters: {'keyword': keyword},
      );
      final data = response.data;
      if (data is Map && data['success'] == true) {
        final animes = (data['animes'] as List?) ?? const [];
        final results = animes
            .map(
              (e) => DandanplayAnimeSearchItem.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList();
        _setCache(key, results, _ttlSearch);
        return results;
      }
    } catch (e) {
      debugPrint('Dandanplay searchAnime error: $e');
    }
    return [];
  }

  /// 获取番剧详情（含所有 episodes）
  Future<DandanplayBangumi?> getBangumi(int animeId) async {
    final key = _cacheKey('/api/v2/bangumi/$animeId');
    final cached = _getCache<DandanplayBangumi>(key);
    if (cached != null) return cached;

    final persistentKey = _bangumiCacheKey(animeId);
    final persistentCached = await _dataCache.get(persistentKey);
    if (persistentCached is Map) {
      try {
        final bangumi = DandanplayBangumi.fromJson(
          Map<String, dynamic>.from(persistentCached),
        );
        _setCache(key, bangumi, _ttlSearch);
        return bangumi;
      } catch (_) {
        await _dataCache.remove(persistentKey);
      }
    }

    final inFlight = _bangumiInFlight[animeId];
    if (inFlight != null) return inFlight;

    final request = _fetchBangumi(animeId, key);
    _bangumiInFlight[animeId] = request;
    try {
      return await request;
    } finally {
      _bangumiInFlight.remove(animeId);
    }
  }

  String _bangumiCacheKey(int animeId) => 'dandanplay_bangumi_v1_$animeId';

  Future<DandanplayBangumi?> _fetchBangumi(int animeId, String key) async {
    try {
      final response = await _dio.get('/api/v2/bangumi/$animeId');
      final data = response.data;
      if (data is Map && data['success'] == true && data['bangumi'] is Map) {
        final bangumi = DandanplayBangumi.fromJson(
          Map<String, dynamic>.from(data['bangumi']),
        );
        _setCache(key, bangumi, _ttlSearch);
        await _dataCache.put(
          _bangumiCacheKey(animeId),
          bangumi.toJson(),
          ttl: _ttlSearch,
        );
        return bangumi;
      }
    } catch (e) {
      debugPrint('Dandanplay getBangumi error: $e');
    }
    return null;
  }

  Future<void> clearBangumiCache(int animeId) async {
    _cache.remove(_cacheKey('/api/v2/bangumi/$animeId'));
    _bangumiInFlight.remove(animeId);
    await _dataCache.remove(_bangumiCacheKey(animeId));
  }

  bool _clearCacheWhere(bool Function(String key) shouldRemove) {
    final now = DateTime.now();
    if (_lastClearTime != null &&
        now.difference(_lastClearTime!).inSeconds < 60) {
      return false;
    }
    _lastClearTime = now;
    _cache.removeWhere((key, _) => shouldRemove(key));
    return true;
  }

  /// 清除搜索缓存，限制1分钟内只能清除一次。
  /// 不清除弹幕评论缓存，避免影响已选弹幕来源的加载。
  bool clearSearchCache() {
    return _clearCacheWhere(
      (key) =>
          key.startsWith('/api/v2/search/episodes') ||
          key.startsWith('/api/v2/search/anime') ||
          key.startsWith('/api/v2/bangumi/'),
    );
  }

  /// 清除全部弹弹play缓存，限制1分钟内只能清除一次
  bool clearCache() {
    return _clearCacheWhere((_) => true);
  }

  Future<List<DandanplayComment>> getComments(int episodeId) async {
    final key = _cacheKey('/api/v2/comment/$episodeId');
    final cached = _getCache<List<DandanplayComment>>(key);
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        '/api/v2/comment/$episodeId',
        queryParameters: {'withRelated': 'true'},
      );
      final data = response.data;
      if (data is Map && data['comments'] is List) {
        final comments = data['comments'] as List;
        final results = <DandanplayComment>[];
        for (var c in comments) {
          try {
            final p = c['p'].toString().split(',');
            if (p.length < 3) continue;
            results.add(
              DandanplayComment(
                time: double.parse(p[0]),
                mode: int.parse(p[1]),
                color: int.parse(p[2]),
                text: c['m'] as String,
              ),
            );
          } catch (e) {
            continue;
          }
        }
        _setCache(key, results, _ttlComments);
        return results;
      }
    } catch (e) {
      debugPrint('Dandanplay get comments error: $e');
    }
    return [];
  }
}
