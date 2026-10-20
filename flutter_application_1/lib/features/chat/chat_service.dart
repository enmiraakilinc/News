import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../pair/couple_service.dart';
import '../../core/utils/refresh_stream.dart';
import '../media/chat_media.dart';

class ChatProfile {
  final String name;
  final String emoji;
  final Uint8List? photo;
  ChatProfile({required this.name, this.emoji = '👤', this.photo});
  factory ChatProfile.fromData(Map<String, dynamic> data) {
    Uint8List? photo;
    final encoded = data['photo'];
    if (encoded is String && encoded.length <= 32768 && encoded.isNotEmpty) {
      try {
        photo = base64Decode(encoded);
      } catch (_) {}
    }
    return ChatProfile(
      name: data['name'] as String? ?? '',
      emoji: data['emoji'] as String? ?? '👤',
      photo: photo,
    );
  }
}

class Conversation {
  final String id;
  final bool group;
  final String title;
  final List<String> members;
  final Map<String, String> names;
  final DateTime? updatedAt;
  Conversation({
    required this.id,
    required this.group,
    required this.title,
    required this.members,
    required this.names,
    this.updatedAt,
  });
  String get displayTitle => group
      ? title
      : names.entries
                .where((e) => e.key != CoupleService.uid)
                .map((e) => e.value)
                .firstOrNull ??
            'Sohbet';
}

class ChatMessage {
  final String id;
  final Map<String, String> reactions;
  final bool edited;
  final String sender;
  final String text;
  final DateTime sentAt;
  final DateTime openAt;
  final String? replyTo;
  final List<String> readBy;
  final bool scheduled;
  final bool pending;
  ChatMessage({
    required this.id,
    this.reactions = const {},
    this.edited = false,
    required this.sender,
    required this.text,
    required this.sentAt,
    required this.openAt,
    required this.readBy,
    this.replyTo,
    this.scheduled = true,
    this.pending = false,
  });
  bool get mine => sender == CoupleService.uid;
  bool get unlocked => !scheduled || !openAt.isAfter(DateTime.now());
}

class ChatService {
  static Future<void> edit(String id, String messageId, String text) async {
    await _db
        .collection('chats')
        .doc(id)
        .collection('messages')
        .doc(messageId)
        .update({'text': text, 'editedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> react(
    String id,
    String messageId,
    String emoji,
    String? current,
  ) async {
    await _db
        .collection('chats')
        .doc(id)
        .collection('messages')
        .doc(messageId)
        .update({
          'reactions.$_uid': current == emoji ? FieldValue.delete() : emoji,
        });
  }

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static String get _uid => CoupleService.uid!;
  static Stream<T> _ready<T>(Stream<T> Function() source) async* {
    await CoupleService.ensureReady().timeout(const Duration(seconds: 20));
    var received = false;
    await for (final value in source().timeout(
      const Duration(seconds: 25),
      onTimeout: (sink) {
        if (!received) {
          sink.addError(TimeoutException('Sohbet yüklenemedi.'));
          sink.close();
        }
      },
    )) {
      received = true;
      yield value;
    }
  }

  static Future<String?> myName({bool cacheOnly = false}) async {
    await CoupleService.ensureReady();
    final doc = await _db
        .collection('chatProfiles')
        .doc(_uid)
        .get(
          cacheOnly
              ? const GetOptions(source: Source.cache)
              : const GetOptions(),
        );
    return doc.data()?['name'] as String?;
  }

  static Stream<ChatProfile?> profileStream(String userId) => _ready(
    () => _db
        .collection('chatProfiles')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? ChatProfile.fromData(doc.data()!) : null),
  );

  static Future<void> saveAvatar({String? emoji, Uint8List? photo}) async {
    if ((emoji == null) == (photo == null) ||
        (emoji != null && (emoji.isEmpty || utf8.encode(emoji).length > 64)) ||
        (photo != null && (photo.isEmpty || photo.length > 24576))) {
      throw Exception('Profil resmi en fazla 24 KB olabilir.');
    }
    await CoupleService.ensureReady();
    await _db.collection('chatProfiles').doc(_uid).set({
      'name': await myName() ?? 'Kullanıcı',
      'emoji': emoji ?? '',
      'photo': photo == null ? '' : base64Encode(photo),
    }, SetOptions(merge: true));
  }

  static Future<void> saveName(String name) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 40) {
      throw Exception('1–40 karakterlik bir ad yaz.');
    }
    await CoupleService.ensureReady();
    await _db.collection('chatProfiles').doc(_uid).set({
      'name': clean,
    }, SetOptions(merge: true));
  }

  /// The owner is already attached to the generated code; entering it on the
  /// second device creates the shared direct conversation for both people.
  static Future<String> createInvite() async {
    await CoupleService.ensureReady();
    final name = await myName();
    if (name == null) throw Exception('Önce sohbet adını kaydet.');
    final random = Random.secure();
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = List.generate(8, (_) => random.nextInt(10)).join();
      final ref = _db.collection('chatInvites').doc(code);
      final created = await _db.runTransaction((tx) async {
        if ((await tx.get(ref)).exists) return false;
        tx.set(ref, {
          'owner': _uid,
          'name': name,
          'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(hours: 1)),
          ),
          'usedBy': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (created) return code;
    }
    throw Exception('Kod üretilemedi. Tekrar dene.');
  }

  static String directId(String first, String second) {
    final ids = [first, second]..sort();
    return 'direct_${ids.join('_')}';
  }

  static String normalizeInviteCode(String code) =>
      code.replaceAll(RegExp(r'[\s\-]'), '');

  static Future<String> acceptInvite(String code) async {
    code = normalizeInviteCode(code);
    if (!RegExp(r'^\d{8}$').hasMatch(code)) {
      throw Exception('8 haneli davet kodunu gir.');
    }
    await CoupleService.ensureReady();
    final name = await myName();
    if (name == null) throw Exception('Önce sohbet adını kaydet.');
    return _db.runTransaction((tx) async {
      final ref = _db.collection('chatInvites').doc(code.trim());
      final invite = await tx.get(ref);
      final data = invite.data();
      if (data == null) throw Exception('Davet kodu bulunamadı.');
      // Server rules enforce expiry independently of the phone clock.
      final owner = data['owner'] as String;
      if (owner == _uid) {
        throw Exception(
          'Bu senin kodun. Diğer kişi bu kodu girince ikinizde de sohbet açılır.',
        );
      }
      if (data['usedBy'] != null && data['usedBy'] != _uid) {
        throw Exception('Bu kod kullanılmış.');
      }
      final id = directId(owner, _uid);
      final conversation = _db.collection('chats').doc(id);
      final existing = await tx.get(conversation);
      if (!existing.exists) {
        tx.set(conversation, {
          'group': false,
          'title': '',
          'members': [owner, _uid],
          'names': {owner: data['name'], _uid: name},
          'createdBy': _uid,
          'updatedAt': FieldValue.serverTimestamp(),
          'inviteCode': code.trim(),
        });
      }
      if (data['usedBy'] == null) tx.update(ref, {'usedBy': _uid});
      return id;
    });
  }

  static Stream<List<Conversation>> conversations() => _ready(
    () => _db
        .collection('chats')
        .where('members', arrayContains: _uid)
        .snapshots()
        .map((snapshot) {
          final result = snapshot.docs
              .map((doc) => _conversation(doc))
              .toList();
          result.sort(
            (a, b) => (b.updatedAt ?? DateTime(2000)).compareTo(
              a.updatedAt ?? DateTime(2000),
            ),
          );
          return result;
        }),
  );

  static Conversation _conversation(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return Conversation(
      id: doc.id,
      group: data['group'] == true,
      title: data['title'] as String,
      members: List<String>.from(data['members']),
      names: Map<String, String>.from(data['names']),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  static Future<String> createGroup(
    String title,
    Map<String, String> selected,
  ) async {
    await CoupleService.ensureReady();
    final name = await myName();
    if (name == null ||
        title.trim().isEmpty ||
        title.trim().length > 60 ||
        selected.length < 2 ||
        selected.length > 19) {
      throw Exception('Grup adı yaz ve 2–19 kişi seç.');
    }
    final ref = _db.collection('chats').doc();
    await ref.set({
      'group': true,
      'title': title.trim(),
      'members': [_uid, ...selected.keys],
      'names': {_uid: name, ...selected},
      'createdBy': _uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Stream<List<ChatMessage>> messages(
    String id, {
    int limit = 100,
  }) => _ready(
    () =>
        refreshStream(
          _db
              .collection('chats')
              .doc(id)
              .collection('messages')
              .orderBy('sentAt', descending: true)
              .limit(limit)
              .snapshots(),
          nextRefreshAt: (snapshot) {
            final now = DateTime.now();
            DateTime? next;
            for (final document in snapshot.docs) {
              if (document.data()['scheduled'] == false) continue;
              final date =
                  (document.data()['openAt'] as Timestamp?)?.toDate() ??
                  DateTime.now();
              if (date.isAfter(now) && (next == null || date.isBefore(next))) {
                next = date;
              }
            }
            return next;
          },
        ).map((snapshot) {
          final result = snapshot.docs.map((doc) {
            final data = doc.data();
            return ChatMessage(
              id: doc.id,
              reactions: Map<String, String>.from(data['reactions'] ?? {}),
              edited: data['editedAt'] != null,
              scheduled: data['scheduled'] != false,
              pending: doc.metadata.hasPendingWrites && data['sentAt'] == null,
              sender: data['sender'] as String,
              text: data['text'] as String,
              sentAt:
                  (data['sentAt'] as Timestamp?)?.toDate() ??
                  (data['openAt'] as Timestamp?)?.toDate() ??
                  DateTime.now(),
              openAt:
                  (data['openAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              replyTo: data['replyTo'] as String?,
              readBy: List<String>.from(data['readBy'] ?? []),
            );
          }).toList();
          result.sort((a, b) => b.sentAt.compareTo(a.sentAt));
          return result;
        }),
  );

  static Future<void> send(
    String id,
    String text,
    DateTime? openAt, {
    String? replyTo,
  }) async {
    await CoupleService.ensureReady();
    if (text.trim().isEmpty || text.length > 800000) {
      throw Exception('Mesaj çok uzun.');
    }
    final ref = _db.collection('chats').doc(id);
    final batch = _db.batch();
    batch.set(ref.collection('messages').doc(), {
      'sender': _uid,
      'text': text.trim(),
      'sentAt': FieldValue.serverTimestamp(),
      'openAt': openAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(openAt),
      'scheduled': openAt != null,
      'readBy': [_uid],
      'replyTo': replyTo,
    });
    batch.update(ref, {'updatedAt': FieldValue.serverTimestamp()});
    await batch.commit();
  }

  static Future<void> markRead(String id, ChatMessage message) async {
    if (message.mine || !message.unlocked || message.readBy.contains(_uid)) {
      return;
    }
    await _db
        .collection('chats')
        .doc(id)
        .collection('messages')
        .doc(message.id)
        .update({
          'readBy': FieldValue.arrayUnion([_uid]),
        });
  }

  static Future<void> deleteMessage(String id, String messageId) async {
    final ref = _db
        .collection('chats')
        .doc(id)
        .collection('messages')
        .doc(messageId);
    final text = (await ref.get()).data()?['text'] as String?;
    if (text != null && text.startsWith(mediaPrefix)) {
      await ChatMedia.remove(ChatMedia.idFrom(text), explicitly: true);
    }
    await ref.delete();
  }
}
