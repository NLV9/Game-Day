import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'models.dart';

// ---------- Fixture sources ----------

const _keys = {
  'Maccabi Tel Aviv': 'maccabi tel aviv',
  'Real Madrid': 'real madrid',
  'Liverpool': 'liverpool',
  'Dortmund': 'dortmund',
};
String _norm(String s) => s.toLowerCase().replaceAll('-', ' ');

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

DateTime? parseUtc(String s) {
  final t = (s.endsWith('Z') || s.contains('+')) ? s : '${s}Z';
  return DateTime.tryParse(t)?.toLocal();
}

String? _sport(String s) {
  switch (s.toLowerCase()) {
    case 'soccer':
      return 'Football';
    case 'basketball':
      return 'Basketball';
    case 'handball':
      return 'Handball';
    case 'volleyball':
      return 'Volleyball';
  }
  return null;
}

/// football-data.org (free key): Real Madrid, Liverpool, Dortmund. League + Champions League.
Future<List<Game>> fetchFootballData(String token) async {
  const ids = {'Real Madrid': 86, 'Liverpool': 64, 'Dortmund': 4};
  final out = <Game>[];
  for (final e in ids.entries) {
    final r = await http.get(
      Uri.parse('https://api.football-data.org/v4/teams/${e.value}/matches?status=SCHEDULED,TIMED&limit=60'),
      headers: {'X-Auth-Token': token},
    );
    if (r.statusCode != 200) throw 'football-data.org (${e.key}): HTTP ${r.statusCode}';
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
    }
  }
  return out;
}

/// TheSportsDB free key: next games of every sport the teams play (limited number per team).
const _db = 'https://www.thesportsdb.com/api/v1/json/3';
Future<List<Game>> fetchSportsDb() async {
  const queries = {
    'Maccabi Tel Aviv': ['Maccabi Tel Aviv', 'Maccabi Tel-Aviv'],
    'Real Madrid': ['Real Madrid'],
    'Liverpool': ['Liverpool'],
    'Dortmund': ['Borussia Dortmund'],
  };
  const countries = {'Maccabi Tel Aviv': 'Israel', 'Real Madrid': 'Spain', 'Liverpool': 'England', 'Dortmund': 'Germany'};
  final skip = RegExp(r'women|ladies|u\d\d|youth|reserve');
  final out = <Game>[];
  final seen = <String>{};
  for (final e in queries.entries) {
    final team = e.key, key = _keys[team]!;
    for (final q in e.value) {
      final r = await http.get(Uri.parse('$_db/searchteams.php?t=${Uri.encodeComponent(q)}'));
      if (r.statusCode != 200) continue;
      for (final t in (jsonDecode(r.body)['teams'] as List?) ?? const []) {
        final name = _norm('${t['strTeam']}');
        final sport = _sport('${t['strSport']}');
        if (sport == null || '${t['strCountry']}' != countries[team]) continue;
        if (!name.contains(key) || skip.hasMatch(name)) continue;
        if (team != 'Maccabi Tel Aviv' && sport != 'Football') continue;
        if (!seen.add('${t['idTeam']}')) continue;
        final er = await http.get(Uri.parse('$_db/eventsnext.php?id=${t['idTeam']}'));
        if (er.statusCode != 200) continue;
        for (final ev in (jsonDecode(er.body)['events'] as List?) ?? const []) {
          final raw = ev['strTimestamp'] ?? '${ev['dateEvent']}T${ev['strTime'] ?? '00:00:00'}';
          final start = parseUtc('$raw');
          if (start == null) continue;
          final home = '${ev['strHomeTeam']}', away = '${ev['strAwayTeam']}';
          final mine = _norm(home).contains(key);
          final league = '${ev['strLeague'] ?? ''}';
          out.add(Game(
            team: team,
            sport: sport,
            comp: classify(league),
            compName: league,
            opponent: '${mine ? away : home} (${mine ? 'home' : 'away'})',
            start: start,
          ));
        }
      }
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

// ---------- App state ----------

class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  List<Game> games = [], manual = [];
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
    final ls = _p.getString('last');
    lastSync = ls == null ? null : DateTime.tryParse(ls);
    notifyListeners();
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

  Future<void> sync() async {
    if (loading) return;
    loading = true;
    status = null;
    notifyListeners();
    final errors = <String>[];
    var found = <Game>[];
    if (token.isNotEmpty) {
      try {
        found = await fetchFootballData(token);
      } catch (e) {
        errors.add('$e');
      }
    }
    try {
      found = mergeGames(found, await fetchSportsDb());
    } catch (e) {
      errors.add('TheSportsDB: $e');
    }
    final cutoff = DateTime.now().subtract(const Duration(hours: 3));
    found = found.where((g) => g.start.isAfter(cutoff)).toList();
    if (found.isNotEmpty) {
      games = found;
      lastSync = DateTime.now();
    }
    status = errors.isEmpty
        ? (token.isEmpty ? 'Synced. Add a football-data.org key in Settings for full football schedules.' : 'Synced.')
        : errors.join('\n');
    loading = false;
    save();
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
