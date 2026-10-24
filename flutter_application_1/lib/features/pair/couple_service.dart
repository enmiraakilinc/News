import '../../core/utils/refresh_stream.dart';
import '../../core/data/oracle_firestore_bridge.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

Map<String, String?> decodeLetterBatch(Map<String, dynamic> payload) {
  final result = <String, String?>{};
  for (final entry in (payload['ciphers'] as Map<String, dynamic>).entries) {
    try {
      result[entry.key] = CoupleService._decrypt(
        entry.value as String,
        payload['secret'] as String,
      );
    } catch (_) {
      result[entry.key] = null;
    }
  }
  return result;
}

/// A live chat decodes only new/edited messages, not its entire recent history
/// again for every message, receipt or reaction update.
class LetterDecodeCache {
  final Future<Map<String, String?>> Function(Map<String, dynamic>) worker;
  final _ciphers = <String, String>{};
  final _decoded = <String, String?>{};
  String? _secret;
  LetterDecodeCache({
    Future<Map<String, String?>> Function(Map<String, dynamic>)? worker,
  }) : worker = worker ?? ((payload) => compute(decodeLetterBatch, payload));

  Future<Map<String, String?>> decode(
    String secret,
    Map<String, String> ciphers,
  ) async {
    if (_secret != secret) {
      _ciphers.clear();
      _decoded.clear();
      _secret = secret;
    }
    _ciphers.removeWhere((id, _) => !ciphers.containsKey(id));
    _decoded.removeWhere((id, _) => !ciphers.containsKey(id));
    final changed = {
      for (final entry in ciphers.entries)
        if (_ciphers[entry.key] != entry.value) entry.key: entry.value,
    };
    if (changed.isNotEmpty) {
      final result = await worker({'secret': secret, 'ciphers': changed});
      _ciphers.addAll(changed);
      _decoded.addAll(result);
    }
    return Map.of(_decoded);
  }
}

// Native compute runs large AES/base64 conversions off the UI thread.
Map<String, Uint8List?> decodePrivateImageBatch(Map<String, dynamic> payload) {
  final secret = payload['secret'] as String;
  final result = <String, Uint8List?>{};
  for (final entry in (payload['images'] as Map<String, dynamic>).entries) {
    try {
      result[entry.key] = base64Decode(
        CoupleService._decrypt(entry.value as String, secret),
      );
    } catch (_) {
      result[entry.key] = null;
    }
  }
  return result;
}

/// İki telefonu eşleştiren, mektupları uçtan uca şifreleyip Firebase üzerinden
/// senkronlayan servis.
///
/// Gizlilik modeli:
/// - Eşleşme kodu (6 hane) sadece "hangi çift" olduğunu bulmaya yarar.
/// - Asıl güvenlik "gizli kelime"den gelir: iki taraf aynı kelimeyi girer,
///   bu kelime SUNUCUYA HİÇ GİTMEZ, sadece cihazda saklanır.
/// - Mektup metni bu kelimeden türetilen anahtarla şifrelenir. Firebase yalnızca
///   şifreli metni ve açılış tarihini görür; içeriği okuyamaz.
class CoupleService {
  /// Reuse the pair's existing cipher format for separately scoped features.
  static String encodePrivateText(String text, String secret) =>
      _encrypt(text, secret);
  static String decodePrivateText(String text, String secret) =>
      _decrypt(text, secret);
  static Future<void> editLetter(String id, String text) async {
    final ref = await _coupleRef();
    final word = await secret();
    if (ref == null || word == null) throw Exception('Bağ bulunamadı.');
    final doc = ref.collection('letters').doc(id);
    if ((await doc.get()).data()?['from'] != uid) {
      throw Exception('Yalnızca kendi mesajını düzenleyebilirsin.');
    }
    await doc.update({
      'cipher': _encrypt(text, word),
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> reactLetter(
    String id,
    String emoji,
    String? current,
  ) async {
    final ref = await _coupleRef();
    if (ref == null) throw Exception('Bağ bulunamadı.');
    await ref.collection('letters').doc(id).update({
      'reactions.$uid': current == emoji ? FieldValue.delete() : emoji,
    });
  }

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Future<Map<String, Uint8List?>> _decodeImages(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    String secret,
  ) => compute(decodePrivateImageBatch, {
    'secret': secret,
    'images': {
      for (final document in snapshot.docs) document.id: document.data()['img'],
    },
  });

  /// Firebase henüz başlatılmadıysa null döner (açılışın ilk anları).
  static String? get uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  static const String _kCoupleId = 'couple_id';
  static const String _kSecret = 'couple_secret';

  // ── Eşleşme durumu ─────────────────────────────────────────
  static Future<String?> coupleId() async =>
      (await SharedPreferences.getInstance()).getString(_kCoupleId);

  static Future<String?> secret() async =>
      (await SharedPreferences.getInstance()).getString(_kSecret);

  static Future<bool> isPaired() async => (await coupleId()) != null;

  static Future<void> _saveLocal(String coupleId, String secret) async {
    clearStreamCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCoupleId, coupleId);
    await prefs.setString(_kSecret, secret);
  }

  /// Bu cihazda eşleşmeyi kaldırır (sunucudaki veriyi silmez).
  static Future<void> unpairLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCoupleId);
    await prefs.remove(_kSecret);
    // Sekme önbelleği eski çiftin içeriğini taşımasın.
    clearStreamCache();
  }

  // ── Oturum hazırlığı ───────────────────────────────────────
  // Firebase başlatma ve anonim oturum açma ağ ister; uygulama açılışı bunu
  // beklemez (yoksa açılış ekranında takılır). Ama Firestore'a oturum AÇILMADAN
  // bağlanılırsa sunucu dinlemeyi reddeder: istemci önce önbellekteki eski
  // kayıtları gösterir, ret cevabı gelince liste hata verip kaybolur.
  // Bu yüzden Firestore'a dokunan her yol önce buradan geçip oturumu bekler.

  static Future<void>? _readyFuture;
  static bool _preparing = false;

  /// Firebase başlatılana ve oturum açılana kadar bekler.
  static Future<void> ensureReady() {
    final mevcut = _readyFuture;
    if (mevcut != null) return mevcut;

    _preparing = true;
    final f = _prepare().whenComplete(() => _preparing = false);
    _readyFuture = f;
    // Başarısız olursa (internet yok) önbellekte kalmasın; sonraki deneme
    // sıfırdan başlasın.
    f.catchError((Object _) {
      if (identical(_readyFuture, f)) _readyFuture = null;
    });
    return f;
  }

  /// "Tekrar dene" için: bir sonraki istekte bağlantı sıfırdan kurulsun.
  /// Hazırlık hâlâ sürüyorsa dokunma — yoksa ikinci bir oturum açma başlar.
  static void resetConnection() {
    if (!_preparing) _readyFuture = null;
  }

  static Future<void> _prepare() async {
    await Firebase.initializeApp();
    installOracleReadBridge();
    final auth = FirebaseAuth.instance;
    if (auth.currentUser != null) return;

    // Chat-only accounts also need their persisted identity restored before
    // creating a new anonymous account, otherwise their contacts disappear.
    final restored = await auth.authStateChanges().first.timeout(
      const Duration(seconds: 5),
      onTimeout: () => auth.currentUser,
    );
    if (restored != null) return;

    // Eşleşme kayıtlıysa bu cihazın zaten bir hesabı var; oturumun diskten
    // yüklenmesini bekle. Beklemezsek yeni bir anonim hesap açılır: çift
    // fazladan bir üye kazanır ve eski hesabın yazdıkları "eşten gelmiş"
    // sayılmaz olur.
    if (await coupleId() != null) {
      for (int i = 0; i < 10 && auth.currentUser == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (auth.currentUser != null) return;
    }

    // Zayıf bağlantıda ilk deneme sık sık düşüyor — kısa aralıklarla tekrarla.
    Object? sonHata;
    for (int deneme = 0; deneme < 3; deneme++) {
      try {
        await auth.signInAnonymously();
        return;
      } catch (e) {
        sonHata = e;
        // Oturum bu arada başka bir yerden açılmış olabilir.
        if (auth.currentUser != null) return;
        await Future<void>.delayed(Duration(seconds: 1 << deneme));
      }
    }
    throw Exception('Bağlantı kurulamadı: $sonHata');
  }

  /// Sekmelerin son gördüğü içerik. Bir sekmeye tekrar girildiğinde liste
  /// anında görünsün diye tutulur (yoksa her girişte dönen çark beklenirdi).
  static final Map<String, Object?> _sonDeger = {};

  /// Oturum açılana kadar bekletip sonra asıl akışı yayan sarmalayıcı.
  /// Böylece ekranlar "yetkisiz dinleyici" hatası yerine dönen çarkı görür.
  ///
  /// [cacheKey] verilirse: akış önce EN SON bilinen içeriği yayar, ardından
  /// sunucudan geleni. Böylece sekmeler ilk açılıştan sonra anında açılır;
  /// tazelenme arka planda sessizce olur.
  static Stream<T> _gated<T>(
    String? cacheKey,
    Stream<T> Function() build,
  ) async* {
    if (cacheKey != null) {
      final onceki = _sonDeger[cacheKey];
      if (onceki is T) yield onceki;
    }
    await ensureReady().timeout(const Duration(seconds: 20));
    var received = false;
    await for (final deger in build().timeout(
      const Duration(seconds: 25),
      onTimeout: (sink) {
        if (!received) {
          sink.addError(TimeoutException('Kayıtlar yüklenemedi.'));
          sink.close();
        }
      },
    )) {
      received = true;
      if (cacheKey != null) _sonDeger[cacheKey] = deger;
      yield deger;
    }
  }

  /// Eşleşme kaldırılınca/değişince önbellek başka çifte sızmasın.
  static void clearStreamCache() => _sonDeger.clear();

  /// Eşleşilen çiftin Firestore kökü; oturumun açılmasını bekler.
  /// Eşleşme yoksa null döner.
  static Future<DocumentReference<Map<String, dynamic>>?> _coupleRef() async {
    final cid = await coupleId();
    if (cid == null) return null;
    await ensureReady();
    return _db.collection('couples').doc(cid);
  }

  // ── Şifreleme ──────────────────────────────────────────────
  static enc.Encrypter _encrypter(String secret) {
    final keyBytes = sha256.convert(utf8.encode(secret)).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));
    return enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
  }

  static enc.IV _randomIv() {
    final r = Random.secure();
    return enc.IV(
      Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256))),
    );
  }

  static String _encrypt(String plain, String secret) {
    final iv = _randomIv();
    final e = _encrypter(secret).encrypt(plain, iv: iv);
    return '${iv.base64}:${e.base64}';
  }

  static String _decrypt(String stored, String secret) {
    final parts = stored.split(':');
    final iv = enc.IV.fromBase64(parts[0]);
    return _encrypter(secret).decrypt64(parts[1], iv: iv);
  }

  /// Gizli kelimenin doğruluğunu kanıtlamak için (kelimenin kendisi değil).
  static String _secretCheck(String secret) =>
      sha256.convert(utf8.encode('check::$secret')).toString();

  static String _sixDigitCode() {
    final r = Random.secure();
    return List<int>.generate(6, (_) => r.nextInt(10)).join();
  }

  static String _loginId(String word) => 'secret-${_secretCheck(word)}';

  /// Mevcut eşleşmeleri yeni giriş akışına taşır; içerikleri değiştirmez.
  static Future<void> enableSecretLogin() async {
    final cid = await coupleId();
    final word = await secret();
    if (cid == null || word == null) return;
    await ensureReady();
    await _registerSecretLogin(cid, word);
  }

  static Future<void> _registerSecretLogin(String cid, String word) async {
    final ref = _db.collection('invites').doc(_loginId(word));
    await _db.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists && existing.data()!['coupleId'] != cid) {
        throw Exception('Bu gizli kelime başka bir bağda kullanılıyor.');
      }
      if (!existing.exists) tx.set(ref, {'coupleId': cid});
    });
  }

  static Future<void> signInWithSecret(String word) async {
    if (word.isEmpty) throw Exception('Gizli kelimeyi gir.');
    await ensureReady();
    final login = await _db.collection('invites').doc(_loginId(word)).get();
    if (!login.exists) {
      throw Exception(
        'Gizli kelime bulunamadı. Kelimeyi kontrol edip tekrar dene.',
      );
    }
    final cid = login.data()!['coupleId'] as String;
    final ref = _db.collection('couples').doc(cid);
    // Firestore validates the proof before granting private membership.
    // Non-members cannot read the stored secret hash.
    await ref.update({
      'members': FieldValue.arrayUnion([uid!]),
      'joinProof': _secretCheck(word),
    });
    await _saveLocal(cid, word);
  }

  /// Depolama/sıralama için tarih: 2026-03-17
  static String _isoDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  // ── Eşleşme ────────────────────────────────────────────────
  /// Yeni bir çift oluşturur, davet kodunu döndürür.
  static Future<String> createCouple(String secretWord) async {
    await ensureReady();
    final u = uid;
    if (u == null) throw Exception('Bağlantı yok');

    final coupleRef = _db.collection('couples').doc();
    final code = _sixDigitCode();

    final loginRef = _db.collection('invites').doc(_loginId(secretWord));
    await _db.runTransaction((tx) async {
      final existing = await tx.get(loginRef);
      if (existing.exists) {
        throw Exception(
          'Bu gizli kelime kullanılıyor. Gizli kelime ile giriş yap.',
        );
      }
      tx.set(coupleRef, {
        'members': [u],
        'secretCheck': _secretCheck(secretWord),
        'createdAt': FieldValue.serverTimestamp(),
      });
      tx.set(_db.collection('invites').doc(code), {'coupleId': coupleRef.id});
      tx.set(loginRef, {'coupleId': coupleRef.id});
    });

    await _saveLocal(coupleRef.id, secretWord);
    return code;
  }

  /// Aynı çift için yeni davet kodu üretir. Eski kod tek kullanımlıktır,
  /// ama mevcut eşleşme devam etsin diye yenisi yeniden oluşturulabilir.
  static Future<String> reissueInviteCode({String? coupleId}) async {
    await ensureReady();
    final cid = coupleId ?? await CoupleService.coupleId();
    if (cid == null) throw Exception('Eşleşme bulunamadı.');

    for (int i = 0; i < 1000; i++) {
      final code = _sixDigitCode();
      final inviteRef = _db.collection('invites').doc(code);
      final inviteSnap = await inviteRef.get();
      if (inviteSnap.exists) continue;

      await inviteRef.set({'coupleId': cid});
      return code;
    }

    throw Exception('Kod üretilemedi. Biraz sonra tekrar dene.');
  }

  /// Davet koduyla mevcut çifte katılır.
  static Future<void> joinCouple(String code, String secretWord) async {
    await ensureReady();
    final u = uid;
    if (u == null) throw Exception('Bağlantı yok');

    final inviteSnap = await _db.collection('invites').doc(code.trim()).get();
    if (!inviteSnap.exists) {
      await signInWithSecret(secretWord);
      return;
    }
    final coupleId = inviteSnap.data()!['coupleId'] as String;

    // Secret verification is enforced by the server on this update.
    await _db.collection('couples').doc(coupleId).update({
      'members': FieldValue.arrayUnion([u]),
      'joinProof': _secretCheck(secretWord),
    });
    await _registerSecretLogin(coupleId, secretWord);
    await _db.collection('invites').doc(code.trim()).delete();

    await _saveLocal(coupleId, secretWord);
  }

  // ── Mektuplar ──────────────────────────────────────────────
  /// Şifreli mektup gönderir. Açılış tarihi düz (şifresiz) saklanır ki
  /// kilitli kutunun üstünde "şu tarihte açılacak" yazabilsin.
  static Future<void> sendLetter({
    required String text,
    required String emoji,
    required DateTime? openDate,
    String? replyToId,
  }) async {
    final ref = await _coupleRef();
    final sec = await secret();
    if (ref == null || sec == null) throw Exception('Önce eşleşmelisin');

    await ref.collection('letters').add({
      'from': uid,
      'emoji': emoji,
      'cipher': _encrypt(text, sec),
      'openDate': openDate == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(openDate),
      'scheduled': openDate != null,
      'createdAt': FieldValue.serverTimestamp(),
      'replyTo': ?replyToId,
    });
  }

  /// Mektupları canlı dinler (yeni gelince anında güncellenir).
  static Stream<List<Letter>> lettersStream(
    String coupleId,
    String secret, {
    int limit = 100,
  }) {
    final decoder = LetterDecodeCache();
    return _gated(
      'letters:$coupleId:${_secretCheck(secret)}:$limit',
      () =>
          refreshStream(
            _db
                .collection('couples')
                .doc(coupleId)
                .collection('letters')
                .orderBy('createdAt', descending: true)
                .limit(limit)
                .snapshots(),
            nextRefreshAt: (snapshot) {
              final now = DateTime.now();
              DateTime? next;
              for (final document in snapshot.docs) {
                if (document.data()['scheduled'] == false) continue;
                final date =
                    (document.data()['openDate'] as Timestamp?)?.toDate() ??
                    DateTime.now();
                if (date.isAfter(now) &&
                    (next == null || date.isBefore(next))) {
                  next = date;
                }
              }
              return next;
            },
          ).asyncMap((snap) async {
            final decoded = await decoder.decode(secret, {
              for (final doc in snap.docs)
                if (doc.data()['scheduled'] == false ||
                    !(doc.data()['openDate'] as Timestamp).toDate().isAfter(
                      DateTime.now(),
                    ))
                  doc.id: doc.data()['cipher'] as String,
            });
            final list = snap.docs.map((d) {
              final data = d.data();
              final openDate =
                  (data['openDate'] as Timestamp?)?.toDate() ?? DateTime.now();
              final bool acildi =
                  data['scheduled'] == false ||
                  !openDate.isAfter(DateTime.now());
              // Gönderim zamanı. serverTimestamp yazılana kadar kısa süre null olur.
              final ts = data['createdAt'];
              final DateTime? sentDate = ts is Timestamp ? ts.toDate() : null;
              final bool readByRecipient = data['readByRecipient'] == true;
              // Alıcının mektubu açtığı an. Eski mektuplarda bu alan yok → null.
              final rts = data['readAt'];
              final DateTime? readAt = rts is Timestamp ? rts.toDate() : null;
              String? metin;
              if (acildi) {
                try {
                  metin =
                      decoded[d.id] ??
                      '(Bu mektup çözülemedi — gizli kelime farklı olabilir.)';
                } catch (_) {
                  metin =
                      '(Bu mektup çözülemedi — gizli kelime farklı olabilir.)';
                }
              }
              return Letter(
                id: d.id,
                reactions: Map<String, String>.from(data['reactions'] ?? {}),
                edited: data['editedAt'] != null,
                fromMe: data['from'] == uid,
                emoji: (data['emoji'] ?? '💌').toString(),
                openDate: openDate,
                sentDate: sentDate,
                readByRecipient: readByRecipient,
                readAt: readAt,
                replyToId: data['replyTo'] as String?,
                text: metin, // açılmadıysa null
              );
            }).toList();
            // En son gelen mektup en ÜSTTE olsun (yeniden eskiye). Firestore
            // sorgusu açılış tarihine göre sıralı geliyor; burada gönderim anına
            // göre yeniden diziyoruz ki liste hep yukarıdan aşağı aksın.
            list.sort((a, b) {
              final ad = a.sentDate ?? a.openDate;
              final bd = b.sentDate ?? b.openDate;
              return bd.compareTo(ad);
            });
            return list;
          }),
    );
  }

  static Future<void> deleteLetter(String letterId) async {
    final ref = await _coupleRef();
    if (ref == null) return;
    await ref.collection('letters').doc(letterId).delete();
  }

  /// Alıcı mektubu açıp okuduğunda çağrılır. Yalnızca alıcı (gönderen olmayan)
  /// tarafın çağırması beklenir; gönderen bunu "Okundu" olarak görür.
  static Future<void> markLetterRead(String letterId) async {
    try {
      final ref = await _coupleRef();
      if (ref == null) return;
      await ref.collection('letters').doc(letterId).update({
        'readByRecipient': true,
        // Açıldığı an — gönderen tarafta "Açıldı: …" olarak görünür.
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // İnternet yok / yarış durumu — sessizce geç, sonraki açılışta tekrar denenir.
    }
  }

  // ── Anılar (paylaşımlı anılar) ───────────────────────
  /// Bir anıyı çifte ekler. Fotoğraf, mektuplar gibi UÇTAN UCA şifrelenir:
  /// Firebase yalnızca şifreli baytları görür. Fotoğraf çağıran tarafça
  /// önceden küçültülüp verilmelidir (Firestore belge sınırı ~1MB).
  static Future<void> addTimelineMemory({
    required Uint8List imageBytes,
    required DateTime date,
    required String place,
    required String note,
  }) async {
    final ref = await _coupleRef();
    final sec = await secret();
    if (ref == null || sec == null) throw Exception('Önce eşleşmelisin');

    final String imgCipher = _encrypt(base64Encode(imageBytes), sec);
    // Şifreli hâli bile Firestore belge sınırına (≈1MB) sığmalı.
    if (imgCipher.length > 1000000) {
      throw Exception(
        'Fotoğraf çok büyük. Daha küçük/başka bir fotoğraf dene.',
      );
    }
    final String metaCipher = _encrypt(
      jsonEncode({'place': place, 'note': note}),
      sec,
    );

    await ref.collection('timeline').add({
      'from': uid,
      'img': imgCipher,
      'meta': metaCipher,
      'date': _isoDate(date), // düz — sıralama/başlık için
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Çiftin anılarını canlı dinler (yeni eklenince iki telefonda da belirir).
  static Stream<List<TimelineMemory>> timelineStream(
    String coupleId,
    String secret,
  ) {
    // Önbelleğe ALINMAZ: her anı çözülmüş bir fotoğraf taşır. Bellekte tutmak
    // onlarca MB'ı kalıcı olarak canlı tutar ve çöp toplayıcıyı sürekli
    // çalıştırıp tüm uygulamayı yavaşlatır.
    return _gated(
      null,
      () => _db
          .collection('couples')
          .doc(coupleId)
          .collection('timeline')
          .orderBy('date', descending: true)
          .snapshots()
          .asyncMap((snap) async {
            final decoded = await _decodeImages(snap, secret);
            return snap.docs.map((d) {
              final data = d.data();
              final bytes = decoded[d.id];
              String place = '';
              String note = '';
              try {
                final m =
                    jsonDecode(_decrypt(data['meta'] as String, secret))
                        as Map<String, dynamic>;
                place = (m['place'] ?? '').toString();
                note = (m['note'] ?? '').toString();
              } catch (_) {}
              return TimelineMemory(
                id: d.id,
                fromMe: data['from'] == uid,
                ownerUid: (data['from'] ?? '').toString(),
                focus: (data['focus'] as num?)?.toDouble() ?? 0,
                date:
                    DateTime.tryParse((data['date'] ?? '').toString()) ??
                    DateTime.now(),
                place: place,
                note: note,
                image: bytes,
              );
            }).toList();
          }),
    );
  }

  /// Tünel kartında fotoğrafın hangi kısmının görüneceğini kaydeder.
  /// [focus] -1 (üst) ile 1 (alt) arasında; 0 = orta.
  static Future<void> setTimelineFocus(String id, double focus) async {
    try {
      final ref = await _coupleRef();
      if (ref == null) return;
      await ref.collection('timeline').doc(id).update({'focus': focus});
    } catch (_) {}
  }

  static Future<void> deleteTimelineMemory(String id) async {
    final ref = await _coupleRef();
    if (ref == null) return;
    await ref.collection('timeline').doc(id).delete();
  }

  // ── Günün Sorusu ───────────────────────────────────────────
  static String todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Bugünün soru-cevap belgesini canlı dinler.
  static Stream<DailyAnswers> todayAnswersStream(
    String coupleId,
    String secret,
    int qIndex,
  ) {
    return _gated('questions', () {
      final me = uid;
      return _db
          .collection('couples')
          .doc(coupleId)
          .collection('questions')
          .doc(todayKey())
          .snapshots()
          .map((doc) {
            String? mine;
            String? partner;
            final data = doc.data();
            if (data != null && data['answers'] is Map) {
              final answers = Map<String, dynamic>.from(data['answers']);
              answers.forEach((u, cipher) {
                String metin;
                try {
                  metin = _decrypt(cipher as String, secret);
                } catch (_) {
                  metin = '(çözülemedi)';
                }
                if (u == me) {
                  mine = metin;
                } else {
                  partner = metin;
                }
              });
            }
            return DailyAnswers(myAnswer: mine, partnerAnswer: partner);
          });
    });
  }

  static Future<void> setTodayAnswer(String text) async {
    final ref = await _coupleRef();
    final sec = await secret();
    final me = uid;
    if (ref == null || sec == null || me == null) {
      throw Exception('Eşleşme yok');
    }

    await ref.collection('questions').doc(todayKey()).set({
      'answers': {me: _encrypt(text, sec)},
    }, SetOptions(merge: true));
  }

  // ── Ortak Dilekler (paylaşımlı hayal / yapılacak listesi) ──
  /// Yeni dilek ekler. Metin mektuplar gibi UÇTAN UCA şifrelenir.
  static Future<void> addWish(String text) async {
    final ref = await _coupleRef();
    final sec = await secret();
    if (ref == null || sec == null) throw Exception('Önce eşleşmelisin');
    await ref.collection('wishes').add({
      'from': uid,
      'cipher': _encrypt(text, sec),
      'done': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Dilekleri canlı dinler. Bekleyenler üstte (yeni→eski), gerçekleşenler
  /// altta (son gerçekleşen üstte) sıralanır — istemci tarafında, indeks gerekmez.
  static Stream<List<Wish>> wishesStream(String coupleId, String secret) {
    return _gated(
      'wishes',
      () => _db
          .collection('couples')
          .doc(coupleId)
          .collection('wishes')
          .snapshots()
          .map((snap) {
            final list = snap.docs.map((d) {
              final data = d.data();
              String text;
              try {
                text = _decrypt(data['cipher'] as String, secret);
              } catch (_) {
                text = '(çözülemedi — gizli kelime farklı olabilir)';
              }
              final ts = data['createdAt'];
              final dts = data['doneAt'];
              return Wish(
                id: d.id,
                fromMe: data['from'] == uid,
                text: text,
                done: data['done'] == true,
                doneByMe: data['doneBy'] == uid,
                createdAt: ts is Timestamp ? ts.toDate() : null,
                doneAt: dts is Timestamp ? dts.toDate() : null,
              );
            }).toList();
            list.sort((a, b) {
              if (a.done != b.done) return a.done ? 1 : -1;
              final at =
                  (a.done ? a.doneAt : a.createdAt)?.millisecondsSinceEpoch ??
                  0;
              final bt =
                  (b.done ? b.doneAt : b.createdAt)?.millisecondsSinceEpoch ??
                  0;
              return bt.compareTo(at);
            });
            return list;
          }),
    );
  }

  /// Dileği gerçekleşti/bekliyor olarak işaretler.
  static Future<void> setWishDone(String id, bool done) async {
    final ref = await _coupleRef();
    if (ref == null) return;
    await ref.collection('wishes').doc(id).update({
      'done': done,
      'doneBy': done ? uid : FieldValue.delete(),
      'doneAt': done ? FieldValue.serverTimestamp() : FieldValue.delete(),
    });
  }

  static Future<void> deleteWish(String id) async {
    final ref = await _coupleRef();
    if (ref == null) return;
    await ref.collection('wishes').doc(id).delete();
  }

  // ── Sesli Notlar (paylaşımlı) ──────────────────────────────
  /// Sesli notu ekler. Ses de mektuplar gibi UÇTAN UCA şifrelenir. Kayıt
  /// çağıran tarafça küçük tutulmalı (Firestore belge sınırı ~1MB).
  static Future<void> addVoiceNote({
    required Uint8List audioBytes,
    required String title,
  }) async {
    final ref = await _coupleRef();
    final sec = await secret();
    if (ref == null || sec == null) throw Exception('Önce eşleşmelisin');
    final cipher = _encrypt(base64Encode(audioBytes), sec);
    if (cipher.length > 1000000) {
      throw Exception('Kayıt çok uzun. Daha kısa bir kayıt bırak.');
    }
    await ref.collection('voicenotes').add({
      'from': uid,
      'audio': cipher,
      'title': _encrypt(title, sec),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Sesli notları canlı dinler (yeni gelince iki telefonda da belirir).
  static Stream<List<VoiceNote>> voiceNotesStream(
    String coupleId,
    String secret,
  ) {
    // Önbelleğe ALINMAZ — çözülmüş ses baytları taşır.
    return _gated(
      null,
      () => _db
          .collection('couples')
          .doc(coupleId)
          .collection('voicenotes')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map(
            (snap) => snap.docs.map((d) {
              final data = d.data();
              Uint8List? bytes;
              try {
                bytes = base64Decode(_decrypt(data['audio'] as String, secret));
              } catch (_) {
                bytes = null;
              }
              String title;
              try {
                title = _decrypt(data['title'] as String, secret);
              } catch (_) {
                title = 'Sesli not';
              }
              final ts = data['createdAt'];
              return VoiceNote(
                id: d.id,
                fromMe: data['from'] == uid,
                title: title,
                createdAt: ts is Timestamp ? ts.toDate() : null,
                audio: bytes,
                readByRecipient: data['readByRecipient'] == true,
              );
            }).toList(),
          ),
    );
  }

  static Future<void> deleteVoiceNote(String id) async {
    final ref = await _coupleRef();
    if (ref == null) return;
    await ref.collection('voicenotes').doc(id).delete();
  }

  /// Sesli notu dinleyen (gönderen olmayan) taraf çağırır.
  static Future<void> markVoiceNoteRead(String id) async {
    try {
      final ref = await _coupleRef();
      if (ref == null) return;
      await ref.collection('voicenotes').doc(id).update({
        'readByRecipient': true,
      });
    } catch (_) {}
  }

  // ── Gizli Resimler (paylaşımlı) ────────────────────────────
  /// Gizli resmi ekler. Resim UÇTAN UCA şifrelenir; çağıran taraf önceden
  /// küçültmelidir (Firestore belge sınırı ~1MB).
  static Future<void> addHiddenImage(Uint8List imageBytes) async {
    final ref = await _coupleRef();
    final sec = await secret();
    if (ref == null || sec == null) throw Exception('Önce eşleşmelisin');
    final cipher = _encrypt(base64Encode(imageBytes), sec);
    if (cipher.length > 1000000) {
      throw Exception('Fotoğraf çok büyük. Başka bir fotoğraf dene.');
    }
    await ref.collection('hiddenimages').add({
      'from': uid,
      'img': cipher,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<List<HiddenImage>> hiddenImagesStream(
    String coupleId,
    String secret,
  ) {
    // Önbelleğe ALINMAZ — çözülmüş resim baytları taşır (bkz. timelineStream).
    return _gated(
      null,
      () => _db
          .collection('couples')
          .doc(coupleId)
          .collection('hiddenimages')
          .orderBy('createdAt', descending: true)
          .snapshots()
          .asyncMap((snap) async {
            final decoded = await _decodeImages(snap, secret);
            return snap.docs.map((d) {
              final data = d.data();
              final bytes = decoded[d.id];
              // Emoji tepkiler: {uid: emoji}
              String? mine;
              String? theirs;
              final rx = data['reactions'];
              if (rx is Map) {
                rx.forEach((k, v) {
                  if (k == uid) {
                    mine = v.toString();
                  } else {
                    theirs = v.toString();
                  }
                });
              }
              return HiddenImage(
                id: d.id,
                fromMe: data['from'] == uid,
                image: bytes,
                ownerUid: (data['from'] ?? '').toString(),
                myReaction: mine,
                partnerReaction: theirs,
              );
            }).toList();
          }),
    );
  }

  static Future<void> deleteHiddenImage(String id) async {
    final ref = await _coupleRef();
    if (ref == null) return;
    await ref.collection('hiddenimages').doc(id).delete();
  }

  /// Gizli resme emoji tepki bırakır. [emoji] boş/null ise tepkiyi kaldırır.
  static Future<void> setHiddenImageReaction(String id, String? emoji) async {
    try {
      final couple = await _coupleRef();
      final u = uid;
      if (couple == null || u == null) return;
      final ref = couple.collection('hiddenimages').doc(id);
      if (emoji == null || emoji.isEmpty) {
        await ref.update({'reactions.$u': FieldValue.delete()});
      } else {
        await ref.set({
          'reactions': {u: emoji},
        }, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  // ── Özel Günler & Notlar (paylaşımlı) ──────────────────────
  /// Not/özel gün ekler. Metin şifrelenir; [date] doluysa (yyyy-MM-dd) bu bir
  /// özel gündür ve gün sayacı tutulur.
  static Future<void> addNote({
    required String text,
    required String emoji,
    String? date,
  }) async {
    final ref = await _coupleRef();
    final sec = await secret();
    if (ref == null || sec == null) throw Exception('Önce eşleşmelisin');
    await ref.collection('notes').add({
      'from': uid,
      'cipher': _encrypt(text, sec),
      'emoji': emoji,
      'date': date, // düz — sıralama/sayaç için, null olabilir
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<List<CoupleNote>> notesStream(String coupleId, String secret) {
    return _gated(
      'notes',
      () => _db
          .collection('couples')
          .doc(coupleId)
          .collection('notes')
          .snapshots()
          .map(
            (snap) => snap.docs.map((d) {
              final data = d.data();
              String text;
              try {
                text = _decrypt(data['cipher'] as String, secret);
              } catch (_) {
                text = '(çözülemedi)';
              }
              return CoupleNote(
                id: d.id,
                fromMe: data['from'] == uid,
                text: text,
                emoji: (data['emoji'] ?? '📌').toString(),
                date: data['date'] as String?,
              );
            }).toList(),
          ),
    );
  }

  static Future<void> deleteNote(String id) async {
    final ref = await _coupleRef();
    if (ref == null) return;
    await ref.collection('notes').doc(id).delete();
  }

  // ── Fotoğraf indirme izni ──────────────────────────────────
  /// Eşin yüklediği fotoğrafı indirmek için ondan izin ister.
  /// [kind]: 'hiddenimage' | 'timeline'
  static Future<void> requestDownload({
    required String kind,
    required String itemId,
    required String ownerUid,
  }) async {
    final ref = await _coupleRef();
    final u = uid;
    if (ref == null || u == null) throw Exception('Önce eşleşmelisin');
    await ref.collection('downloadRequests').add({
      'from': u,
      'owner': ownerUid,
      'kind': kind,
      'itemId': itemId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static DownloadRequest _toRequest(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final data = d.data();
    return DownloadRequest(
      id: d.id,
      fromUid: (data['from'] ?? '').toString(),
      ownerUid: (data['owner'] ?? '').toString(),
      kind: (data['kind'] ?? '').toString(),
      itemId: (data['itemId'] ?? '').toString(),
      status: (data['status'] ?? '').toString(),
    );
  }

  /// Sahibi ben olan, onay bekleyen istekler (bana "kabul ediyor musun?" sorulacak).
  static Stream<List<DownloadRequest>> incomingDownloadRequests(
    String coupleId,
  ) {
    // İzin istekleri anlıktır — önbellekten eski istek gösterilmemeli.
    return _gated(
      null,
      () => _db
          .collection('couples')
          .doc(coupleId)
          .collection('downloadRequests')
          .where('owner', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((s) => s.docs.map(_toRequest).toList()),
    );
  }

  /// Benim isteyip onaylanan indirmeler (artık kaydedebilirim).
  static Stream<List<DownloadRequest>> myApprovedDownloads(String coupleId) {
    return _gated(
      null,
      () => _db
          .collection('couples')
          .doc(coupleId)
          .collection('downloadRequests')
          .where('from', isEqualTo: uid)
          .where('status', isEqualTo: 'approved')
          .snapshots()
          .map((s) => s.docs.map(_toRequest).toList()),
    );
  }

  static Future<void> respondDownload(String id, bool approved) async {
    final ref = await _coupleRef();
    if (ref == null) return;
    await ref.collection('downloadRequests').doc(id).update({
      'status': approved ? 'approved' : 'denied',
    });
  }

  /// İstek işi bitince (kaydedildi/iptal) kaydı temizler.
  static Future<void> clearDownloadRequest(String id) async {
    try {
      final ref = await _coupleRef();
      if (ref == null) return;
      await ref.collection('downloadRequests').doc(id).delete();
    } catch (_) {}
  }

  /// Tek bir gizli resmi kimliğiyle getirir (indirme onaylanınca kaydetmek için).
  static Future<Uint8List?> fetchHiddenImageBytes(String id) async {
    try {
      final ref = await _coupleRef();
      final sec = await secret();
      if (ref == null || sec == null) return null;
      final d = await ref.collection('hiddenimages').doc(id).get();
      final img = d.data()?['img'];
      if (img is String) return base64Decode(_decrypt(img, sec));
    } catch (_) {}
    return null;
  }

  /// Tek bir tünel fotoğrafını kimliğiyle getirir.
  static Future<Uint8List?> fetchTimelineImageBytes(String id) async {
    try {
      final ref = await _coupleRef();
      final sec = await secret();
      if (ref == null || sec == null) return null;
      final d = await ref.collection('timeline').doc(id).get();
      final img = d.data()?['img'];
      if (img is String) return base64Decode(_decrypt(img, sec));
    } catch (_) {}
    return null;
  }
}

/// Günün sorusuna iki tarafın cevabı.
class DailyAnswers {
  final String? myAnswer;
  final String? partnerAnswer;
  DailyAnswers({this.myAnswer, this.partnerAnswer});
}

/// Bir mektubun ekrana taşınmış hali. [text] null ise kutu henüz kilitli.
class Letter {
  final String id;
  final Map<String, String> reactions;
  final bool edited;
  final bool fromMe;
  final String emoji;

  /// Mektubun açılacağı (kilidinin kalkacağı) gün.
  final DateTime openDate;

  /// Mektubun gönderildiği an. Sunucu zaman damgası yazılana kadar null olabilir.
  final DateTime? sentDate;

  /// Alıcı mektubu açıp okudu mu. Kilit açılmasından ("acildi") bağımsızdır:
  /// tarih gelince kilit açılır ama okunmuş sayılmaz — alıcı dokunup okuyunca true olur.
  final bool readByRecipient;

  /// Alıcının mektubu açtığı an. Eski (bu özellikten önceki) mektuplarda null.
  final DateTime? readAt;

  /// Bu mektup başka bir mektuba yanıtsa, onun kimliği.
  final String? replyToId;

  final String? text;

  Letter({
    required this.id,
    this.reactions = const {},
    this.edited = false,
    required this.fromMe,
    required this.emoji,
    required this.openDate,
    required this.sentDate,
    required this.readByRecipient,
    required this.text,
    this.readAt,
    this.replyToId,
  });

  /// Kilit açıldı mı (açılış tarihi geçti mi). Okunma ile karıştırılmamalı.
  bool get acildi => text != null;
}

/// Anılarndeki bir anının ekrana taşınmış hali. [image] çözülemezse null.
class TimelineMemory {
  final String id;
  final bool fromMe;
  final DateTime date;
  final String place;
  final String note;
  final Uint8List? image;

  /// Yükleyenin kimliği — indirme izni isterken gerekir.
  final String ownerUid;

  /// Kartta fotoğrafın hangi kısmının görüneceği: -1 üst, 0 orta, 1 alt.
  final double focus;

  TimelineMemory({
    required this.id,
    required this.fromMe,
    required this.date,
    required this.place,
    required this.note,
    required this.image,
    this.ownerUid = '',
    this.focus = 0,
  });
}

/// Ortak dilek listesindeki bir madde.
class Wish {
  final String id;
  final bool fromMe; // dileği ben mi ekledim
  final String text;
  final bool done; // gerçekleşti mi
  final bool doneByMe; // gerçekleşti işaretini ben mi koydum
  final DateTime? createdAt;
  final DateTime? doneAt;

  Wish({
    required this.id,
    required this.fromMe,
    required this.text,
    required this.done,
    required this.doneByMe,
    required this.createdAt,
    required this.doneAt,
  });
}

/// Paylaşımlı bir sesli not. [audio] çözülemezse null.
class VoiceNote {
  final String id;
  final bool fromMe;
  final String title;
  final DateTime? createdAt;
  final Uint8List? audio;

  /// Alıcı bu sesli notu dinledi mi (mektuplardaki okundu bilgisi gibi).
  final bool readByRecipient;

  VoiceNote({
    required this.id,
    required this.fromMe,
    required this.title,
    required this.createdAt,
    required this.audio,
    required this.readByRecipient,
  });
}

/// Paylaşımlı gizli resim. [image] çözülemezse null.
class HiddenImage {
  final String id;
  final bool fromMe;
  final Uint8List? image;

  /// Yükleyenin kimliği — indirme izni isterken gerekir.
  final String ownerUid;

  /// Emoji tepkiler: benimki ve eşinki (yoksa null).
  final String? myReaction;
  final String? partnerReaction;

  HiddenImage({
    required this.id,
    required this.fromMe,
    required this.image,
    this.ownerUid = '',
    this.myReaction,
    this.partnerReaction,
  });
}

/// Fotoğraf indirme izni isteği (sahibi onaylayınca indirilebilir).
class DownloadRequest {
  final String id;
  final String fromUid; // isteyen
  final String ownerUid; // fotoğrafın sahibi
  final String kind; // 'hiddenimage' | 'timeline'
  final String itemId;
  final String status; // pending | approved | denied

  DownloadRequest({
    required this.id,
    required this.fromUid,
    required this.ownerUid,
    required this.kind,
    required this.itemId,
    required this.status,
  });
}

/// Paylaşımlı not / özel gün. [date] doluysa özel gündür (gün sayacı tutulur).
class CoupleNote {
  final String id;
  final bool fromMe;
  final String text;
  final String emoji;
  final String? date;

  CoupleNote({
    required this.id,
    required this.fromMe,
    required this.text,
    required this.emoji,
    required this.date,
  });
}
