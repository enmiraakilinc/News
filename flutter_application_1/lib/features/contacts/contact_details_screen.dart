import '../chat/conversation_style.dart';
import 'package:flutter/material.dart';
import 'contact_names.dart';
import 'chat_presence.dart';
import 'profile_avatar.dart';
import '../starred/starred_messages.dart';
import '../../core/utils/user_errors.dart';
import '../wakeup/wakeup_service.dart';
import '../../core/theme/chat_theme.dart';
import '../../core/notifications/notif_prefs.dart';
import 'shared_contact_label.dart';
import '../calls/voice_call.dart';

class ContactChatHeader extends StatelessWidget {
  final String contactId, fallbackName, sourceKey;
  final String? userId;
  final Map<String, String>? members;
  final VoidCallback? onUnpair;
  const ContactChatHeader({
    super.key,
    required this.contactId,
    required this.fallbackName,
    required this.sourceKey,
    this.userId,
    this.members,
    this.onUnpair,
  });
  @override
  Widget build(BuildContext context) {
    void details() {
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ContactDetailsScreen(
            contactId: contactId,
            fallbackName: fallbackName,
            sourceKey: sourceKey,
            userId: userId,
            members: members,
            onUnpair: onUnpair,
          ),
        ),
      );
    }

    Future<void> open(BuildContext anchor) async {
      final box = anchor.findRenderObject() as RenderBox;
      final overlay =
          Overlay.of(anchor).context.findRenderObject() as RenderBox;
      final rect = Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      );
      final action = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
        items: [
          PopupMenuItem(value: 'stars', child: Text('Yıldızlı mesajlar')),
          PopupMenuItem(value: 'rename', child: Text('Kişi adını değiştir')),
          PopupMenuItem(
            value: 'avatar',
            child: Text('Profil resmi / emoji ekle'),
          ),
          PopupMenuItem(
            value: 'saved',
            child: Text('Karşı tarafın beni kaydettiği isim'),
          ),
          PopupMenuItem(value: 'details', child: Text('Tüm kişi ayarları')),
          if (members == null)
            const PopupMenuItem(value: 'call', child: Text('Sesli ara')),
          if (members == null)
            const PopupMenuItem(value: 'video', child: Text('Görüntülü ara')),
        ],
      );
      if (!context.mounted || action == null) return;
      try {
        switch (action) {
          case 'stars':
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => StarredMessagesScreen(sourceKey: sourceKey),
              ),
            );
          case 'rename':
            await ContactNames.rename(context, contactId, fallbackName);
          case 'avatar':
            await editProfileAvatar(context, contactId: contactId);
          case 'saved':
            await SharedContactLabel.show(context, sourceKey);
          case 'details':
            details();
          case 'call':
            await VoiceCalls.start(
              context,
              sourceKey,
              ContactNames.name(contactId, fallbackName),
            );
          case 'video':
            await VoiceCalls.start(
              context,
              sourceKey,
              ContactNames.name(contactId, fallbackName),
              video: true,
            );
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(userError(error))));
        }
      }
    }

    Future<void> call(bool video) async {
      try {
        await VoiceCalls.start(
          context,
          sourceKey,
          ContactNames.name(contactId, fallbackName),
          video: video,
        );
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(userError(error))));
        }
      }
    }

    return ValueListenableBuilder<int>(
      valueListenable: ContactNames.changes,
      builder: (_, _, _) => Row(
        children: [
          Builder(
            builder: (anchor) => ContactAvatar(
              contactId: contactId,
              userId: userId,
              onTap: () => open(anchor),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: details,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ContactNames.name(contactId, fallbackName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  LastSeenLabel(
                    peer: userId,
                    source: sourceKey,
                    fallback: members == null
                        ? 'Kişi ayrıntıları'
                        : '${members!.length} kişi · Grup ayrıntıları',
                  ),
                ],
              ),
            ),
          ),
          if (members == null) ...[
            IconButton(
              tooltip: 'Sesli ara',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.call_outlined, size: 22),
              onPressed: () => call(false),
            ),
            IconButton(
              tooltip: 'Görüntülü ara',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.videocam_outlined, size: 23),
              onPressed: () => call(true),
            ),
          ],
        ],
      ),
    );
  }
}

class ContactDetailsScreen extends StatelessWidget {
  final String contactId;
  final String fallbackName;
  final String sourceKey;
  final String? userId;
  final Map<String, String>? members;
  final VoidCallback? onUnpair;
  const ContactDetailsScreen({
    super.key,
    required this.contactId,
    required this.fallbackName,
    required this.sourceKey,
    this.userId,
    this.members,
    this.onUnpair,
  });
  @override
  Widget build(BuildContext context) => ChatScaffold(
    conversationStyle: true,
    appBar: AppBar(title: const Text('Kişi ayrıntıları')),
    body: ValueListenableBuilder<int>(
      valueListenable: ContactNames.changes,
      builder: (context, _, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConversationSection(
            children: [
              const SizedBox(height: 24),
              Center(
                child: SizedBox.square(
                  dimension: 88,
                  child: Center(
                    child: Transform.scale(
                      scale: 2,
                      child: ContactAvatar(
                        contactId: contactId,
                        userId: userId,
                      ),
                    ),
                  ),
                ),
              ),
              ListTile(
                title: Text(ContactNames.name(contactId, fallbackName)),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () =>
                    ContactNames.rename(context, contactId, fallbackName),
              ),
              ListTile(
                leading: const Icon(Icons.add_a_photo_outlined),
                title: const Text('Bu kişinin fotoğrafı veya emojisi'),
                subtitle: const Text('Yalnızca senin kayıtlarında değişir.'),
                onTap: () async {
                  try {
                    await editProfileAvatar(context, contactId: contactId);
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(userError(error))));
                    }
                  }
                },
              ),
            ],
          ),
          ConversationSection(
            children: [
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: const Text('Yıldızlı mesajlar'),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StarredMessagesScreen(sourceKey: sourceKey),
                  ),
                ),
              ),
              const ListTile(
                leading: Icon(Icons.palette_outlined),
                title: Text('Sohbet teması'),
                trailing: ChatThemeButton(),
              ),
              LastSeenSwitch(source: sourceKey, peer: userId),
              if (members == null) ...[
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('Görüntülü ara'),
                  onTap: () => VoiceCalls.start(
                    context,
                    sourceKey,
                    ContactNames.name(contactId, fallbackName),
                    video: true,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.call_outlined),
                  title: const Text('Sesli ara'),
                  onTap: () => VoiceCalls.start(
                    context,
                    sourceKey,
                    ContactNames.name(contactId, fallbackName),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Karşı tarafın beni kaydettiği isim'),
                  onTap: () => SharedContactLabel.show(context, sourceKey),
                ),
                ShareContactLabelSwitch(
                  source: sourceKey,
                  contactId: contactId,
                  fallback: fallbackName,
                ),
              ],
              if (members != null) ...[
                const ListTile(title: Text('Grup üyeleri')),
                for (final name in members!.values)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(name),
                  ),
              ],
            ],
          ),
          if (sourceKey.startsWith('couple/'))
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Bildirim yazısı'),
              onTap: () => editNotifText(context, kNotifLetters),
            ),
          if (userId != null || sourceKey.startsWith('couple/'))
            ConversationSection(
              children: [WakeupSettings(sourceKey: sourceKey)],
            ),
          if (onUnpair != null)
            ConversationSection(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.link_off,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('Bağı bu telefondan kaldır'),
                  onTap: () {
                    Navigator.pop(context);
                    onUnpair!();
                  },
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
