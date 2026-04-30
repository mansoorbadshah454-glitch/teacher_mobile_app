import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LocalDbService {
  static const String cacheBoxName = 'offlineCache';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(cacheBoxName);
  }

  static Box get cacheBox => Hive.box(cacheBoxName);

  static dynamic _sanitize(dynamic data) {
    if (data is Timestamp) return data.toDate().toIso8601String();
    if (data is DateTime) return data.toIso8601String();
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), _sanitize(value)));
    }
    if (data is List) {
      return data.map((e) => _sanitize(e)).toList();
    }
    return data;
  }

  static Future<void> saveCache(String key, dynamic data) async {
    final sanitizedData = _sanitize(data);
    await cacheBox.put(key, jsonEncode(sanitizedData));
  }

  static dynamic getCache(String key) {
    final data = cacheBox.get(key);
    if (data != null) {
      try {
        return jsonDecode(data);
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}
