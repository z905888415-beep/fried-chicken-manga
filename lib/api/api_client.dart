import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import '../models/comic.dart';
import '../models/chapter.dart';
import '../models/chapter_comment.dart';
import '../models/comic_comment.dart';
import '../models/user_manager.dart';
import '../utils/network_error.dart';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_js/flutter_js.dart';
import 'api_helpers.dart';

part 'js_source_manager.dart';
part 'manga/manga_api.dart';
part 'network/network_api.dart';
part 'user/user_api.dart';

const _hostSg = 'mapi.hotmangasg.com';
const _hostSd = 'mapi.hotmangasd.com';
const _hostMangaHome = 'api.2024manga.com';
// const _hostComment = 'api.mangacopy.com';
const _hostComment = 'api.copy2000.online';
const _hostComicComment = 'api.copy2000.online';
const _hostMemberComment = 'api.mangacopy.com';
const _hostCopy = 'www.mangacopy.com';
const _hostWeb = 'www.manga2026.xyz';

const _routes = [
  ['mapi.hotmangasg.com', 'mapi.hotmangasd.com', 'mapi.hotmangasf.com'],
  ['mapi.elfgjfghkk.club', 'mapi.fgjfghkkcenter.club', 'mapi.fgjfghkk.club'],
];

abstract class _ApiClientBase {
  late final Dio _dio;
  late final Dio _commentDio;
  final _user = UserManager();
  int _hostIndex = 0;
  // 手动管理 cookie: host → {name: value}
  final Map<String, Map<String, String>> _cookies = {};
  // 防止并发 401 触发多次自动登录
  Completer<bool>? _autoLoginCompleter;

  Future<Map<String, dynamic>> login(String username, String password);
  Future<Map<String, dynamic>> copyLogin(String username, String password);

  _ApiClientBase() {
    _dio = Dio()..interceptors.add(NetworkError.rateLimitInterceptor());
    _commentDio = Dio(
      BaseOptions(
        headers: {
          'accept': 'application/json, text/plain, */*',
          'accept-language':
              'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7,en-GB;q=0.6,ru;q=0.5,ja;q=0.4,zh-TW;q=0.3',
          'cache-control': 'no-cache',
          'origin': 'https://www.mangacopy.com',
          'pragma': 'no-cache',
          'priority': 'u=1, i',
          'sec-ch-ua':
              '"Chromium";v="148", "Microsoft Edge";v="148", "Not/A)Brand";v="99"',
          'sec-ch-ua-mobile': '?0',
          'sec-ch-ua-platform': '"Windows"',
          'sec-fetch-dest': 'empty',
          'sec-fetch-mode': 'cors',
          'sec-fetch-site': 'same-site',
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0',
          'Host': _hostComment,
          'Connection': 'keep-alive',
        },
      ),
    )..interceptors.add(NetworkError.rateLimitInterceptor());
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers.addAll({
            'Accept': 'application/json',
            'platform': '3',
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 15; 23113RKC6C Build/AQ3A.240812.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.200 Mobile Safari/537.36',
            'webp': '1',
            'version': '2024.04.28',
            'X-Requested-With': 'com.manga2020.app',
          });

          // 动态注入 token
          final token = _user.token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Token $token';
          }

          // 注入已保存的 cookie
          final hostCookies = _cookies[options.uri.host];
          if (hostCookies != null && hostCookies.isNotEmpty) {
            options.headers['Cookie'] = hostCookies.entries
                .map((e) => '${e.key}=${e.value}')
                .join('; ');
          }

          handler.next(options);
        },
        onResponse: (response, handler) {
          // 宽松解析 set-cookie，避免 Dart 严格解析报错
          final setCookies = response.headers['set-cookie'];
          if (setCookies != null) {
            final host = response.requestOptions.uri.host;
            _cookies.putIfAbsent(host, () => {});
            for (final raw in setCookies) {
              final nameValue = raw.split(';').first.trim();
              final eqIdx = nameValue.indexOf('=');
              if (eqIdx > 0) {
                final name = nameValue.substring(0, eqIdx);
                final value = nameValue.substring(eqIdx + 1);
                if (value.isEmpty || value == '""') {
                  _cookies[host]!.remove(name);
                } else {
                  _cookies[host]![name] = value;
                }
              }
            }
          }
          // 业务错误码（如 210 账号密码错误）视为请求失败
          final data = response.data;
          if (data is Map) {
            final code = data['code'];
            if (code != null && code != 200) {
              final message =
                  data['message']?.toString() ??
                  (data['results'] is Map
                      ? data['results']['detail']?.toString()
                      : null) ??
                  '请求失败（code: $code）';
              return handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  response: response,
                  message: message,
                  error: message,
                  type: DioExceptionType.badResponse,
                ),
              );
            }
          }
          handler.next(response);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401 && _user.autoLogin) {
            final username = _user.savedUsername;
            final password = _user.savedPassword;
            if (username != null &&
                username.isNotEmpty &&
                password != null &&
                password.isNotEmpty) {
              // 限制 401 自动重登录重试次数,避免死循环
              final retryCount =
                  error.requestOptions.extra['authRetryCount'] as int? ?? 0;
              if (retryCount >= 1) {
                return handler.next(error);
              }
              try {
                // 防止并发 401 同时触发多次登录
                if (_autoLoginCompleter != null) {
                  final success = await _autoLoginCompleter!.future;
                  if (!success) return handler.next(error);
                } else {
                  _autoLoginCompleter = Completer<bool>();
                  try {
                    final result = _user.loginSource == 'copy'
                        ? await copyLogin(username, password)
                        : await login(username, password);
                    await _user.saveLogin(
                      token: result['token'],
                      userId: result['user_id'],
                      username: result['username'],
                      nickname: result['nickname'] ?? result['username'],
                      avatar: result['avatar'] ?? '',
                    );
                    _autoLoginCompleter!.complete(true);
                  } catch (_) {
                    _autoLoginCompleter!.complete(false);
                    _autoLoginCompleter = null;
                    return handler.next(error);
                  }
                  _autoLoginCompleter = null;
                }
                // 用新 token 重试原请求,标记已重试次数避免死循环
                final opts = error.requestOptions;
                opts.headers['Authorization'] = 'Token ${_user.token}';
                opts.extra['authRetryCount'] = retryCount + 1;
                final resp = await _dio.fetch(opts);
                return handler.resolve(resp);
              } catch (_) {
                return handler.next(error);
              }
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Map<String, double> _hostWeights = {};

  String _nextHost() {
    final route = _routes[_user.apiRoute];

    double totalWeight = 0.0;
    for (final host in route) {
      if (!_hostWeights.containsKey(host)) {
        _hostWeights[host] = 1.0;
      }
      totalWeight += _hostWeights[host]!;
    }

    if (totalWeight <= 0) {
      // 如果所有节点都超时（权重为0），或者未测试，退回到轮询
      final host = route[_hostIndex % route.length];
      _hostIndex++;
      return host;
    }

    double r = Random().nextDouble() * totalWeight;
    for (final host in route) {
      r -= _hostWeights[host]!;
      if (r <= 0) return host;
    }

    final host = route[_hostIndex % route.length];
    _hostIndex++;
    return host;
  }

  String _url(String path, [String? _]) => 'https://${_nextHost()}$path';

  Options _browserRequestOptions(
    String host, {
    String secFetchSite = 'same-site',
    String? contentType,
    Map<String, dynamic>? headers,
  }) {
    return Options(
      contentType: contentType,
      headers: {
        'Host': host,
        'referer': 'https://www.mangacopy.com/',
        'sec-fetch-site': secFetchSite,
        ...?headers,
      },
    );
  }

  String _buildRegisterCookie() {
    final random = Random();

    String segment(int length) => List.generate(
      length,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();

    return 'uncer=${segment(8)}-${segment(4)}-${segment(4)}-${segment(4)}-${segment(12)}; age=18; webp=1';
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, dynamic>? params,
    String host = _hostSg,
  }) async {
    // 固定域名(manga home)不走多域名容灾
    if (host == _hostMangaHome) {
      final resp = await _dio.get(
        'https://$host$path',
        queryParameters: params,
      );
      return _extractResults(resp, path);
    }
    // 路由组域名:失败时切换 host 重试,实现请求级容灾
    const maxAttempts = 3;
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final selectedHost = _nextHost();
      try {
        final resp = await _dio.get(
          'https://$selectedHost$path',
          queryParameters: params,
        );
        return _extractResults(resp, path);
      } on DioException catch (e) {
        lastError = e;
        // 仅对网络/服务器错误重试切换 host;业务错误(401/429 等)直接抛出
        if (!_isTransientNetworkError(e)) rethrow;
        // 衰减失败域名权重,降低下次被选中的概率
        _hostWeights[selectedHost] = (_hostWeights[selectedHost] ?? 1.0) * 0.5;
      }
    }
    throw lastError ?? StateError('请求失败: $path');
  }

  /// 从响应中提取 results 字段,做防御式校验。
  Map<String, dynamic> _extractResults(Response resp, String path) {
    final data = resp.data;
    final results = data is Map ? data['results'] : null;
    if (results is Map<String, dynamic>) return results;
    if (results is Map) return Map<String, dynamic>.from(results);
    throw DioException(
      requestOptions: resp.requestOptions,
      response: resp,
      message: '响应结构异常(results 缺失): $path',
      error: '响应结构异常: $path',
      type: DioExceptionType.badResponse,
    );
  }

  /// 判断是否为可重试的瞬时网络/服务器错误。
  bool _isTransientNetworkError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError ||
        (e.response?.statusCode != null && e.response!.statusCode! >= 500)) {
      return true;
    }
    final inner = e.error;
    if (inner is HttpException || inner is SocketException) return true;
    if (e.type == DioExceptionType.unknown && inner != null) return true;
    return false;
  }
}

class ApiClient extends _ApiClientBase with _UserApi, _MangaApi, _NetworkApi {
  static const routeLabels = ['线路 1', '线路 2'];

  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;

  ApiClient._() : super() {
    JsSourceManager().init(this);
  }
}
