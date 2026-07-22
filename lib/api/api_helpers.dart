/// API 解析辅助工具：纯函数 + 类型化异常。
///
/// 设计意图（对应 BUG-01「静默吞错」闭环）：
/// - 主数据（页面渲染的核心 list/total）使用 [required: true]，
///   畸形时抛出 [ApiParseException]，由页面 `_load` 的 `catch` 接住并显示错误态。
/// - 次级/可选字段使用 [required: false]，畸形时安全降级（空集合 / fallback 值），避免崩溃。
library;

/// 类型化解析异常，携带可读信息与被解析的原始值，便于上层显错与排查。
class ApiParseException implements Exception {
  final String message;
  final dynamic raw;

  ApiParseException(this.message, [this.raw]);

  @override
  String toString() =>
      'ApiParseException: $message'
      '${raw == null ? '' : ' (raw: $raw)'}';
}

/// 将动态值安全转换为 [List<T>]。
///
/// - 是 [List] 时按类型过滤为 [T] 列表；
/// - 否则：[required] 为 true 抛 [ApiParseException]，否则返回空列表。
List<T> safeRawList<T>(dynamic v, {bool required = false}) => v is List
    ? v.whereType<T>().toList()
    : (required ? throw ApiParseException('expected List', v) : <T>[]);

/// 将动态值安全转换为 [int]。
///
/// - 是 [int] 直接用；否则尝试 [int.tryParse]；
/// - 解析失败：[required] 为 true 抛 [ApiParseException]，否则返回 [fallback]。
int safeInt(dynamic v, {bool required = false, int fallback = 0}) => v is int
    ? v
    : (int.tryParse(v.toString()) ??
          (required ? throw ApiParseException('expected int', v) : fallback));

/// 将动态值安全转换为 [Map<String, dynamic>]。
///
/// - 是 [Map] 时规范化为 [Map<String, dynamic>]；
/// - 否则：[required] 为 true 抛 [ApiParseException]，否则返回空 Map。
Map<String, dynamic> safeMap(dynamic v, {bool required = false}) => v is Map
    ? Map<String, dynamic>.from(v)
    : (required
          ? throw ApiParseException('expected Map', v)
          : <String, dynamic>{});

/// 从接口顶层 [data] 安全取出 `results` 字段（规范化为 [Map<String, dynamic>]）。
///
/// - [data] 是 [Map] 时取 `results`（缺失则按 [required] 处理）；
/// - 否则：[required] 为 true 抛 [ApiParseException]，否则返回空 Map。
Map<String, dynamic> safeResults(dynamic data, {bool required = false}) {
  if (data is Map) {
    final results = data['results'];
    if (results is Map) {
      return Map<String, dynamic>.from(results);
    }
    if (required) throw ApiParseException('missing results', data);
    return <String, dynamic>{};
  }
  if (required) throw ApiParseException('expected Map', data);
  return <String, dynamic>{};
}
