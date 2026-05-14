part of '../anime_player_page.dart';

class _ErrorPanel extends StatelessWidget {
  final String message;
  final String? rawError;
  final bool requiresLogin;
  final VoidCallback onLogin;
  final VoidCallback onRetry;
  final VoidCallback onLogCopied;

  const _ErrorPanel({
    required this.message,
    this.rawError,
    required this.requiresLogin,
    required this.onLogin,
    required this.onRetry,
    required this.onLogCopied,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              requiresLogin ? Icons.lock_outline : Icons.cloud_off,
              color: Colors.white70,
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              requiresLogin ? '需要登录' : '播放失败',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            if (requiresLogin)
              FilledButton.icon(
                onPressed: onLogin,
                icon: const Icon(Icons.login),
                label: const Text('去登录'),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (rawError != null) ...[
                    TextButton.icon(
                      onPressed: () => _showErrorLog(context),
                      icon: const Icon(Icons.bug_report_outlined, size: 18),
                      label: const Text('查看日志'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.tonal(
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _showErrorLog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误日志'),
        content: SingleChildScrollView(
          child: SelectableText(
            rawError ?? '无日志信息',
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (rawError != null) {
                await Clipboard.setData(ClipboardData(text: rawError!));
                if (context.mounted) {
                  onLogCopied();
                }
              }
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
