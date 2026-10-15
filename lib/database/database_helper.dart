import 'package:hive/hive.dart';
import 'package:celechron/planner/item.dart';

/// Account-scoped raw response cache used only by undergraduate adapters.
class DatabaseHelper {
  late Box<String> _cache;
  Future<void> init(String account) async {
    _cache = await Hive.openBox<String>('school_cache_v1_${stableId(account)}');
  }

  String? getCachedWebPage(String key) => _cache.get(key);
  Future<void> setCachedWebPage(String key, String value) =>
      _cache.put(key, value);
  Future<void> removeCachedWebPage(String key) => _cache.delete(key);
  Future<void> removeAllCachedWebPage() => _cache.clear();
}
