import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'models.dart';

// ---------- Fixture sources ----------

/// Every network call gives up after 12 seconds, so a stuck request can never freeze the sync.
Future<http.Response> _get(String url, {Map<String, String>? headers}) =>
    http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 12));

/// Short report of what each source returned; shown at the top of the Games tab.
final List<String> syncLog = [];

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

/// football-data.org (optional free key): Real Madrid, Liverpool, Dortmund. League + Champions League.
Future<List<Game>> fetchFootballData(String token) async {
  const ids = {'Real Madrid': 86, 'Liverpool': 64, 'Dortmund': 4};
  final out = <Game>[];
  for (final e in ids.entries) {
    final r = await _get(
      'https://api.football-data.org/v4/teams/${e.value}/matches?status=SCHEDULED,TIMED&limit=60',
      headers: {'X-Auth-Token': token},
    );
    if (r.statusCode != 200) throw 'football-data.org (${e.key}): HTTP ${r.statusCode}';
    var n = 0;
    for (final m in (jsonDecode(r.body)['matches'] as List)) {
      final mine = m['homeTeam']['id'] == e.value;
      final opp = mine ? m['awayTeam'] : m['homeTeam'];
      final c = m['competition'];
      out.add(Game(
        team: e.key,
        sport: 'Football',
        comp: classify('${c['name']}', type: c['type'], code: c['code']),
        compName: '${c['name']}',
        opponent: '${opp['shortName'] ?? opp['name']} (${mine ? 'home' : 'away'})',
        start: DateTime.parse(m['utcDate']).toLocal(),
      ));
      n++;
    }
    syncLog.add('football-data.org ${e.key}: $n games');
  }
  return out;
}

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

Future<List<Game>> fetchCalendars(List<CalSource> sources) async {
  final out = <Game>[];
  for (final s in sources) {
    final label = '${s.team} ${s.sport} calendar';
    try {
      final url = s.url.trim().replaceFirst(RegExp(r'^webcal://', caseSensitive: false), 'https://');
      final r = await _get(url);
      if (r.statusCode != 200) {
        syncLog.add('$label: HTTP ${r.statusCode}');
        continue;
      }
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (!body.contains('BEGIN:VCALENDAR')) {
        syncLog.add('$label: not a calendar file (the link may need a login)');
        continue;
      }
      final games = parseIcs(body, s);
      syncLog.add('$label: ${games.length} games');
      out.addAll(games);
    } catch (e) {
      syncLog.add('$label: $e');
    }
  }
  return out;
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

/// Official EuroLeague schedule (no key needed). Times come from the UTC field, so they are exact.
Future<List<Game>> fetchEuroLeague() async {
  final now = DateTime.now();
  final season = 'E${now.month >= 7 ? now.year : now.year - 1}';
  final r = await http
      .get(Uri.parse('https://api-live.euroleague.net/v2/competitions/E/seasons/$season/games'))
      .timeout(const Duration(seconds: 25));
  if (r.statusCode != 200) throw 'EuroLeague: HTTP ${r.statusCode}';
  final out = <Game>[];
  for (final g in (jsonDecode(utf8.decode(r.bodyBytes))['data'] as List)) {
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
    ));
  }
  syncLog.add('EuroLeague, Maccabi basketball: ${out.length} games');
  return out;
}

// ---------- App state ----------

class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  List<Game> games = [], manual = [];
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
    if (lastSync != null) _p.setString('last', lastSync!.toIso8601String());
    notifyListeners();
  }

  List<Game> get all => [...games, ...manual]..sort((a, b) => a.start.compareTo(b.start));

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

  Future<void> sync({bool force = true}) async {
    if (loading) return;
    // At app start, do not hit the sources again if the last sync was under 3 hours ago.
    if (!force && lastSync != null && games.isNotEmpty && DateTime.now().difference(lastSync!).inHours < 3) {
      return;
    }
    loading = true;
    status = 'Syncing...';
    syncLog.clear();
    notifyListeners();
    try {
      final errors = <String>[];
      var found = <Game>[];
      try {
        found = await fetchCalendars([...builtInCals, ...cals]);
      } catch (e) {
        errors.add('Calendars: $e');
      }
      try {
        found = mergeGames(found, await fetchEuroLeague());
      } catch (e) {
        errors.add('$e');
      }
      if (token.isNotEmpty) {
        try {
          found = mergeGames(found, await fetchFootballData(token));
        } catch (e) {
          errors.add('$e');
        }
      }
      final cutoff = DateTime.now().subtract(const Duration(hours: 3));
      found = found.where((g) => g.start.isAfter(cutoff)).toList();
      if (found.isNotEmpty) {
        games = found;
        lastSync = DateTime.now();
      }
      status = [
        found.isEmpty ? 'No games found.' : 'Synced: ${found.length} games.',
        ...errors,
        ...syncLog,
      ].join('\n');
    } catch (e) {
      status = 'Sync failed: $e';
    } finally {
      loading = false;
      save();
    }
    try {
      await scheduleAlerts(this);
    } catch (e) {
      status = '${status ?? ''}\nAlerts: $e';
      notifyListeners();
    }
  }
}

String compText(Game g) => g.compName.isEmpty || g.compName == g.comp ? g.comp : '${g.comp} (${g.compName})';

String gameLine(AppState s, Game g) =>
    '${hm(g.start)} ${g.team} vs ${g.opponent}\n${g.sport} · ${compText(g)} · ${s.channelOf(g) ?? 'Channel not confirmed'}';

// ---------- Notifications ----------

final _np = FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  try {
    tzdata.initializeTimeZones();
  } catch (_) {}
  await _np.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  await _np
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
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
