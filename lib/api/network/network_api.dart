part of '../api_client.dart';

mixin _NetworkApi on _ApiClientBase {
  // ── 线路延迟测试 ──

  /// 获取指定线路的所有 host
  List<String> getRouteHosts(int routeIndex) => _routes[routeIndex];

  /// 测试指定线路所有 host 的延迟，返回 {host: 毫秒数，超时为 null}
  Future<Map<String, int?>> testRouteLatency(int routeIndex) async {
    final hosts = getRouteHosts(routeIndex);
    final results = <String, int?>{};
    await Future.wait(
      hosts.map((host) async {
        try {
          final sw = Stopwatch()..start();
          final socket = await SecureSocket.connect(
            host,
            443,
            timeout: const Duration(seconds: 3),
          );
          sw.stop();
          socket.destroy();
          results[host] = sw.elapsedMilliseconds;
        } catch (_) {
          results[host] = null;
        }
      }),
    );

    for (final entry in results.entries) {
      if (entry.value == null || entry.value! <= 0) {
        _hostWeights[entry.key] = 0.0;
      } else {
        _hostWeights[entry.key] = 1000.0 / entry.value!;
      }
    }

    return results;
  }
}
