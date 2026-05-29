import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/zhipu_api.dart';
import '../utils/network_error.dart';
import '../utils/toast.dart';

class ZhipuChatPage extends StatefulWidget {
  const ZhipuChatPage({super.key});

  @override
  State<ZhipuChatPage> createState() => _ZhipuChatPageState();
}

class _ZhipuChatPageState extends State<ZhipuChatPage> {
  final _settings = ZhipuSettings();
  final _api = ZhipuApi();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<ZhipuMessage> _messages = [];
  bool _sending = false;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _settings.load();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _settings.removeListener(_onSettingsChanged);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  List<String> get _allModels {
    final seen = <String>{};
    final result = <String>[];
    for (final m in _settings.customModels) {
      if (seen.add(m)) result.add(m);
    }
    if (_settings.model.isNotEmpty && seen.add(_settings.model)) {
      result.add(_settings.model);
    }
    return result;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openApiKeyDialog() async {
    final ctrl = TextEditingController(text: _settings.apiKey ?? '');
    var obscure = true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('智谱清言 API 密钥'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '前往智谱开放平台（bigmodel.cn）控制台创建。密钥仅保存在本机。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => launchUrl(
                  Uri.parse('https://open.bigmodel.cn/apikey/platform'),
                  mode: LaunchMode.externalApplication,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '获取 API 密钥',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'API Key',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setLocal(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__clear__'),
              child: const Text('清除'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    if (result == '__clear__') {
      await _settings.setApiKey(null);
      if (mounted) showToast(context, '已清除密钥');
    } else {
      await _settings.setApiKey(result);
      if (mounted) showToast(context, '密钥已保存');
    }
  }

  Future<void> _openModelManager() async {
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ModelManagerSheet(settings: _settings),
    );
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    if (!_settings.hasApiKey) {
      showToast(context, '请先配置 API 密钥', isError: true);
      _openApiKeyDialog();
      return;
    }

    _inputCtrl.clear();
    setState(() {
      _messages.add(ZhipuMessage(role: 'user', content: text));
      _messages.add(const ZhipuMessage(role: 'assistant', content: ''));
      _sending = true;
    });
    _scrollToBottom();

    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    final history = _messages
        .sublist(0, _messages.length - 1)
        .where((m) => m.content.isNotEmpty || m.role == 'user')
        .toList();

    final buffer = StringBuffer();
    try {
      final stream = _api.streamChat(
        apiKey: _settings.apiKey!,
        model: _settings.model,
        messages: history,
        cancelToken: cancelToken,
      );
      await for (final delta in stream) {
        if (!mounted) return;
        buffer.write(delta);
        setState(() {
          _messages[_messages.length - 1] = ZhipuMessage(
            role: 'assistant',
            content: buffer.toString(),
          );
        });
        _scrollToBottom();
      }
      if (buffer.isEmpty && mounted) {
        setState(() {
          _messages[_messages.length - 1] = const ZhipuMessage(
            role: 'assistant',
            content: '(模型未返回内容)',
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = _extractError(e);
      setState(() {
        _messages[_messages.length - 1] = ZhipuMessage(
          role: 'assistant',
          content: buffer.isEmpty
              ? '请求失败：$msg'
              : '${buffer.toString()}\n\n[出错：$msg]',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
      _cancelToken = null;
    }
  }

  String _extractError(Object e) {
    return NetworkError.message(e);
  }

  void _stop() {
    _cancelToken?.cancel('user_stop');
  }

  void _clearChat() {
    if (_messages.isEmpty) return;
    setState(_messages.clear);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('智谱清言'),
            if (_allModels.isNotEmpty)
              DropdownButton<String>(
                value: _allModels.contains(_settings.model)
                    ? _settings.model
                    : null,
                hint: Text(
                  _settings.model,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                icon: const Icon(Icons.unfold_more, size: 16),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                underline: const SizedBox.shrink(),
                isDense: true,
                padding: EdgeInsets.zero,
                items: _allModels
                    .map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(m, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
                onChanged: (m) {
                  if (m != null) _settings.setModel(m);
                },
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '模型管理',
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: _openModelManager,
          ),
          IconButton(
            tooltip: 'API 密钥',
            icon: Icon(
              _settings.hasApiKey ? Icons.key : Icons.key_off_outlined,
              color: _settings.hasApiKey ? null : cs.error,
            ),
            onPressed: _openApiKeyDialog,
          ),
          IconButton(
            tooltip: '清空对话',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmpty(cs)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _buildBubble(_messages[i], cs),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: '说点什么…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  suffixIcon: _sending
                      ? IconButton(
                          onPressed: _stop,
                          icon: const Icon(Icons.stop),
                          tooltip: '停止',
                        )
                      : IconButton(
                          onPressed: _send,
                          icon: const Icon(Icons.send),
                          tooltip: '发送',
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _settings.hasApiKey ? '开始一段对话吧' : '先在右上角填入 API 密钥',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(ZhipuMessage msg, ColorScheme cs) {
    final isUser = msg.role == 'user';
    final bg = isUser ? cs.primary : cs.surfaceContainerHighest;
    final fg = isUser ? cs.onPrimary : cs.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: GestureDetector(
          onLongPress: () async {
            if (msg.content.isEmpty) return;
            await Clipboard.setData(ClipboardData(text: msg.content));
            if (mounted) showToast(context, '已复制');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: msg.content.isEmpty
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                : isUser
                ? Text(msg.content, style: TextStyle(color: fg, fontSize: 15))
                : MarkdownBody(
                    data: msg.content,
                    selectable: false,
                    onTapLink: (text, href, title) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri == null) return;
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    styleSheet: _markdownStyle(cs, fg),
                  ),
          ),
        ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(ColorScheme cs, Color fg) {
    final base = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: fg, fontSize: 15, height: 1.45);
    final codeBg = cs.surfaceContainerHigh;
    return MarkdownStyleSheet(
      p: base,
      h1: base?.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
      h2: base?.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
      h3: base?.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
      h4: base?.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
      strong: base?.copyWith(fontWeight: FontWeight.bold),
      em: base?.copyWith(fontStyle: FontStyle.italic),
      a: base?.copyWith(
        color: cs.primary,
        decoration: TextDecoration.underline,
      ),
      blockquote: base?.copyWith(color: cs.onSurfaceVariant),
      blockquoteDecoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      code: base?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: codeBg,
        fontSize: 14,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      listBullet: base,
      tableBody: base,
      tableHead: base?.copyWith(fontWeight: FontWeight.bold),
      tableBorder: TableBorder.all(color: cs.outlineVariant, width: 1),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
    );
  }
}

class _ModelManagerSheet extends StatefulWidget {
  final ZhipuSettings settings;

  const _ModelManagerSheet({required this.settings});

  @override
  State<_ModelManagerSheet> createState() => _ModelManagerSheetState();
}

class _ModelManagerSheetState extends State<_ModelManagerSheet> {
  List<String> get _myModels => widget.settings.customModels;

  Future<void> _addManual() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加模型'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '模型 ID',
            hintText: 'GLM-4',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await widget.settings.addCustomModel(result);
      if (mounted) setState(() {});
    }
  }

  Future<void> _removeModel(String modelId) async {
    await widget.settings.removeCustomModel(modelId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('模型管理', style: tt.titleMedium),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => launchUrl(
                Uri.parse(
                  'https://docs.bigmodel.cn/cn/guide/start/model-overview#%E6%96%87%E6%9C%AC%E6%A8%A1%E5%9E%8B',
                ),
                mode: LaunchMode.externalApplication,
              ),
              child: Row(
                children: [
                  Icon(Icons.open_in_new, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    '查看智谱模型列表',
                    style: tt.bodySmall?.copyWith(
                      color: cs.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addManual,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加模型'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await widget.settings.resetCustomModels();
                      if (mounted) setState(() {});
                    },
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('恢复默认'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _myModels.length,
              itemBuilder: (_, i) {
                final m = _myModels[i];
                final isSelected = m == widget.settings.model;
                return ListTile(
                  dense: true,
                  title: Text(m),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected)
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        ),
                      IconButton(
                        icon: Icon(Icons.close, size: 18, color: cs.error),
                        tooltip: '删除',
                        onPressed: () => _removeModel(m),
                      ),
                    ],
                  ),
                  selected: isSelected,
                  onTap: () async {
                    await widget.settings.setModel(m);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
