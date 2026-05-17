import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AcknowledgementPage extends StatelessWidget {
  const AcknowledgementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('致谢')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Text(
            '感谢以下服务与项目的支持',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAcknowledgementItem(
                    context,
                    icon: Icons.subtitles_rounded,
                    title: '弹弹play',
                    description: '提供弹幕服务',
                    url: 'https://www.dandanplay.com/',
                  ),
                  const Divider(height: 24),
                  _buildAcknowledgementItem(
                    context,
                    icon: Icons.translate_rounded,
                    title: '繁化姬',
                    description: '提供简体化服务',
                    url: 'https://zhconvert.org/',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '依赖库',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDependencyItem(
                    context,
                    name: 'Dio',
                    description: 'HTTP 客户端',
                    url: 'https://pub.dev/packages/dio',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'cached_network_image',
                    description: '网络图片缓存',
                    url: 'https://pub.dev/packages/cached_network_image',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'flutter_cache_manager',
                    description: '缓存管理',
                    url: 'https://pub.dev/packages/flutter_cache_manager',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'shared_preferences',
                    description: '本地存储',
                    url: 'https://pub.dev/packages/shared_preferences',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'package_info_plus',
                    description: '应用信息',
                    url: 'https://pub.dev/packages/package_info_plus',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'path_provider',
                    description: '路径管理',
                    url: 'https://pub.dev/packages/path_provider',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'url_launcher',
                    description: 'URL 启动器',
                    url: 'https://pub.dev/packages/url_launcher',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'flutter_svg',
                    description: 'SVG 渲染',
                    url: 'https://pub.dev/packages/flutter_svg',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'flex_color_picker',
                    description: '颜色选择器',
                    url: 'https://pub.dev/packages/flex_color_picker',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'scrollable_positioned_list',
                    description: '可定位滚动列表',
                    url: 'https://pub.dev/packages/scrollable_positioned_list',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'crypto',
                    description: '加密工具',
                    url: 'https://pub.dev/packages/crypto',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'canvas_danmaku',
                    description: '弹幕渲染',
                    url: 'https://pub.dev/packages/canvas_danmaku',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'media_kit',
                    description: '跨平台视频播放',
                    url: 'https://pub.dev/packages/media_kit',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'screen_brightness',
                    description: '屏幕亮度控制',
                    url: 'https://pub.dev/packages/screen_brightness',
                  ),
                  const Divider(height: 20),
                  _buildDependencyItem(
                    context,
                    name: 'wakelock_plus',
                    description: '屏幕常亮',
                    url: 'https://pub.dev/packages/wakelock_plus',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '感谢所有开源贡献者的辛勤付出',
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildAcknowledgementItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required String url,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: cs.onPrimaryContainer, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildDependencyItem(
    BuildContext context, {
    required String name,
    required String description,
    required String url,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  Text(
                    description,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
