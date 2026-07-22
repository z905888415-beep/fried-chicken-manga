import 'package:flutter/material.dart';

/// 加载中占位视图。
class LoadingView extends StatelessWidget {
  /// 可选提示文案。
  final String? message;

  const LoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// 空数据视图。
class EmptyView extends StatelessWidget {
  /// 提示文案。
  final String message;

  /// 图标。
  final IconData icon;

  /// 可选操作组件（如「去逛逛」按钮）。
  final Widget? action;

  const EmptyView({
    super.key,
    this.message = '暂无内容',
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: cs.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// 错误视图（带可选重试）。
class ErrorView extends StatelessWidget {
  /// 提示文案。
  final String message;

  /// 重试回调；为 `null` 时不展示按钮。
  final VoidCallback? onRetry;

  /// 图标。
  final IconData icon;

  const ErrorView({
    super.key,
    this.message = '加载失败',
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(message, style: tt.titleMedium),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ],
      ),
    );
  }
}
