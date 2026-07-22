/// 耽美 APP 分类配置
///
/// 精简为 12 个分类（含根分类），适配首页 Wrap 两行 x 6 布局。
class CategoryItem {
  final String categoryId;
  final String categoryName;
  final String? themeSlug;
  final String? searchKeyword;

  const CategoryItem({
    required this.categoryId,
    required this.categoryName,
    this.themeSlug,
    this.searchKeyword,
  });

  bool get isRoot => themeSlug != null && searchKeyword == null;
}

class CategoryConfig {
  static const String rootCategoryId = 'danmei';
  static const String rootCategoryName = '耽美';

  static const List<CategoryItem> categories = [
    CategoryItem(
      categoryId: 'danmei',
      categoryName: '全部',
      themeSlug: 'danmei',
    ),
    CategoryItem(
      categoryId: 'danmei_school',
      categoryName: '校园',
      searchKeyword: '校园',
    ),
    CategoryItem(
      categoryId: 'danmei_city',
      categoryName: '都市',
      searchKeyword: '都市',
    ),
    CategoryItem(
      categoryId: 'danmei_entertainment',
      categoryName: '娱乐圈',
      searchKeyword: '明星',
    ),
    CategoryItem(
      categoryId: 'danmei_abo',
      categoryName: 'ABO',
      searchKeyword: 'ABO',
    ),
    CategoryItem(
      categoryId: 'danmei_rebirth',
      categoryName: '重生',
      searchKeyword: '重生',
    ),
    CategoryItem(
      categoryId: 'danmei_isekai',
      categoryName: '穿越',
      searchKeyword: '穿越',
    ),
    CategoryItem(
      categoryId: 'danmei_sweet',
      categoryName: '甜宠',
      searchKeyword: '甜宠',
    ),
    CategoryItem(
      categoryId: 'danmei_angst',
      categoryName: '虐恋',
      searchKeyword: '虐',
    ),
    CategoryItem(
      categoryId: 'danmei_younger',
      categoryName: '年下',
      searchKeyword: '年下',
    ),
    CategoryItem(
      categoryId: 'danmei_underworld',
      categoryName: '黑道',
      searchKeyword: '黑道',
    ),
    CategoryItem(
      categoryId: 'danmei_adult',
      categoryName: '高H',
      searchKeyword: '高H',
    ),
  ];

  static CategoryItem findById(String categoryId) {
    return categories.firstWhere(
      (c) => c.categoryId == categoryId,
      orElse: () => categories.first,
    );
  }
}