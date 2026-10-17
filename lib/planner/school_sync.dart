import 'dart:io';
import 'package:celechron/database/database_helper.dart';
import 'package:celechron/http/calendar_config_parser.dart';
import 'package:celechron/http/data_source_status.dart';
import 'package:celechron/http/time_config_service.dart';
import 'package:celechron/http/zjuServices/courses.dart';
import 'package:celechron/http/zjuServices/zdbk.dart';
import 'package:celechron/http/zjuServices/zjuam.dart';
import 'package:celechron/http/zjuServices/exceptions.dart';
import 'package:celechron/model/semester.dart';
import 'package:celechron/utils/global.dart';
import 'item.dart';
import 'data_api.dart';
import 'repository.dart';

/// Foreground-only, single-flight synchronizer. Grades are never requested.
class SchoolSync implements SchoolDataApi {
  final PlannerRepository repository;
  final String username, password;
  Future<void>? _flight;
  DateTime? _lastAttempt;
  static const refreshInterval = Duration(minutes: 2);
  bool get shouldRefresh =>
      !_disposed &&
      username.isNotEmpty &&
      password.isNotEmpty &&
      (_lastAttempt == null ||
          DateTime.now().difference(_lastAttempt!) >= refreshInterval);
  @override
  bool get busy => _flight != null;
  bool _disposed = false;
  HttpClient? _client;
  SchoolSync(this.repository, this.username, this.password);
  @override
  void dispose() {
    _disposed = true;
    _client?.close(force: true);
  }

  @override
  Future<void> refresh({bool force = false, bool interactive = false}) {
    if (_flight != null) return _flight!;
    if (_disposed ||
        username.isEmpty ||
        password.isEmpty ||
        (!force &&
            _lastAttempt != null &&
            DateTime.now().difference(_lastAttempt!) < refreshInterval)) {
      return Future.value();
    }
    _lastAttempt = DateTime.now();
    return _flight = _run(interactive).whenComplete(() => _flight = null);
  }

  Future<void> _run(bool interactive) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'Mozilla/5.0';
    _client = client;
    GlobalStatus.isFirstScreenReq = !interactive;
    Future<void> failure(String partition, Object e) async {
      if (!_disposed) {
        await repository.mergeSchool(
          partition,
          [],
          fresh: false,
          error: shortErrorText(e),
        );
      }
    }

    try {
      final cache = DatabaseHelper();
      await cache.init(username);
      final zdbk = Zdbk()..db = cache;
      final courses = Courses()..db = cache;
      final calendar = TimeConfigService()..db = cache;
      final cookie = await ZjuAm.getSsoCookie(client, username, password);
      Future<void> timetable() async {
        try {
          await zdbk.login(client, cookie);
          if (!_disposed) {
            await repository.mergeSchool("courses", [], fresh: true);
          }
          final now = DateTime.now();
          final year = academicYearStartFor(now);
          // Current year, plus next year when registration is likely to open.
          for (final y in [
            year,
            if (now.month >= 6 && now.month <= 8) year + 1,
          ]) {
            for (final term in [1, 2]) {
              final partition = 'courses:$y:$term';
              try {
                final key = '$y-${y + 1}-$term';
                final sem = Semester('$y-${y + 1}${term == 1 ? '秋冬' : '春夏'}');
                final config = await calendar.getConfig(client, key);
                if (config.item2 == null) {
                  throw const FormatException('校历配置不可用');
                }
                applyCalendarConfig(config.item2!, sem, {}, context: key);
                Object? error;
                for (final season
                    in term == 1 ? ['1|秋', '1|冬'] : ['2|春', '2|夏']) {
                  final response = await zdbk.getTimetable(
                    client,
                    '$y-${y + 1}',
                    season,
                  );
                  error ??= response.item1;
                  for (final session in response.item2) {
                    sem.addSession(session, key);
                  }
                }
                // Approximate calendars are not accurate enough to overwrite real dates.
                error ??= config.item3 != DataSourceStatus.live
                    ? const FormatException('校历未实时更新，保留已有课表')
                    : null;
                final byId = <String, Item>{};
                for (final p in sem.periods) {
                  final id = stableId(
                    '$partition:${p.summary}:${p.startTime.toIso8601String()}',
                  );
                  byId[id] = Item(
                    id: id,
                    categoryId: 'course',
                    title: p.summary,
                    subject: p.summary,
                    notes: p.description,
                    location: p.location,
                    origin: 'school',
                    sourceKey: partition,
                    start: p.startTime,
                    end: p.endTime,
                  );
                }
                if (!_disposed) {
                  await repository.mergeSchool(
                    partition,
                    byId.values.toList(),
                    fresh: error == null,
                    error: error == null ? null : shortErrorText(error),
                  );
                }
              } catch (e) {
                await failure(partition, e);
              }
            }
          }
          try {
            final response = await zdbk.getExamsDto(client);
            final items = <String, Item>{};
            for (final dto in response.item2) {
              for (final exam in dto.exams) {
                if (exam.time.length < 2) continue;
                // The parser uses year 1970 for dates relative to an exam week.
                final dated = exam.time.first.year >= 2020;
                final id = stableId('exam:${exam.id}:${exam.type}');
                items[id] = Item(
                  id: id,
                  categoryId: 'exam',
                  title: '${exam.name} 考试',
                  subject: exam.name,
                  origin: 'school',
                  sourceKey: 'exams',
                  start: dated ? exam.time.first : null,
                  end: dated ? exam.time.last : null,
                  location: exam.location ?? '',
                  notes: [
                    if (!dated) exam.dateLabel ?? '考试日期待公布',
                    if (exam.seat != null) '座位：${exam.seat}',
                  ].join('；'),
                );
              }
            }
            if (!_disposed) {
              await repository.mergeSchool(
                'exams',
                items.values.toList(),
                fresh: response.item1 == null,
                error: response.item1 == null
                    ? null
                    : shortErrorText(response.item1),
              );
            }
          } catch (e) {
            await failure('exams', e);
          }
        } catch (e) {
          await failure('courses', e);
          await failure('exams', e);
        }
      }

      Future<void> homework() async {
        try {
          await courses.login(client, cookie);
          final response = await courses.getTodo(client);
          if (!_disposed) {
            await repository.mergeSchool(
              'homework',
              response.item2
                  .map(
                    (todo) => Item(
                      id: stableId('homework:${todo.id}'),
                      categoryId: 'homework',
                      title: todo.name,
                      subject: todo.course,
                      deadline: todo.endTime,
                      origin: 'school',
                      sourceKey: 'homework',
                    ),
                  )
                  .toList(),
              fresh: response.item3 == DataSourceStatus.live,
              error: response.item1 == null
                  ? null
                  : shortErrorText(response.item1),
            );
          }
        } catch (e) {
          await failure('homework', e);
        }
      }

      await Future.wait([timetable(), homework()]);
    } catch (e) {
      await failure('courses', e);
      await failure('homework', e);
      await failure('exams', e);
    } finally {
      GlobalStatus.isFirstScreenReq = false;
      ZjuAm.releaseClient(client);
      client.close(force: true);
      _client = null;
    }
  }
}
