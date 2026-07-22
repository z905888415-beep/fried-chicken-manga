part of 'api_client.dart';

class JsSourceManager {
  static final JsSourceManager _instance = JsSourceManager._();
  factory JsSourceManager() => _instance;
  JsSourceManager._();

  late JavascriptRuntime _jsRuntime;
  bool _initialized = false;

  Future<void> init(ApiClient apiClient) async {
    if (_initialized) return;
    try {
      _jsRuntime = getJavascriptRuntime();
    } catch (e) {
      // 原生 JS 引擎库（quickjs_c_bridge）缺失或当前环境不支持时，
      // 优雅降级：不阻塞 ApiClient 构造，仅标记为未初始化。
      // 漫画动态解析相关接口在缺少引擎的环境下不可用时将抛出明确错误。
      debugPrint('JS 动态解析引擎初始化失败（缺少原生库或环境不支持）: $e');
      return;
    }

    // 注册 httpGetAsync 通道
    _jsRuntime.onMessage('httpGetAsync', (dynamic args) {
      try {
        final Map<String, dynamic> params = args is Map
            ? Map<String, dynamic>.from(args)
            : jsonDecode(args.toString());
        final int requestId = params['requestId'] as int;
        final String path = params['path'] as String;
        final Map<String, dynamic> queryParams = Map<String, dynamic>.from(
          params['params'] ?? {},
        );
        final String? hostKey = params['hostKey'] as String?;

        String? targetHost;
        if (hostKey == 'home') {
          targetHost = _hostMangaHome;
        } else if (hostKey == 'sd') {
          targetHost = _hostSd;
        } else if (hostKey == 'sg') {
          targetHost = _hostSg;
        }

        apiClient
            ._get(path, params: queryParams, host: targetHost ?? _hostSg)
            .then((result) {
              final encoded = jsonEncode(result);
              final escaped = encoded
                  .replaceAll(r'\', r'\\')
                  .replaceAll(r'"', r'\"')
                  .replaceAll('\n', r'\n')
                  .replaceAll('\r', r'\r');
              _jsRuntime.evaluate(
                'resolveRequest($requestId, "$escaped", null)',
              );
            })
            .catchError((e) {
              final escapedError = e
                  .toString()
                  .replaceAll(r'\', r'\\')
                  .replaceAll(r'"', r'\"')
                  .replaceAll('\n', r'\n')
                  .replaceAll('\r', r'\r');
              _jsRuntime.evaluate(
                'resolveRequest($requestId, null, "$escapedError")',
              );
            });
      } catch (e) {
        debugPrint('httpGetAsync handler error: $e');
      }
      return null;
    });

    try {
      final script = await rootBundle.loadString(
        'assets/sources/kopymanga_bl.js',
      );
      final evalResult = _jsRuntime.evaluate(script);
      if (evalResult.isError) {
        debugPrint('JS 脚本执行错误: ${evalResult.stringResult}');
      } else {
        _initialized = true;
        debugPrint('JS 动态解析引擎初始化成功！');
      }
    } catch (e) {
      debugPrint('加载 JS 脚本失败: $e');
    }
  }

  Future<dynamic> getMangaHome() async {
    final result = await _jsRuntime.evaluateAsync('getMangaHome()');
    if (result.isError) {
      throw Exception('JS getMangaHome error: ${result.stringResult}');
    }
    final resolved = await _jsRuntime.handlePromise(result);
    if (resolved.isError) {
      throw Exception(
        'JS getMangaHome promise error: ${resolved.stringResult}',
      );
    }
    return jsonDecode(resolved.stringResult);
  }

  Future<dynamic> searchComics(String query, int offset) async {
    final safeQuery = query.replaceAll("'", "\\'").replaceAll('"', '\\"');
    final result = await _jsRuntime.evaluateAsync(
      "searchComics('$safeQuery', $offset)",
    );
    if (result.isError) {
      throw Exception('JS searchComics error: ${result.stringResult}');
    }
    final resolved = await _jsRuntime.handlePromise(result);
    if (resolved.isError) {
      throw Exception(
        'JS searchComics promise error: ${resolved.stringResult}',
      );
    }
    return jsonDecode(resolved.stringResult);
  }

  Future<dynamic> getComicDetail(String pathWord) async {
    final result = await _jsRuntime.evaluateAsync(
      "getComicDetail('$pathWord')",
    );
    if (result.isError) {
      throw Exception('JS getComicDetail error: ${result.stringResult}');
    }
    final resolved = await _jsRuntime.handlePromise(result);
    if (resolved.isError) {
      throw Exception(
        'JS getComicDetail promise error: ${resolved.stringResult}',
      );
    }
    return jsonDecode(resolved.stringResult);
  }

  Future<dynamic> getChapterDetail(String pathWord, String chapterUuid) async {
    final result = await _jsRuntime.evaluateAsync(
      "getChapterDetail('$pathWord', '$chapterUuid')",
    );
    if (result.isError) {
      throw Exception('JS getChapterDetail error: ${result.stringResult}');
    }
    final resolved = await _jsRuntime.handlePromise(result);
    if (resolved.isError) {
      throw Exception(
        'JS getChapterDetail promise error: ${resolved.stringResult}',
      );
    }
    return jsonDecode(resolved.stringResult);
  }
}
