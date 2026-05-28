import 'package:shared_preferences/shared_preferences.dart';

/// 按章节 uuid 持久化 AI 评论总结。
class ChapterSummaryCache {
  static const _prefix = 'zhipu_chapter_summary_';

  static Future<String?> get(String chapterUuid) async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('$_prefix$chapterUuid');
  }

  static Future<void> set(String chapterUuid, String content) async {
    final sp = await SharedPreferences.getInstance();
    if (content.isEmpty) {
      await sp.remove('$_prefix$chapterUuid');
    } else {
      await sp.setString('$_prefix$chapterUuid', content);
    }
  }

  static Future<void> remove(String chapterUuid) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('$_prefix$chapterUuid');
  }
}
