import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/comic.dart';

class LocalFavorites {
  LocalFavorites._();

  static const _key = 'local_favorite_comics_v1';
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<List<Comic>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((item) => Comic.fromJson(Map<String, dynamic>.from(item)))
        .where((comic) => comic.pathWord.isNotEmpty)
        .toList();
  }

  static Future<bool> contains(String pathWord) async {
    final items = await list();
    return items.any((comic) => comic.pathWord == pathWord);
  }

  static Future<void> setFavorite(Comic comic, bool favorite) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await list();
    final existingIndex = items.indexWhere(
      (item) => item.pathWord == comic.pathWord,
    );
    if (favorite) {
      if (existingIndex >= 0) {
        items[existingIndex] = comic;
      } else {
        items.insert(0, comic);
      }
    } else if (existingIndex >= 0) {
      items.removeAt(existingIndex);
    }
    await prefs.setString(
      _key,
      jsonEncode(items.map((comic) => comic.toJson()).toList()),
    );
    changes.value++;
  }
}
