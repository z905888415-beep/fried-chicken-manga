import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地阅读记录，记录每部漫画在各分组上次阅读到哪一话、第几页。
class ReadingHistory {
  static const _prefix = 'reading_history_';
  static const defaultGroup = 'default';

  static String _legacyKey(String pathWord) => '$_prefix$pathWord';

  static String _groupKey(String pathWord, String group) =>
      '${_legacyKey(pathWord)}_group_${Uri.encodeComponent(group)}';

  /// 保存阅读进度
  static Future<void> save({
    required String pathWord,
    String? group,
    required String chapterUuid,
    required String chapterName,
    int page = 1,
    int totalPage = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedGroup = group?.trim();
    final data = jsonEncode({
      if (normalizedGroup != null && normalizedGroup.isNotEmpty)
        'group': normalizedGroup,
      'chapterUuid': chapterUuid,
      'chapterName': chapterName,
      'page': page,
      'totalPage': totalPage,
    });
    if (normalizedGroup == null || normalizedGroup.isEmpty) {
      await prefs.setString(_legacyKey(pathWord), data);
      return;
    }
    await prefs.setString(_groupKey(pathWord, normalizedGroup), data);
    if (normalizedGroup == defaultGroup) {
      await prefs.setString(_legacyKey(pathWord), data);
    }
  }

  /// 获取阅读进度，返回 null 表示无记录
  static Future<ReadingRecord?> get(
    String pathWord, {
    String? group,
    bool fallbackToLegacy = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedGroup = group?.trim();
    final raw = normalizedGroup == null || normalizedGroup.isEmpty
        ? prefs.getString(_legacyKey(pathWord))
        : prefs.getString(_groupKey(pathWord, normalizedGroup)) ??
              (fallbackToLegacy && normalizedGroup == defaultGroup
                  ? prefs.getString(_legacyKey(pathWord))
                  : null);
    if (raw == null) return null;
    return _decode(raw);
  }

  static ReadingRecord? _decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ReadingRecord(
        chapterUuid: map['chapterUuid'] as String,
        chapterName: map['chapterName'] as String,
        page: map['page'] as int? ?? 1,
        totalPage: map['totalPage'] as int? ?? 0,
        group: map['group']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}

class ReadingRecord {
  final String chapterUuid;
  final String chapterName;
  final int page;
  final int totalPage;
  final String? group;

  const ReadingRecord({
    required this.chapterUuid,
    required this.chapterName,
    required this.page,
    this.totalPage = 0,
    this.group,
  });
}
