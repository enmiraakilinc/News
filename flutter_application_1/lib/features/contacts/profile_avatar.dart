import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../chat/chat_service.dart';
import '../../core/widgets/emoji_picker.dart';
import 'contact_names.dart';
import '../media/media_viewer.dart';

/// Small profile previews keep contact lists fast.
Future<void> editProfileAvatar(
  BuildContext context, {
  String? contactId,
}) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.emoji_emotions_outlined),
            title: const Text('Emoji kullan'),
            onTap: () => Navigator.pop(ctx, 'emoji'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('Profil fotoğrafı seç'),
            onTap: () => Navigator.pop(ctx, 'photo'),
          ),
        ],
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  if (kind == 'emoji') {
    final emoji = await chooseEmoji(context, title: 'Profil emojisi');
    if (emoji != null) {
      if (contactId == null) {
        await ChatService.saveAvatar(emoji: emoji);
      } else {
        await ContactNames.saveAvatar(contactId, emoji: emoji);
      }
    }
    return;
  }
  final image = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    requestFullMetadata: false,
  );
  if (image == null) return;
  final original = await image.readAsBytes();
  Uint8List? small;
  for (final quality in [70, 50, 30]) {
    final bytes = await FlutterImageCompress.compressWithList(
      original,
      minWidth: 192,
      minHeight: 192,
      quality: quality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (bytes.isNotEmpty && bytes.length <= 24576) {
      small = bytes;
      break;
    }
  }
  if (small == null) {
    throw Exception('Bu fotoğraf küçültülemedi. Başka bir fotoğraf seç.');
  }
  if (contactId == null) {
    await ChatService.saveAvatar(photo: small);
  } else {
    await ContactNames.saveAvatar(contactId, photo: small);
  }
}

class ContactAvatar extends StatelessWidget {
  final String contactId;
  final String? userId;
  final VoidCallback? onTap;
  const ContactAvatar({
    super.key,
    required this.contactId,
    this.userId,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: ContactNames.changes,
    builder: (_, _, _) {
      final avatar = ContactNames.avatar(contactId);
      if (avatar == null && userId != null) {
        return ProfileAvatar(userId: userId!, onTap: onTap);
      }
      return InkWell(
        onTap:
            onTap ??
            () async {
              if (avatar?.photo != null) {
                try {
                  showPrivatePhoto(context, avatar!.photo!);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Fotoğraf açılamadı. Bağlantını kontrol edip yeniden dene.',
                        ),
                      ),
                    );
                  }
                }
              } else {
                showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    content: Text(
                      avatar?.emoji ?? '👤',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 96),
                    ),
                  ),
                );
              }
            },
        child: CircleAvatar(
          child: avatar?.photo == null
              ? Text(avatar?.emoji ?? '👤')
              : ClipOval(
                  child: Image.memory(
                    avatar!.photo!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    cacheWidth: 128,
                  ),
                ),
        ),
      );
    },
  );
}

class ProfileAvatar extends StatefulWidget {
  final String userId;
  final Stream<ChatProfile?>? profiles;
  final VoidCallback? onTap;
  const ProfileAvatar({
    super.key,
    required this.userId,
    this.profiles,
    this.onTap,
  });
  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  late Stream<ChatProfile?> _stream =
      widget.profiles ?? ChatService.profileStream(widget.userId);
  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.profiles != widget.profiles) {
      _stream = widget.profiles ?? ChatService.profileStream(widget.userId);
    }
  }

  Future<void> _show(ChatProfile? profile) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(profile?.name ?? 'Profil'),
      content: SizedBox(
        width: 280,
        height: 280,
        child: profile?.photo == null
            ? Center(
                child: Text(
                  profile?.emoji.isNotEmpty == true ? profile!.emoji : '👤',
                  style: const TextStyle(fontSize: 96),
                ),
              )
            : InteractiveViewer(
                child: Image.memory(profile!.photo!, fit: BoxFit.contain),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Kapat'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<ChatProfile?>(
    stream: _stream,
    builder: (_, snapshot) {
      final profile = snapshot.data;
      if (profile?.photo != null) {
        return InkWell(
          onTap: widget.onTap ?? () => _show(profile),
          child: CircleAvatar(
            child: ClipOval(
              child: Image.memory(
                profile!.photo!,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                cacheWidth: 128,
                errorBuilder: (_, _, _) => const Icon(Icons.person_outline),
              ),
            ),
          ),
        );
      }
      return InkWell(
        onTap: widget.onTap ?? () => _show(profile),
        child: CircleAvatar(
          child: Text(
            profile?.emoji.isNotEmpty == true ? profile!.emoji : '👤',
            style: const TextStyle(fontSize: 24),
          ),
        ),
      );
    },
  );
}
