import 'package:flutter/material.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import '../models/app_theme_option.dart';
import '../models/user_manager.dart';
import '../utils/toast.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  final _user = UserManager();

  static const _navMeta = {
    'comic': (Icons.menu_book_outlined, '漫画'),
    'anime': (Icons.movie_outlined, '动漫'),
    'search': (Icons.search_outlined, '搜索'),
    'bookshelf': (Icons.bookmark_border, '书架'),
    'profile': (Icons.person_outline, '我的'),
  };

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

  Future<void> _pickCustomThemeColor() async {
    var selectedColor = _user.customThemeColor;
    final didSelectColor =
        await ColorPicker(
          color: selectedColor,
          onColorChanged: (color) => selectedColor = color,
          pickersEnabled: const <ColorPickerType, bool>{
            ColorPickerType.both: false,
            ColorPickerType.primary: false,
            ColorPickerType.accent: false,
            ColorPickerType.bw: false,
            ColorPickerType.custom: false,
            ColorPickerType.wheel: true,
          },
          enableShadesSelection: false,
          enableTonalPalette: false,
          enableOpacity: false,
          showColorCode: true,
          colorCodeHasColor: true,
          showEditIconButton: true,
          wheelDiameter: 220,
          wheelWidth: 20,
          wheelSquareBorderRadius: 12,
          wheelHasBorder: true,
          heading: const Text('点击色盘选择一个自定义主题色'),
          wheelSubheading: const Text('拖动取色点，实时预览主题色'),
          borderRadius: 12,
        ).showPickerDialog(
          context,
          constraints: const BoxConstraints(maxWidth: 460),
        );

    if (!didSelectColor) return;

    await _user.setCustomThemeColor(selectedColor);
    if (mounted) {
      showToast(context, '主题配色已更新为 ${_colorToHex(selectedColor)}');
    }
  }

  Brightness _previewBrightness(BuildContext context) {
    switch (_user.themeMode) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
        return MediaQuery.platformBrightnessOf(context);
    }
  }

  ThemeData _buildPreviewTheme(Brightness brightness) {
    final seedColor = _user.themeOption.seedColor;
    var colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: _user.themeVariant,
    );

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

    return ThemeData(colorScheme: colorScheme, useMaterial3: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final selectedVariant = _user.themeVariantOption;
    final previewTheme = _buildPreviewTheme(_previewBrightness(context));

    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Card(
            color: cs.surfaceContainerLow,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(
                    Icons.text_fields_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  title: const Text('底部导航栏显示文字'),
                  value: _user.bottomNavShowLabels,
                  onChanged: _user.setBottomNavShowLabels,
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      Icon(Icons.swap_vert, color: cs.onSurfaceVariant, size: 20),
                      const SizedBox(width: 16),
                      Text('导航栏顺序', style: tt.titleSmall),
                    ],
                  ),
                ),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _user.navOrder.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final order = List<String>.of(_user.navOrder);
                    final item = order.removeAt(oldIndex);
                    order.insert(newIndex, item);
                    _user.setNavOrder(order);
                  },
                  itemBuilder: (context, index) {
                    final key = _user.navOrder[index];
                    final meta = _navMeta[key]!;
                    return ListTile(
                      key: ValueKey(key),
                      leading: Icon(meta.$1, color: cs.onSurfaceVariant),
                      title: Text(meta.$2),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: Icon(Icons.drag_handle, color: cs.onSurfaceVariant),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.brightness_6, color: cs.onSurfaceVariant),
                      const SizedBox(width: 16),
                      const Text('主题模式'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.settings_brightness),
                          label: Text('系统'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('浅色'),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('深色'),
                        ),
                      ],
                      selected: {_user.themeMode},
                      onSelectionChanged: (v) => _user.setThemeMode(v.first),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette_outlined, color: cs.onSurfaceVariant),
                      const SizedBox(width: 16),
                      const Text('主题风格'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当前风格：${selectedVariant.label} · ${selectedVariant.description}',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in appThemeVariantOptions)
                        Tooltip(
                          message: option.description,
                          child: ChoiceChip(
                            label: Text(option.label),
                            selected: _user.themeVariant == option.variant,
                            onSelected: (_) =>
                                _user.setThemeVariant(option.variant),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '主题配色',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '点击颜色块切换主题色，带勾选的为当前配色。',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final option in appThemeOptions)
                        _ThemeColorTile(
                          color: option.seedColor,
                          selected: _user.themeColor == option.id,
                          onTap: () => _user.setThemeColor(option.id),
                        ),
                      _ThemeColorTile(
                        color: _user.customThemeColor,
                        selected: _user.themeColor == customThemeOptionId,
                        onTap: _pickCustomThemeColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '主题预览',
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const SizedBox(height: 12),
                  Theme(data: previewTheme, child: const _ThemePreviewCard()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeColorTile extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeColorTile({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: selected ? color.withValues(alpha: 0.14) : cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? color.withValues(alpha: 0.65) : cs.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                if (selected)
                  Positioned(
                    top: 1,
                    right: 1,
                    child: Icon(
                      Icons.check_circle,
                      size: 16,
                      color: cs.onPrimary,
                      shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black26),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemePreviewCard extends StatelessWidget {
  const _ThemePreviewCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: cs.primary,
                  child: Icon(
                    Icons.auto_awesome,
                    color: cs.onPrimary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kira 主题预览',
                        style: tt.titleSmall?.copyWith(
                          color: cs.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '按钮、卡片、标签会随主题自动换色',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onPrimaryContainer.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.palette_outlined, color: cs.onPrimaryContainer),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PreviewBadge(
                label: '主色',
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
              _PreviewBadge(
                label: '次级',
                backgroundColor: cs.secondaryContainer,
                foregroundColor: cs.onSecondaryContainer,
              ),
              _PreviewBadge(
                label: '强调',
                backgroundColor: cs.tertiaryContainer,
                foregroundColor: cs.onTertiaryContainer,
              ),
            ],
          ),
          const SizedBox(height: 14),
          IgnorePointer(
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('加入书架'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('下载'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '同一主题色切换不同风格后，整套页面的主色、容器色和标签色都会一起变化。',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _PreviewBadge({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: foregroundColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _colorToHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
