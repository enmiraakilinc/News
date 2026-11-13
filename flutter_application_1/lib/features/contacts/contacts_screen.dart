// Kişi listesi ve kalıcı kişi silmedir.
import '../chat/delivery_status.dart';
import 'contact_names.dart';
import '../chat/search/message_search.dart';
import '../chat/letters_screen.dart';
import '../../core/theme/chat_theme.dart';
import '../media/message_content.dart';

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat/chat_service.dart';
import '../chat/chat_widgets.dart';
import '../chat/chat_unread.dart';
import '../pair/couple_service.dart';
import '../../core/utils/sync_state.dart';
import 'profile_avatar.dart';
import '../location/location_share.dart';
import '../media/chat_media.dart';
import 'contact_details_screen.dart';
import '../../core/utils/user_errors.dart';
import '../account/chat_account_screen.dart';

class _UnreadMessagesDivider extends StatelessWidget {
  const _UnreadMessagesDivider();

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('unread-messages-divider'),
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'Okunmamış mesajlar',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Divider(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ],
    ),
  );
}

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    this.profileLoader,
    this.conversationsLoader,
    this.contactLoader,
  });
  final Future<String?> Function()? profileLoader;
  final Stream<List<Conversation>> Function()? conversationsLoader;
  final Future<void> Function()? contactLoader;
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late Stream<List<Conversation>> _stream;
  late Future<String?> _profile;
  String? _profileName;
  List<Conversation> _conversations = [];

  Future<String?> _loadProfile() async {
    if (widget.profileLoader != null) return widget.profileLoader!();
    await CoupleService.ensureReady();
    final uid = CoupleService.uid;
    final remote = ChatService.myName().timeout(const Duration(seconds: 20));
    // Attach handlers immediately, even when a cached profile wins the race.
    final refreshed = remote.then((name) {
      if (mounted && CoupleService.uid == uid && name != null) {
        setState(() => _profileName = name);
      }
      return name;
    }, onError: (Object error) => throw error);
    // A second observer prevents an early network failure becoming unhandled.
    refreshed.catchError((_) => null);
    final cached = await ChatService.myName(
      cacheOnly: true,
    ).catchError((_) => null);
    return cached ?? await refreshed;
  }

  @override
  void initState() {
    super.initState();
    _stream = (widget.conversationsLoader ?? ChatService.conversations)();
    _profile = _loadProfile();
    ContactNames.changes.addListener(_contactsChanged);
    _refreshContacts();
  }

  void _contactsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshContacts() async {
    try {
      if (widget.contactLoader != null) {
        await widget.contactLoader!();
        return;
      }
      await CoupleService.ensureReady();
      await ContactNames.load();
    } catch (_) {
      /* Keep the visible list and local contact metadata. */
    }
  }

  @override
  void dispose() {
    ContactNames.changes.removeListener(_contactsChanged);
    super.dispose();
  }

  Future<void> _remove(Conversation chat) async {
    if (chat.group) return;
    await _removeId(chat.id);
  }

  Future<void> _removeId(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kişiyi silmek istediğine emin misin?'),
        content: const Text(
          'Bu kişi her iki taraftan da silinir. Yeniden konuşmak için yeni bir davet kodu gerekir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (id == ContactNames.posniId) {
        await CoupleService.severPair();
      } else {
        await ChatService.deleteDirect(id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userError(
                error,
                fallback:
                    'Kişi kaldırılamadı. Bağlantını kontrol edip yeniden dene.',
              ),
            ),
          ),
        );
      }
      return;
    }
    if (mounted) setState(() {});
  }

  bool _busy = false;

  void _retry() {
    CoupleService.resetConnection();
    setState(() {
      _profileName = null;
      _stream = (widget.conversationsLoader ?? ChatService.conversations)();
      _profile = _loadProfile();
    });
    _refreshContacts();
  }

  Future<String?> _ask(
    String title,
    String hint, {
    bool numeric = false,
    String? initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: numeric ? 8 : 40,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          inputFormatters: numeric
              ? [FilteringTextInputFormatter.digitsOnly]
              : [],
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx, controller.text.trim());
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    // The dialog's closing animation may still refer to its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    return result;
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _name([String? initial]) async {
    final name = await _ask(
      'Kendi profil adın',
      'Senin adın; kişiye verdiğin kayıt adından ayrıdır',
      initial: initial,
    );
    if (name == null) return;
    await _run(() async {
      await ChatService.saveName(name);
      if (mounted) {
        setState(() {
          _profileName = name;
          _profile = Future.value(name);
        });
      }
    });
  }

  Future<void> _invite() => _run(() async {
    final code = await ChatService.createInvite();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kişi ekleme kodun'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              code,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Bu kod 1 saat geçerli ve tek kişi için kullanılabilir. Diğer kişi “Kod gir” bölümüne yazınca ikinizde de birebir sohbet açılır. Bu davet yalnızca sohbet içindir; özel alana üyelik vermez. Gizli kelimeni paylaşma.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Kopyala'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  });

  Future<void> _join() async {
    final code = await _ask('Davet kodu gir', '8 haneli kod', numeric: true);
    if (code == null) return;
    final alias = await _ask(
      'Kişiyi hangi adla kaydedelim?',
      'Yalnızca senin hesabında görünür',
    );
    if (alias == null) return;
    await _run(() async {
      final id = await ChatService.acceptInvite(code);
      await ContactNames.save(id, alias);
      if (mounted) setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kişi eklendi. Sohbetiniz listede görünecek.'),
          ),
        );
      }
    });
  }

  Future<void> _group() async {
    final contacts = <String, String>{};
    for (final chat in _conversations.where((c) => !c.group)) {
      for (final entry in chat.names.entries) {
        if (entry.key != CoupleService.uid) contacts[entry.key] = entry.value;
      }
    }
    if (contacts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Grup kurmak için önce en az iki kişi ekle.'),
        ),
      );
      return;
    }
    final title = TextEditingController();
    final selected = <String, String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Yeni grup'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    maxLength: 60,
                    decoration: const InputDecoration(hintText: 'Grup adı'),
                  ),
                  for (final entry in contacts.entries)
                    CheckboxListTile(
                      title: Text(entry.value),
                      value: selected.containsKey(entry.key),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          selected[entry.key] = entry.value;
                        } else {
                          selected.remove(entry.key);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                if (title.text.trim().isNotEmpty && selected.length >= 2) {
                  Navigator.pop(ctx, true);
                }
              },
              child: const Text('Grup kur'),
            ),
          ],
        ),
      ),
    );
    final name = title.text.trim();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    title.dispose();
    if (ok != true) return;
    await _run(() async {
      await ChatService.createGroup(name, selected);
    });
  }

  Future<void> _openChat(Conversation chat) async {
    if (!chat.group && !ContactNames.hasAlias(chat.id)) {
      final name = await _ask(
        'Kişiyi hangi adla kaydedelim?',
        'Yalnızca senin hesabında görünür',
        initial: chat.displayTitle,
      );
      if (name == null) return;
      await ContactNames.save(chat.id, name);
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ConversationScreen(conversation: chat)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    appBar: AppBar(
      title: const Text('Sohbetler'),
      actions: [
        IconButton(
          tooltip: 'Kişisel sohbet hesabı',
          icon: const Icon(Icons.manage_accounts_outlined),
          onPressed: _busy
              ? null
              : () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ChatAccountScreen(),
                    ),
                  );
                  if (mounted) _retry();
                },
        ),
        IconButton(
          onPressed: _busy ? null : _group,
          icon: const Icon(Icons.group_add_outlined),
          tooltip: 'Grup kur',
        ),
      ],
    ),
    body: Column(
      children: [
        Card(
            margin: const EdgeInsets.all(16),
            child: ListTile(
              leading: const ContactAvatar(contactId: ContactNames.posniId),
              title: Text(
                ContactNames.name(ContactNames.posniId, 'Posni'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Mektuplar ve sohbet'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Sohbet adını değiştir',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      await ContactNames.rename(
                        context,
                        ContactNames.posniId,
                        'Posni',
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                  PopupMenuButton<String>(
                    onSelected: (_) => _removeId(ContactNames.posniId),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'delete', child: Text('Kişiyi sil')),
                    ],
                  ),
                ],
              ),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LettersScreen()),
                );
                if (mounted) setState(() {});
              },
            ),
          ),
        Expanded(
          child: FutureBuilder<String?>(
            future: _profile,
            builder: (context, profile) {
              final profileName = _profileName ?? profile.data;
              final profileLoading =
                  profile.connectionState == ConnectionState.waiting &&
                  profileName == null;
              return Column(
                children: [
                  ListTile(
                    leading: InkWell(
                      onTap: _busy
                          ? null
                          : () => _run(() => editProfileAvatar(context)),
                      child: CoupleService.uid == null
                          ? const CircleAvatar(
                              child: Icon(Icons.person_outline),
                            )
                          : ProfileAvatar(userId: CoupleService.uid!),
                    ),
                    title: Text(
                      profileName ??
                          (profileLoading
                              ? 'Profil yükleniyor…'
                              : 'Profil adını belirle'),
                    ),
                    subtitle: const Text(
                      'Kendi profilin · Kişi ayarları sohbetin içinde',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _busy
                              ? null
                              : () => _run(() => editProfileAvatar(context)),
                          icon: const Icon(Icons.add_a_photo_outlined),
                          tooltip: 'Kendi profil fotoğrafını veya emojini seç',
                        ),
                        IconButton(
                          onPressed: _busy ? null : () => _name(profileName),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Adını değiştir',
                        ),
                      ],
                    ),
                  ),
                  if (profileLoading) const LinearProgressIndicator(),
                  if (profile.hasError)
                    ListTile(
                      title: const Text(
                        'Profil bilgisi alınamadı; sohbetlerini yine de açabilirsin.',
                      ),
                      trailing: TextButton(
                        onPressed: _retry,
                        child: const Text('Yeniden dene'),
                      ),
                    ),
                  if (!profileLoading &&
                      !profile.hasError &&
                      profileName == null)
                    TextButton(
                      onPressed: _busy ? null : () => _name(),
                      child: const Text('Kendi profil adını belirle'),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy || profileName == null
                                ? null
                                : _invite,
                            icon: const Icon(Icons.add),
                            label: const Text('Kod üret'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy || profileName == null
                                ? null
                                : _join,
                            icon: const Icon(Icons.pin_outlined),
                            label: const Text('Kod gir'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<List<Conversation>>(
                      stream: _stream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return SyncError(
                            label: 'Sohbetler',
                            onRetry: _retry,
                            error: snapshot.error,
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        _conversations = snapshot.data!.toList();
                        if (_conversations.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Henüz kişi yok. Bir davet kodu üret veya arkadaşının kodunu gir.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: _conversations.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, indent: 76),
                          itemBuilder: (context, index) {
                            final chat = _conversations[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 8,
                              ),
                              leading: chat.group
                                  ? const CircleAvatar(
                                      child: Text(
                                        '👥',
                                        style: TextStyle(fontSize: 24),
                                      ),
                                    )
                                  : ContactAvatar(
                                      contactId: chat.id,
                                      key: ValueKey(chat.id),
                                      userId: chat.members
                                          .where(
                                            (id) => id != CoupleService.uid,
                                          )
                                          .firstOrNull,
                                    ),
                              title: Text(
                                ContactNames.name(chat.id, chat.displayTitle),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                chat.group
                                    ? '${chat.members.length} kişi • Grup sohbeti'
                                    : 'Birebir sohbet',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ChatUnreadBadge(chatId: chat.id),
                                  PopupMenuButton<String>(
                                    onSelected: (value) async {
                                      if (value == 'delete') {
                                        await _remove(chat);
                                      } else {
                                        await ContactNames.rename(
                                          context,
                                          chat.id,
                                          chat.displayTitle,
                                        );
                                        if (mounted) setState(() {});
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem(
                                        value: 'rename',
                                        child: Text('Adını değiştir'),
                                      ),
                                      if (!chat.group)
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Kişiyi sil'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              onLongPress: () async {
                                await ContactNames.rename(
                                  context,
                                  chat.id,
                                  chat.displayTitle,
                                );
                                if (mounted) setState(() {});
                              },
                              onTap: () => _openChat(chat),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    ),
  );
}

class ConversationScreen extends StatefulWidget {
  final Conversation conversation;
  const ConversationScreen({super.key, required this.conversation});
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  final _messageKeys = <String, GlobalKey>{};
  String? _highlightId;
  GlobalKey _messageKey(String id) =>
      _messageKeys.putIfAbsent(id, GlobalKey.new);

  void _watchConversation() {
    final resumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(
      ActiveConversation.set(
        resumed ? 'chat/${widget.conversation.id}' : null,
      ),
    );
  }

  void _showQuoted(String? id) {
    if (id == null) return;
    final target = _messageKey(id).currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 280),
        alignment: 0.35,
      );
    }
    setState(() => _highlightId = id);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted && _highlightId == id) setState(() => _highlightId = null);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchConversation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _watchConversation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(ActiveConversation.set(null));
    super.dispose();
  }

  int _messageLimit = 100;
  late Stream<List<ChatMessage>> _stream = ChatService.messages(
    widget.conversation.id,
  );
  Future<void> _action(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
      }
    }
  }

  ChatMessage? _reply;
  Future<void> Function(String, DateTime?) get _sendHandler {
    final replyTo = _reply?.id;
    final chatId = widget.conversation.id;
    return (text, openAt) =>
        ChatService.send(chatId, text, openAt, replyTo: replyTo);
  }

  final Set<String> _pendingReads = {};
  void _retry() {
    CoupleService.resetConnection();
    setState(
      () => _stream = ChatService.messages(
        widget.conversation.id,
        limit: _messageLimit,
      ),
    );
  }

  void _read(ChatMessage message) {
    if (message.mine ||
        !message.unlocked ||
        message.readBy.contains(CoupleService.uid) ||
        !_pendingReads.add(message.id)) {
      return;
    }
    ChatService.markRead(widget.conversation.id, message)
        .catchError((Object _) {})
        .whenComplete(() => _pendingReads.remove(message.id));
  }

  Future<void> _delete(ChatMessage message) async {
    final forMe = !message.mine;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          forMe ? 'Kendin için silinsin mi?' : 'Herkesten silinsin mi?',
        ),
        content: Text(
          forMe
              ? 'Bu mesaj yalnızca senin sohbet görünümünden kaldırılacak.'
              : 'Bu mesaj sohbetin tüm katılımcılarından silinecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(forMe ? 'Kendin için sil' : 'Herkesten sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        if (forMe) {
          await ChatService.deleteMessageForMe(
            widget.conversation.id,
            message.id,
          );
        } else {
          await ChatService.deleteMessage(widget.conversation.id, message.id);
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Silinemedi. Tekrar dene.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => ChatScaffold(
    starsSource: 'chat/${widget.conversation.id}',
    appBar: AppBar(
      titleSpacing: 0,
      actions: [
        IconButton(
          tooltip: 'Mesajlarda ara',
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  MessageSearchScreen(source: 'chat/${widget.conversation.id}'),
            ),
          ),
        ),
      ],
      title: ContactChatHeader(
        contactId: widget.conversation.id,
        fallbackName: widget.conversation.displayTitle,
        sourceKey: 'chat/${widget.conversation.id}',
        userId: widget.conversation.group
            ? null
            : widget.conversation.members.firstWhere(
                (id) => id != CoupleService.uid,
              ),
        members: widget.conversation.group ? widget.conversation.names : null,
      ),
    ),
    bottomNavigationBar: ChatComposer(
      chatId: widget.conversation.id,
      onTyping: (typing) =>
          ChatService.setTyping(widget.conversation.id, typing),
      onShareLocation: () => LocationShares.send(
        context,
        chatId: widget.conversation.id,
        onSend: (text, date) =>
            ChatService.send(widget.conversation.id, text, date),
      ),
      replyPreview: _reply?.text,
      onCancelReply: () => setState(() => _reply = null),
      onSend: _sendHandler,
    ),
    body: StreamBuilder<List<ChatMessage>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SyncError(label: 'Mektuplar', onRetry: _retry);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final messages = snapshot.data!;
        final photoMessages = [
          for (final message in messages.reversed)
            if (message.unlocked) message.text,
        ];
        final byId = {for (final message in messages) message.id: message};
        final unreadDivider = unreadDividerIndex(messages);
        final hasMoreMessages = messages.length >= _messageLimit;
        if (messages.isEmpty) {
          return const Center(child: Text('İlk mektubunu aşağıdan gönder.'));
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(12),
          itemCount: messages.length +
              (hasMoreMessages ? 1 : 0) +
              (unreadDivider == null ? 0 : 1),
          findChildIndexCallback: (key) {
            if (key is! ValueKey<String> ||
                !key.value.startsWith('chat-message-')) {
              return null;
            }
            final id = key.value.substring('chat-message-'.length);
            final index = messages.indexWhere((message) => message.id == id);
            if (index < 0) return null;
            return index +
                (unreadDivider != null && index >= unreadDivider ? 1 : 0);
          },
          itemBuilder: (context, index) {
            if (index == unreadDivider) {
              return const _UnreadMessagesDivider();
            }
            final messageIndex =
                unreadDivider != null && index > unreadDivider
                ? index - 1
                : index;
            if (messageIndex == messages.length) {
              return TextButton.icon(
                onPressed: () => setState(() {
                  _messageLimit += 100;
                  _stream = ChatService.messages(
                    widget.conversation.id,
                    limit: _messageLimit,
                  );
                }),
                icon: const Icon(Icons.history),
                label: const Text('Eski mesajları yükle'),
              );
            }
            final message = messages[messageIndex];
            if (message.unlocked) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _read(message);
              });
            }
            final original = byId[message.replyTo];
            final date = message.sentAt;
            final previous = messageIndex + 1 < messages.length
                ? messages[messageIndex + 1].sentAt
                : null;
            final dateLabel =
                previous == null ||
                previous.day != date.day ||
                previous.month != date.month ||
                previous.year != date.year;
            return Column(
              key: ValueKey('chat-message-${message.id}'),
              children: [
                KeyedSubtree(
                  key: _messageKey(message.id),
                  child: const SizedBox.shrink(),
                ),
                if (dateLabel)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Chip(
                      label: Text(
                        '${date.day}.${date.month}.${date.year}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      side: BorderSide.none,
                    ),
                  ),
                MessageBubble(
                  messageId: message.id,
                  highlighted: _highlightId == message.id,
                  onQuoteTap: original == null
                      ? null
                      : () => _showQuoted(original.id),
                  copyOrder: date.millisecondsSinceEpoch,
                  photoMessages: photoMessages,
                  starMessageId: message.unlocked ? message.id : null,
                  mine: message.mine,
                  author: message.mine
                      ? null
                      : widget.conversation.group
                      ? ContactNames.name(
                          ChatService.directId(
                            CoupleService.uid!,
                            message.sender,
                          ),
                          widget.conversation.names[message.sender] ??
                              'Katılımcı',
                        )
                      : ContactNames.name(
                          widget.conversation.id,
                          widget.conversation.displayTitle,
                        ),
                  text: message.unlocked
                      ? message.text
                      : 'Geleceğe bırakılmış bir mektup',
                  quoted: original == null
                      ? null
                      : original.unlocked
                      ? original.text
                      : 'Kilitli mektup',
                  time: message.unlocked
                      ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
                      : 'Açılış: ${message.openAt.day}.${message.openAt.month}.${message.openAt.year} ${message.openAt.hour.toString().padLeft(2, '0')}:${message.openAt.minute.toString().padLeft(2, '0')}',
                  status: chatDeliveryStatus(
                    pending: message.pending,
                    mine: message.mine,
                    edited: message.edited,
                    read: widget.conversation.members.every(
                      message.readBy.contains,
                    ),
                  ),
                  reactions: message.reactions,
                  onReact: message.unlocked
                      ? (emoji) => _action(
                          () => ChatService.react(
                            widget.conversation.id,
                            message.id,
                            emoji,
                            message.reactions[CoupleService.uid],
                          ),
                        )
                      : null,
                  onEdit:
                      message.mine &&
                          message.unlocked &&
                          !message.text.startsWith(locationPrefix) &&
                          !message.text.startsWith(attachmentPrefix) &&
                          !message.text.startsWith(mediaPrefix)
                      ? () async {
                          final text = await editMessage(context, message.text);
                          if (text != null) {
                            await _action(
                              () => ChatService.edit(
                                widget.conversation.id,
                                message.id,
                                text,
                              ),
                            );
                          }
                        }
                      : null,
                  scheduled: !message.unlocked,
                  onReply: message.unlocked
                      ? () => setState(() => _reply = message)
                      : null,
                  onDelete: () => _delete(message),
                ),
              ],
            );
          },
        );
      },
    ),
  );
}
