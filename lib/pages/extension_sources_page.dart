import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/toast.dart';

class ExtensionSourcesPage extends StatefulWidget {
  const ExtensionSourcesPage({super.key});

  @override
  State<ExtensionSourcesPage> createState() => _ExtensionSourcesPageState();
}

class _ExtensionSourcesPageState extends State<ExtensionSourcesPage> {
  static const _activeSourceKey = 'active_manga_source';
  // 注意：eu.kanade.tachiyomi.extension.all.kopymanga 不存在于 Keiyoushi 仓库。
  // 本 App 使用内置 CopyMangaSourceAdapter，非 Tachiyomi 扩展。
  static const _builtinSourceId = 'copymanga';

  final _dio = Dio();
  final _searchController = TextEditingController();

  List<dynamic> _extensions = [];
  List<dynamic> _filteredExtensions = [];
  String _activeSourcePkg = _builtinSourceId;
  bool _loading = true;
  String? _error;

  final List<String> _popularKeywords = [
    'kopymanga',
    'mangadex',
    'bilibilicomics',
    'webtoons',
    'mangareader',
    'manhuaplus',
    'manhwa18',
    'nhentai',
  ];

  @override
  void initState() {
    super.initState();
    _loadActiveSource();
    _fetchExtensions();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveSource() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _activeSourcePkg =
            prefs.getString(_activeSourceKey) ?? _builtinSourceId;
      });
    }
  }

  Future<void> _saveActiveSource(String pkg, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeSourceKey, pkg);
    if (mounted) {
      setState(() {
        _activeSourcePkg = pkg;
      });
    }

    if (!mounted) return;

    if (pkg.toLowerCase().contains('kopymanga') || pkg == _builtinSourceId) {
      showToast(context, '已激活核心数据源：$name');
    } else {
      showToast(context, '已选择数据源：$name。主程序使用内置 CopyManga 适配器运行。');
    }
  }

  int _getPopularityScore(String pkg) {
    for (int i = 0; i < _popularKeywords.length; i++) {
      if (pkg.toLowerCase().contains(_popularKeywords[i])) {
        return _popularKeywords.length - i;
      }
    }
    return 0;
  }

  Future<void> _fetchExtensions() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await _dio.get(
        'https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json',
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );

      dynamic rawData = resp.data;
      if (rawData is String) {
        rawData = jsonDecode(rawData);
      }

      if (rawData is List) {
        final list = List<dynamic>.from(rawData);
        // Sort extensions: popular ones first
        list.sort((a, b) {
          final pkgA = a['pkg'] as String? ?? '';
          final pkgB = b['pkg'] as String? ?? '';
          final scoreA = _getPopularityScore(pkgA);
          final scoreB = _getPopularityScore(pkgB);
          if (scoreA != scoreB) {
            return scoreB.compareTo(scoreA); // higher score first
          }
          final nameA = a['name'] as String? ?? '';
          final nameB = b['name'] as String? ?? '';
          return nameA.toLowerCase().compareTo(nameB.toLowerCase());
        });

        if (mounted) {
          setState(() {
            _extensions = list;
            _filteredExtensions = list;
            _loading = false;
          });
        }
      } else {
        throw Exception('无效的数据格式');
      }
    } catch (e) {
      debugPrint('Error fetching extension index: $e');
      if (mounted) {
        setState(() {
          _error = '无法连接至数据源仓库：${e.toString()}';
          _loading = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filteredExtensions = _extensions;
      });
      return;
    }

    setState(() {
      _filteredExtensions = _extensions.where((ext) {
        final name = (ext['name'] as String? ?? '').toLowerCase();
        final pkg = (ext['pkg'] as String? ?? '').toLowerCase();
        return name.contains(query) || pkg.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('数据源扩展仓库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchExtensions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search box
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索漫画数据源扩展...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_off, size: 64, color: cs.error),
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 24),
                          FilledButton.tonal(
                            onPressed: _fetchExtensions,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _filteredExtensions.isEmpty
                ? Center(
                    child: Text(
                      '没有找到匹配的扩展源',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredExtensions.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final ext = _filteredExtensions[index];
                      final name = ext['name'] as String? ?? '未知扩展';
                      final pkg = ext['pkg'] as String? ?? '';
                      final version = ext['version'] as String? ?? '1.0.0';
                      final lang = ext['lang'] as String? ?? 'all';
                      final isNsfw = ext['nsfw'] == 1;

                      final isActive = _activeSourcePkg == pkg;
                      final isPopular = _getPopularityScore(pkg) > 0;
                      final isKopymanga = pkg.toLowerCase().contains(
                        'kopymanga',
                      );

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: isActive ? 2 : 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isActive
                                ? cs.primary
                                : cs.outlineVariant.withValues(alpha: 0.5),
                            width: isActive ? 2 : 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: tt.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: isActive
                                                  ? cs.primary
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        if (isNsfw)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            margin: const EdgeInsets.only(
                                              left: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: cs.errorContainer,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '18+',
                                              style: tt.labelSmall?.copyWith(
                                                color: cs.onErrorContainer,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        if (isPopular)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            margin: const EdgeInsets.only(
                                              left: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: cs.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '热门',
                                              style: tt.labelSmall?.copyWith(
                                                color: cs.onPrimaryContainer,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      pkg,
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.language,
                                          size: 14,
                                          color: cs.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          lang.toUpperCase(),
                                          style: tt.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Icon(
                                          Icons.info_outline,
                                          size: 14,
                                          color: cs.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'v$version',
                                          style: tt.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isKopymanga) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        '注意：此扩展不存在于 Keiyoushi 仓库。App 使用内置 CopyManga 适配器。',
                                        style: tt.bodySmall?.copyWith(
                                          color: cs.error,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Switch(
                                value: isActive,
                                onChanged: (val) {
                                  if (val) {
                                    _saveActiveSource(pkg, name);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
