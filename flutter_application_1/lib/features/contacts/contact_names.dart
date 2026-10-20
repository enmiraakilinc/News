import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import '../media/message_content.dart';
import '../pair/couple_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../chat/chat_service.dart';
import '../media/chat_media.dart';
import 'shared_contact_label.dart';

class ContactNames {
  static const posniId = 'letters_partner';
  static final changes = ValueNotifier<int>(0);
  static final Map<String, String> _names = {};
  static final Map<String, ChatProfile> _avatars = {};
  static ChatProfile? avatar(String id) => _avatars[id];
  static final Set<String> removed = {};
  static void reset() {
    ChatMedia.clearCache();
    _names.clear();
    _avatars.clear();
    removed.clear();
    changes.value++;
  }

  static String _prefix(String? uid) =>
      uid == null ? 'contact_alias_' : 'contact_${uid}_alias_';

  static CollectionReference<Map<String, dynamic>> _contacts(String uid) =>
      FirebaseFirestore.instance
          .collection('chatAccounts')
          .doc(uid)
          .collection('contacts');

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = CoupleService.uid;
    final prefix = _prefix(uid);
    if (uid != null && prefs.getString('contact_legacy_owner') == null) {
      await prefs.setString('contact_legacy_owner', uid);
      for (final key
          in prefs
              .getKeys()
              .where((k) => k.startsWith('contact_alias_'))
              .toList()) {
        await prefs.setString(
          '$prefix${key.substring(14)}',
          prefs.getString(key)!,
        );
      }
      await prefs.setStringList(
        'removed_contacts_$uid',
        prefs.getStringList('removed_contacts') ?? [],
      );
    }
    _names.clear();
    removed
      ..clear()
      ..addAll(
        prefs.getStringList(
              uid == null ? 'removed_contacts' : 'removed_contacts_$uid',
            ) ??
            [],
      );
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      _names[key.substring(prefix.length)] = prefs.getString(key)!;
    }
    changes.value++;
    if (uid != null) {
      try {
        final snapshot = await _contacts(
          uid,
        ).get().timeout(const Duration(seconds: 8));
        if (CoupleService.uid != uid) return;
        final existing = snapshot.docs.map((d) => d.id).toSet();
        final missing = {..._names.keys, ...removed}.difference(existing);
        // Upload legacy device aliases once; remote records always win afterwards.
        for (final id in missing) {
          await _contacts(uid).doc(id).set({
            if (_names[id] != null) 'alias': _names[id],
            'hidden': removed.contains(id),
          }, SetOptions(merge: true));
        }
        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (data['avatarEmoji'] != null || data['avatarPhoto'] != null) {
            _avatars[doc.id] = ChatProfile.fromData({
              'name': data['alias'] ?? '',
              'emoji': data['avatarEmoji'] ?? '',
              'photo': data['avatarPhoto'] ?? '',
            });
          }
          if (data['alias'] is String) {
            _names[doc.id] = data['alias'] as String;
            await prefs.setString('$prefix${doc.id}', data['alias'] as String);
          }
          if (data['hidden'] == true) {
            removed.add(doc.id);
          } else {
            removed.remove(doc.id);
          }
        }
        await prefs.setStringList('removed_contacts_$uid', removed.toList());
      } catch (_) {
        // Offline devices keep their last saved contact names.
      }
    }
    changes.value++;
  }

  static String name(String id, String fallback) => _names[id] ?? fallback;
  static bool hasAlias(String id) => _names.containsKey(id);
  static Future<void> save(String id, String value) async {
    final clean = value.trim();
    if (clean.isEmpty || clean.length > 60) {
      throw Exception('1–60 karakterlik bir kayıt adı yaz.');
    }
    final uid = CoupleService.uid;
    if (uid != null) {
      await _contacts(
        uid,
      ).doc(id).set({'alias': clean}, SetOptions(merge: true));
    }
    _names[id] = clean;
    await SharedContactLabel.updateIfShared(id, clean).catchError((_) {});
    await (await SharedPreferences.getInstance()).setString(
      '${_prefix(uid)}$id',
      clean,
    );
    changes.value++;
  }

  static Future<void> setHidden(String id, bool hidden) async {
    final uid = CoupleService.uid;
    if (uid != null) {
      await _contacts(
        uid,
      ).doc(id).set({'hidden': hidden}, SetOptions(merge: true));
    }
    if (hidden) {
      removed.add(id);
    } else {
      removed.remove(id);
    }
    await (await SharedPreferences.getInstance()).setStringList(
      uid == null ? 'removed_contacts' : 'removed_contacts_$uid',
      removed.toList(),
    );
    changes.value++;
  }

  static Future<void> saveAvatar(
    String id, {
    String? emoji,
    Uint8List? photo,
  }) async {
    if ((emoji == null) == (photo == null) ||
        (emoji != null && (emoji.isEmpty || utf8.encode(emoji).length > 64)) ||
        (photo != null && (photo.isEmpty || photo.length > 24576))) {
      throw Exception(
        'Bu profil resmi kaydedilemedi. Başka bir emoji veya fotoğraf seç.',
      );
    }
    await CoupleService.ensureReady();
    final uid = CoupleService.uid!;
    await _contacts(uid).doc(id).set({
      'avatarEmoji': emoji ?? '',
      'avatarPhoto': photo == null ? '' : base64Encode(photo),
    }, SetOptions(merge: true));
    _avatars[id] = ChatProfile(
      name: name(id, ''),
      emoji: emoji ?? '',
      photo: photo,
    );
    changes.value++;
  }

  static Future<void> rename(
    BuildContext context,
    String id,
    String initial,
  ) async {
    final value = await editMessage(
      context,
      name(id, initial),
      title: 'Kayıt adını değiştir',
    );
    if (value == null || value.length > 60) return;
    await save(id, value);
  }
}
