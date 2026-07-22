# 分类页最热 / 最新：在耽美围栏内排序

## 问题本质

你要的不是「全站排序」，而是：

> **屏蔽非耽美的同时**，对耽美内容做「最热 / 最新」。

CopyManga 的坑在于：

| 接口 | 能锁 `theme=danmei`？ | 能 `ordering`？ | 能同时？ |
|------|----------------------|-----------------|----------|
| `GET /comics` | ✅ | ✅ | ✅ **唯一双杀路径** |
| `GET /search/comic` | ✅ | ❌ 加了会冲破 theme | ❌ |

之前错误地把 `ordering` 塞进 search，部分线路直接忽略 `theme=danmei`，  
普通校园漫（《校园時光》《校園傳說》）就漏进来了。

## 正确方案

### 全部耽美

```
GET /api/v3/comics?theme=danmei&ordering=-popular
GET /api/v3/comics?theme=danmei&ordering=-datetime_updated
```

服务端同时完成围栏 + 排序。雷电实测：

- 最热：五号公寓 381 万…（高人气 BL）
- 最新：异世界半魔… 1.x 万（与最热明显不同，仍是耽美）

### 子分类（校园 / ABO…）

子题材不是独立 theme，只能关键词搜：

```
GET /search/comic?q=校园&theme=danmei   // 禁止 ordering
```

拉约 105 条窗口 → **本地**按 `popular` / `datetime_updated` 排序 → 分页。

- 围栏：靠 `theme=danmei` + 不带 ordering（与改之前一致）
- 最热/最新：本地排序，按钮有可见差异

## 代码

- `lib/api/copymanga_source_adapter.dart`
- `lib/api/manga/manga_api.dart`（search 不再接受 ordering）
- `lib/pages/category_comics_page.dart`（最热 / 最新 UI）

## APK

`D:\AI\kira-source\build\app\outputs\flutter-apk\kira-v1.1.1-danmei-sort.apk`
