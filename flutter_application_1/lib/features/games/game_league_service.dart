import 'package:cloud_firestore/cloud_firestore.dart';

import '../chat/chat_service.dart';
import '../pair/couple_service.dart';

class GameLeagueEntry {
  final String uid;
  final String displayName;
  final int score;

  const GameLeagueEntry({
    required this.uid,
    required this.displayName,
    required this.score,
  });

  factory GameLeagueEntry.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) => GameLeagueEntry(
    uid: document.id,
    displayName: document.data()['displayName'] as String? ?? 'Oyuncu',
    score: document.data()['score'] as int? ?? 0,
  );
}

class GameLeagueService {
  static const games = <({String id, String label})>[
    (id: 'sudoku', label: 'Sudoku'),
    (id: 'sliding_puzzle', label: '15 Taş'),
    (id: 'block_blast', label: 'Block Blast'),
  ];

  static String seasonId([DateTime? date]) {
    final now = (date ?? DateTime.now()).toUtc();
    final quarter = ((now.month - 1) ~/ 3) + 1;
    return '${now.year}-Q$quarter';
  }

  static DateTime seasonEnd([DateTime? date]) {
    final now = (date ?? DateTime.now()).toUtc();
    final quarter = ((now.month - 1) ~/ 3) + 1;
    return DateTime.utc(now.year, quarter * 3 + 1);
  }

  static List<String> recentSeasons([DateTime? date]) {
    final now = (date ?? DateTime.now()).toUtc();
    final current = seasonId(now);
    final start = DateTime.utc(
      now.year,
      ((now.month - 1) ~/ 3) * 3 + 1,
    );
    final previousEnd = start;
    if (now.difference(previousEnd) < const Duration(days: 30)) {
      final previous = DateTime.utc(start.year, start.month - 1);
      final quarter = ((previous.month - 1) ~/ 3) + 1;
      return [
        current,
        '${previous.year}-Q$quarter',
      ];
    }
    return [current];
  }

  static CollectionReference<Map<String, dynamic>> _entries(
    String game, [
    DateTime? date,
    String? season,
  ]) => FirebaseFirestore.instance
      .collection('gameLeagues')
      .doc(season ?? seasonId(date))
      .collection('games')
      .doc(game)
      .collection('entries');

  static Stream<List<GameLeagueEntry>> leaderboard(
    String game, [
    DateTime? date,
    String? season,
  ]) async* {
    await CoupleService.ensureReady();
    await for (final snapshot in _entries(
      game,
      date,
      season,
    ).orderBy('score', descending: true).limit(100).snapshots()) {
      yield snapshot.docs.map(GameLeagueEntry.fromDocument).toList();
    }
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> myEntry(
    String game, [
    DateTime? date,
    String? season,
  ]) async* {
    await CoupleService.ensureReady();
    final uid = CoupleService.uid;
    if (uid == null) throw StateError('Hesabına giriş yap.');
    yield* _entries(game, date, season).doc(uid).snapshots();
  }

  static Future<void> recordBestScore({
    required String game,
    required int score,
  }) async {
    final maxScore = switch (game) {
      'sudoku' => 1000000,
      'sliding_puzzle' => 10000,
      'block_blast' => 10000000,
      _ => 0,
    };
    if (score < 1 || score > maxScore) {
      throw ArgumentError.value(score, 'score', 'Lig puanı geçersiz.');
    }
    await CoupleService.ensureReady();
    final uid = CoupleService.uid;
    if (uid == null) throw StateError('Hesabına giriş yap.');
    final name = (await ChatService.myName())?.trim();
    if (name == null || name.isEmpty) {
      throw StateError('Lig tablosunda görünmek için önce sohbet adını belirle.');
    }

    final entry = _entries(game);
    final reference = entry.doc(uid);
    final current = await reference.get(const GetOptions(source: Source.server));
    final best = current.data()?['score'] as int? ?? 0;
    final savedName = current.data()?['displayName'] as String?;
    if (best > score && savedName == name) return;
    await reference.set({
      'uid': uid,
      'displayName': name,
      'score': best > score ? best : score,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
