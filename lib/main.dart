import 'package:flutter/material.dart';
import 'catalog.dart';
import 'data.dart';
import 'logo.dart';
import 'teams_page.dart';
import 'models.dart';

final app = AppState();

const blue = Color(0xFF0B3D91);
const yellow = Color(0xFFFFC400);
const navy = Color(0xFF0A1F44);
const soft = Color(0xFFDCE9FF);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.load(); // saved games are on screen immediately
  runApp(const GameDayApp());
  startNotifications(); // in the background, never blocks the screen
  app.sync(force: false); // only goes online if nothing is saved or the data is over 12 hours old
}

// No red anywhere: every "error" colour is mapped to blue.
ThemeData buildTheme(bool dark) {
  final cs = dark
      ? const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFF6FA3FF), onPrimary: navy,
          secondary: yellow, onSecondary: navy,
          error: Color(0xFF6FA3FF), onError: navy,
          surface: Color(0xFF0B1B3F), onSurface: Color(0xFFEAF1FF),
          primaryContainer: Color(0xFF16306A), onPrimaryContainer: Color(0xFFEAF1FF),
          secondaryContainer: Color(0xFF16306A), onSecondaryContainer: Color(0xFFEAF1FF),
          tertiary: yellow, onTertiary: navy,
          errorContainer: Color(0xFF16306A), onErrorContainer: Color(0xFFEAF1FF),
          surfaceContainerHighest: Color(0xFF16306A), outline: Color(0xFF6FA3FF),
        )
      : const ColorScheme(
          brightness: Brightness.light,
          primary: blue, onPrimary: Colors.white,
          secondary: yellow, onSecondary: navy,
          error: blue, onError: Colors.white,
          surface: Color(0xFFF4F8FF), onSurface: navy,
          primaryContainer: soft, onPrimaryContainer: navy,
          secondaryContainer: soft, onSecondaryContainer: navy,
          tertiary: yellow, onTertiary: navy,
          errorContainer: soft, onErrorContainer: navy,
          surfaceContainerHighest: soft, outline: blue,
        );
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? navy : blue,
      foregroundColor: yellow,
      titleTextStyle: const TextStyle(color: yellow, fontSize: 22, fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(indicatorColor: yellow),
    cardTheme: CardThemeData(color: dark ? const Color(0xFF0F2350) : Colors.white, margin: const EdgeInsets.symmetric(vertical: 5), clipBehavior: Clip.antiAlias),
  );
}

class GameDayApp extends StatelessWidget {
  const GameDayApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GDS - Game Day Schedule',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(false),
        darkTheme: buildTheme(true),
        home: const Splash(),
      );
}

/// Opening screen: shows the app name for a moment, then the games list.
class Splash extends StatefulWidget {
  const Splash({super.key});
  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Home()));
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: blue,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GdsLogo(size: 150),
            SizedBox(height: 18),
            Text('GDS', style: TextStyle(color: yellow, fontSize: 56, fontWeight: FontWeight.w900)),
            SizedBox(height: 4),
            Text('Game Day Schedule', style: TextStyle(color: yellow, fontSize: 24, fontWeight: FontWeight.w700)),
            SizedBox(height: 28),
            Text('Your teams. Your evenings.', style: TextStyle(color: Colors.white, fontSize: 15)),
          ]),
        ),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  bool freeSeen = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: Text(tab == 0 ? 'GDS' : 'Free nights'),
            actions: [
              if (app.loading)
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: GdsLogo(size: 30, spin: true))
              else
                IconButton(icon: const Icon(Icons.refresh), tooltip: 'Update now', onPressed: app.sync),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
              ),
            ],
            bottom: app.loading
                ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator())
                : null,
          ),
          body: IndexedStack(index: tab, children: [GamesTab(), if (freeSeen) FreeTab() else const SizedBox()]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() {
              tab = i;
              if (i == 1) freeSeen = true;
            }),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.sports_soccer), label: 'Games'),
              NavigationDestination(icon: Icon(Icons.nightlight_round), label: 'Free nights'),
            ],
          ),
        ),
      );
}

// ---------- Shared widgets ----------

Widget pick(BuildContext c, String label, bool sel, VoidCallback onTap) {
  final cs = Theme.of(c).colorScheme;
  return FilterChip(
    label: Text(label, style: TextStyle(color: sel ? cs.onPrimary : cs.onSurface)),
    selected: sel,
    showCheckmark: false,
    selectedColor: cs.primary,
    onSelected: (_) => onTap(),
  );
}

Widget tag(BuildContext c, String text, {bool filled = false}) {
  final cs = Theme.of(c).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: filled ? cs.primary : cs.primaryContainer,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: TextStyle(fontSize: 13, color: filled ? cs.onPrimary : cs.onPrimaryContainer)),
  );
}

Widget gameCard(BuildContext c, Game g) {
  final ch = app.channelOf(g);
  return Card(
    child: IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          width: 78,
          color: yellow,
          alignment: Alignment.center,
          child: Text(hm(g.start), style: const TextStyle(color: navy, fontWeight: FontWeight.w800, fontSize: 19)),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${g.team} vs ${oppName(g)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (venue(g) != null) tag(c, venue(g)!),
                tag(c, g.sport),
                tag(c, g.comp),
                tag(c, ch ?? 'TV channel TBC', filled: ch != null),
              ]),
            ]),
          ),
        ),
      ]),
    ),
  );
}

class FilterPanel extends StatelessWidget {
  const FilterPanel({super.key});

  Widget group(BuildContext c, String title, List<String> items, Set<String> sel) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(title)),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final v in items)
              pick(c, v, sel.contains(v), () {
                sel.contains(v) ? sel.remove(v) : sel.add(v);
                app.save();
              }),
          ]),
        ],
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (context, _) => panel(context));

  Widget panel(BuildContext context) => Card(
        child: ExpansionTile(
          title: const Text('Filters', style: TextStyle(fontWeight: FontWeight.w600)),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            group(context, 'Teams', app.teamNames, app.fTeams),
            group(context, 'Sport', sports, app.fSports),
            group(context, 'Competition', comps, app.fComps),
            const Padding(padding: EdgeInsets.only(top: 10, bottom: 4), child: Text('TV broadcast')),
            Wrap(spacing: 6, children: [
              for (final o in [['all', 'All'], ['yes', 'On TV'], ['no', 'Not on TV']])
                pick(context, o[1], app.tv == o[0], () {
                  app.tv = o[0];
                  app.save();
                }),
            ]),
            TextButton(onPressed: app.resetFilters, child: const Text('Reset filters')),
          ],
        ),
      );
}

// ---------- Games tab ----------

class GamesTab extends StatelessWidget {
  const GamesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = dayOnly(DateTime.now());
    final r = app.range ?? DateTimeRange(start: today, end: DateTime(today.year, today.month, today.day + 14));
    final list = app.filtered.where((g) {
      final d = dayOnly(g.start);
      return !d.isBefore(dayOnly(r.start)) && !d.isAfter(dayOnly(r.end));
    }).toList();
    final up = app.filtered.where((g) => g.start.isAfter(DateTime.now())).toList();

    Widget? preview;
    if (up.isNotEmpty) {
      final d = dayOnly(up.first.start);
      final gs = up.where((g) => dayOnly(g.start) == d).toList();
      preview = Card(
        color: cs.secondaryContainer,
        child: Container(
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: yellow, width: 6))),
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('11:00 alert · ${d == today ? 'Today' : dayLabel(d)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            for (final g in gs) Padding(padding: const EdgeInsets.only(top: 8), child: Text(gameLine(app, g))),
          ]),
        ),
      );
    }

    final rows = <Widget>[];
    var last = '';
    for (final g in list) {
      final k = dayLabel(g.start);
      if (k != last) {
        rows.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Text(k, style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
        ));
        last = k;
      }
      rows.add(gameCard(context, g));
    }

    return RefreshIndicator(
      onRefresh: app.sync,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(app.status ?? 'Showing the saved schedule. Tap refresh to update.', style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              'Game Day $appVersion · ${app.lastSync == null ? 'never updated' : 'last update ${dayLabel(app.lastSync!)} ${hm(app.lastSync!)}'}',
              style: const TextStyle(fontSize: 12),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            expandedAlignment: Alignment.centerLeft,
            children: [
              Text([
                ...syncLog,
                if (app.alertsNote.isNotEmpty) app.alertsNote.length > 200 ? app.alertsNote.substring(0, 200) : app.alertsNote,
              ].join('\n')),
            ],
          ),
        ),
        if (preview != null) preview,
        const FilterPanel(),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range),
          label: Text('${dayLabel(r.start)} to ${dayLabel(r.end)}'),
          onPressed: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: today,
              lastDate: DateTime(today.year, today.month, today.day + 120),
              initialDateRange: r,
            );
            if (picked != null) {
              app.range = picked;
              app.save();
            }
          },
        ),
        ...rows,
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(28),
            child: Text('No games match the selected filters and dates. Adjust the filters or the date range, or pull down to refresh.', textAlign: TextAlign.center),
          ),
      ]),
    );
  }
}

// ---------- Free nights tab ----------

class FreeTab extends StatefulWidget {
  const FreeTab({super.key});
  @override
  State<FreeTab> createState() => _FreeTabState();
}

class _FreeTabState extends State<FreeTab> {
  int w = 0;

  Widget month(BuildContext c, DateTime first, DateTime today, DateTime end) {
    final cs = Theme.of(c).colorScheme;
    final days = DateTime(first.year, first.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday first
    final cells = <Widget>[
      for (final h in ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
        Center(child: Text(h, style: Theme.of(c).textTheme.bodySmall)),
      for (var i = 0; i < lead; i++) const SizedBox(),
    ];
    for (var d = 1; d <= days; d++) {
      final date = DateTime(first.year, first.month, d);
      if (date.isBefore(today) || date.isAfter(end)) {
        cells.add(Center(child: Text('$d', style: TextStyle(color: cs.onSurface.withOpacity(.35)))));
        continue;
      }
      final busy = app.eveningGames(date).isNotEmpty;
      cells.add(InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          final gs = app.filtered.where((g) => dayOnly(g.start) == date).toList();
          showModalBottomSheet(
            context: c,
            isScrollControlled: true,
            builder: (_) => ListView(shrinkWrap: true, padding: const EdgeInsets.all(14), children: [
              Text(dayLabel(date), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 8),
              if (gs.isEmpty) const Text('No games: free evening.'),
              for (final g in gs) gameCard(c, g),
            ]),
          );
        },
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(color: busy ? cs.primary : yellow, borderRadius: BorderRadius.circular(8)),
          child: Text('$d', style: TextStyle(fontWeight: FontWeight.w700, color: busy ? cs.onPrimary : navy)),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(top: 16, bottom: 6), child: Text(monthLabel(first), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        children: cells,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = dayOnly(DateTime.now());
    final end = DateTime(today.year, today.month, today.day + 90);
    final ws = DateTime(today.year, today.month, today.day + w * 7); // starts today, then 7 days
    final we = DateTime(ws.year, ws.month, ws.day + 6);

    final weekRows = <Widget>[];
    for (var i = 0; i < 7; i++) {
      final d = DateTime(ws.year, ws.month, ws.day + i);
      final gs = app.eveningGames(d, useFilters: false);
      final free = gs.isEmpty;
      weekRows.add(Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: free ? yellow : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(d == today ? '${dayLabel(d)} (today)' : dayLabel(d), style: TextStyle(fontWeight: FontWeight.w700, color: free ? navy : cs.onSurface)),
          Flexible(
            child: Text(
              free ? (d.isBefore(today) ? 'Past' : 'Free evening') : gs.map((g) => '${g.team} ${hm(g.start)}').join(', '),
              textAlign: TextAlign.end,
              style: TextStyle(color: free ? navy : cs.onSurface),
            ),
          ),
        ]),
      ));
    }

    var n = 0;
    for (var i = 0; i <= 90; i++) {
      if (app.eveningGames(DateTime(today.year, today.month, today.day + i)).isEmpty) n++;
    }

    final months = <Widget>[];
    for (var m = 0; m < 4; m++) {
      final first = DateTime(today.year, today.month + m, 1);
      if (first.isAfter(end)) break;
      months.add(month(context, first, today, end));
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        color: cs.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(w == 0 ? 'Next 7 days' : '7 days from ${dayLabel(ws)}', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('${dayLabel(ws)} to ${dayLabel(we)} · all teams, filters not applied'),
            Row(children: [
              TextButton(onPressed: w > 0 ? () => setState(() => w--) : null, child: const Text('Previous 7 days')),
              TextButton(onPressed: () => setState(() => w++), child: const Text('Next 7 days')),
            ]),
          ]),
        ),
      ),
      ...weekRows,
      const SizedBox(height: 8),
      const FilterPanel(),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Text('$n free evenings in the next three months (filters applied).', style: const TextStyle(fontWeight: FontWeight.w700)))),
      Row(children: [
        Container(width: 12, height: 12, color: yellow),
        const SizedBox(width: 6),
        const Text('Free evening'),
        const SizedBox(width: 16),
        Container(width: 12, height: 12, color: cs.primary),
        const SizedBox(width: 6),
        const Text('Game'),
      ]),
      ...months,
    ]);
  }
}

// ---------- Settings ----------

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final tokenC = TextEditingController(text: app.token);
  final mapC = TextEditingController(text: app.channelMap);

  @override
  void dispose() {
    app.rescheduleAlerts();
    super.dispose();
  }

  Widget hourDrop(String label, int v, int from, int to, void Function(int) set) => Row(children: [
        Expanded(child: Text(label)),
        DropdownButton<int>(
          value: v,
          items: [for (var h = from; h <= to; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}:00'))],
          onChanged: (x) {
            set(x!);
            app.save();
          },
        ),
      ]);

  Widget drop(String label, String v, List<String> items, void Function(String) set) => Row(children: [
        SizedBox(width: 110, child: Text(label)),
        Expanded(
          child: DropdownButton<String>(
            isExpanded: true,
            value: v,
            items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i))],
            onChanged: (x) => set(x!),
          ),
        ),
      ]);

  Future<void> addCal(BuildContext context) async {
    var team = app.teamNames.first, sport = sports[0];
    final url = TextEditingController();
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Add a calendar'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              drop('Team', team, app.teamNames, (v) => set(() => team = v)),
              drop('Sport', sport, sports, (v) => set(() => sport = v)),
              TextField(controller: url, decoration: const InputDecoration(labelText: 'Calendar link (.ics or webcal://)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final u = url.text.trim();
                if (u.isEmpty) return;
                app.cals.add(CalSource(url: u, team: team, sport: sport));
                app.save();
                Navigator.pop(c);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> addGame(BuildContext context) async {
    var team = app.teamNames.first, sport = sports[1], comp = comps[0];
    final opp = TextEditingController(), ch = TextEditingController();
    final t0 = DateTime.now().add(const Duration(days: 1));
    var when = DateTime(t0.year, t0.month, t0.day, 20);
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Add a game manually'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              drop('Team', team, app.teamNames, (v) => set(() => team = v)),
              drop('Sport', sport, sports, (v) => set(() => sport = v)),
              drop('Competition', comp, comps, (v) => set(() => comp = v)),
              TextField(controller: opp, decoration: const InputDecoration(labelText: 'Opponent')),
              TextField(controller: ch, decoration: const InputDecoration(labelText: 'TV channel (optional)')),
              TextButton(
                onPressed: () async {
                  final d = await showDatePicker(
                    context: c,
                    initialDate: when,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 400)),
                  );
                  if (d != null) set(() => when = DateTime(d.year, d.month, d.day, when.hour, when.minute));
                },
                child: Text('Date: ${dayLabel(when)}'),
              ),
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(context: c, initialTime: TimeOfDay(hour: when.hour, minute: when.minute));
                  if (t != null) set(() => when = DateTime(when.year, when.month, when.day, t.hour, t.minute));
                },
                child: Text('Time: ${hm(when)}'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (opp.text.trim().isEmpty) return;
                app.manual.add(Game(
                  team: team, sport: sport, comp: comp, compName: comp,
                  opponent: opp.text.trim(), start: when,
                  channel: ch.text.trim().isEmpty ? null : ch.text.trim(), manual: true,
                ));
                app.save();
                Navigator.pop(c);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: yellow, foregroundColor: navy, padding: const EdgeInsets.all(16)),
              icon: const Icon(Icons.groups),
              label: const Text('My Teams', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeamsPage())),
            ),
            const SizedBox(height: 4),
            Text('Followed teams: ${app.teamNames.join(', ')}'),
            const SizedBox(height: 22),
            const Text('Manual games', style: TextStyle(fontWeight: FontWeight.w700)),
            const Text('Use this for handball, volleyball or any game the sources do not cover.'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => addGame(context), icon: const Icon(Icons.add), label: const Text('Add a game manually')),
            ),
            for (var i = 0; i < app.manual.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${app.manual[i].team} vs ${app.manual[i].opponent}'),
                subtitle: Text('${dayLabel(app.manual[i].start)} ${hm(app.manual[i].start)} · ${app.manual[i].sport}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: () {
                    app.manual.removeAt(i);
                    app.save();
                  },
                ),
              ),
            const SizedBox(height: 22),
            const Text('Additional calendars (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text("Schedules for your teams load automatically. To add a schedule that is not available, paste an .ics or webcal:// calendar link, choose the team and sport, then tap Update now."),
            for (var i = 0; i < app.cals.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${app.cals[i].team} · ${app.cals[i].sport}'),
                subtitle: Text(app.cals[i].url, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: () {
                    app.cals.removeAt(i);
                    app.save();
                  },
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => addCal(context), icon: const Icon(Icons.add), label: const Text('Add a calendar')),
            ),
            FilledButton.icon(
              onPressed: app.loading ? null : app.sync,
              icon: const Icon(Icons.sync),
              label: const Text('Update now'),
            ),
            const SizedBox(height: 22),
            const Text('Football data key (optional)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Optional: a free football-data.org key adds league and Champions League fixtures for Real Madrid, Liverpool and Dortmund.'),
            TextField(
              controller: tokenC,
              decoration: const InputDecoration(labelText: 'football-data.org API key'),
              onChanged: (v) {
                app.token = v.trim();
                app.save();
              },
            ),
            const SizedBox(height: 22),
            const Text('Evening window', style: TextStyle(fontWeight: FontWeight.w700)),
            hourDrop('Evening starts', app.evStart, 15, 21, (v) => app.evStart = v),
            hourDrop('Evening ends', app.evEnd, 21, 24, (v) => app.evEnd = v),
            const SizedBox(height: 22),
            const Text('TV channels in Israel', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('One rule per line: a keyword from the team or competition, an equals sign, then the channel that holds the broadcast rights in Israel. The first matching rule applies.'),
            TextField(
              controller: mapC,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(hintText: 'champions league=Channel name\nliverpool=Channel name'),
              onChanged: (v) {
                app.channelMap = v;
                app.save();
              },
            ),
          ]),
        ),
      );
}
