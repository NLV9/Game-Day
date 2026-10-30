import 'models.dart';

/// One team a person can follow. Where its schedule comes from:
/// [fm] FotMob team calendar, [el] EuroLeague club code, [il] name on the Israeli league site.
class Club {
  final String name, sport, league, country;
  final int? fm;
  final String? el, il;
  final List<String> alias;
  const Club(this.name, this.sport, this.league, this.country, {this.fm, this.el, this.il, this.alias = const []});
  String get id => '$sport|$name';
  bool get hasSource => fm != null || el != null || il != null;
  List<String> get keys => [name.toLowerCase(), ...alias];
}

// ---------- Blocked teams (built into the code; no setting can switch this off) ----------

const _arabCountries = {
  'algeria', 'bahrain', 'comoros', 'djibouti', 'egypt', 'iraq', 'jordan', 'kuwait', 'lebanon',
  'libya', 'mauritania', 'morocco', 'oman', 'palestine', 'qatar', 'saudi arabia', 'somalia',
  'sudan', 'syria', 'tunisia', 'united arab emirates', 'uae', 'yemen',
};

/// Israeli Arab clubs and Hapoel Tel Aviv, matched on words inside the team name.
final _blockedNames = RegExp(
  r"hapoel\s+(?:ibi\s+|irony\s+|ironi\s+)?tel[\s-]?aviv|הפועל\s+תל[\s-]?אביב|"
  r"sakhnin|סכנין|umm\s+al[\s-]?fahm|אום\s+אל|kafr\s+qasim|kafr\s+kasim|כפר\s+קאסם|"
  r"tayibe|taibe|טייבה|arraba|ערבה|bnei\s+reineh|bnei\s+raina|בני\s+ריינה|ahi\s+nazareth|אחי\s+נצרת|"
  r"kafr\s+kanna|kabilio|shefa[\s-]?amr|שפרעם|tamra|טמרה|baqa|באקה|iksal|majd\s+al|deir\s+hanna|"
  r"nazareth|נצרת|abu\s+snan|bnei\s+yafa|jisr|ג'סר",
  caseSensitive: false,
);

bool isBlocked(String name, [String country = '']) {
  final n = name.toLowerCase().trim();
  final c = country.toLowerCase().trim();
  if (_arabCountries.contains(n) || _arabCountries.contains(c)) return true;
  return _blockedNames.hasMatch(name);
}

// ---------- Teams we can really get schedules for ----------

const sportOrder = ['Football', 'Basketball', 'Handball', 'Volleyball'];

const _all = <Club>[
  // Football: Premier League
  Club('Arsenal', 'Football', 'Premier League', 'England', fm: 9825),
  Club('Aston Villa', 'Football', 'Premier League', 'England', fm: 10252),
  Club('Bournemouth', 'Football', 'Premier League', 'England', fm: 8678),
  Club('Brentford', 'Football', 'Premier League', 'England', fm: 9937),
  Club('Brighton', 'Football', 'Premier League', 'England', fm: 10204),
  Club('Burnley', 'Football', 'Premier League', 'England', fm: 8191),
  Club('Chelsea', 'Football', 'Premier League', 'England', fm: 8455),
  Club('Crystal Palace', 'Football', 'Premier League', 'England', fm: 9826),
  Club('Everton', 'Football', 'Premier League', 'England', fm: 8668),
  Club('Fulham', 'Football', 'Premier League', 'England', fm: 9879),
  Club('Leeds United', 'Football', 'Premier League', 'England', fm: 8463, alias: ['leeds']),
  Club('Liverpool', 'Football', 'Premier League', 'England', fm: 8650),
  Club('Manchester City', 'Football', 'Premier League', 'England', fm: 8456, alias: ['man city']),
  Club('Manchester United', 'Football', 'Premier League', 'England', fm: 10260, alias: ['man united', 'man utd']),
  Club('Newcastle United', 'Football', 'Premier League', 'England', fm: 10261, alias: ['newcastle']),
  Club('Nottingham Forest', 'Football', 'Premier League', 'England', fm: 10203, alias: ["nott'm forest", 'nottm forest', 'forest']),
  Club('Sunderland', 'Football', 'Premier League', 'England', fm: 8472),
  Club('Tottenham Hotspur', 'Football', 'Premier League', 'England', fm: 8586, alias: ['tottenham', 'spurs']),
  Club('West Ham United', 'Football', 'Premier League', 'England', fm: 8654, alias: ['west ham']),
  Club('Wolverhampton Wanderers', 'Football', 'Premier League', 'England', fm: 8602, alias: ['wolves', 'wolverhampton']),
  // La Liga
  Club('Real Madrid', 'Football', 'La Liga', 'Spain', fm: 8633, alias: ['ריאל מדריד']),
  Club('Barcelona', 'Football', 'La Liga', 'Spain', fm: 8634, alias: ['barca', 'barça']),
  Club('Atletico Madrid', 'Football', 'La Liga', 'Spain', fm: 9906, alias: ['atletico', 'atlético']),
  Club('Sevilla', 'Football', 'La Liga', 'Spain', fm: 8302),
  Club('Valencia', 'Football', 'La Liga', 'Spain', fm: 10267),
  Club('Villarreal', 'Football', 'La Liga', 'Spain', fm: 10205),
  Club('Real Betis', 'Football', 'La Liga', 'Spain', fm: 8603, alias: ['betis']),
  Club('Athletic Club', 'Football', 'La Liga', 'Spain', fm: 8315, alias: ['athletic']),
  Club('Real Sociedad', 'Football', 'La Liga', 'Spain', fm: 8560, alias: ['sociedad']),
  Club('Celta Vigo', 'Football', 'La Liga', 'Spain', fm: 9910, alias: ['celta']),
  Club('Osasuna', 'Football', 'La Liga', 'Spain', fm: 8371),
  Club('Getafe', 'Football', 'La Liga', 'Spain', fm: 8305),
  Club('Girona', 'Football', 'La Liga', 'Spain', fm: 7732),
  Club('Rayo Vallecano', 'Football', 'La Liga', 'Spain', fm: 8370, alias: ['rayo']),
  Club('Mallorca', 'Football', 'La Liga', 'Spain', fm: 8661),
  Club('Espanyol', 'Football', 'La Liga', 'Spain', fm: 8558),
  Club('Alaves', 'Football', 'La Liga', 'Spain', fm: 9866, alias: ['alavés']),
  // Bundesliga
  Club('Dortmund', 'Football', 'Bundesliga', 'Germany', fm: 9789, alias: ['borussia dortmund', 'bvb', 'דורטמונד']),
  Club('Bayern Munich', 'Football', 'Bundesliga', 'Germany', fm: 9823, alias: ['bayern']),
  Club('Bayer Leverkusen', 'Football', 'Bundesliga', 'Germany', fm: 8178, alias: ['leverkusen']),
  Club('RB Leipzig', 'Football', 'Bundesliga', 'Germany', fm: 178475, alias: ['leipzig']),
  Club('Eintracht Frankfurt', 'Football', 'Bundesliga', 'Germany', fm: 9810, alias: ['frankfurt']),
  Club('VfB Stuttgart', 'Football', 'Bundesliga', 'Germany', fm: 10269, alias: ['stuttgart']),
  Club('VfL Wolfsburg', 'Football', 'Bundesliga', 'Germany', fm: 8721, alias: ['wolfsburg']),
  Club('Borussia Monchengladbach', 'Football', 'Bundesliga', 'Germany', fm: 9788, alias: ['gladbach', 'monchengladbach', 'mönchengladbach']),
  Club('SC Freiburg', 'Football', 'Bundesliga', 'Germany', fm: 8358, alias: ['freiburg']),
  Club('Union Berlin', 'Football', 'Bundesliga', 'Germany', fm: 8149),
  Club('Werder Bremen', 'Football', 'Bundesliga', 'Germany', fm: 8697, alias: ['bremen']),
  Club('Mainz 05', 'Football', 'Bundesliga', 'Germany', fm: 9905, alias: ['mainz']),
  Club('Hoffenheim', 'Football', 'Bundesliga', 'Germany', fm: 8226),
  Club('FC Augsburg', 'Football', 'Bundesliga', 'Germany', fm: 8406, alias: ['augsburg']),
  Club('FC Koln', 'Football', 'Bundesliga', 'Germany', fm: 8722, alias: ['köln', 'koln', 'cologne']),
  Club('Hamburger SV', 'Football', 'Bundesliga', 'Germany', fm: 9790, alias: ['hamburg']),
  Club('St. Pauli', 'Football', 'Bundesliga', 'Germany', fm: 8152, alias: ['pauli']),
  // Serie A
  Club('Juventus', 'Football', 'Serie A', 'Italy', fm: 9885),
  Club('Inter', 'Football', 'Serie A', 'Italy', fm: 8636, alias: ['internazionale']),
  Club('AC Milan', 'Football', 'Serie A', 'Italy', fm: 8564, alias: ['milan']),
  Club('Napoli', 'Football', 'Serie A', 'Italy', fm: 9875),
  Club('Roma', 'Football', 'Serie A', 'Italy', fm: 8686),
  Club('Lazio', 'Football', 'Serie A', 'Italy', fm: 8543),
  Club('Atalanta', 'Football', 'Serie A', 'Italy', fm: 8524),
  Club('Fiorentina', 'Football', 'Serie A', 'Italy', fm: 8535),
  Club('Bologna', 'Football', 'Serie A', 'Italy', fm: 9857),
  Club('Torino', 'Football', 'Serie A', 'Italy', fm: 9804),
  Club('Genoa', 'Football', 'Serie A', 'Italy', fm: 10233),
  Club('Udinese', 'Football', 'Serie A', 'Italy', fm: 8600),
  Club('Cagliari', 'Football', 'Serie A', 'Italy', fm: 8529),
  Club('Como', 'Football', 'Serie A', 'Italy', fm: 10171),
  // Ligue 1
  Club('Paris Saint-Germain', 'Football', 'Ligue 1', 'France', fm: 9847, alias: ['paris saint', 'psg', 'paris sg']),
  Club('Marseille', 'Football', 'Ligue 1', 'France', fm: 8592),
  Club('Lyon', 'Football', 'Ligue 1', 'France', fm: 9748),
  Club('Monaco', 'Football', 'Ligue 1', 'France', fm: 9829),
  Club('Lille', 'Football', 'Ligue 1', 'France', fm: 8639),
  Club('Nice', 'Football', 'Ligue 1', 'France', fm: 9831),
  Club('Lens', 'Football', 'Ligue 1', 'France', fm: 8588),
  Club('Rennes', 'Football', 'Ligue 1', 'France', fm: 9851),
  // Israeli Premier League
  Club('Maccabi Tel Aviv', 'Football', 'Israeli Premier League', 'Israel', fm: 7855, alias: ['maccabi tel aviv', 'maccabi ta', 'מכבי תל אביב', 'מכבי ת"א']),
  Club('Maccabi Haifa', 'Football', 'Israeli Premier League', 'Israel', fm: 10185),
  Club("Hapoel Be'er Sheva", 'Football', 'Israeli Premier League', 'Israel', fm: 9754, alias: ['hapoel beer sheva', 'beer sheva', "be'er sheva"]),
  Club('Beitar Jerusalem', 'Football', 'Israeli Premier League', 'Israel', fm: 8173),
  Club('Hapoel Jerusalem', 'Football', 'Israeli Premier League', 'Israel', fm: 459591),
  Club('Maccabi Netanya', 'Football', 'Israeli Premier League', 'Israel', fm: 1832),
  Club('Maccabi Petah Tikva', 'Football', 'Israeli Premier League', 'Israel', fm: 7929, alias: ['maccabi petach tikva']),
  Club('Hapoel Haifa', 'Football', 'Israeli Premier League', 'Israel', fm: 8301),
  Club('Hapoel Petah Tikva', 'Football', 'Israeli Premier League', 'Israel', fm: 9755, alias: ['hapoel petach tikva']),
  Club('Hapoel Hadera', 'Football', 'Israeli Premier League', 'Israel', fm: 857444),
  Club('Ironi Kiryat Shmona', 'Football', 'Israeli Premier League', 'Israel', fm: 2095, alias: ['kiryat shmona']),
  Club('FC Ashdod', 'Football', 'Israeli Premier League', 'Israel', fm: 6203, alias: ['ashdod']),
  // National teams (football)
  Club('Israel', 'Football', 'National teams', 'Israel', fm: 8567),
  Club('Brazil', 'Football', 'National teams', 'Brazil', fm: 8256),
  Club('Argentina', 'Football', 'National teams', 'Argentina', fm: 6706),
  Club('France', 'Football', 'National teams', 'France', fm: 6723),
  Club('Germany', 'Football', 'National teams', 'Germany', fm: 8570),
  Club('Spain', 'Football', 'National teams', 'Spain', fm: 6720),
  Club('England', 'Football', 'National teams', 'England', fm: 8491),
  Club('Portugal', 'Football', 'National teams', 'Portugal', fm: 8361),
  Club('Netherlands', 'Football', 'National teams', 'Netherlands', fm: 6708, alias: ['holland']),
  Club('Italy', 'Football', 'National teams', 'Italy', fm: 8204),
  Club('Belgium', 'Football', 'National teams', 'Belgium', fm: 8263),
  Club('Croatia', 'Football', 'National teams', 'Croatia', fm: 10155),
  Club('Uruguay', 'Football', 'National teams', 'Uruguay', fm: 5796),
  Club('Colombia', 'Football', 'National teams', 'Colombia', fm: 8258),
  Club('Mexico', 'Football', 'National teams', 'Mexico', fm: 6710),
  Club('USA', 'Football', 'National teams', 'USA', fm: 6713, alias: ['united states']),
  Club('Japan', 'Football', 'National teams', 'Japan', fm: 6715),
  Club('South Korea', 'Football', 'National teams', 'South Korea', fm: 7804, alias: ['korea republic']),
  Club('Poland', 'Football', 'National teams', 'Poland', fm: 8568),
  Club('Switzerland', 'Football', 'National teams', 'Switzerland', fm: 6717),
  Club('Denmark', 'Football', 'National teams', 'Denmark', fm: 8238),
  Club('Sweden', 'Football', 'National teams', 'Sweden', fm: 8520),
  Club('Norway', 'Football', 'National teams', 'Norway', fm: 8492),
  Club('Serbia', 'Football', 'National teams', 'Serbia', fm: 8205),
  Club('Greece', 'Football', 'National teams', 'Greece', fm: 6383),
  Club('Turkey', 'Football', 'National teams', 'Turkey', fm: 6595, alias: ['türkiye', 'turkiye']),
  Club('Ukraine', 'Football', 'National teams', 'Ukraine', fm: 6718),
  Club('Austria', 'Football', 'National teams', 'Austria', fm: 8255),
  Club('Scotland', 'Football', 'National teams', 'Scotland', fm: 8498),
  Club('Czechia', 'Football', 'National teams', 'Czechia', fm: 8496, alias: ['czech republic']),
  Club('Hungary', 'Football', 'National teams', 'Hungary', fm: 8565),
  Club('Romania', 'Football', 'National teams', 'Romania', fm: 9730),
  Club('Bulgaria', 'Football', 'National teams', 'Bulgaria', fm: 10150),
  Club('Cyprus', 'Football', 'National teams', 'Cyprus', fm: 5793),
  Club('Georgia', 'Football', 'National teams', 'Georgia', fm: 8268),
  Club('Canada', 'Football', 'National teams', 'Canada', fm: 5810),
  Club('Australia', 'Football', 'National teams', 'Australia', fm: 6716),
  Club('Nigeria', 'Football', 'National teams', 'Nigeria', fm: 6346),
  Club('Senegal', 'Football', 'National teams', 'Senegal', fm: 6395),
  Club('Ghana', 'Football', 'National teams', 'Ghana', fm: 6714),
  Club('Ivory Coast', 'Football', 'National teams', 'Ivory Coast', fm: 6709, alias: ["côte d'ivoire", 'cote d ivoire']),
  Club('Cameroon', 'Football', 'National teams', 'Cameroon', fm: 6629),
  Club('South Africa', 'Football', 'National teams', 'South Africa', fm: 6316),
  // Basketball: EuroLeague (codes checked against the official schedule file)
  Club('Maccabi Tel Aviv', 'Basketball', 'EuroLeague', 'Israel', el: 'TEL'),
  Club('Real Madrid', 'Basketball', 'EuroLeague', 'Spain', el: 'MAD'),
  Club('Barcelona', 'Basketball', 'EuroLeague', 'Spain', el: 'BAR'),
  Club('Baskonia', 'Basketball', 'EuroLeague', 'Spain', el: 'BAS'),
  Club('Valencia Basket', 'Basketball', 'EuroLeague', 'Spain', el: 'PAM'),
  Club('Olympiacos', 'Basketball', 'EuroLeague', 'Greece', el: 'OLY'),
  Club('Panathinaikos', 'Basketball', 'EuroLeague', 'Greece', el: 'PAN'),
  Club('Fenerbahce', 'Basketball', 'EuroLeague', 'Turkey', el: 'ULK'),
  Club('Anadolu Efes', 'Basketball', 'EuroLeague', 'Turkey', el: 'IST'),
  Club('Besiktas', 'Basketball', 'EuroLeague', 'Turkey', el: 'BES'),
  Club('Bayern Munich', 'Basketball', 'EuroLeague', 'Germany', el: 'MUN'),
  Club('Olimpia Milano', 'Basketball', 'EuroLeague', 'Italy', el: 'MIL'),
  Club('Virtus Bologna', 'Basketball', 'EuroLeague', 'Italy', el: 'VIR'),
  Club('Partizan', 'Basketball', 'EuroLeague', 'Serbia', el: 'PAR'),
  Club('Crvena Zvezda', 'Basketball', 'EuroLeague', 'Serbia', el: 'RED'),
  Club('Zalgiris', 'Basketball', 'EuroLeague', 'Lithuania', el: 'ZAL'),
  Club('ASVEL', 'Basketball', 'EuroLeague', 'France', el: 'ASV'),
  Club('Paris Basketball', 'Basketball', 'EuroLeague', 'France', el: 'PRS'),
  Club('Dubai Basketball', 'Basketball', 'EuroLeague', 'United Arab Emirates', el: 'DUB'),
  // Basketball: Israeli league (official league site)
  Club('Maccabi Tel Aviv', 'Basketball', 'Israeli Winner League', 'Israel', il: 'Maccabi Rapyd Tel Aviv'),
  Club('Hapoel Jerusalem', 'Basketball', 'Israeli Winner League', 'Israel', il: 'Hapoel Midtown Jerusalem'),
  Club('Hapoel Eilat', 'Basketball', 'Israeli Winner League', 'Israel', il: 'Hapoel Irony Eilat'),
  Club('Hapoel Galil Elyon', 'Basketball', 'Israeli Winner League', 'Israel', il: 'Hapoel Alfi Benedek Galil Elion'),
  Club('Ironi Ness Ziona', 'Basketball', 'Israeli Winner League', 'Israel', il: 'Ironi Hai Motors Ness Ziona'),
];

/// Everything a person can see or search. Blocked teams are removed here, so they cannot
/// appear in any list or search result, whatever else changes in the app.
final List<Club> catalog = [for (final c in _all) if (!isBlocked(c.name, c.country)) c];

List<String> leaguesOf(String sport) {
  final out = <String>[];
  for (final c in catalog) {
    if (c.sport == sport && !out.contains(c.league)) out.add(c.league);
  }
  return out;
}

List<Club> clubsIn(String sport, String league) =>
    [for (final c in catalog) if (c.sport == sport && c.league == league) c];

List<Club> searchClubs(String q, String sport) {
  final t = q.toLowerCase().trim();
  if (t.isEmpty) return [];
  return [
    for (final c in catalog)
      if (c.sport == sport && (c.name.toLowerCase().contains(t) || c.alias.any((a) => a.toLowerCase().contains(t)))) c
  ];
}

/// The teams a new install follows: the same as before this update.
const defaultFollowed = [
  'Football|Maccabi Tel Aviv',
  'Football|Real Madrid',
  'Football|Liverpool',
  'Football|Dortmund',
  'Basketball|Maccabi Tel Aviv',
];
