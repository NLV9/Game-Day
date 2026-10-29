import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'models.dart';

/// Every source gets at most this long. A slow source never blocks the others or the app.
const sourceDeadline = Duration(seconds: 5);

Future<http.Response> _get(http.Client c, String url, {Map<String, String>? headers}) =>
    c.get(Uri.parse(url), headers: headers);

/// Short report of what each source returned (shown only under "Details").
final List<String> syncLog = [];
const appVersion = 'v6';
void _log(String line) => syncLog.add(line);

String classify(String name, {String? type, String? code}) {
  final n = name.toLowerCase();
  if (code == 'CL' || n.contains('champions league')) return 'Champions League';
  if (n.contains('europa') || n.contains('conference') || n.contains('euroleague') ||
      n.contains('eurocup') || n.contains('european') || n.contains('ehf')) {
    return 'Europe';
  }
  if (type == 'CUP' || n.contains('cup') || n.contains('copa') || n.contains('pokal') || n.contains('trophy')) {
    return 'Domestic cup';
  }
  return 'League';
}

/// football-data.org (optional free key): one team per call, run in parallel.
Future<List<Game>> fetchFootballDataTeam(http.Client c, String token, String team, int id) async {
  final r = await _get(
    c,
    'https://api.football-data.org/v4/teams/$id/matches?status=SCHEDULED,TIMED&limit=60',
    headers: {'X-Auth-Token': token},
  );
  if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
  final out = <Game>[];
  for (final m in (jsonDecode(r.body)['matches'] as List)) {
    final mine = m['homeTeam']['id'] == id;
    final opp = mine ? m['awayTeam'] : m['homeTeam'];
    final comp = m['competition'];
    out.add(Game(
      team: team,
      sport: 'Football',
      comp: classify('${comp['name']}', type: comp['type'], code: comp['code']),
      compName: '${comp['name']}',
      opponent: '${opp['shortName'] ?? opp['name']} (${mine ? 'home' : 'away'})',
      start: DateTime.parse(m['utcDate']).toLocal(),
    ));
  }
  return out;
}

const footballDataIds = {'Real Madrid': 86, 'Liverpool': 64, 'Dortmund': 4};

// ---------- Calendar links (.ics) ----------

/// Built-in sources, always on. FotMob publishes a public fixtures calendar for every club
/// (league, cups and European games). The numbers are FotMob's team ids.
const builtInCals = [
  CalSource(url: 'https://pub.fotmob.com/prod/pub/api/v2/calendar/team/8650.ics', team: 'Liverpool', sport: 'Football'),
  CalSource(url: 'https://pub.fotmob.com/prod/pub/api/v2/calendar/team/8633.ics', team: 'Real Madrid', sport: 'Football'),
  CalSource(url: 'https://pub.fotmob.com/prod/pub/api/v2/calendar/team/9789.ics', team: 'Dortmund', sport: 'Football'),
  CalSource(url: 'https://pub.fotmob.com/prod/pub/api/v2/calendar/team/7855.ics', team: 'Maccabi Tel Aviv', sport: 'Football'),
];


const _teamKeys = {
  'Maccabi Tel Aviv': ['maccabi tel aviv', 'maccabi ta', 'מכבי תל אביב', 'מכבי ת"א'],
  'Real Madrid': ['real madrid', 'ריאל מדריד'],
  'Liverpool': ['liverpool', 'ליברפול'],
  'Dortmund': ['dortmund', 'bvb', 'דורטמונד'],
};
final _sep = RegExp(r'\s+(?:v|vs\.?|-|–|—|x)\s+', caseSensitive: false);

String _unesc(String s) =>
    s.replaceAll(r'\n', ' ').replaceAll(r'\N', ' ').replaceAll(r'\,', ',').replaceAll(r'\;', ';');

String _stripParen(String t, List<String> found) {
  final m = RegExp(r'^(.*?)\s*\(([^()]*)\)\s*$').firstMatch(t);
  if (m == null) return t;
  found.add(m[2]!.trim());
  return m[1]!.trim();
}

String _clean(String s) => s.replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '').trim();

DateTime? _icsStart(String v, String params) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z?)$').firstMatch(v.trim());
  if (m == null) return null; // all-day events have no kick-off time, so they are skipped
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final h = int.parse(m[4]!), mi = int.parse(m[5]!), sec = int.parse(m[6] ?? '0');
  if (m[7] == 'Z') return DateTime.utc(y, mo, d, h, mi, sec).toLocal();
  final tzm = RegExp(r'TZID=([^;:]+)', caseSensitive: false).firstMatch(params);
  if (tzm != null) {
    try {
      final loc = tz.getLocation(tzm[1]!.replaceAll('"', ''));
      final t = tz.TZDateTime(loc, y, mo, d, h, mi, sec);
      return DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch);
    } catch (_) {}
  }
  return DateTime(y, mo, d, h, mi, sec);
}

Game? _icsGame(Map<String, String> ev, CalSource src) {
  if ((ev['STATUS'] ?? '').toUpperCase() == 'CANCELLED') return null;
  final start = _icsStart(ev['DTSTART'] ?? '', ev['DTSTART_PARAMS'] ?? '');
  if (start == null) return null;
  final summary = _unesc(ev['SUMMARY'] ?? '').trim();
  if (summary.isEmpty) return null;
  var s = summary;
  var hint = '';
  final ci = s.indexOf(': ');
  if (ci > 0 && !_sep.hasMatch(s.substring(0, ci))) {
    hint = s.substring(0, ci).trim();
    s = s.substring(ci + 2);
  }
  final keys = _teamKeys[src.team] ?? [src.team.toLowerCase()];
  bool mine(String t) {
    final n = t.toLowerCase().replaceAll('-', ' ');
    return keys.any((k) => n.contains(k));
  }

  final extra = <String>[];
  final parts = s.split(_sep);
  String opponent;
  if (parts.length >= 2) {
    final a = _clean(_stripParen(parts[0], extra)), b = _clean(_stripParen(parts[1], extra));
    if (parts.length >= 3 && hint.isEmpty) hint = parts[2].trim();
    if (mine(a)) {
      opponent = '$b (home)';
    } else if (mine(b)) {
      opponent = '$a (away)';
    } else {
      opponent = _clean(s);
    }
  } else {
    opponent = _clean(_stripParen(s, extra));
  }
  if (hint.isEmpty) {
    for (final e in extra) {
      if (e.length > 3) {
        hint = e;
        break;
      }
    }
  }
  final cats = _unesc(ev['CATEGORIES'] ?? '');
  final desc = _unesc(ev['DESCRIPTION'] ?? '');
  final compName = hint.isNotEmpty ? hint : cats;
  return Game(
    team: src.team,
    sport: src.sport,
    comp: classify('$hint $cats ${desc.length > 120 ? desc.substring(0, 120) : desc}'),
    compName: compName,
    opponent: opponent,
    start: start,
  );
}

List<Game> parseIcs(String text, CalSource src) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'\n[ \t]'), '')
      .split('\n');
  final out = <Game>[];
  Map<String, String>? ev;
  var alarm = false;
  for (final raw in lines) {
    final line = raw.trimRight();
    if (line == 'BEGIN:VEVENT') {
      ev = {};
      alarm = false;
      continue;
    }
    if (line == 'END:VEVENT') {
      if (ev != null) {
        final g = _icsGame(ev, src);
        if (g != null) out.add(g);
      }
      ev = null;
      continue;
    }
    if (ev == null) continue;
    if (line == 'BEGIN:VALARM') {
      alarm = true;
      continue;
    }
    if (line == 'END:VALARM') {
      alarm = false;
      continue;
    }
    if (alarm) continue;
    final i = line.indexOf(':');
    if (i < 1) continue;
    final name = line.substring(0, i);
    final key = name.split(';').first.toUpperCase();
    ev[key] = line.substring(i + 1);
    if (key == 'DTSTART') ev['DTSTART_PARAMS'] = name;
  }
  return out;
}

/// Runs in a background isolate so reading a big file never freezes the screen.
String _parseIcsJob(Map<String, String> a) {
  final body = a['text']!;
  if (body.contains('TZID=')) {
    try {
      tzdata.initializeTimeZones();
    } catch (_) {}
  }
  final src = CalSource(url: '', team: a['team']!, sport: a['sport']!);
  return jsonEncode(parseIcs(body, src).map((g) => g.toJson()).toList());
}

List<Game> _fromJsonText(String t) =>
    (jsonDecode(t) as List).map((e) => Game.fromJson(Map<String, dynamic>.from(e as Map))).toList();

Future<List<Game>> fetchCalendar(http.Client c, CalSource s) async {
  final url = s.url.trim().replaceFirst(RegExp(r'^webcal://', caseSensitive: false), 'https://');
  final r = await _get(c, url);
  if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
  final body = utf8.decode(r.bodyBytes, allowMalformed: true);
  if (!body.contains('BEGIN:VCALENDAR')) throw 'not a calendar file (the link may need a login)';
  final text = await compute(_parseIcsJob, <String, String>{'text': body, 'team': s.team, 'sport': s.sport});
  return _fromJsonText(text);
}

List<Game> mergeGames(List<Game> a, List<Game> b) {
  final out = [...a];
  for (final g in b) {
    final dup = out.any((x) => x.team == g.team && x.sport == g.sport && x.start.difference(g.start).inHours.abs() < 3);
    if (!dup) out.add(g);
  }
  return out;
}

// ---------- EuroLeague (Maccabi Tel Aviv basketball) ----------

/// Runs in a background isolate: the EuroLeague file is large (about 700 KB).
String _parseEuroJob(String body) {
  final out = <Map<String, dynamic>>[];
  for (final g in (jsonDecode(body)['data'] as List)) {
    if (g['played'] == true) continue;
    final home = g['local']['club'], away = g['road']['club'];
    final homeMine = home['code'] == 'TEL';
    if (!homeMine && away['code'] != 'TEL') continue;
    final start = DateTime.tryParse('${g['utcDate']}')?.toLocal();
    if (start == null) continue;
    final opp = homeMine ? away : home;
    out.add(Game(
      team: 'Maccabi Tel Aviv',
      sport: 'Basketball',
      comp: 'Europe',
      compName: 'EuroLeague round ${g['round']}${g['confirmedHour'] == false ? ' (time TBC)' : ''}',
      opponent: '${opp['abbreviatedName'] ?? opp['name']} (${homeMine ? 'home' : 'away'})',
      start: start,
    ).toJson());
  }
  return jsonEncode(out);
}

/// Official EuroLeague schedule (no key needed). Times come from the UTC field, so they are exact.
Future<List<Game>> fetchEuroLeague(http.Client c) async {
  final now = DateTime.now();
  final season = 'E${now.month >= 7 ? now.year : now.year - 1}';
  final r = await _get(c, 'https://api-live.euroleague.net/v2/competitions/E/seasons/$season/games');
  if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
  final text = await compute(_parseEuroJob, utf8.decode(r.bodyBytes));
  return _fromJsonText(text);
}

// ---------- App state ----------

class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  List<Game> games = [], manual = [];
  Map<String, List<Game>> bySrc = {}; // last good result of each source
  List<Game>? _allCache;
  String alertsNote = '';
  List<CalSource> cals = [];
  String token = '', channelMap = '', tv = 'all';
  int evStart = 18, evEnd = 23;
  Set<String> fTeams = {...teams}, fSports = {...sports}, fComps = {...comps};
  DateTimeRange? range;
  bool loading = false;
  String? status;
  DateTime? lastSync;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    token = _p.getString('token') ?? '';
    channelMap = _p.getString('map') ?? '';
    tv = _p.getString('tv') ?? 'all';
    evStart = _p.getInt('evs') ?? 18;
    evEnd = _p.getInt('eve') ?? 23;
    fTeams = (_p.getStringList('ft') ?? teams).toSet();
    fSports = (_p.getStringList('fs') ?? sports).toSet();
    fComps = (_p.getStringList('fc') ?? comps).toSet();
    games = _read('games');
    manual = _read('manual');
    bySrc = _readBySrc();
    _allCache = null;
    cals = _readCals();
    final ls = _p.getString('last');
    lastSync = ls == null ? null : DateTime.tryParse(ls);
    notifyListeners();
  }

  List<CalSource> _readCals() {
    final s = _p.getString('cals');
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List).map((e) => CalSource.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, List<Game>> _readBySrc() {
    final s = _p.getString('bysrc');
    if (s == null) return {};
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(
          k, (v as List).map((e) => Game.fromJson(Map<String, dynamic>.from(e as Map))).toList()));
    } catch (_) {
      return {};
    }
  }

  List<Game> _read(String k) {
    final s = _p.getString(k);
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List).map((e) => Game.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  void save() {
    _p.setString('token', token);
    _p.setString('map', channelMap);
    _p.setString('tv', tv);
    _p.setInt('evs', evStart);
    _p.setInt('eve', evEnd);
    _p.setStringList('ft', fTeams.toList());
    _p.setStringList('fs', fSports.toList());
    _p.setStringList('fc', fComps.toList());
    _p.setString('games', jsonEncode(games.map((g) => g.toJson()).toList()));
    _p.setString('manual', jsonEncode(manual.map((g) => g.toJson()).toList()));
    _p.setString('cals', jsonEncode(cals.map((c) => c.toJson()).toList()));
    _p.setString('bysrc', jsonEncode(bySrc.map((k, v) => MapEntry(k, v.map((g) => g.toJson()).toList()))));
    _allCache = null;
    if (lastSync != null) _p.setString('last', lastSync!.toIso8601String());
    notifyListeners();
  }

  List<Game> get all => _allCache ??= ([...games, ...manual]..sort((a, b) => a.start.compareTo(b.start)));

  String? channelOf(Game g) {
    if (g.channel != null && g.channel!.isNotEmpty) return g.channel;
    final hay = '${g.team} ${g.sport} ${g.compName} ${g.comp}'.toLowerCase();
    for (final line in channelMap.split('\n')) {
      final i = line.indexOf('=');
      if (i < 1) continue;
      if (hay.contains(line.substring(0, i).trim().toLowerCase())) {
        final c = line.substring(i + 1).trim();
        if (c.isNotEmpty) return c;
      }
    }
    return null;
  }

  bool pass(Game g) =>
      fTeams.contains(g.team) &&
      fSports.contains(g.sport) &&
      fComps.contains(g.comp) &&
      (tv == 'all' || (tv == 'yes') == (channelOf(g) != null));

  List<Game> get filtered => all.where(pass).toList();

  bool isEvening(Game g) {
    final a = g.start.hour * 60 + g.start.minute; // games are assumed to last 2 hours
    return a < evEnd * 60 && a + 120 > evStart * 60;
  }

  List<Game> eveningGames(DateTime day, {bool useFilters = true}) =>
      all.where((g) => dayOnly(g.start) == day && isEvening(g) && (!useFilters || pass(g))).toList();

  void resetFilters() {
    fTeams = {...teams};
    fSports = {...sports};
    fComps = {...comps};
    tv = 'all';
    save();
  }

  /// Combines the last good result of every source into the list the screens show.
  void _rebuild() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 3));
    var found = <Game>[];
    for (final list in bySrc.values) {
      found = mergeGames(found, list.where((g) => g.start.isAfter(cutoff)).toList());
    }
    games = found;
    _allCache = null;
  }

  /// Refresh from the internet. The screen keeps showing the saved games meanwhile, and each
  /// source updates the list the moment it answers. No source may take longer than 5 seconds.
  /// Without [force] (app start) it only runs when nothing is saved or the data is over 12 hours old.
  Future<void> sync({bool force = true}) async {
    if (loading) return;
    if (!force && games.isNotEmpty && lastSync != null && DateTime.now().difference(lastSync!).inHours < 12) {
      return;
    }
    loading = true;
    syncLog.clear();
    status = games.isEmpty ? 'Loading games...' : 'Updating...';
    notifyListeners();
    final client = http.Client();
    var ok = 0, bad = 0;
    final jobs = <Future<void>>[];

    void add(String key, String label, Future<List<Game>> Function() run) {
      jobs.add(() async {
        try {
          final r = await run().timeout(sourceDeadline);
          bySrc[key] = r;
          ok++;
          _log('$label: ${r.length} games');
          _rebuild();
          notifyListeners();
        } on TimeoutException {
          bad++;
          _log('$label: too slow, kept saved games');
        } catch (e) {
          bad++;
          _log('$label: $e');
        }
      }());
    }

    try {
      for (final s in [...builtInCals, ...cals]) {
        add('cal:${s.url}', '${s.team} ${s.sport} calendar', () => fetchCalendar(client, s));
      }
      add('euroleague', 'EuroLeague, Maccabi basketball', () => fetchEuroLeague(client));
      if (token.isNotEmpty) {
        for (final e in footballDataIds.entries) {
          add('fd:${e.key}', 'football-data.org ${e.key}', () => fetchFootballDataTeam(client, token, e.key, e.value));
        }
      }
      await Future.wait(jobs);
      if (ok > 0) lastSync = DateTime.now();
      status = ok == 0
          ? 'Could not reach the sources. Showing saved games.'
          : bad == 0
              ? 'Updated just now: ${games.length} games.'
              : 'Updated: ${games.length} games ($bad source(s) did not answer, saved data kept).';
    } catch (e) {
      status = 'Update failed, showing saved games.';
      _log('$e');
    } finally {
      client.close();
      loading = false;
      save();
    }
    _alertsInBackground();
  }

  bool _scheduling = false;

  void rescheduleAlerts() => _alertsInBackground();

  /// Notifications are set up after the screen is already updated, and never block it.
  void _alertsInBackground() {
    if (_scheduling) return;
    _scheduling = true;
    scheduleAlerts(this).then((_) {
      alertsNote = '';
    }).catchError((Object e) {
      alertsNote = 'Alerts could not be set: $e';
    }).whenComplete(() {
      _scheduling = false;
      notifyListeners();
    });
  }
}

String compText(Game g) => g.compName.isEmpty || g.compName == g.comp ? g.comp : '${g.comp} (${g.compName})';

String gameLine(AppState s, Game g) =>
    '${hm(g.start)} ${g.team} vs ${g.opponent}\n${g.sport} · ${compText(g)} · ${s.channelOf(g) ?? 'Channel not confirmed'}';

// ---------- Notifications ----------

final _np = FlutterLocalNotificationsPlugin();

Future<void>? notifInit;

/// Started without waiting, so the app opens instantly.
void startNotifications() {
  notifInit = initNotifications().catchError((Object _) {});
}

Future<void> initNotifications() async {
  try {
    tzdata.initializeTimeZones();
  } catch (_) {}
  await _np.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  // Not awaited: the permission pop-up must never block the app.
  _np.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
}

Future<void> _at(DateTime t, int id, String title, String body) => _np.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(t, tz.UTC),
      NotificationDetails(
        android: AndroidNotificationDetails(
          'gameday',
          'Game day alerts',
          importance: Importance.high,
          priority: Priority.high,
          color: const Color(0xFF0B3D91),
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );

/// Game day alert at 11:00 and Sunday free-evening summary at 10:00, for the next 60 days.
Future<void> scheduleAlerts(AppState s) async {
  await notifInit;
  await _np.cancelAll();
  final now = DateTime.now();
  final today = dayOnly(now);
  for (var i = 0; i < 60; i++) {
    final day = DateTime(today.year, today.month, today.day + i);
    final num = day.year * 10000 + day.month * 100 + day.day;
    final gs = s.all.where((g) => dayOnly(g.start) == day).toList();
    final at = DateTime(day.year, day.month, day.day, 11);
    if (gs.isNotEmpty && at.isAfter(now)) {
      await _at(at, num, gs.length == 1 ? 'Game day' : 'Game day: ${gs.length} games',
          gs.map((g) => gameLine(s, g)).join('\n\n'));
    }
    final sun = DateTime(day.year, day.month, day.day, 10);
    if (day.weekday == DateTime.sunday && sun.isAfter(now)) {
      final free = <String>[];
      for (var j = 0; j < 7; j++) {
        final d = DateTime(day.year, day.month, day.day + j);
        if (s.eveningGames(d, useFilters: false).isEmpty) free.add(dayLabel(d));
      }
      await _at(sun, 100000000 + num, 'Your week',
          free.isEmpty ? 'No free evening this week.' : 'Free evenings this week: ${free.join(', ')}');
    }
  }
}
