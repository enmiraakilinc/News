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
  late Stream<List<GameLeagueEntry>> _leaderboard;
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _mine;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _selectGame(_game);
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _selectGame(String game) {
    _game = game;
    _leaderboard = GameLeagueService.leaderboard(game);
    _mine = GameLeagueService.myEntry(game);
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String _remaining(DateTime end) {
    final remaining = end.difference(DateTime.now().toUtc());
    if (remaining.isNegative) return 'Sezon tamamlandı';
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    return '$days gün $hours saat kaldı';
  }

  @override
  Widget build(BuildContext context) {
    final season = GameLeagueService.seasonId();
    final end = GameLeagueService.seasonEnd();
    final game = GameLeagueService.games.firstWhere((item) => item.id == _game);
    return Scaffold(
      appBar: AppBar(title: const Text('Oyun Ligleri')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '$season sezonu',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(_remaining(end), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                for (final option in GameLeagueService.games)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: _game == option.id,
                    onSelected: (_) => setState(() => _selectGame(option.id)),
                  ),
              ],
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
                        const SizedBox(height: 8),
                        Text(
                          'İlk 10 oyuncu',
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
                              title: Text(myData?['displayName'] as String? ?? 'Sen'),
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
