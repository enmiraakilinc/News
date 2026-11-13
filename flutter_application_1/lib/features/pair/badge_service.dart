// Ana sayfadaki okunmamış rozetleri sayar.
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/notifications/notif_prefs.dart';
import '../../core/utils/date_format.dart';

/// Gizli bölümdeki kırmızı "+N" rozetleri.
///
/// Bildirim çubuğundan TAMAMEN bağımsızdır: rozet sayaçları `badge_seen_*`
/// anahtarlarında tutulur ve yalnızca kullanıcı ilgili bölümü açınca sıfırlanır.
/// (Bildirimlerin `seen_*` sayaçları arka plan görevinde de güncellendiği için
/// rozet onlara bakamaz — baksaydı uygulama her açılışta rozeti silerdi.)
class BadgeService {
  static String badgeKey(ContentNotif n) => 'badge_seen_${n.collection}';

  /// Tek bir türü sayar. Belgeler İNDİRİLMEZ — sunucuya yalnızca "kaç tane
  /// var" diye sorulur. Resim/ses belgeleri base64 olarak megabaytlarca yer
  /// tuttuğu için burada `.get()` kullanmak felaket olurdu.
  static Future<int> _sayKind(
    DocumentReference<Map<String, dynamic>> base,
    ContentNotif kind,
    List<String> partners,
  ) async {
    if (kind.collection == 'questions') {
      final prefs = await SharedPreferences.getInstance();
      final day = formatIsoDate(DateTime.now());
      if (prefs.getString('question_seen_day') == day) return 0;
      final snap = await base.collection('questions').doc(day).get();
      final data = snap.data();
      final me = FirebaseAuth.instance.currentUser?.uid;
      final seenBy = data?['seenBy'];
      if (me != null && seenBy is List && seenBy.contains(me)) {
        await prefs.setString('question_seen_day', day);
        return 0;
      }
      final ans = data?['answers'];
      if (ans is Map) {
        for (final k in ans.keys) {
          if (partners.contains(k.toString())) return 1;
        }
      }
      return 0;
    }
    final agg = await base
        .collection(kind.collection)
        .where('from', whereIn: partners)
        .count()
        .get();
    return agg.count ?? 0;
  }

  /// Eşin eklediği içerik sayısını tür tür döndürür. Yedi tür AYNI ANDA
  /// sorulur; sırayla sorulsa yedi ayrı gidiş-dönüş beklenirdi.
  /// Hata/eşleşme yoksa boş döner.
  static Future<Map<String, int>> partnerCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cid = prefs.getString('couple_id');
      final myUid = prefs.getString('my_uid');
      if (cid == null || myUid == null || myUid.isEmpty) return {};

      final base = FirebaseFirestore.instance.collection('couples').doc(cid);
      final coupleDoc = await base.get();
      final members = (coupleDoc.data()?['members'] as List?) ?? [];
      final partners = [
        for (final m in members)
          if (m.toString() != myUid) m.toString(),
      ];
      if (partners.isEmpty) return {}; // eş henüz katılmamış

      final sonuclar = await Future.wait(
        kAllContentNotifs.map((k) => _sayKind(base, k, partners)),
      );
      return {
        for (int i = 0; i < kAllContentNotifs.length; i++)
          kAllContentNotifs[i].collection: sonuclar[i],
      };
    } catch (_) {
      return {};
    }
  }

  /// Elde hazır sayımlardan rozetleri hesaplar — ağa çıkmaz.
  static Future<Map<String, int>> unseenFrom(Map<String, int> counts) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, int> out = {};
    for (final kind in kAllContentNotifs) {
      final total = counts[kind.collection];
      if (total == null) continue;
      final seen = prefs.getInt(badgeKey(kind));
      if (seen == null) {
        // İlk açılış: mevcut içerik "eski" sayılsın, rozetler patlamasın.
        await prefs.setInt(badgeKey(kind), total);
        continue;
      }
      final fark = total - seen;
      if (fark > 0) out[kind.collection] = fark;
    }
    return out;
  }

  /// Elde hazır sayımlarla "görüldü" işaretler — ağa çıkmaz.
  static Future<void> markQuestionSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('question_seen_day', formatIsoDate(DateTime.now()));
  }

  static Future<void> markSeenWith(
    Map<String, int> counts,
    List<ContentNotif> kinds,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final n in kinds) {
        final total = counts[n.collection];
        if (total != null) await prefs.setInt(badgeKey(n), total);
      }
    } catch (_) {}
  }

  /// Kolaylık: say + hesapla. Sayımı zaten elinde olan çağıran
  /// [unseenFrom] kullanmalı ki ağa ikinci kez çıkılmasın.
  static Future<Map<String, int>> unseen() async {
    try {
      return await unseenFrom(await partnerCounts());
    } catch (_) {
      return {};
    }
  }
}

/// Kırmızı "+N" rozeti. Yalnızca uygulamanın içinde görünür; bildirim
/// çubuğuyla hiçbir ilgisi yoktur.
class YeniRozet extends StatelessWidget {
  final int sayi;
  const YeniRozet(this.sayi, {super.key});

  @override
  Widget build(BuildContext context) {
    if (sayi <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        "+$sayi",
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
