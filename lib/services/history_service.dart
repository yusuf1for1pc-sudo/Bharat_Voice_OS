import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Persisted history item stored in Hive.
class StoredHistoryItem {
  final String id;
  final String title;
  final String subtitle;
  final String iconName;
  final DateTime timestamp;
  final bool wasSuccessful;

  StoredHistoryItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.timestamp,
    required this.wasSuccessful,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'iconName': iconName,
        'timestamp': timestamp.toIso8601String(),
        'wasSuccessful': wasSuccessful,
      };

  factory StoredHistoryItem.fromMap(Map<dynamic, dynamic> map) {
    return StoredHistoryItem(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String? ?? '',
      iconName: map['iconName'] as String? ?? '✨',
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
      wasSuccessful: map['wasSuccessful'] as bool? ?? true,
    );
  }
}

/// HistoryService — wraps Hive storage for task history.
class HistoryService {
  static const _boxName = 'task_history';
  static Box? _box;

  /// Initialize Hive and open the box. Call once at app startup.
  static Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
  }

  /// Save a new history item.
  static Future<void> saveItem(StoredHistoryItem item) async {
    try {
      await _box?.put(item.id, item.toMap());
    } catch (e) {
      debugPrint('HistoryService: saveItem error: $e');
    }
  }

  /// Get all history items, newest first.
  static List<StoredHistoryItem> getAll() {
    try {
      if (_box == null) return [];
      final items = <StoredHistoryItem>[];
      for (final key in _box!.keys) {
        final map = _box!.get(key);
        if (map is Map) {
          items.add(StoredHistoryItem.fromMap(map));
        }
      }
      // Sort newest first
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items;
    } catch (e) {
      debugPrint('HistoryService: getAll error: $e');
      return [];
    }
  }

  /// Clear all history.
  static Future<void> clear() async {
    try {
      await _box?.clear();
    } catch (e) {
      debugPrint('HistoryService: clear error: $e');
    }
  }
}
