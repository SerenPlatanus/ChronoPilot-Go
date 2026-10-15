import 'package:flutter/foundation.dart';
import 'item.dart';

/// UI-facing local data API. A future remote adapter can implement this without
/// moving storage, authentication, or school scraping into individual pages.
abstract interface class PlannerDataApi implements Listenable {
  List<Item> get items;
  Item? find(String id);
  String get preferences;
  Map<String, dynamic> get syncStatus;
  List<Map<String, dynamic>> get sessions;
  Future<void> saveItem(Item item);
  Future<void> removeItem(String id);
  Future<void> setPreferences(String value);
  Future<void> saveSession(Map<String, dynamic> session);
  Future<void> deleteSession(String id);
}

abstract interface class SchoolDataApi {
  bool get busy;
  Future<void> refresh({bool force = false, bool interactive = false});
  void dispose();
}
