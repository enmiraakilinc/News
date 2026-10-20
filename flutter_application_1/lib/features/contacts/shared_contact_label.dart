import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../pair/couple_service.dart';
import 'contact_names.dart';
import '../../core/utils/user_errors.dart';

class SharedContactLabel {
  static Future<void> updateIfShared(String contactId, String label) async {
    final uid = CoupleService.uid;
    if (uid == null) return;
    final cid = contactId == ContactNames.posniId
        ? await CoupleService.coupleId()
        : null;
    if (contactId == ContactNames.posniId && cid == null) return;
    final source = contactId == ContactNames.posniId
        ? 'couple/$cid'
        : 'chat/$contactId';
    final ref = reference(source, uid);
    if ((await ref.get()).exists) await ref.update({'label': label});
  }

  static DocumentReference<Map<String, dynamic>> reference(
    String source,
    String uid,
  ) {
    final parts = source.split('/');
    return FirebaseFirestore.instance
        .collection(
          parts[0] == 'chat' ? 'chatContactLabels' : 'coupleContactLabels',
        )
        .doc(parts[1])
        .collection('names')
        .doc(uid);
  }

  static Future<String?> otherName(String source) async {
    await CoupleService.ensureReady();
    final parts = source.split('/');
    final data =
        (await FirebaseFirestore.instance
                .collection(parts[0] == 'chat' ? 'chats' : 'couples')
                .doc(parts[1])
                .get())
            .data();
    final members = List<String>.from(data?['members'] ?? []);
    if (members.length != 2 || !members.contains(CoupleService.uid)) {
      return null;
    }
    final other = members.firstWhere((id) => id != CoupleService.uid);
    return (await reference(
          source,
          other,
        ).get(const GetOptions(source: Source.server))).data()?['label']
        as String?;
  }

  static Future<void> show(BuildContext context, String source) async {
    try {
      final label = await otherName(source);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Karşı tarafın beni kaydettiği isim'),
          content: Text(label ?? 'Karşı taraf kayıt adını paylaşmamış.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    }
  }
}

class ShareContactLabelSwitch extends StatefulWidget {
  final String source, contactId, fallback;
  const ShareContactLabelSwitch({
    super.key,
    required this.source,
    required this.contactId,
    required this.fallback,
  });
  @override
  State<ShareContactLabelSwitch> createState() =>
      _ShareContactLabelSwitchState();
}

class _ShareContactLabelSwitchState extends State<ShareContactLabelSwitch> {
  bool _enabled = false, _ready = false, _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await CoupleService.ensureReady();
      final doc = await SharedContactLabel.reference(
        widget.source,
        CoupleService.uid!,
      ).get();
      if (mounted) {
        setState(() {
          _enabled = doc.exists;
          _ready = true;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: const Text('Verdiğim kayıt adını paylaş'),
    subtitle: const Text(
      'Açarsan bu kişiyi ne diye kaydettiğini karşı taraf görebilir.',
    ),
    value: _enabled,
    onChanged: !_ready || _busy
        ? null
        : (value) async {
            setState(() => _busy = true);
            try {
              final ref = SharedContactLabel.reference(
                widget.source,
                CoupleService.uid!,
              );
              if (value) {
                await ref.set({
                  'label': ContactNames.name(widget.contactId, widget.fallback),
                });
              } else {
                await ref.delete();
              }
              if (mounted) setState(() => _enabled = value);
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(userError(error))));
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}
