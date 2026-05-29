import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChapterSummaryProgress extends ChangeNotifier {
  bool _isGenerating = false;
  String _content = '';
  String? _error;

  bool get isGenerating => _isGenerating;
  String get content => _content;
  String? get error => _error;
  bool get hasState => _isGenerating || _content.isNotEmpty || _error != null;

  void _start({String initialContent = ''}) {
    _isGenerating = true;
    _content = initialContent;
    _error = null;
    notifyListeners();
  }

  void _update(String content) {
    _content = content;
    _error = null;
    notifyListeners();
  }

  void _complete(String content) {
    _isGenerating = false;
    _content = content;
    _error = null;
    notifyListeners();
  }

  void _fail(String error) {
    _isGenerating = false;
    _error = error;
    notifyListeners();
  }

  void _clear() {
    _isGenerating = false;
    _content = '';
    _error = null;
    notifyListeners();
  }
}

/// 按章节 uuid 持久化 AI 评论总结。
class ChapterSummaryCache {
  static const _prefix = 'zhipu_chapter_summary_';
  static final Map<String, ChapterSummaryProgress> _progress = {};

  static ChapterSummaryProgress progressOf(String chapterUuid) =>
      _progress.putIfAbsent(chapterUuid, () => ChapterSummaryProgress());

  static bool isGenerating(String chapterUuid) =>
      _progress[chapterUuid]?.isGenerating ?? false;

  static void startProgress(String chapterUuid, {String initialContent = ''}) {
    progressOf(chapterUuid)._start(initialContent: initialContent);
  }

  static void updateProgress(String chapterUuid, String content) {
    progressOf(chapterUuid)._update(content);
  }

  static void failProgress(String chapterUuid, String error) {
    progressOf(chapterUuid)._fail(error);
  }

  static void clearProgress(String chapterUuid) {
    progressOf(chapterUuid)._clear();
  }

  static Future<String?> get(String chapterUuid) async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('$_prefix$chapterUuid');
  }

  static Future<void> set(String chapterUuid, String content) async {
    final sp = await SharedPreferences.getInstance();
    if (content.isEmpty) {
      await sp.remove('$_prefix$chapterUuid');
      clearProgress(chapterUuid);
    } else {
      await sp.setString('$_prefix$chapterUuid', content);
      progressOf(chapterUuid)._complete(content);
    }
  }

  static Future<void> remove(String chapterUuid) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('$_prefix$chapterUuid');
    clearProgress(chapterUuid);
  }
}
