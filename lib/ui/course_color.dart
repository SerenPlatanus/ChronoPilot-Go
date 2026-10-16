import 'package:flutter/material.dart';
import '../planner/item.dart';

/// Stable across sessions, themes and calendar/list views (never hashCode).
Color courseColor(Item item) {
  final key = item.subject.trim().isEmpty
      ? item.categoryId
      : item.subject.trim();
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  const colors = [
    Color(0xffef5350),
    Color(0xffffbe0b),
    Color(0xff87cb39),
    Color(0xff19b9d4),
    Color(0xff6486ff),
    Color(0xffb887ef),
    Color(0xffed85b0),
    Color(0xff25b88a),
    Color(0xffff9154),
  ];
  return colors[hash % colors.length];
}
