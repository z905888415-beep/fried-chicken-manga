import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

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

  Future<Map<String, dynamic>?> getRawMatch(String fileName, {String? hash}) async {
    try {
      final response = await _dio.post(
        '/api/v2/match',
        data: {
          'fileName': fileName,
          'fileHash': hash ?? '00000000000000000000000000000000',
          'fileSize': 0,
          'videoDuration': 0,
          'matchMode': hash != null ? 'hashAndFileName' : 'fileNameOnly',
        },
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }

  Future<List<DandanplayEpisode>> match(String fileName, {String? hash}) async {
    final data = await getRawMatch(fileName, hash: hash);
    if (data != null && data['success'] == true) {
      final matches = data['matches'] as List;
      final results = <DandanplayEpisode>[];
      for (var ep in matches) {
        results.add(
          DandanplayEpisode(
            episodeId: ep['episodeId'] as int,
            animeTitle: ep['animeTitle'] as String,
            episodeTitle: ep['episodeTitle'] as String,
          ),
        );
      }
      return results;
    }
    return [];
  }

  Future<List<DandanplayEpisode>> search(String animeName) async {
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
        return results;
      }
    } catch (e) {
      print('Dandanplay search error: $e');
    }
    return [];
  }

  Future<List<DandanplayComment>> getComments(int episodeId) async {
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
        return results;
      }
    } catch (e) {
      print('Dandanplay get comments error: $e');
    }
    return [];
  }
}
