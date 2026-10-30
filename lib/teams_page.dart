import 'package:flutter/material.dart';
import 'catalog.dart';
import 'data.dart';
import 'main.dart' show app, pick;

/// Settings > My Teams: choose sport, then league, then team; or search by name.
class TeamsPage extends StatefulWidget {
  const TeamsPage({super.key});
  @override
  State<TeamsPage> createState() => _TeamsPageState();
}

class _TeamsPageState extends State<TeamsPage> {
  bool bySearch = false;
  String sport = 'Football';
  String? league;
  final q = TextEditingController();

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  void toggle(Club c) {
    final wasOn = app.isFollowed(c);
    app.toggleFollow(c);
    if (!wasOn) app.sync(); // fetch the new team's games right away
  }

  Widget teamTile(Club c, {bool showLeague = false}) => CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: app.isFollowed(c),
        onChanged: (_) => toggle(c),
        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(showLeague ? '${c.sport} · ${c.league}' : c.country),
        controlAffinity: ListTileControlAffinity.trailing,
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (context, _) => _page(context));

  Widget _page(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final leagues = leaguesOf(sport);
    final lg = leagues.contains(league) ? league : (leagues.isEmpty ? null : leagues.first);
    final body = <Widget>[];

    if (bySearch) {
      body.add(TextField(
        controller: q,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Find a team or country',
          border: OutlineInputBorder(),
        ),
      ));
      body.add(const SizedBox(height: 10));
      final res = searchClubs(q.text, sport);
      if (q.text.trim().isEmpty) {
        body.add(const Text('Choose the sport above, then type the name.'));
      } else if (res.isEmpty) {
        body.add(const Text('No team found.'));
      } else {
        for (final c in res) {
          body.add(teamTile(c, showLeague: true));
        }
      }
    } else if (leagues.isEmpty) {
      body.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('No live source for this sport yet, so no teams can be followed. You can still add single games by hand in Settings.'),
      ));
    } else {
      body.add(const Text('League', style: TextStyle(fontWeight: FontWeight.w700)));
      body.add(Wrap(spacing: 6, runSpacing: 4, children: [
        for (final l in leagues) pick(context, l, l == lg, () => setState(() => league = l)),
      ]));
      body.add(const SizedBox(height: 10));
      body.add(const Text('Teams (tick to follow)', style: TextStyle(fontWeight: FontWeight.w700)));
      for (final c in clubsIn(sport, lg!)) {
        body.add(teamTile(c));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Teams')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Following', style: TextStyle(fontWeight: FontWeight.w700)),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final c in app.followedClubs)
            InputChip(
              label: Text('${c.name} · ${c.sport}'),
              backgroundColor: cs.primaryContainer,
              onDeleted: () => toggle(c),
            ),
        ]),
        if (app.followedClubs.isEmpty) const Text('No team followed yet.'),
        const SizedBox(height: 14),
        Wrap(spacing: 6, children: [
          pick(context, 'By league', !bySearch, () => setState(() => bySearch = false)),
          pick(context, 'Find a team', bySearch, () => setState(() => bySearch = true)),
        ]),
        const SizedBox(height: 10),
        const Text('Sport', style: TextStyle(fontWeight: FontWeight.w700)),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final s in sportOrder)
            pick(context, s, s == sport, () => setState(() {
                  sport = s;
                  league = null;
                })),
        ]),
        const SizedBox(height: 12),
        ...body,
      ]),
    );
  }
}
