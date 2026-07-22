/// 通用格式化工具。
///
/// 从各页面卡片组件（如 [ComicCard]）中迁移而来，统一处理
/// “人气 / 热度” 与 “相对时间” 的展示文案，避免多处实现不一致。
class Format {
  /// 将漫画人气值格式化为带「万 / 亿」单位的中文简写。
  ///
  /// 例：`12345 -> 1.2万`，`123456789 -> 1.2亿`。
  static String formatPopular(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n.toString();
  }

  /// 将 ISO 时间字符串格式化为相对时间。
  ///
  /// 例：`刚刚 / 5分钟前 / 3小时前 / 2天前 / 1个月前 / 2年前`。
  /// 解析失败时原样返回输入字符串。
  static String formatRelativeTime(String dateStr) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return dateStr;
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}个月前';
    return '${(diff.inDays / 365).floor()}年前';
  }
}
