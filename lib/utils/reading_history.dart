import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地阅读记录，记录每部漫画在各分组上次阅读到哪一话、第几页。
class ReadingHistory {
  static const _prefix = 'reading_history_';
  static const defaultGroup = 'default';
  static const _lastReadKey = 'last_read_comic_v1';
  static const _recentReadListKey = 'recent_read_comics_v1';

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

  /// 记录最近阅读的漫画（用于"继续阅读"卡片）
  static Future<void> saveLastRead({
    required String pathWord,
    required String comicName,
    String? coverUrl,
    required String chapterName,
    int page = 1,
    int totalPage = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final record = {
      'pathWord': pathWord,
      'name': comicName,
      'cover': coverUrl ?? '',
      'chapterName': chapterName,
      'page': page,
      'totalPage': totalPage,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    await prefs.setString(_lastReadKey, jsonEncode(record));
    // 维护最近阅读列表（最多 50 条，去重）
    final rawList = prefs.getStringList(_recentReadListKey) ?? [];
    final list = <Map<String, dynamic>>[];
    for (final raw in rawList) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['pathWord'] != pathWord) {
          list.add(map);
        }
      } catch (_) {}
    }
    list.insert(0, record);
    final trimmed = list.take(50).map((e) => jsonEncode(e)).toList();
    await prefs.setStringList(_recentReadListKey, trimmed);
  }

  /// 获取最近阅读的漫画记录
  static Future<LastReadRecord?> getLastRead() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastReadKey);
    if (raw == null) return null;
    try {
      return LastReadRecord.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// 获取最近阅读的漫画列表
  static Future<List<LastReadRecord>> getRecentReads({int limit = 30}) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_recentReadListKey) ?? [];
    final records = <LastReadRecord>[];
    for (final raw in rawList.take(limit)) {
      try {
        records.add(LastReadRecord.fromJson(jsonDecode(raw)));
      } catch (_) {}
    }
    return records;
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

class LastReadRecord {
  final String pathWord;
  final String name;
  final String cover;
  final String chapterName;
  final int page;
  final int totalPage;
  final int timestamp;

  const LastReadRecord({
    required this.pathWord,
    required this.name,
    required this.cover,
    required this.chapterName,
    this.page = 1,
    this.totalPage = 0,
    this.timestamp = 0,
  });

  factory LastReadRecord.fromJson(Map<String, dynamic> json) => LastReadRecord(
    pathWord: json['pathWord']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    cover: json['cover']?.toString() ?? '',
    chapterName: json['chapterName']?.toString() ?? '',
    page: json['page'] as int? ?? 1,
    totalPage: json['totalPage'] as int? ?? 0,
    timestamp: json['timestamp'] as int? ?? 0,
  );
}