// Oyun sıralaması ekranıdır.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'game_league_service.dart';

class GameLeagueScreen extends StatefulWidget {
  const GameLeagueScreen({super.key});

  @override
  State<GameLeagueScreen> createState() => _GameLeagueScreenState();
}

class _GameLeagueScreenState extends State<GameLeagueScreen> {
  String _game = GameLeagueService.games.first.id;
  String? _season;
  String? _continuation;
  late Stream<List<GameLeagueEntry>> _leaderboard;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _mine;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _leaderboard = const Stream.empty();
    _mine = const Stream.empty();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_openContinuation());
  }

  Future<void> _openContinuation() async {
    late final String season;
    try {
      season = await GameLeagueService.continuationSeason().timeout(
        const Duration(seconds: 20),
      );
    } catch (_) {
      season = GameLeagueService.seasonId();
    }
    if (!mounted) return;
    setState(() {
      _continuation = season;
      _selectSeason(season);
    });
  }

  void _selectGame(String game) {
    _game = game;
    final season = _season;
    if (season == null) return;
    _leaderboard = GameLeagueService.leaderboard(game, null, season);
    _mine = GameLeagueService.myEntry(game, null, season);
  }

  void _selectSeason(String season) {
    _season = season;
    _selectGame(_game);
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final season = _season;
    if (season == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final seasons = GameLeagueService.recentSeasons();
    if (!seasons.contains(season)) seasons.insert(0, season);
    final game = GameLeagueService.games.firstWhere((item) => item.id == _game);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lig tablosu'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              Icons.grid_view_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xff174b54),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(
                      Icons.emoji_events_outlined,
                      color: Color(0xff54ddc0),
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${game.label} Ligi',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Sezon $season',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                DropdownButton<String>(
                  value: season,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final item in seasons)
                      DropdownMenuItem(
                        value: item,
                        child: Text(
                          item == _continuation ? 'Devam eden lig' : item,
                        ),
                      ),
                  ],
                  onChanged: (season) {
                    if (season != null) {
                      setState(() => _selectSeason(season));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.schedule, size: 15, color: Color(0xffffd66b)),
                const SizedBox(width: 6),
                Text(
                  season == _continuation
                      ? 'Bu lig devam ediyor'
                      : 'Geçmiş sezon',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final option in GameLeagueService.games)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(option.label),
                        selected: _game == option.id,
                        onSelected: (_) =>
                            setState(() => _selectGame(option.id)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _mine,
              builder: (context, mineSnapshot) {
                if (mineSnapshot.hasError) {
                  return _errorCard(
                    context,
                    'Kendi puanın yüklenemedi: ${mineSnapshot.error}',
                  );
                }
                final myData = mineSnapshot.data?.data();
                final myScore = myData?['score'] as int?;
                final myUid = mineSnapshot.data?.id;
                return StreamBuilder<List<GameLeagueEntry>>(
                  stream: _leaderboard,
                  builder: (context, boardSnapshot) {
                    if (boardSnapshot.hasError) {
                      return _errorCard(
                        context,
                        'Lig sıralaması yüklenemedi: ${boardSnapshot.error}',
                      );
                    }
                    final entries = boardSnapshot.data;
                    final index = entries?.indexWhere(
                      (entry) => entry.uid == myUid,
                    );
                    final rank = index == null || index < 0 ? null : index + 1;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text(
                                  game.label,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  myScore == null
                                      ? 'Bu sezon henüz puanın yok.'
                                      : rank == null
                                      ? 'Puanın: $myScore · İlk 100 dışında'
                                      : 'Sıran: $rank · Puanın: $myScore',
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Oyuncular',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (entries == null)
                          const Center(child: CircularProgressIndicator())
                        else if (entries.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'Bu oyun liginde henüz puan yok. Oyun oynayıp ilk puanı kazan.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        else
                          for (var i = 0; i < entries.take(10).length; i++)
                            _entryTile(
                              context,
                              entry: entries[i],
                              rank: i + 1,
                              highlighted: entries[i].uid == myUid,
                            ),
                        if (myScore != null && rank == null)
                          Card(
                            child: ListTile(
                              leading: const CircleAvatar(child: Text('…')),
                              title: Text(
                                myData?['displayName'] as String? ?? 'Sen',
                              ),
                              subtitle: const Text('İlk 100 dışında'),
                              trailing: Text('$myScore puan'),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Puanlar her oyun için ayrı tutulur. Yeni sezon başladığında sıralama yeniden başlar.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(BuildContext context, String message) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );

  Widget _entryTile(
    BuildContext context, {
    required GameLeagueEntry entry,
    required int rank,
    required bool highlighted,
  }) => Card(
    color: highlighted ? Theme.of(context).colorScheme.primaryContainer : null,
    child: ListTile(
      leading: CircleAvatar(child: Text('$rank')),
      title: Text(entry.displayName),
      trailing: Text('${entry.score} puan'),
    ),
  );
}
