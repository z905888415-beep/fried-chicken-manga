import '../models/comic.dart' hide Theme;
import '../models/chapter.dart';

/// 漫画源适配器抽象接口
///
/// 每个漫画源必须实现此接口，提供标准化的数据访问方法。
/// 数据流：UI → ViewModel/State → MangaSourceAdapter → 真实远程请求 → 标准模型
abstract class MangaSourceAdapter {
  /// 源唯一标识（如 'copymanga'）
  String get sourceId;

  /// 源显示名称
  String get sourceName;

  /// 源是否可用
  bool get isAvailable;

  /// 获取热门漫画（分页）
  Future<MangaPage> getPopularManga(int page);

  /// 获取最新更新（分页）
  Future<MangaPage> getLatestUpdates(int page);

  /// 搜索漫画
  Future<MangaPage> searchManga(
    String query, {
    int page = 1,
    Map<String, String> filters = const {},
  });

  /// 按分类浏览漫画
  Future<MangaPage> browseByCategory(
    String categoryId, {
    int page = 1,
    String ordering = '-popular',
  });

  /// 获取漫画详情
  Future<Comic> getMangaDetails(String mangaId);

  /// 获取章节列表
  Future<List<Chapter>> getChapterList(String mangaId);

  /// 获取章节图片列表
  Future<List<String>> getPageList(String mangaId, String chapterId);
}

/// 分页结果
class MangaPage {
  final List<Comic> comics;
  final int total;
  final bool hasNextPage;

  const MangaPage({
    required this.comics,
    required this.total,
    required this.hasNextPage,
  });
}
