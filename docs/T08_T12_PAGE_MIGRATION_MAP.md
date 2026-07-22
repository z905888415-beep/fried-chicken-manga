# T08–T12 各页面接入映射对照表（Engineer 落地手册）

> 产出方：software-architect（高见远）｜日期：2026-07-21
> 配合定稿 T01（theme_tokens/layout/format）、T02（kira_app_bar/section_header/state_views/comic_cover_card/comic_list_tile/circle_icon_button）、T04（api_helpers）使用。
> 所有迁移均为"替换+适配"，**不新增业务字段、不改接口契约**。

## HEAD 核验
以下旧组件名全部存在；T01/T02/T04 的目标新文件（theme_tokens.dart / layout.dart / format.dart / api_helpers.dart / kira_app_bar.dart 等）均尚不存在，确认迁移对象为全新组件。行号取自当前 HEAD。

---

## T08 — ComicCoverCard / ComicListTile 落地（卡片与列表行统一）
**目标**：消灭 ≥4 种私有漫画卡实现，统一为 `ComicCoverCard`（standard / grid / collection 三 variant）+ `ComicListTile`（列表行）。依赖 T02。

| 页面 | 旧组件（file:line） | 新组件 | 改动要点 | 复用 / Token 注意 |
|---|---|---|---|---|
| home_page.dart | `ComicCard`（class :1065，r14，name+popular） | `ComicCoverCard.standard` | 圆角由写死 14 改为 `ThemeTokens.cardRadius`（=appleCardRadius 22，见 T12）；字段 name/popular 直传 | 复用 `formatPopular`/`formatRelativeTime`（T01 format.dart），勿重复实现 |
| home_page.dart | `_GridComicCard`（class :848，r16，name+themes+star） | `ComicCoverCard.grid` | 传 themes[]、star 评分；圆角由 variant 统一 | 复用 `ComicHeroTags` |
| recommend_page.dart / ranking_page.dart | 共享 `ComicCard`（引自 home_page:1065） | `ComicCoverCard.standard` | 直接替换引用即可 | grid `childAspectRatio` 见 T11 |
| search_page.dart | `_ComicGridItem`（class :575，r22，name-only） | `ComicCoverCard.grid`（nameOnly） | 原 r22 与全局 22 一致，保留；仅传 name | 去除页内重复 Card 包装 |
| category_comics_page.dart | `_CategoryComicCard`（class :257，GlassCard r16，name+author+popular） | `ComicCoverCard.collection`（showAuthor:true） | 保留 author/popular | 与 favorite `_CollectionCard` 合并为同一 collection variant |
| favorite_page.dart | `_CollectionCard`（class :434，GlassCard r14） | `ComicCoverCard.collection` | r14→统一半径；字段同 collection | 与 category_comics 共用 collection variant |
| ranking/recommend 榜单行 | 页内手写 `ListTile` | `ComicListTile` | 统一"左缩略封面 + 右标题/热度" | 复用 main.dart 已定义的 `listTileTheme` |

---

## T09 — StateViews 落地（加载 / 空 / 错误状态统一）
**目标**：替换手写 loading/empty/error；**修复 ranking/recommend `catch (_)` 静默失败（BUG-01 复发，P0）**。依赖 T02。

| 页面 | 旧实现（file:line） | 新组件 | 改动要点 | 复用 / Token 注意 |
|---|---|---|---|---|
| ranking_page.dart | `catch (_)` 静默失败（:51、:71） | `StateViews.error` + retry | **关键**：catch 内 `setState(()=>_error=e)`，渲染 `ErrorView(message: NetworkError.message(e), onRetry: _load)` | 必须用 `NetworkError.message(e)`，禁止 `catch (_)` 吞错（与 T04 lint 约定一致） |
| recommend_page.dart | `catch (_)` 静默失败（:43、:63） | `StateViews.error` + retry | 同上 | 同上 |
| search_page.dart | 私有 `_searchError` + retry（:159-165、:319-352） | `StateViews.error` | 改为引用共享 `ErrorView`，删除页内私有 `_searchError` 控件 | 保留搜索输入区常驻的特化布局 |
| category_comics_page.dart | 已有 `ErrorView`+retry | `StateViews.error` | 仅替换私有 ErrorView 引用，行为不变 | 校验与共享 StateViews 行为一致 |
| 所有页 grid/list 加载 | 手写 `ComicCardSkeleton`（ranking:129/146、recommend:91/108、category:218、search:550、extension_browse:340） | `StateViews.loading`（内部用 `ComicCardSkeleton`） | 统一骨架屏入口 | **复用既有 `ComicCardSkeleton`，勿重写** |
| 所有页空态 | 手写"暂无数据" | `StateViews.empty` | 统一空态文案/图标 | 文案走常量/i18n |

---

## T10 — KiraAppBar / CircleIconButton / SectionHeader 落地（顶栏 / 图标按钮 / 区块标题统一）
**目标**：统一 3 种 AppBar 模式；消灭 `_CircleIconButton`/`_IconBtn` 重复；统一区块标题。依赖 T02。

| 页面 | 旧组件（file:line） | 新组件 | 改动要点 | 复用 / Token 注意 |
|---|---|---|---|---|
| home_page.dart | 自定义 AppBar（含搜索入口）+ `_CircleIconButton`（:536、:544）+ `_cutePink` + `_BannerCard`（:689，硬写色） | `KiraAppBar` + `CircleIconButton` + `applePink`/ColorScheme | 搜索入口移入 `KiraAppBar.leading`/`actions`；`_cutePink`→`applePink`（glass_widgets 已有）；`_BannerCard` 硬写 `Colors.white`/`0xFF1C1C1E`/`black`→`ColorScheme.surface`/`onSurface` | **删除 `_SearchSheet`（class :962，lint 标记 unused）** |
| favorite_page.dart | `_IconBtn`（:76、:84，=home `_CircleIconButton` 复制）+ `_cutePink`（const :229） | `CircleIconButton` + `applePink` | 删除私有 `_IconBtn`，引用共享 `CircleIconButton` | 消除与 home 的重复定义 |
| search_page.dart | 自有 AppBar | `KiraAppBar` | 统一标题/返回键风格 | centerTitle 17 w700（main.appBarTheme 已定） |
| ranking_page.dart / recommend_page.dart / category_comics_page.dart | 各自 AppBar | `KiraAppBar` | 统一；ranking 分类标签可放 `KiraAppBar.bottom` | — |
| 以上各页区块标题 | 手写 `Text`/`Padding` 标题 | `SectionHeader` | 统一字号/间距/可选"更多"action | 复用 `AppSpacing.sectionGap`（T11 落地后） |

---

## T11 — layout.dart 落地（间距标尺 / 内容宽度收口）
**目标**：引入间距标尺 + 内容宽度 clamp，消除魔法数字。依赖 T01。

| 页面 | 旧实现（file:line） | 新组件 / Token | 改动要点 | 复用 / Token 注意 |
|---|---|---|---|---|
| favorite_page.dart | 写死 `fromLTRB(20,...)`（无内容宽度 clamp） | `Layout.contentWidth(context)` + `AppSpacing.pagePadding` | 用 `contentWidth` 计算居中内容宽度；padding 改用 `AppSpacing.pagePadding` | 大屏不再顶到边 |
| 所有页 | 散落魔法 padding/margin 数字 | `AppSpacing.*`（xs/sm/md/lg/xl） | 全局替换散落数字 | 间距标尺来自 T01 layout.dart |
| ranking_page.dart / recommend_page.dart | grid `childAspectRatio: 0.55` | `Layout.comicCardAspectRatio` | 提取为布局常量，便于统一调参 | 与 ComicCoverCard 半径配合 |
| 列表项垂直间距 | 手写 `SizedBox` 高度 | `AppSpacing.listRowGap` | 统一 | — |

---

## T12 — theme_tokens.dart 落地（配色 token 收口）
**目标**：把 `apple*` 常量、硬写色、复制的 `_cutePink` 收口到 `ThemeTokens` / `ColorScheme`。依赖 T01。

| 页面 / 文件 | 旧实现（file:line） | 新组件 / Token | 改动要点 | 复用 / Token 注意 |
|---|---|---|---|---|
| main.dart | `_cardTheme` 半径 `appleCardRadius`（22） | `ThemeTokens.cardRadius`（alias appleCardRadius） | 主题定义改为读 `ThemeTokens` | glass_widgets.apple* 保留为底层常量，`ThemeTokens` 做统一出口 |
| glass_widgets.dart | `appleBlue`(:8)/`applePink`(:11)/`appleCardRadius`(:32)/`appleButtonRadius`(:33)/`applePillRadius`(:34) | `ThemeTokens.*`（alias 指向 apple*） | 新增 `ThemeTokens` 作为唯一配色出口；apple* 保留但仅内部用 | 避免多出处 |
| home_page.dart `_BannerCard` | 硬写 `Colors.white`/`0xFF1C1C1E`/`black` | `ColorScheme.surface`/`onSurface`/`primary` | 跟随主题明暗自适应 | 去除硬写 |
| favorite_page.dart `_cutePink`（:229）/ home_page.dart `_cutePink`（:29） | `0xFFFF2D55` 复制 | `applePink`（= `ThemeTokens.pink`） | 删除两处页内常量 | 与 T10 的 `CircleIconButton` 配色引用一致 |
| 全局强调色 | 散落 `applePink` 直引 | `ColorScheme.primary` 或 `ThemeTokens.pink` | 统一引用出口 | — |

---

## 跨任务说明（执行顺序 / 冲突 / 验收）

1. **依赖与执行顺序**
   - T08 / T09 / T10 依赖 **T02**（组件就绪）；T11 / T12 依赖 **T01**（token/layout 就绪）。
   - T08–T12 之间**无相互依赖**，可按页面并行派工。
   - 同一页面若同时出现在多个任务（如 home 出现在 T08/T10/T12），建议在该页内按 **T12 → T11 → T10 → T08 → T09** 顺序合批改动，减少重复 churn 与冲突。

2. **与 T04 的关系（重要）**
   - T08–T12 仅触及 UI 层（`lib/pages/*`、`lib/widgets/*`(T02 新)、`lib/utils/glass_widgets.dart`、`lib/main.dart`），**不触碰 `lib/api`**。
   - T04（api_helpers + 硬转换迁移 + 模型层兜底 + 禁裸 `as` lint）与 T08–T12 **零文件冲突**，可完全并行；T04 的 lint 约定（禁裸 `as List`/`as int`/`as Map`）不影响 UI 迁移。

3. **SectionHeader 采纳站点**
   - 主要落在 home（"热门推荐"/"最新上架"等区块标题）、recommend、ranking（分类标题）、category_comics（分类标题）。统一为 `SectionHeader(title, onMore?)`。

4. **验收口径**
   - 迁移后 `flutter analyze` 警告数应 **≤ 16**（基线），且不新增 `unused_import` / `unused_field`。
   - 删除的私有控件对应的 lint 应清零：删除 `_SearchSheet`（home_page:962，原 unused 警告）、`_IconBtn`/`_cutePink`(favorite)、`_cutePink`(home) 等后，相关重复/未用告警消除。
   - BUG-01 复发项（ranking/recommend `catch (_)`）必须全部改为 `StateViews.error` + retry，不得残留静默失败。
