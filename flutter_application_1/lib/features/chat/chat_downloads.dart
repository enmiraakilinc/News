import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import '../media/chat_media.dart';
import '../pair/couple_service.dart';
import '../../core/utils/user_errors.dart';
import '../media/media_viewer.dart';

class ChatDownloads {
  static CollectionReference<Map<String, dynamic>> get requests =>
      FirebaseFirestore.instance.collection('mediaDownloadRequests');

  static String source(Map<String, dynamic> media) => media['chatId'] != null
      ? 'chat/${media['chatId']}'
      : 'couple/${media['coupleId']}';

  static Future<void> saveOrRequest(BuildContext context, String id) async {
    try {
      final media =
          (await FirebaseFirestore.instance.doc('chatMedia/$id').get()).data();
      if (media == null) throw Exception('Bu ek artık mevcut değil.');
      final uid = CoupleService.uid;
      if (uid == null) throw Exception('Hesabına tekrar giriş yap.');
      final ref = requests.doc('${id}_$uid');
      final request = media['owner'] == uid ? null : (await ref.get()).data();
      if (media['owner'] == uid || request?['status'] == 'approved') {
        await save(id);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Galeriye kaydedildi.')));
        }
      } else {
        if (request == null) {
          await ref.set({
            'mediaId': id,
            'ownerUid': media['owner'],
            'requesterUid': uid,
            'sourceKey': source(media),
            'status': 'pending',
            'requestedAt': FieldValue.serverTimestamp(),
            'expiresAt': Timestamp.fromDate(chatMediaExpiresAt(media)),
          });
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                request?['status'] == 'declined'
                    ? 'Gönderen bu indirme isteğini kabul etmedi.'
                    : 'İndirme isteğin sohbete eklendi. Gönderen uygulamada onaylayınca buradan kaydedebilirsin.',
              ),
            ),
          );
        }
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userError(
                error,
                fallback: 'İndirme isteği gönderilemedi. Yeniden dene.',
              ),
            ),
          ),
        );
      }
    }
  }

  static Future<void> save(String id) async {
    final media = (await FirebaseFirestore.instance.doc('chatMedia/$id').get())
        .data();
    if (media == null || !['photo', 'video'].contains(media['kind'])) {
      throw Exception('Ek bulunamadı.');
    }
    final uid = CoupleService.uid;
    if (uid == null) throw Exception('Giriş gerekli.');
    if (media['owner'] != uid) {
      final permission =
          (await requests
                  .doc('${id}_$uid')
                  .get(const GetOptions(source: Source.server)))
              .data();
      if (permission?['status'] != 'approved') {
        throw Exception('Gönderenin indirme onayı gerekli.');
      }
    }
    final bytes = await ChatMedia.download(
      id,
    ); // Also checks the two-day expiry.
    if (!await Gal.hasAccess()) await Gal.requestAccess();
    if (!await Gal.hasAccess()) {
      throw Exception('Galeriye kaydetme izni verilmedi.');
    }
    if (media['kind'] == 'photo') {
      await Gal.putImageBytes(bytes);
    } else {
      final folder = await getTemporaryDirectory();
      final extension = (media['name'] as String).split('.').last.toLowerCase();
      final suffix =
          ['mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv', 'avi'].contains(extension)
          ? extension
          : 'mp4';
      final file = File(
        '${folder.path}/neural_media_save_${id}_${DateTime.now().microsecondsSinceEpoch}.$suffix',
      );
      try {
        await file.writeAsBytes(bytes);
        await Gal.putVideo(file.path);
      } finally {
        if (await file.exists()) await file.delete();
      }
    }
  }
}

/// Visible only inside this conversation. Never posts a system notification.
class ChatDownloadRequests extends StatefulWidget {
  final String sourceKey;
  const ChatDownloadRequests({super.key, required this.sourceKey});
  @override
  State<ChatDownloadRequests> createState() => _ChatDownloadRequestsState();
}

class _ChatDownloadRequestsState extends State<ChatDownloadRequests> {
  final _busy = <String>{};
  final _dismissed = <String>{};
  late final uid = CoupleService.uid;
  late final incoming = uid == null
      ? null
      : ChatDownloads.requests.where('ownerUid', isEqualTo: uid).snapshots();
  late final outgoing = uid == null
      ? null
      : ChatDownloads.requests
            .where('requesterUid', isEqualTo: uid)
            .snapshots();

  Future<void> _act(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String action,
  ) async {
    setState(() => _busy.add(doc.id));
    try {
      if (action == 'view') {
        final id = doc.data()['mediaId'] as String;
        final media =
            (await FirebaseFirestore.instance.doc('chatMedia/$id').get())
                .data();
        if (media == null) throw Exception('Ek artık mevcut değil.');
        final bytes = await ChatMedia.download(id);
        if (!mounted) return;
        if (media['kind'] == 'photo') {
          await showPrivatePhoto(context, bytes);
        } else {
          final folder = await getTemporaryDirectory();
          final file = File('${folder.path}/neural_media_request_$id.mp4');
          try {
            await file.writeAsBytes(bytes);
            if (mounted) {
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => PrivateVideoScreen(file: file),
                ),
              );
            }
          } finally {
            if (await file.exists()) await file.delete();
          }
        }
      } else if (action == 'save') {
        await ChatDownloads.save(doc.data()['mediaId'] as String);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Galeriye kaydedildi.')));
          setState(() => _dismissed.add(doc.id));
        }
      } else {
        await doc.reference.update({
          'status': action,
          'decidedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(doc.id));
    }
  }

  Widget _list(
    Stream<QuerySnapshot<Map<String, dynamic>>>? stream,
    bool owner,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: stream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Text('İndirme isteklerine şu an ulaşılamıyor.'),
        );
      }
      final docs = (snapshot.data?.docs ?? []).where((doc) {
        final d = doc.data();
        final date = d['expiresAt'];
        return d['sourceKey'] == widget.sourceKey &&
            !_dismissed.contains(doc.id) &&
            date is Timestamp &&
            date.toDate().isAfter(DateTime.now()) &&
            d['status'] == (owner ? 'pending' : 'approved');
      }).toList();
      if (docs.isEmpty) return const SizedBox.shrink();
      return ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          owner
              ? '${docs.length} indirme isteği'
              : '${docs.length} indirme isteğin onaylandı',
        ),
        children: [
          for (final doc in docs)
            ListTile(
              dense: true,
              title: Text(
                owner
                    ? 'Gönderdiğin fotoğraf/video telefona kaydedilmek isteniyor.'
                    : 'Gönderen izin verdi. İki günlük süre dolmadan kaydedebilirsin.',
              ),
              subtitle: Text(
                'İstek zamanı: ${(doc.data()['requestedAt'] as Timestamp).toDate().toLocal().toString().substring(0, 16)}',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'İstenen eki gör',
                    onPressed: _busy.contains(doc.id)
                        ? null
                        : () => _act(doc, 'view'),
                    icon: const Icon(Icons.visibility_outlined),
                  ),
                  if (owner)
                    IconButton(
                      tooltip: 'Reddet',
                      onPressed: _busy.contains(doc.id)
                          ? null
                          : () => _act(doc, 'declined'),
                      icon: const Icon(Icons.close),
                    ),
                  TextButton(
                    onPressed: _busy.contains(doc.id)
                        ? null
                        : () => _act(doc, owner ? 'approved' : 'save'),
                    child: Text(
                      _busy.contains(doc.id)
                          ? 'Bekle…'
                          : owner
                          ? 'Kabul et'
                          : 'Kaydet',
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => uid == null
      ? const SizedBox.shrink()
      : ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .3,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [_list(incoming, true), _list(outgoing, false)],
            ),
          ),
        );
}
