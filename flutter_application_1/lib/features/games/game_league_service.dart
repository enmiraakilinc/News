// Oyun skorunu kaydeder.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/open_stream.dart';
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
    final seasons = <String>[];
    var cursor = DateTime.utc(now.year, ((now.month - 1) ~/ 3) * 3 + 1);
    for (var i = 0; i < 4; i++) {
      final quarter = ((cursor.month - 1) ~/ 3) + 1;
      seasons.add('${cursor.year}-Q$quarter');
      cursor = DateTime.utc(cursor.year, cursor.month - 3);
    }
    return seasons;
  }

  static Future<String> continuationSeason() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('league_continuation');
    if (saved != null && RegExp(r'^20\d{2}-Q[1-4]$').hasMatch(saved)) {
      return saved;
    }
    try {
      await CoupleService.ensureReady().timeout(const Duration(seconds: 6));
    } catch (_) {}
    String? fullest;
    var fullestCount = 0;
    var probed = false;
    for (final season in recentSeasons()) {
      var count = 0;
      for (final game in games) {
        try {
          final snap = await _entries(
            game.id,
            null,
            season,
          ).limit(20).get().timeout(const Duration(seconds: 6));
          probed = true;
          count += snap.docs.length;
        } catch (_) {}
      }
      if (count > fullestCount) {
        fullestCount = count;
        fullest = season;
      }
    }
    if (fullest != null) {
      await prefs.setString('league_continuation', fullest);
      return fullest;
    }
    final seasons = recentSeasons();
    if (!probed && seasons.length > 1) return seasons[1];
    final season = seasonId();
    await prefs.setString('league_continuation', season);
    return season;
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
  ]) => openStreamAfter(
    CoupleService.ensureReady,
    () => _entries(game, date, season)
        .orderBy('score', descending: true)
        .limit(100)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(GameLeagueEntry.fromDocument).toList(),
        ),
    message: 'Lig yüklenemedi.',
  );

  static Stream<DocumentSnapshot<Map<String, dynamic>>> myEntry(
    String game, [
    DateTime? date,
    String? season,
  ]) => openStreamAfter(CoupleService.ensureReady, () {
    final uid = CoupleService.uid;
    if (uid == null) throw StateError('Hesabına giriş yap.');
    return _entries(game, date, season).doc(uid).snapshots();
  }, message: 'Puanın yüklenemedi.');

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
      throw StateError(
        'Lig tablosunda görünmek için önce sohbet adını belirle.',
      );
    }

    final entry = _entries(game, null, await continuationSeason());
    final reference = entry.doc(uid);
    final current = await reference.get(
      const GetOptions(source: Source.server),
    );
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
