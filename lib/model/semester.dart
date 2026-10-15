import 'package:celechron/utils/json_utils.dart';
import 'session.dart';
import 'period.dart';

/// Undergraduate calendar expansion. No grades, GPA or account state.
class Semester {
  final String name;
  final List<Session> _sessions = [];
  List<Session> get sessions => List.unmodifiable(_sessions);
  List<List<Duration>> _sessionToTime = List.generate(16, (_) => []);
  List<List<List<List<DateTime>>>> _dayOfWeekToDays = List.generate(
    2,
    (_) => List.generate(2, (_) => List.generate(8, (_) => <DateTime>[])),
  );
  Map<DateTime, String> _holidays = {};
  Map<DateTime, DateTime> _exchanges = {};
  List<Period>? _periodsCache;
  Semester(this.name);
  void _invalidatePeriodsCache() => _periodsCache = null;
  List<Period> get periods => _periodsCache ??= _buildPeriods();
  void addSession(Session session, String semesterId) {
    if (session.time.isEmpty ||
        session.dayOfWeek < 1 ||
        session.dayOfWeek > 7) {
      return;
    }
    _invalidatePeriodsCache();
    session.id ??= '$semesterId:${session.name}';
    for (final old in _sessions) {
      if (old.name == session.name &&
          old.dayOfWeek == session.dayOfWeek &&
          old.time.join(',') == session.time.join(',') &&
          old.location == session.location &&
          old.oddWeek == session.oddWeek &&
          old.evenWeek == session.evenWeek) {
        old.firstHalf = old.firstHalf || session.firstHalf;
        old.secondHalf = old.secondHalf || session.secondHalf;
        return;
      }
    }
    _sessions.add(session);
  }

  void addZjuCalendar(Map<String, dynamic> json) {
    _invalidatePeriodsCache();
    final startEnd = (asDynamicList(json['startEnd']) ?? const [])
        .map(asString)
        .whereType<String>()
        .map(asDateTime)
        .whereType<DateTime>()
        .toList();
    if (startEnd.length != 4) {
      throw const FormatException('校历缺少四个有效的学期起止日期');
    }

    final sessionToTime = <List<Duration>>[];
    for (final rawPeriod in asDynamicList(json['sessionTime']) ?? const []) {
      final period = <Duration>[];
      for (final rawTime in asDynamicList(rawPeriod) ?? const []) {
        final parts = (asString(rawTime) ?? '').split(':');
        if (parts.length < 2) continue;
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          period.add(Duration(hours: hour, minutes: minute));
        }
      }
      sessionToTime.add(period);
    }
    if (sessionToTime.isEmpty ||
        sessionToTime.every((period) => period.isEmpty)) {
      throw const FormatException('校历缺少有效的节次时间');
    }

    final holidays = <DateTime, String>{};
    for (final entry in (asStringMap(json['holiday']) ?? const {}).entries) {
      final date = asDateTime(entry.key);
      final name = asString(entry.value);
      if (date != null && name != null) holidays[date] = name;
    }
    final exchanges = <DateTime, DateTime>{};
    for (final key in (asStringMap(json['exchange']) ?? const {}).keys) {
      if (key.length < 16) continue;
      final first = asDateTime(key.substring(0, 8));
      final second = asDateTime(key.substring(8, 16));
      if (first != null && second != null) {
        exchanges[first] = second;
        exchanges[second] = first;
      }
    }

    _sessionToTime = sessionToTime;
    _holidays = holidays;
    _exchanges = exchanges;
    _dayOfWeekToDays = [
      [
        /*上半学期*/
        /*单周日期*/ [[], [], [], [], [], [], [], []],
        /*双周日期*/ [[], [], [], [], [], [], [], []],
      ],
      [
        /*下半学期*/
        /*单周日期*/ [[], [], [], [], [], [], [], []],
        /*双周日期*/ [[], [], [], [], [], [], [], []],
      ],
    ];
    // 上半学期
    var weekday = startEnd[0].weekday;
    var oddEvenWeek = 0;
    for (
      DateTime day = startEnd[0];
      !day.isAfter(startEnd[1]);
      day = day.add(const Duration(days: 1))
    ) {
      _dayOfWeekToDays[0][oddEvenWeek][weekday++].add(day);
      if (weekday == 8) {
        weekday = 1;
        oddEvenWeek = 1 - oddEvenWeek;
      }
    }
    weekday = startEnd[2].weekday;
    oddEvenWeek = 0;
    for (
      DateTime day = startEnd[2];
      !day.isAfter(startEnd[3]);
      day = day.add(const Duration(days: 1))
    ) {
      _dayOfWeekToDays[1][oddEvenWeek][weekday++].add(day);
      if (weekday == 8) {
        weekday = 1;
        oddEvenWeek = 1 - oddEvenWeek;
      }
    }
  }

  List<Period> _buildPeriods() {
    List<Period> periods = [];
    for (var session in _sessions.where(
      (s) => s.confirmed && s.time.isNotEmpty,
    )) {
      // 自定义单双周的课程在后面处理（目前均为研究生课）
      if (session.customRepeat) {
        continue;
      }
      // 常规单双周的课程（目前均为本科生课）
      if (session.firstHalf) {
        if (session.oddWeek) {
          for (var day in _dayOfWeekToDays[0][0][session.dayOfWeek]) {
            var period = Period(
              uid: '${session.id}${session.dayOfWeek}${session.time.first}',
              fromUid: session.id,
              type: PeriodType.classes,
              description: "教师: ${session.teacher}",
              location: session.location ?? "未知",
              summary: session.name,
              startTime: day.add(
                _sessionToTime[session.time.first].firstOrNull ?? Duration.zero,
              ),
              endTime: day.add(
                _sessionToTime[session.time.last].lastOrNull ?? Duration.zero,
              ),
            );
            periods.add(period);
          }
        }
        if (session.evenWeek) {
          for (var day in _dayOfWeekToDays[0][1][session.dayOfWeek]) {
            var period = Period(
              uid: '${session.id}${session.dayOfWeek}${session.time.first}',
              fromUid: session.id,
              type: PeriodType.classes,
              description: "教师: ${session.teacher}",
              location: session.location ?? "未知",
              summary: session.name,
              startTime: day.add(
                _sessionToTime[session.time.first].firstOrNull ?? Duration.zero,
              ),
              endTime: day.add(
                _sessionToTime[session.time.last].lastOrNull ?? Duration.zero,
              ),
            );
            periods.add(period);
          }
        }
      }
      if (session.secondHalf) {
        if (session.oddWeek) {
          for (var day in _dayOfWeekToDays[1][0][session.dayOfWeek]) {
            var period = Period(
              uid: '${session.id}${session.dayOfWeek}${session.time.first}',
              fromUid: session.id,
              type: PeriodType.classes,
              description: "教师: ${session.teacher}",
              location: session.location ?? "未知",
              summary: session.name,
              startTime: day.add(
                _sessionToTime[session.time.first].firstOrNull ?? Duration.zero,
              ),
              endTime: day.add(
                _sessionToTime[session.time.last].lastOrNull ?? Duration.zero,
              ),
            );
            periods.add(period);
          }
        }
        if (session.evenWeek) {
          for (var day in _dayOfWeekToDays[1][1][session.dayOfWeek]) {
            var period = Period(
              uid: '${session.id}${session.dayOfWeek}${session.time.first}',
              fromUid: session.id,
              type: PeriodType.classes,
              description: "教师: ${session.teacher}",
              location: session.location ?? "未知",
              summary: session.name,
              startTime: day.add(
                _sessionToTime[session.time.first].firstOrNull ?? Duration.zero,
              ),
              endTime: day.add(
                _sessionToTime[session.time.last].lastOrNull ?? Duration.zero,
              ),
            );
            periods.add(period);
          }
        }
      }
    }
    // 放假不调休的课直接去掉
    periods = periods
        .where(
          (e) => !_holidays.containsKey(
            DateTime(e.startTime.year, e.startTime.month, e.startTime.day),
          ),
        )
        .toList();
    // 调休的课，调整时间
    for (var period in periods) {
      var originalDay = DateTime(
        period.startTime.year,
        period.startTime.month,
        period.startTime.day,
      );
      if (_exchanges.containsKey(originalDay)) {
        var exchangedDay =
            _exchanges[DateTime(
              period.startTime.year,
              period.startTime.month,
              period.startTime.day,
            )]!;
        period.startTime = period.startTime.add(
          exchangedDay.difference(originalDay),
        );
        period.endTime = period.endTime.add(
          exchangedDay.difference(originalDay),
        );
      }
    }
    return periods.where((p) => p.endTime.isAfter(p.startTime)).toList();
  }
}
