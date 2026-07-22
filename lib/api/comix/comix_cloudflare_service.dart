import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Comix.to 请求服务
///
/// 保持一个持久 HeadlessInAppWebView 实例，加载 comix.to 后
/// 所有 API 请求通过 WebView 内的 JS fetch 执行。
/// 这样自动携带正确的 Cloudflare Cookie + 客户端 Token。
class ComixWebViewService {
  static final ComixWebViewService _instance = ComixWebViewService._();
  factory ComixWebViewService() => _instance;
  ComixWebViewService._();

  static const _targetUrl = 'https://comix.to';

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  bool _ready = false;
  Completer<void>? _readyCompleter;

  /// 确保 WebView 已加载并就绪
  Future<void> ensureReady() async {
    if (_ready && _controller != null) return;
    if (_readyCompleter != null) {
      return _readyCompleter!.future;
    }

    _readyCompleter = Completer<void>();
    debugPrint('[ComixWV] 启动持久 HeadlessWebView...');

    _webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_targetUrl)),
      initialSettings: InAppWebViewSettings(
        userAgent:
            'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
        javaScriptEnabled: true,
        domStorageEnabled: true,
        useHybridComposition: true,
      ),
      onLoadStop: (controller, url) async {
        debugPrint('[ComixWV] 页面加载完成: $url');
        _controller = controller;
        // 等待 SPA 水合 + token 生成
        await Future.delayed(const Duration(seconds: 5));
        _ready = true;
        if (!(_readyCompleter?.isCompleted ?? true)) {
          _readyCompleter!.complete();
        }
      },
      onReceivedError: (controller, request, error) {
        debugPrint('[ComixWV] 请求错误: ${error.description}');
      },
    );

    await _webView!.run();

    // 超时保护
    await _readyCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('[ComixWV] WebView 加载超时，尝试继续...');
        _ready = true;
      },
    );
  }

  /// 在 WebView 内执行 API 请求（自动带 cookie + token）
  /// 返回解析后的 JSON 对象
  Future<dynamic> fetchApi(String path, {Map<String, dynamic>? params}) async {
    await ensureReady();
    if (_controller == null) {
      throw Exception('WebView 未就绪');
    }

    // 构建完整 URL
    final uri = Uri.parse('https://comix.to/api/v1$path');
    final url = params != null && params.isNotEmpty
        ? uri.replace(
            queryParameters: params.map((k, v) => MapEntry(k, v.toString())),
          )
        : uri;

    // 在 WebView 内执行 fetch（页面上下文自动带 cookie + 任何拦截器添加的 header）
    final js =
        '''
      (async () => {
        try {
          const resp = await fetch("$url", {
            credentials: 'include',
            headers: { 'Accept': 'application/json' }
          });
          const text = await resp.text();
          return JSON.stringify({ status: resp.status, body: text });
        } catch(e) {
          return JSON.stringify({ status: 0, body: e.message });
        }
      })()
    ''';

    final result = await _controller!.evaluateJavascript(source: js);
    if (result == null) {
      throw Exception('WebView JS 执行返回 null');
    }

    final parsed = jsonDecode(result.toString());
    if (parsed is Map) {
      final status = parsed['status'] as int? ?? 0;
      final body = parsed['body']?.toString() ?? '';

      if (status == 0) {
        throw Exception('网络错误: $body');
      }
      if (status == 403) {
        // CF 拦截，尝试刷新页面
        debugPrint('[ComixWV] 403，刷新 WebView...');
        await _refreshWebView();
        throw Exception('Cloudflare 拦截 (403)，已尝试刷新');
      }

      try {
        return jsonDecode(body);
      } catch (_) {
        throw Exception(
          'API 返回非 JSON (status=$status): ${body.substring(0, 200)}',
        );
      }
    }

    throw Exception('WebView 返回格式异常: $result');
  }

  /// 刷新 WebView（重新获取 CF cookie + token）
  Future<void> _refreshWebView() async {
    _ready = false;
    _readyCompleter = Completer<void>();
    _controller?.reload();
    await Future.delayed(const Duration(seconds: 5));
    _ready = true;
    if (!(_readyCompleter?.isCompleted ?? true)) {
      _readyCompleter!.complete();
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await _webView?.dispose();
    _webView = null;
    _controller = null;
    _ready = false;
    _readyCompleter = null;
  }
}
