import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:system_fonts/system_fonts.dart';

import 'models/user_manager.dart';
import 'pages/favorite_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'utils/glass_widgets.dart';

bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit init failed (non-ARM device?): $e');
  }
  await UserManager().init();
  if (isDesktop) {
    final font = UserManager().desktopFontFamily;
    if (font.isNotEmpty) {
      try {
        await SystemFonts().loadFont(font);
      } catch (_) {}
    }
  }
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values,
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
    ),
  );
  runApp(const KiraApp());
}

/// 允许鼠标拖拽触发滚动和下拉刷新（桌面端适配）
class _AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

class KiraApp extends StatefulWidget {
  const KiraApp({super.key});

  @override
  State<KiraApp> createState() => _KiraAppState();
}

class _KiraAppState extends State<KiraApp> {
  final _user = UserManager();

  static final _cardTheme = CardThemeData(
    clipBehavior: Clip.antiAlias,
    color: Colors.white,
    shadowColor: Colors.black.withValues(alpha: 0.06),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(appleCardRadius),
    ),
    elevation: 0,
    surfaceTintColor: Colors.transparent,
  );

  @override
  void initState() {
    super.initState();
    _user.addListener(_onChanged);
  }

  @override
  void dispose() {
    _user.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  ThemeData _buildTheme(Brightness brightness) {
    // 苹果风配色常量
    const lightBg = appleLightBg;
    const lightSurface = Color(0xFF1C1C1E);
    const lightVariant = Color(0xFF8E8E93);

    final seedColor = brightness == Brightness.light
        ? appleBlue
        : _user.themeOption.seedColor;
    var colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: _user.themeVariant,
    );

    // 修复“彩虹”等变体会固定生成独立色相且不随主题色变化的背景问题
    if (_user.themeVariant == DynamicSchemeVariant.rainbow) {
      final standardScheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      );
      colorScheme = colorScheme.copyWith(
        surface: standardScheme.surface,
        surfaceDim: standardScheme.surfaceDim,
        surfaceBright: standardScheme.surfaceBright,
        surfaceContainerLowest: standardScheme.surfaceContainerLowest,
        surfaceContainerLow: standardScheme.surfaceContainerLow,
        surfaceContainer: standardScheme.surfaceContainer,
        surfaceContainerHigh: standardScheme.surfaceContainerHigh,
        surfaceContainerHighest: standardScheme.surfaceContainerHighest,
        onSurface: standardScheme.onSurface,
        onSurfaceVariant: standardScheme.onSurfaceVariant,
      );
    }

    if (brightness == Brightness.light) {
      // 苹果风浅色模式:系统灰背景 + 冷调表面色
      colorScheme = colorScheme.copyWith(
        primary: appleBlue,
        onPrimary: Colors.white,
        surface: lightBg,
        onSurface: lightSurface,
        surfaceDim: const Color(0xFFE5E5EA),
        surfaceBright: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF7F7FA),
        surfaceContainer: const Color(0xFFF2F2F7),
        surfaceContainerHigh: const Color(0xFFE5E5EA),
        surfaceContainerHighest: const Color(0xFFD1D1D6),
        onSurfaceVariant: lightVariant,
        outline: const Color(0xFFD1D1D6),
        outlineVariant: const Color(0xFFE5E5EA),
      );
    } else {
      // 苹果风深色模式:纯黑背景 + 分层灰
      colorScheme = colorScheme.copyWith(
        surface: appleDarkBg,
        onSurface: Colors.white,
        surfaceDim: appleDarkBgSecondary,
        surfaceBright: const Color(0xFF2C2C2E),
        surfaceContainerLowest: appleDarkBg,
        surfaceContainerLow: const Color(0xFF1C1C1E),
        surfaceContainer: appleDarkBgSecondary,
        surfaceContainerHigh: const Color(0xFF2C2C2E),
        surfaceContainerHighest: const Color(0xFF3A3A3C),
        onSurfaceVariant: const Color(0xFF8E8E93),
        outline: const Color(0xFF3A3A3C),
        outlineVariant: const Color(0xFF2C2C2E),
      );
    }

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
      cardTheme: _cardTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        elevation: 0,
        height: 0,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: colorScheme.onSurface, fontSize: 0),
        ),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: colorScheme.onSurface),
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(
          (brightness == Brightness.light ? Colors.white : Colors.black)
              .withValues(alpha: 0.72),
        ),
        elevation: const WidgetStatePropertyAll(0),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        hintStyle: WidgetStatePropertyAll(
          TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        textStyle: WidgetStatePropertyAll(
          TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w500),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(appleButtonRadius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor:
            (brightness == Brightness.light ? Colors.white : Colors.black)
                .withValues(alpha: 0.6),
        selectedColor: colorScheme.primary.withValues(alpha: 0.85),
        labelStyle: TextStyle(color: colorScheme.onSurface),
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            (brightness == Brightness.light ? Colors.white : Colors.black)
                .withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(appleButtonRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(appleButtonRadius),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(appleButtonRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(appleButtonRadius),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(appleButtonRadius),
        ),
      ),
      fontFamily: isDesktop && _user.desktopFontFamily.isNotEmpty
          ? _user.desktopFontFamily
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '炸鸡腿漫画',
      debugShowCheckedModeBanner: false,
      scrollBehavior: _AppScrollBehavior(),
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _user.themeMode,
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _DisclaimerDialog extends StatefulWidget {
  final List<String> items;
  final String confirmLabel;

  const _DisclaimerDialog({required this.items, required this.confirmLabel});

  @override
  State<_DisclaimerDialog> createState() => _DisclaimerDialogState();
}

class _DisclaimerDialogState extends State<_DisclaimerDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('免责声明'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in widget.items) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ', style: tt.bodyMedium),
                            Expanded(child: Text(item, style: tt.bodyMedium)),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '继续使用本应用，即表示您已阅读、理解并同意上述说明；如您不同意，请立即停止使用并退出本应用。',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _accepted,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(widget.confirmLabel),
                onChanged: (value) {
                  setState(() => _accepted = value ?? false);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('不同意并退出'),
          ),
          FilledButton(
            onPressed: _accepted ? () => Navigator.of(context).pop(true) : null,
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }
}

/// 全局底部导航索引，供子页面切换 Tab
final globalNavIndex = ValueNotifier<int>(0);

class _MainPageState extends State<MainPage> {
  final _user = UserManager();
  int _selectedIndex = 0;
  bool _didCheckDisclaimer = false;

  static const _disclaimerItems = [
    '本应用为非官方第三方客户端，仅基于第三方平台提供的接口或公开可访问资源进行内容展示与访问。',
    '本应用不生产、上传、编辑、修改或预先审查具体展示内容，相关内容均来源于第三方返回结果，开发者无法对其进行完全控制。',
    '本应用展示的内容中，可能包含成人内容或其他不适宜未成年人浏览的信息；如您未满 18 周岁，或您所在地法律法规禁止访问相关内容，请立即停止使用本应用。',
    '用户应自行判断相关内容是否适合浏览，并确保其使用行为符合所在地法律法规。',
    '如第三方内容存在侵权、违法、违规或其他不当情形，相关责任原则上由内容提供方承担；开发者将在收到有效通知后，根据实际情况采取必要处理措施。',
  ];

  static const _disclaimerConfirmText = '我已年满 18 周岁，并已阅读、理解且同意上述免责声明';

  List<String> get _disclaimerItemsList => _disclaimerItems;
  String get _disclaimerConfirmLabel => _disclaimerConfirmText;

  @override
  void initState() {
    super.initState();
    globalNavIndex.addListener(_onGlobalNavChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runStartupFlow();
    });
  }

  Future<void> _runStartupFlow() async {
    await _ensureDisclaimerAccepted();
  }

  Future<void> _ensureDisclaimerAccepted() async {
    if (_didCheckDisclaimer || _user.disclaimerAccepted || !mounted) return;
    _didCheckDisclaimer = true;

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DisclaimerDialog(
        items: _disclaimerItemsList,
        confirmLabel: _disclaimerConfirmLabel,
      ),
    );
    if (!mounted) return;

    if (accepted == true) {
      await _user.setDisclaimerAccepted(true);
    }
  }

  @override
  @override
  void dispose() {
    globalNavIndex.removeListener(_onGlobalNavChanged);
    super.dispose();
  }

  void _onGlobalNavChanged() {
    if (globalNavIndex.value != _selectedIndex) {
      setState(() => _selectedIndex = globalNavIndex.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 扩展页已隐藏，入口保留以备后用
    // 如需恢复：取消下方 ExtensionBrowsePage 注释 + 底部导航加回 '扩展' tab
    const pages = [
      HomePage(),
      // ExtensionBrowsePage(),
      FavoritePage(),
      ProfilePage(),
    ];

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      extendBody: true,
      bottomNavigationBar: GlassBottomBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
          globalNavIndex.value = index;
        },
        destinations: const [
          GlassDestination(
            icon: _NavMascotIcon(assetPath: 'assets/nav_danmei.png'),
            selectedIcon: _NavMascotIcon(
              assetPath: 'assets/nav_danmei.png',
              selected: true,
            ),
            label: '耽美',
          ),
          // 扩展 tab 已隐藏
          // GlassDestination(
          //   icon: _NavMascotIcon(assetPath: 'assets/nav_local.png'),
          //   selectedIcon: _NavMascotIcon(
          //     assetPath: 'assets/nav_local.png',
          //     selected: true,
          //   ),
          //   label: '扩展',
          // ),
          GlassDestination(
            icon: _NavMascotIcon(assetPath: 'assets/nav_mine.png'),
            selectedIcon: _NavMascotIcon(
              assetPath: 'assets/nav_mine.png',
              selected: true,
            ),
            label: '收藏',
          ),
          GlassDestination(
            icon: _NavMascotIcon(assetPath: 'assets/nav_local.png'),
            selectedIcon: _NavMascotIcon(
              assetPath: 'assets/nav_local.png',
              selected: true,
            ),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

class _NavMascotIcon extends StatelessWidget {
  final String assetPath;
  final bool selected;

  const _NavMascotIcon({required this.assetPath, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final size = selected ? 34.0 : 28.0;
    return AnimatedScale(
      scale: selected ? 1.06 : 1,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: Opacity(
        opacity: selected ? 1 : 0.72,
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          cacheWidth: selected ? 102 : 84,
          cacheHeight: selected ? 102 : 84,
        ),
      ),
    );
  }
}
