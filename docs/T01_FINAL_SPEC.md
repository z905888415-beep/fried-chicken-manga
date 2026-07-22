# T01 最终版令牌/布局权威定义（theme_tokens / layout / format）

> 产出方：software-architect（高见远）｜日期：2026-07-21
> 唯一真相源。T02 组件、T08–T12 页面迁移均依赖本文件。首轮 `k*` 顶层常量草案已作废。

## 0. 冲突裁决
1. 命名空间版为唯一真相源：`ThemeTokens.*` / `AppSpacing.*` / `Layout.*` 生效；首轮 `kSpaceXS`/`kRadiusCard`/`kTitlePage` 等顶层常量全部作废。
2. **卡片圆角 = 22**：`ThemeTokens.cardRadius` alias `appleCardRadius`(22.0)，与 `main._cardTheme` 一致。home `ComicCard`14 / `_GridComicCard`16 / favorite `_CollectionCard`14 / category `_CategoryComicCard`16 → 全部升到 22（刻意统一）。
3. 标题样式收进 `ThemeTokens`（不再留顶层 `kTitle*`）。

## 1. lib/utils/theme_tokens.dart
```dart
import 'package:flutter/material.dart';
import 'package:kira/utils/glass_widgets.dart'; // appleBlue / applePink / appleCardRadius / appleButtonRadius / applePillRadius

class ThemeTokens {
  // 颜色（静态品牌色；surface/onSurface 由运行期 ColorScheme 提供，不在此）
  static const Color blue = appleBlue;     // 0xFF007AFF
  static const Color pink = applePink;     // 0xFFFF2D55
  static const Color primary = appleBlue;  // 强调色统一出口（替代散落的 applePink/appleBlue 直引）

  // 圆角
  static const double cardRadius = appleCardRadius;     // 22.0
  static const double buttonRadius = appleButtonRadius; // 16.0
  static const double pillRadius = applePillRadius;     // 999.0

  // 标题样式（收口到 ThemeTokens，废弃首轮 kTitle*）
  static const TextStyle appBarTitle = TextStyle(fontSize: 17, fontWeight: FontWeight.w700);
  static const TextStyle titlePage = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
  static const TextStyle titleSection = TextStyle(fontSize: 17, fontWeight: FontWeight.w700);
  static const TextStyle titleItem = TextStyle(fontSize: 14, fontWeight: FontWeight.w500);
}
```

## 2. lib/utils/layout.dart
```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;

  static const double pagePadding = 20.0;
  static const double sectionGap = 16.0;
  static const double listRowGap = 12.0;
}

class Layout {
  static const double maxContentWidth = 860.0;

  static double contentWidth(BuildContext context) =>
      math.min(MediaQuery.of(context).size.width, maxContentWidth);

  static const double comicCardAspectRatio = 0.55;

  static EdgeInsets hp([double? value]) =>
      EdgeInsets.symmetric(horizontal: value ?? AppSpacing.pagePadding);
}
```

## 3. lib/utils/format.dart
> 合并自 home_page / browse_history_page / comic_detail_page / category_comics_page 的重复实现；签名与既有调用点完全一致，迁移直接改引用即可。
```dart
String formatPopular(int n) {
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
  return n.toString();
}

String formatRelativeTime(String dateStr) {
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
```

## 4. 给工程师的落地约束
- T02 组件 import：`package:kira/utils/theme_tokens.dart`、`package:kira/utils/layout.dart`、`package:kira/utils/format.dart`。
- 禁止再出现首轮 `k*` 顶层常量；若编译报 `kSpaceXS`/`kRadiusCard`/`kTitlePage` 等未定义，一律改为对应命名空间常量。
- format.dart 配套清理（属 T01）：删 `home_page.ComicCard.formatPopular`(~1119)、`home_page` 顶层 `formatPopular`、`browse_history_page._BrowseHistoryPageState.formatPopular/formatRelativeTime`(~312/318)、`comic_detail_page._formatPopular`(~1412)、`category_comics_page._formatPopular`(~359) 等私有重复，改引 `format.dart` 顶层函数。
- `ThemeTokens.primary` 仅作品牌别名（=appleBlue）；真正主题强调色由 `ColorScheme.primary` 在运行期提供，`_BannerCard` 等硬写色改引 `ColorScheme` 而非 `ThemeTokens.primary`。
- `maxContentWidth=860` 为可调经验值。
