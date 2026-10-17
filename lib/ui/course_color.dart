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
    Color(0xffff303b),
    Color(0xffffc400),
    Color(0xff77d400),
    Color(0xff00c9e8),
    Color(0xff4263ff),
    Color(0xffb32dff),
    Color(0xffff208c),
    Color(0xff00cd83),
    Color(0xffff7900),
  ];
  return colors[hash % colors.length];
}
