import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/network_error.dart';

/// 提示词预设条目。
class PromptPreset {
  final String id;
  final String name;
  final String prompt;
  final bool isBuiltIn;

  const PromptPreset({
    required this.id,
    required this.name,
    required this.prompt,
    this.isBuiltIn = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'isBuiltIn': isBuiltIn,
  };

  factory PromptPreset.fromJson(Map<String, dynamic> json) => PromptPreset(
    id: json['id'] as String,
    name: json['name'] as String,
    prompt: json['prompt'] as String,
    isBuiltIn: json['isBuiltIn'] as bool? ?? false,
  );

  PromptPreset copyWith({String? name, String? prompt}) => PromptPreset(
    id: id,
    name: name ?? this.name,
    prompt: prompt ?? this.prompt,
    isBuiltIn: isBuiltIn,
  );
}

enum ZhipuAutoSummaryTiming { onOpen, afterPreload }

/// 智谱清言（BigModel）API 客户端与本地设置。
///
/// 密钥与模型选择仅保存在本地 SharedPreferences，不上传到任何位置。
class ZhipuSettings extends ChangeNotifier {
  static final ZhipuSettings _instance = ZhipuSettings._();
  factory ZhipuSettings() => _instance;
  ZhipuSettings._();

  static const _keyApiKey = 'zhipu_api_key';
  static const _keyModel = 'zhipu_model';
  static const _keySummaryEnabled = 'zhipu_summary_enabled';
  static const _keySpoilerAnalysis = 'zhipu_spoiler_analysis';
  static const _keyPresets = 'zhipu_prompt_presets';
  static const _keyActivePreset = 'zhipu_active_preset';
  static const _keyAutoSummary = 'zhipu_auto_summary';
  static const _keyAutoSummaryMin = 'zhipu_auto_summary_min';
  static const _keyAutoSummaryTiming = 'zhipu_auto_summary_timing';
  static const _keySpoilerWarn = 'zhipu_spoiler_warn';
  static const _keyCustomModels = 'zhipu_custom_models';

  /// 常用模型，第一个为默认。glm-4-flash 系列对个人用户免费。
  static const availableModels = <String>[
    'glm-4-Flash-250414',
    'glm-4.5-flash',
    'glm-4.7-flash',
  ];

  static const defaultModel = 'glm-4.5-flash';

  /// 内置预设 ID。
  static const presetBasicId = 'basic';
  static const presetSpoilerId = 'spoiler';

  /// 不带剧透分析的基础提示词（默认）。
  static const defaultPromptBasic =
      '你是一名漫画社区氛围分析师。请基于用户提供的章节评论列表，用简体中文 Markdown 输出一份简洁的总结，包含以下小标题：\n'
      '**整体氛围**（一句话概括）、**大家在聊什么**（要点列表，3~6 条）、'
      '**值得一提**（可选，亮点/梗/争议）。\n'
      '语言要凝练、有趣，不要逐条复述评论，不要编造评论里没有的内容。';

  /// 带剧透分析的提示词。
  static const defaultPromptSpoiler =
      '你是一名漫画社区氛围分析师。请基于用户提供的章节评论列表，用简体中文 Markdown 输出一份简洁的总结，包含以下小标题：\n'
      '**整体氛围**（一句话概括）、**大家在聊什么**（要点列表，3~6 条，注意：不要在这里复述任何剧透内容）、'
      '**值得一提**（可选，亮点/梗/争议，同样不能透露剧透）、'
      '**剧透警告**（仅当存在剧透评论时才输出此段，且只能写"本章评论中有 N 处涉及剧透，已为你遮罩"这一句，绝对不要描述、暗示或概括任何剧情/转折/结局；如果没有任何剧透评论则整段省略，不要输出此标题和任何内容）。\n'
      '语言要凝练、有趣，不要逐条复述评论，不要编造评论里没有的内容。\n\n'
      '【剧透的判定标准 · 非常重要】\n'
      '只有同时满足以下全部条件的评论才应标记为剧透：\n'
      '- 明确透露了尚未在当前章节及之前出场过的剧情走向、角色命运（死亡、复活、背叛等）或结局结果；\n'
      '- 普通的感想（如"太好看了""画风不错"）、角色喜爱（如"XX好帅"）、对已发生情节的正常讨论、对后续的模糊期待（如"期待下一话"）、猜测与假想（未坐实的推理）——这些都【不算】剧透；\n'
      '【机读输出】用户消息中每条评论开头都是它的数字 id（形如 "81216. xxx: ..."）。'
      '在整篇输出的最末尾追加一个 fenced code block（用三个反引号包裹），里面只放一个 JSON 数字数组，列出【高度剧透嫌疑】的评论 id：\n'
      '```\n'
      '[81216, 81230]\n'
      '```\n'
      '如果没有任何高度剧透的评论，依然必须输出该代码块，数组为空：\n'
      '```\n'
      '[]\n'
      '```\n'
      '硬性要求：\n'
      '1) 必须是整篇输出的最后一段，下面不要再写任何字；\n'
      '2) 必须用三个反引号包裹（语言标识写不写都行）；\n'
      '3) 中括号里只能有数字和英文逗号，不要写解释、不要带 id= 前缀；\n'
      '4) 哪怕没有剧透也要写空数组 []，不能省略整个代码块；\n';

  /// 兼容旧版。
  static const defaultSummaryPrompt = defaultPromptBasic;

  static const builtInPresets = <PromptPreset>[
    PromptPreset(
      id: presetBasicId,
      name: '基础提示词',
      prompt: defaultPromptBasic,
      isBuiltIn: true,
    ),
    PromptPreset(
      id: presetSpoilerId,
      name: '带剧透分析的提示词',
      prompt: defaultPromptSpoiler,
      isBuiltIn: true,
    ),
  ];

  String? _apiKey;
  String _model = defaultModel;
  String _summaryPrompt = defaultPromptBasic;
  bool _loaded = false;
  bool _summaryEnabled = false;
  bool _spoilerAnalysis = false;
  bool _autoSummary = false;
  int _autoSummaryMin = 30;
  ZhipuAutoSummaryTiming _autoSummaryTiming = ZhipuAutoSummaryTiming.onOpen;
  bool _spoilerWarn = true;
  List<PromptPreset> _presets = List.from(builtInPresets);
  String _activePresetId = presetBasicId;
  List<String> _customModels = [];

  String? get apiKey => _apiKey;
  String get model => _model;
  String get summaryPrompt => _summaryPrompt;
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;
  bool get summaryEnabled => _summaryEnabled;
  bool get spoilerAnalysis => _spoilerAnalysis;
  bool get autoSummary => _autoSummary;
  int get autoSummaryMin => _autoSummaryMin;
  ZhipuAutoSummaryTiming get autoSummaryTiming => _autoSummaryTiming;
  bool get spoilerWarn => _spoilerWarn;
  List<PromptPreset> get presets => List.unmodifiable(_presets);
  String get activePresetId => _activePresetId;
  List<String> get customModels => List.unmodifiable(_customModels);

  PromptPreset? get activePreset =>
      _presets.where((p) => p.id == _activePresetId).firstOrNull;

  Future<void> load() async {
    if (_loaded) return;
    final sp = await SharedPreferences.getInstance();
    _apiKey = sp.getString(_keyApiKey);
    _model = sp.getString(_keyModel) ?? defaultModel;
    _summaryEnabled = sp.getBool(_keySummaryEnabled) ?? false;
    _spoilerAnalysis = sp.getBool(_keySpoilerAnalysis) ?? false;
    _autoSummary = sp.getBool(_keyAutoSummary) ?? false;
    _autoSummaryMin = sp.getInt(_keyAutoSummaryMin) ?? 30;
    _autoSummaryTiming = _parseAutoSummaryTiming(
      sp.getString(_keyAutoSummaryTiming),
    );
    _spoilerWarn = sp.getBool(_keySpoilerWarn) ?? true;
    _activePresetId = sp.getString(_keyActivePreset) ?? presetBasicId;
    _customModels = sp.getStringList(_keyCustomModels) ?? [];
    // 首次使用时将内置模型加入自定义列表
    if (_customModels.isEmpty) {
      _customModels = List.from(availableModels);
      await sp.setStringList(_keyCustomModels, _customModels);
    }
    await _loadPresets(sp);
    _syncPrompt();
    _loaded = true;
    notifyListeners();
  }

  ZhipuAutoSummaryTiming _parseAutoSummaryTiming(String? value) {
    for (final timing in ZhipuAutoSummaryTiming.values) {
      if (timing.name == value) return timing;
    }
    return ZhipuAutoSummaryTiming.onOpen;
  }

  Future<void> _loadPresets(SharedPreferences sp) async {
    final raw = sp.getString(_keyPresets);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => PromptPreset.fromJson(e as Map<String, dynamic>))
            .toList();
        // 确保内置预设始终存在（用保存的覆盖默认）
        final ids = list.map((e) => e.id).toSet();
        for (final builtIn in builtInPresets) {
          if (!ids.contains(builtIn.id)) {
            list.insert(
              builtIn == builtInPresets[0] ? 0 : list.length,
              builtIn,
            );
          }
        }
        _presets = list;
      } catch (_) {
        _presets = List.from(builtInPresets);
      }
    } else {
      _presets = List.from(builtInPresets);
    }
  }

  Future<void> _savePresets() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _keyPresets,
      jsonEncode(_presets.map((e) => e.toJson()).toList()),
    );
  }

  void _syncPrompt() {
    final preset = activePreset;
    _summaryPrompt = preset?.prompt ?? defaultPromptBasic;
  }

  Future<void> setApiKey(String? key) async {
    final sp = await SharedPreferences.getInstance();
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await sp.remove(_keyApiKey);
      _apiKey = null;
    } else {
      await sp.setString(_keyApiKey, trimmed);
      _apiKey = trimmed;
    }
    notifyListeners();
  }

  Future<void> setModel(String model) async {
    if (model.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyModel, model);
    _model = model;
    notifyListeners();
  }

  Future<void> setSummaryEnabled(bool enabled) async {
    _summaryEnabled = enabled;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keySummaryEnabled, enabled);
    notifyListeners();
  }

  Future<void> setAutoSummary(bool enabled) async {
    _autoSummary = enabled;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyAutoSummary, enabled);
    notifyListeners();
  }

  Future<void> setAutoSummaryMin(int min) async {
    _autoSummaryMin = min < 1 ? 1 : min;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyAutoSummaryMin, _autoSummaryMin);
    notifyListeners();
  }

  Future<void> setAutoSummaryTiming(ZhipuAutoSummaryTiming timing) async {
    _autoSummaryTiming = timing;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyAutoSummaryTiming, timing.name);
    notifyListeners();
  }

  Future<void> setSpoilerWarn(bool enabled) async {
    _spoilerWarn = enabled;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keySpoilerWarn, enabled);
    notifyListeners();
  }

  Future<void> setSpoilerAnalysis(bool enabled) async {
    _spoilerAnalysis = enabled;
    if (enabled && _activePresetId == presetBasicId) {
      _activePresetId = presetSpoilerId;
    } else if (!enabled && _activePresetId == presetSpoilerId) {
      _activePresetId = presetBasicId;
    }
    _syncPrompt();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keySpoilerAnalysis, enabled);
    await sp.setString(_keyActivePreset, _activePresetId);
    notifyListeners();
  }

  Future<void> setActivePreset(String id) async {
    if (_presets.every((p) => p.id != id)) return;
    _activePresetId = id;
    _syncPrompt();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyActivePreset, id);
    notifyListeners();
  }

  Future<void> updatePreset(String id, {String? name, String? prompt}) async {
    final idx = _presets.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _presets[idx] = _presets[idx].copyWith(name: name, prompt: prompt);
    _syncPrompt();
    await _savePresets();
    notifyListeners();
  }

  Future<void> resetPreset(String id) async {
    final builtIn = builtInPresets.where((p) => p.id == id).firstOrNull;
    if (builtIn == null) return;
    final idx = _presets.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _presets[idx] = builtIn;
    _syncPrompt();
    await _savePresets();
    notifyListeners();
  }

  Future<void> addPreset(String name, String prompt) async {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    _presets.add(PromptPreset(id: id, name: name, prompt: prompt));
    _activePresetId = id;
    _syncPrompt();
    await _savePresets();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyActivePreset, _activePresetId);
    notifyListeners();
  }

  Future<void> removePreset(String id) async {
    final preset = _presets.where((p) => p.id == id).firstOrNull;
    if (preset == null || preset.isBuiltIn) return;
    _presets.removeWhere((p) => p.id == id);
    if (_activePresetId == id) {
      _activePresetId = presetBasicId;
    }
    _syncPrompt();
    await _savePresets();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyActivePreset, _activePresetId);
    notifyListeners();
  }

  bool isPresetModified(String id) {
    final builtIn = builtInPresets.where((p) => p.id == id).firstOrNull;
    if (builtIn == null) return false;
    final current = _presets.where((p) => p.id == id).firstOrNull;
    if (current == null) return false;
    return current.prompt != builtIn.prompt || current.name != builtIn.name;
  }

  Future<void> addCustomModel(String modelId) async {
    if (modelId.isEmpty || _customModels.contains(modelId)) return;
    _customModels.add(modelId);
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_keyCustomModels, _customModels);
    notifyListeners();
  }

  Future<void> removeCustomModel(String modelId) async {
    _customModels.remove(modelId);
    if (_model == modelId) {
      _model = _customModels.isNotEmpty ? _customModels.first : defaultModel;
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_keyModel, _model);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_keyCustomModels, _customModels);
    notifyListeners();
  }

  Future<void> resetCustomModels() async {
    _customModels = List.from(availableModels);
    if (!_customModels.contains(_model)) {
      _model = defaultModel;
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_keyModel, _model);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_keyCustomModels, _customModels);
    notifyListeners();
  }
}

class ZhipuMessage {
  final String role;
  final String content;

  const ZhipuMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class ZhipuApi {
  static const _endpoint =
      'https://open.bigmodel.cn/api/paas/v4/chat/completions';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 5),
    ),
  )..interceptors.add(NetworkError.rateLimitInterceptor());

  /// 以流式 SSE 方式调用，逐块吐出文本增量。
  Stream<String> streamChat({
    required String apiKey,
    required String model,
    required List<ZhipuMessage> messages,
    CancelToken? cancelToken,
  }) async* {
    final response = await _dio.post<ResponseBody>(
      _endpoint,
      data: {
        'model': model,
        'messages': messages.map((e) => e.toJson()).toList(),
        'stream': true,
      },
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          // 关键：禁用压缩，否则 Dio 会等待完整响应才能解压，无法流式
          'Accept-Encoding': 'identity',
          'Cache-Control': 'no-cache',
        },
      ),
      cancelToken: cancelToken,
    );

    // 用流式 utf8 解码器 + LineSplitter，正确处理跨 chunk 的中文字符和分行
    final lines = response.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data == '[DONE]') return;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = (choices.first as Map)['delta'] as Map?;
        final content = delta?['content'];
        if (content is String && content.isNotEmpty) {
          yield content;
        }
      } catch (_) {
        // 忽略个别无法解析的行
      }
    }
  }
}
