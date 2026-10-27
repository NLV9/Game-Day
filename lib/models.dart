const teams = ['Maccabi Tel Aviv', 'Real Madrid', 'Liverpool', 'Dortmund'];
const sports = ['Football', 'Basketball', 'Handball', 'Volleyball'];
const comps = ['League', 'Champions League', 'Domestic cup', 'Europe'];
const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

class Game {
  final String team, sport, comp, compName, opponent;
  final DateTime start; // always local time
  final String? channel; // manual override
  final bool manual;
  const Game({
    required this.team,
    required this.sport,
    required this.comp,
    required this.compName,
    required this.opponent,
    required this.start,
    this.channel,
    this.manual = false,
  });

  Map<String, dynamic> toJson() => {
        't': team, 's': sport, 'c': comp, 'cn': compName, 'o': opponent,
        'd': start.toUtc().toIso8601String(), 'ch': channel, 'm': manual,
      };

  factory Game.fromJson(Map<String, dynamic> j) => Game(
        team: j['t'], sport: j['s'], comp: j['c'], compName: j['cn'] ?? '',
        opponent: j['o'], start: DateTime.parse(j['d']).toLocal(),
        channel: j['ch'], manual: j['m'] ?? false,
      );
}

String hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
String dayLabel(DateTime d) => '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';
String monthLabel(DateTime d) => '${_mo[d.month - 1]} ${d.year}';
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
