import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/user_manager.dart';
import 'toast.dart';

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseNotes;
  final String releasePageUrl;
  final String downloadUrl;
  final String mirrorDownloadUrl;
  final String assetName;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseNotes,
    required this.releasePageUrl,
    required this.downloadUrl,
    required this.mirrorDownloadUrl,
    required this.assetName,
  });
}

class AppUpdateService {
  static const _latestReleaseUrl =
      'https://api.github.com/repos/caolib/kira/releases/latest';
  static const _mirrorPrefix = 'https://ghproxy.net/';
  static final Dio _dio = Dio(
    BaseOptions(
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Kira-App',
      },
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  static Future<AppUpdateInfo?> checkForUpdate({
    bool respectSkippedVersion = true,
  }) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final response = await _dio.get(_latestReleaseUrl);
    final data = Map<String, dynamic>.from(response.data as Map);
    final tagName = data['tag_name']?.toString() ?? '';
    final latestVersion = _normalizeVersion(tagName);
    if (latestVersion.isEmpty) return null;
    if (_compareVersions(latestVersion, currentVersion) <= 0) return null;

    final user = UserManager();
    if (respectSkippedVersion && user.skippedUpdateVersion == latestVersion) {
      return null;
    }

    final assets = (data['assets'] as List?) ?? const [];
    Map<String, dynamic>? targetAsset;
    for (final item in assets) {
      if (item is! Map) continue;
      final asset = Map<String, dynamic>.from(item);
      final name = asset['name']?.toString().toLowerCase() ?? '';
      if (name.endsWith('.apk')) {
        targetAsset = asset;
        if (name.contains('arm64-v8a')) break;
      }
    }
    if (targetAsset == null) return null;

    final downloadUrl = targetAsset['browser_download_url']?.toString() ?? '';
    if (downloadUrl.isEmpty) return null;

    return AppUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseName: data['name']?.toString() ?? '发现新版本',
      releaseNotes: data['body']?.toString().trim() ?? '',
      releasePageUrl: data['html_url']?.toString() ?? '',
      downloadUrl: downloadUrl,
      mirrorDownloadUrl: '$_mirrorPrefix$downloadUrl',
      assetName: targetAsset['name']?.toString() ?? 'app-release.apk',
    );
  }

  static Future<void> checkAndPrompt(
    BuildContext context, {
    bool auto = false,
  }) async {
    try {
      final updateInfo = await checkForUpdate(respectSkippedVersion: auto);
      if (!context.mounted) return;

      if (updateInfo == null) {
        if (!auto) {
          showToast(context, '当前已是最新版本');
        }
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _UpdateDialog(updateInfo: updateInfo),
      );
    } catch (_) {
      if (!context.mounted || auto) return;
      showToast(context, '检查更新失败，请稍后重试', isError: true);
    }
  }

  static String _normalizeVersion(String value) {
    return value.trim().replaceFirst(RegExp(r'^[vV]'), '');
  }

  static int _compareVersions(String a, String b) {
    final aParts = a.split(RegExp(r'[.+-]')).map(int.tryParse).toList();
    final bParts = b.split(RegExp(r'[.+-]')).map(int.tryParse).toList();
    final length = aParts.length > bParts.length
        ? aParts.length
        : bParts.length;
    for (var i = 0; i < length; i++) {
      final av = i < aParts.length ? (aParts[i] ?? 0) : 0;
      final bv = i < bParts.length ? (bParts[i] ?? 0) : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}

class _UpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const _UpdateDialog({required this.updateInfo});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _submitting = false;

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      showToast(context, '无法打开下载链接', isError: true);
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _skipVersion() async {
    setState(() => _submitting = true);
    await UserManager().setSkippedUpdateVersion(
      widget.updateInfo.latestVersion,
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _disableAutoCheck() async {
    setState(() => _submitting = true);
    await UserManager().setAutoCheckUpdate(false);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Widget _buildReleaseNotes(String notes, ColorScheme cs, TextTheme tt) {
    final lines = notes.split('\n');
    final children = <Widget>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('## ')) {
        if (children.isNotEmpty) children.add(const SizedBox(height: 10));
        children.add(
          Text(
            trimmed.substring(3),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        );
      } else if (trimmed.startsWith('- ')) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: cs.onSurfaceVariant)),
                Expanded(
                  child: Text(
                    trimmed
                        .substring(2)
                        .replaceFirst(RegExp(r'^\[.*?\]\s*'), '')
                        .replaceFirst(RegExp(r'^\S+\s+\w+:\s*'), ''),
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              trimmed,
              style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
            ),
          ),
        );
      }
    }

    if (children.isEmpty) {
      return Text(
        '暂无更新说明',
        style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final notes = widget.updateInfo.releaseNotes.isEmpty
        ? '暂无更新说明'
        : widget.updateInfo.releaseNotes;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: const Text('有更新'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.updateInfo.releaseName, style: tt.titleSmall),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: _buildReleaseNotes(notes, cs, tt),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => _openUrl(widget.updateInfo.downloadUrl),
                    icon: SvgPicture.asset(
                      'assets/github.svg',
                      width: 18,
                      height: 18,
                      colorFilter: ColorFilter.mode(
                        cs.onPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
                    label: const Text('下载'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => _openUrl(widget.updateInfo.mirrorDownloadUrl),
                    icon: const Icon(Icons.public),
                    label: const Text('镜像'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _submitting
                        ? null
                        : () => _openUrl(widget.updateInfo.releasePageUrl),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('发布'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: _submitting ? null : _skipVersion,
                  child: const Text('跳过此版本'),
                ),
                TextButton(
                  onPressed: _submitting ? null : _disableAutoCheck,
                  child: const Text('取消自动检查更新'),
                ),
                TextButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
