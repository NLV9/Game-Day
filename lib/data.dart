import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'catalog.dart';
import 'models.dart';

/// Every source gets at most this long. A slow source never blocks the others or the app.
const sourceDeadline = Duration(seconds: 5);

Future<http.Response> _get(http.Client c, String url, {Map<String, String>? headers}) =>
    c.get(Uri.parse(url), headers: headers);

/// Short report of what each source returned (shown only under "Details").
final List<String> syncLog = [];
const appVersion = 'v10';
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
  final keys = src.keys.isNotEmpty ? src.keys : (_teamKeys[src.team] ?? [src.team.toLowerCase()]);
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
    comp: src.national ? 'International' : classify('$hint $cats ${desc.length > 120 ? desc.substring(0, 120) : desc}'),
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
/// For built-in teams it also checks that the calendar really belongs to that team.
String _parseIcsJob(Map<String, String> a) {
  final body = a['text']!;
  if (body.contains('TZID=')) {
    try {
      tzdata.initializeTimeZones();
    } catch (_) {}
  }
  final keys = (a['keys'] ?? '').isEmpty ? <String>[] : a['keys']!.split('|');
  final src = CalSource(url: '', team: a['team']!, sport: a['sport']!, keys: keys, national: a['national'] == '1');
  final games = parseIcs(body, src);
  if (a['verify'] == '1' && games.isNotEmpty) {
    final ok = games.where((g) => g.opponent.endsWith('(home)') || g.opponent.endsWith('(away)')).length;
    if (ok * 2 < games.length) return 'MISMATCH';
  }
  return jsonEncode(games.map((g) => g.toJson()).toList());
}

List<Game> _fromJsonText(String t) =>
    (jsonDecode(t) as List).map((e) => Game.fromJson(Map<String, dynamic>.from(e as Map))).toList();

Future<List<Game>> fetchCalendar(http.Client c, CalSource s, {bool verify = false}) async {
  final url = s.url.trim().replaceFirst(RegExp(r'^webcal://', caseSensitive: false), 'https://');
  final r = await _get(c, url);
  if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
  final body = utf8.decode(r.bodyBytes, allowMalformed: true);
  if (!body.contains('BEGIN:VCALENDAR')) throw 'not a calendar file (the link may need a login)';
  final text = await compute(_parseIcsJob, <String, String>{
    'text': body,
    'team': s.team,
    'sport': s.sport,
    'keys': s.keys.join('|'),
    'national': s.national ? '1' : '0',
    'verify': verify ? '1' : '0',
  });
  if (text == 'MISMATCH') throw 'schedule does not match the team name, ignored';
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
/// [a] holds the page text and a code-to-name map of the clubs being followed.
String _parseEuroJob(Map<String, String> a) {
  final codes = (jsonDecode(a['codes']!) as Map).map((k, v) => MapEntry('$k', '$v'));
  final out = <Map<String, dynamic>>[];
  for (final g in (jsonDecode(a['body']!)['data'] as List)) {
    if (g['played'] == true) continue;
    final home = g['local']['club'], away = g['road']['club'];
    final start = DateTime.tryParse('${g['utcDate']}')?.toLocal();
    if (start == null) continue;
    for (final side in [true, false]) {
      final mine = side ? home : away, opp = side ? away : home;
      final name = codes['${mine['code']}'];
      if (name == null) continue;
      out.add(Game(
        team: name,
        sport: 'Basketball',
        comp: 'Europe',
        compName: 'EuroLeague round ${g['round']}${g['confirmedHour'] == false ? ' (time TBC)' : ''}',
        opponent: '${opp['abbreviatedName'] ?? opp['name']} (${side ? 'home' : 'away'})',
        start: start,
      ).toJson());
    }
  }
  return jsonEncode(out);
}

/// Official EuroLeague schedule (no key needed). Times come from the UTC field, so they are exact.
Future<List<Game>> fetchEuroLeague(http.Client c, Map<String, String> codes) async {
  final now = DateTime.now();
  final season = 'E${now.month >= 7 ? now.year : now.year - 1}';
  final r = await _get(c, 'https://api-live.euroleague.net/v2/competitions/E/seasons/$season/games');
  if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
  final text = await compute(_parseEuroJob, <String, String>{
    'body': utf8.decode(r.bodyBytes),
    'codes': jsonEncode(codes),
  });
  return _fromJsonText(text);
}

// ---------- Israeli basketball league (official league site) ----------

/// Runs in a background isolate. The league site is plain HTML; every row reads
/// "date, time, arena, [TV], home team, away team, ...", so the page is turned into a list of
/// text pieces and each row is read from them. Times on the site are Israel time.
String _parseIlJob(Map<String, String> a) {
  final names = (jsonDecode(a['names']!) as Map).map((k, v) => MapEntry('${k}'.toLowerCase(), '$v'));
  var html = a['body']!;
  html = html.replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), ' ');
  html = html.replaceAll(RegExp(r'<[^>]+>'), '\n');
  html = html.replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&#39;', "'").replaceAll('&quot;', '"');
  final toks = html
      .split('\n')
      .map((e) => e.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((e) => e.isNotEmpty)
      .toList();
  try {
    tzdata.initializeTimeZones();
  } catch (_) {}
  final loc = tz.getLocation('Asia/Jerusalem');
  final dateRe = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$');
  final timeRe = RegExp(r'^(\d{1,2}):(\d{2})$');
  final lead = RegExp(r'^\d{1,2}:\d{2}\s');
  final headRe = RegExp(r'^game \d+$', caseSensitive: false);
  final scoreRe = RegExp(r'^\d+\s*[-–:]\s*\d+$');
  const junk = {'tickets', 'game zone', 'game-zone', 'gamezone', 'result', '-', '–', 'vs', 'live', 'details', 'buy', 'buy tickets', 'box score', 'stats', 'tv', 'arena', 'date', 'time', 'home', 'away'};
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < toks.length; i++) {
    final dm = dateRe.firstMatch(toks[i]);
    if (dm == null) continue;
    final row = <String>[];
    for (var j = i + 1; j < toks.length && row.length < 14; j++) {
      if (dateRe.hasMatch(toks[j]) || headRe.hasMatch(toks[j])) break;
      row.add(toks[j]);
    }
    if (row.isEmpty) continue;
    final tm = timeRe.firstMatch(row[0]);
    if (tm == null) continue; // kick-off time not set yet
    final cleaned = row
        .skip(1)
        .where((t) => !timeRe.hasMatch(t) && !lead.hasMatch(t) && !junk.contains(t.toLowerCase()) && !scoreRe.hasMatch(t))
        .toList();
    final rest = <String>[]; // the page repeats team names (logo text, mobile layout): keep one of each neighbour
    for (final t in cleaned) {
      if (rest.isEmpty || rest.last.toLowerCase() != t.toLowerCase()) rest.add(t);
    }
    for (var k = 0; k < rest.length; k++) {
      final mine = names[rest[k].toLowerCase()];
      if (mine == null) continue;
      final me = rest[k].toLowerCase();
      String? opp;
      var home = true;
      for (var j = k + 1; j < rest.length; j++) {
        if (rest[j].toLowerCase() != me && rest[j].length >= 4) {
          opp = rest[j];
          break;
        }
      }
      if (opp == null) {
        home = false;
        for (var j = k - 1; j >= 0; j--) {
          if (rest[j].toLowerCase() != me && rest[j].length >= 4) {
            opp = rest[j];
            break;
          }
        }
      }
      if (opp == null) continue;
      final tvIdx = home ? k - 1 : k - 2;
      final tv = tvIdx >= 0 && rest[tvIdx].length <= 24 ? rest[tvIdx] : null;
      final t = tz.TZDateTime(loc, int.parse(dm[3]!), int.parse(dm[2]!), int.parse(dm[1]!), int.parse(tm[1]!), int.parse(tm[2]!));
      out.add(Game(
        team: mine,
        sport: 'Basketball',
        comp: 'League',
        compName: 'Israeli Winner League',
        opponent: '$opp (${home ? 'home' : 'away'})',
        start: DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch),
        channel: tv,
      ).toJson());
    }
  }
  return jsonEncode(out);
}

Future<List<Game>> fetchIsraeliLeague(http.Client c, Map<String, String> names) async {
  final r = await _get(c, 'https://basket.co.il/results.asp?lang=en');
  if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
  final text = await compute(_parseIlJob, <String, String>{
    'body': utf8.decode(r.bodyBytes, allowMalformed: true),
    'names': jsonEncode(names),
  });
  return _fromJsonText(text);
}

// ---------- App state ----------

class _Job {
  final String key, label;
  final Future<List<Game>> Function(http.Client) run;
  const _Job(this.key, this.label, this.run);
}

class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  List<Game> games = [], manual = [];
  Map<String, List<Game>> bySrc = {}; // last good result of each source
  List<Game>? _allCache;
  String alertsNote = '';
  List<CalSource> cals = [];
  String token = '', channelMap = '', tv = 'all';
  int evStart = 18, evEnd = 23;
  Set<String> followed = {...defaultFollowed}; // Club.id values
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
    final ids = catalog.map((c) => c.id).toSet();
    followed = (_p.getStringList('follow') ?? defaultFollowed).where(ids.contains).toSet(); // blocked teams never load
    fTeams = (_p.getStringList('ft') ?? teams).toSet();
    fSports = (_p.getStringList('fs') ?? sports).toSet();
    fComps = (_p.getStringList('fc') ?? comps).toSet();
    if (!_p.containsKey('fcv')) {
      fComps.add('International'); // new competition type added in this version
      _p.setInt('fcv', 1);
    }
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
    _p.setStringList('follow', followed.toList());
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
      !isBlocked(g.team) &&
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

  List<Club> get followedClubs => [for (final c in catalog) if (followed.contains(c.id)) c];

  /// Names of the followed teams, for the filters and the "add a game" form.
  List<String> get teamNames {
    final n = {for (final c in followedClubs) c.name}.toList()..sort();
    return n.isEmpty ? ['Other'] : n;
  }

  bool isFollowed(Club c) => followed.contains(c.id);

  void toggleFollow(Club c) {
    if (isBlocked(c.name, c.country)) return;
    if (followed.contains(c.id)) {
      followed.remove(c.id);
      if (!followedClubs.any((x) => x.name == c.name)) fTeams.remove(c.name);
      _rebuild();
    } else {
      followed.add(c.id);
      fTeams.add(c.name);
    }
    save();
  }

  /// What to ask the internet for, one job per source. Used by sync and by the "is it stale" check.
  List<_Job> _plan() {
    final jobs = <_Job>[];
    final seen = <String>{};
    final codes = <String, String>{};
    final il = <String, String>{};
    for (final c in followedClubs) {
      if (c.fm != null && seen.add('fm:${c.fm}')) {
        final src = CalSource(
          url: 'https://pub.fotmob.com/prod/pub/api/v2/calendar/team/${c.fm}.ics',
          team: c.name,
          sport: c.sport,
          keys: c.keys,
          national: c.league == 'National teams',
        );
        jobs.add(_Job('fm:${c.fm}', '${c.name} ${c.sport}', (h) => fetchCalendar(h, src, verify: true)));
      }
      if (c.el != null) codes[c.el!] = c.name;
      if (c.il != null) il[c.il!] = c.name;
    }
    if (codes.isNotEmpty) jobs.add(_Job('euroleague', 'EuroLeague', (h) => fetchEuroLeague(h, codes)));
    if (il.isNotEmpty) jobs.add(_Job('il:${il.values.toList()..sort()}', 'Israeli basketball league', (h) => fetchIsraeliLeague(h, il)));
    for (final s in cals) {
      jobs.add(_Job('cal:${s.url}', '${s.team} ${s.sport} calendar', (h) => fetchCalendar(h, s)));
    }
    if (token.isNotEmpty) {
      for (final e in footballDataIds.entries) {
        jobs.add(_Job('fd:${e.key}', 'football-data.org ${e.key}', (h) => fetchFootballDataTeam(h, token, e.key, e.value)));
      }
    }
    return jobs;
  }

  /// Combines the last good result of every source into the list the screens show.
  void _rebuild() {
    final active = _plan().map((j) => j.key).toSet();
    bySrc.removeWhere((k, _) => !active.contains(k));
    final cutoff = DateTime.now().subtract(const Duration(hours: 3));
    var found = <Game>[];
    for (final list in bySrc.values) {
      found = mergeGames(found, list.where((g) => g.start.isAfter(cutoff) && !isBlocked(g.team)).toList());
    }
    games = found;
    _allCache = null;
  }

  /// Refresh from the internet. The screen keeps showing the saved games meanwhile, and each
  /// source updates the list the moment it answers. No source may take longer than 5 seconds.
  /// Without [force] (app start) it only runs when nothing is saved or the data is over 12 hours old.
  bool _again = false;

  Future<void> sync({bool force = true}) async {
    if (loading) {
      if (force) _again = true; // run once more when the current round ends
      return;
    }
    if (!force &&
        games.isNotEmpty &&
        lastSync != null &&
        DateTime.now().difference(lastSync!).inHours < 12 &&
        _plan().every((j) => bySrc.containsKey(j.key))) {
      return;
    }
    loading = true;
    syncLog.clear();
    status = games.isEmpty ? 'Loading schedule...' : 'Updating schedule...';
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
          _log('$label: timed out, saved schedule kept');
        } catch (e) {
          bad++;
          _log('$label: $e');
        }
      }());
    }

    try {
      for (final j in _plan()) {
        add(j.key, j.label, () => j.run(client));
      }
      await Future.wait(jobs);
      if (ok > 0) lastSync = DateTime.now();
      status = ok == 0
          ? 'Unable to reach the data sources. Showing the saved schedule.'
          : bad == 0
              ? 'Updated just now · ${games.length} games'
              : 'Updated · ${games.length} games ($bad source(s) did not respond; saved data kept)';
    } catch (e) {
      status = 'Update failed. Showing the saved schedule.';
      _log('$e');
    } finally {
      client.close();
      loading = false;
      save();
    }
    _alertsInBackground();
    if (_again) {
      _again = false;
      sync();
    }
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

/// Opponent without the "(home)"/"(away)" suffix, and the venue word for the team followed.
String oppName(Game g) => g.opponent.replaceFirst(RegExp(r'\s*\((home|away)\)$'), '');
String? venue(Game g) => g.opponent.endsWith('(home)') ? 'Home' : (g.opponent.endsWith('(away)') ? 'Away' : null);

String compText(Game g) => g.compName.isEmpty || g.compName == g.comp ? g.comp : '${g.comp} (${g.compName})';

String gameLine(AppState s, Game g) =>
    '${hm(g.start)} ${g.team} vs ${oppName(g)}${venue(g) == null ? '' : ' (${venue(g)})'}\n${g.sport} · ${compText(g)} · ${s.channelOf(g) ?? 'TV channel TBC'}';

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
      await _at(sun, 100000000 + num, 'Your week ahead',
          free.isEmpty ? 'No free evenings this week.' : 'Free evenings this week: ${free.join(', ')}');
    }
  }
}
