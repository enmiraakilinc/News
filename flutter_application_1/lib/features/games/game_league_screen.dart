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
      backgroundColor: const Color(0xFF0B1533),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1533),
        foregroundColor: Colors.white,
        title: const Text(
          'OYUN LİGLERİ',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF243F7B), Color(0xFF172650)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFF41598D)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC857).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFFFC857),
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          game.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$season sezonu · ${_remaining(end)}',
                          style: const TextStyle(
                            color: Color(0xFFB9C8E8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 9,
              runSpacing: 6,
              children: [
                for (final option in GameLeagueService.games)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: _game == option.id,
                    showCheckmark: false,
                    backgroundColor: const Color(0xFF142044),
                    selectedColor: const Color(0xFF31529A),
                    labelStyle: TextStyle(
                      color: _game == option.id
                          ? Colors.white
                          : const Color(0xFFB9C8E8),
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => setState(() => _selectGame(option.id)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
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
                          color: const Color(0xFF142044),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: const BorderSide(color: Color(0xFF293B68)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _LeagueStat(
                                  label: 'SIRALAMAN',
                                  value: rank == null ? '—' : '#$rank',
                                  color: const Color(0xFF49D5E8),
                                ),
                                Container(
                                  width: 1,
                                  height: 42,
                                  color: const Color(0xFF33466F),
                                ),
                                _LeagueStat(
                                  label: 'EN İYİ PUANIN',
                                  value: myScore == null ? '—' : '$myScore',
                                  color: const Color(0xFFFFC857),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'LİG SIRALAMASI',
                          style: TextStyle(
                            color: Color(0xFFB9C8E8),
                            fontSize: 12,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
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
                            color: const Color(0xFF172650),
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
            const Text(
              'Puanlar her oyun için ayrı tutulur. Yeni sezon başladığında sıralama yeniden başlar.',
              style: TextStyle(color: Color(0xFF90A5D1), fontSize: 11),
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
    color: highlighted
        ? const Color(0xFF263F78)
        : const Color(0xFF142044),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: highlighted
            ? const Color(0xFF49D5E8)
            : const Color(0xFF293B68),
      ),
    ),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: switch (rank) {
          1 => const Color(0xFFFFC857),
          2 => const Color(0xFFCBD5E1),
          3 => const Color(0xFFCE8B60),
          _ => const Color(0xFF26365F),
        },
        foregroundColor: const Color(0xFF0B1533),
        child: Text(
          '$rank',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      title: Text(
        entry.displayName,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: Text(
        '${entry.score} pt',
        style: const TextStyle(
          color: Color(0xFFFFC857),
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _LeagueStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _LeagueStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Color(0xFF90A5D1),
          fontSize: 9,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        style: TextStyle(
          color: color,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}
