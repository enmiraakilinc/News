import '../media/media_expiry_dialog.dart';
import '../media/media_expiry_scope.dart';
import 'conversation_style.dart';
import '../media/chat_media.dart';
import 'message_selection.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../media/message_content.dart';
import 'reaction_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../media/camera_capture_screen.dart';
import '../media/video_parts.dart';
import '../starred/starred_messages.dart';
import '../media/media_names_screen.dart';
import '../../core/utils/user_errors.dart';
import '../voice_notes/voice_notes_screen.dart';

class MessageBubble extends StatelessWidget {
  final String? starMessageId;
  final int copyOrder;
  final bool mine;
  final String text;
  final List<String> photoMessages;
  final String time;
  final String? author;
  final String? quoted;
  final String? status;
  final bool scheduled;
  final VoidCallback? onTap;
  final VoidCallback? onReply;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final void Function(String)? onReact;
  final Map<String, String> reactions;
  const MessageBubble({
    super.key,
    this.starMessageId,
    this.copyOrder = 0,
    required this.mine,
    required this.text,
    this.photoMessages = const [],
    required this.time,
    this.author,
    this.quoted,
    this.status,
    this.scheduled = false,
    this.onTap,
    this.onReply,
    this.onDelete,
    this.onEdit,
    this.onReact,
    this.reactions = const {},
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ConversationColors(scheme);
    final foreground = scheduled
        ? scheme.onTertiaryContainer
        : mine
        ? colors.onSent
        : colors.onReceived;
    final stars = MessageStarsScope.of(context);
    final selection = MessageSelectionScope.of(context);
    final canStar = stars != null && starMessageId != null;
    final starred = canStar && stars.ids.contains(starMessageId);
    final canCopy =
        !scheduled &&
        !text.startsWith(attachmentPrefix) &&
        !text.startsWith(mediaPrefix);
    final canExtend = mine && text.startsWith(mediaPrefix);
    final canSelect = canCopy && starMessageId != null && selection != null;
    final selecting = selection?.ids.isNotEmpty == true;
    final selected = selection?.ids.contains(starMessageId) == true;
    void toggleSelection() =>
        selection!.toggle(starMessageId!, text, copyOrder);
    return Dismissible(
      key: ValueKey('swipe_${identityHashCode(this)}'),
      direction: onReply == null || selecting
          ? DismissDirection.none
          : DismissDirection.startToEnd,
      background: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Icon(
            Icons.reply,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      confirmDismiss: (_) async {
        onReply?.call();
        return false;
      },
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * .80,
          ),
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 3,
                  )
                : null,
            color: scheduled
                ? Theme.of(context).colorScheme.tertiaryContainer
                : mine
                ? colors.sent
                : colors.received,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x09000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: selecting ? (canSelect ? toggleSelection : null) : onTap,
            onLongPress:
                onReply == null &&
                    onDelete == null &&
                    onEdit == null &&
                    onReact == null &&
                    !canStar &&
                    !canCopy &&
                    !canExtend
                ? null
                : () async {
                    final action = await showConversationActions(
                      context,
                      preview: messagePreview(text),
                      quoted: quoted == null ? null : messagePreview(quoted!),
                      time: time,
                      mine: mine,
                      reactions: onReact != null,
                      actions: [
                        if (canExtend)
                          const ConversationAction(
                            'expiry',
                            'Erişim süresini uzat',
                            Icons.more_time,
                          ),
                        if (canSelect)
                          const ConversationAction(
                            'select',
                            'Toplu seç',
                            Icons.checklist,
                          ),
                        if (canCopy)
                          const ConversationAction(
                            'copy',
                            'Kopyala',
                            Icons.copy_outlined,
                          ),
                        if (canStar)
                          ConversationAction(
                            'star',
                            starred ? 'Yıldızı kaldır' : 'Yıldızla',
                            starred ? Icons.star : Icons.star_border,
                          ),
                        if (onReact != null)
                          const ConversationAction(
                            'reaction',
                            'İfade bırak',
                            Icons.add_reaction_outlined,
                          ),
                        if (onEdit != null)
                          const ConversationAction(
                            'edit',
                            'Düzenle',
                            Icons.edit_outlined,
                          ),
                        if (onReply != null)
                          const ConversationAction(
                            'reply',
                            'Yanıtla',
                            Icons.reply,
                          ),
                        if (onDelete != null)
                          const ConversationAction(
                            'delete',
                            'Sil',
                            Icons.delete_outline,
                            destructive: true,
                          ),
                      ],
                    );
                    if (!context.mounted || action == null) return;
                    if (action.startsWith('emoji:')) {
                      onReact?.call(action.substring(6));
                      return;
                    }
                    switch (action) {
                      case 'expiry':
                        await extendChatAttachment(context, text);
                      case 'select':
                        toggleSelection();
                      case 'copy':
                        await Clipboard.setData(ClipboardData(text: text));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Mesaj kopyalandı.')),
                          );
                        }
                      case 'star':
                        stars!.toggle(starMessageId!, !starred);
                      case 'reaction':
                        final emoji = await chooseReaction(context);
                        if (emoji != null && context.mounted) {
                          onReact?.call(emoji);
                        }
                      case 'edit':
                        onEdit?.call();
                      case 'reply':
                        onReply?.call();
                      case 'delete':
                        onDelete?.call();
                    }
                  },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (author != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        author!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                    ),
                  if (quoted != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: foreground.withValues(alpha: .08),
                        border: Border(
                          left: BorderSide(
                            color: foreground.withValues(alpha: .6),
                            width: 3,
                          ),
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        messagePreview(quoted!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: foreground.withValues(alpha: .85),
                        ),
                      ),
                    ),
                  if (scheduled)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Icon(Icons.lock_clock_outlined, size: 20),
                    ),
                  DefaultTextStyle.merge(
                    style: TextStyle(
                      color: foreground,
                      fontSize: 15,
                      height: 1.45,
                    ),
                    child: MessageContent(
                      text: text,
                      photoMessages: photoMessages,
                    ),
                  ),
                  if (reactions.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      children: reactions.values
                          .toSet()
                          .map(
                            (emoji) => Chip(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: colors.panel,
                              labelStyle: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 12,
                              ),
                              side: BorderSide(color: colors.line),
                              shape: const StadiumBorder(),
                              label: Text(
                                '$emoji ${reactions.values.where((value) => value == emoji).length}',
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 5),
                  MediaExpiryLabel(
                    message: text,
                    color: foreground.withValues(alpha: .75),
                  ),
                  if (starred) const Icon(Icons.star, size: 14),
                  Text(
                    '$time${status == null ? '' : '  ${status!}'}',
                    style: TextStyle(
                      fontSize: 10,
                      color: foreground.withValues(alpha: .75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatComposer extends StatefulWidget {
  final Future<void> Function(String text, DateTime? openDate) onSend;
  final String? replyPreview;
  final VoidCallback? onCancelReply;
  final Future<void> Function()? onShareLocation;
  final String? chatId;
  final String? coupleId;
  final Future<XFile?> Function(bool video, bool gallery)? pickMedia;
  final Future<List<XFile>> Function(bool video)? pickGallery;
  const ChatComposer({
    super.key,
    required this.onSend,
    this.replyPreview,
    this.onCancelReply,
    this.onShareLocation,
    this.chatId,
    this.coupleId,
    this.pickMedia,
    this.pickGallery,
  });
  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _TextDelivery {
  final String text;
  final DateTime? scheduled;
  final Future<void> Function(String, DateTime?) send;
  bool retrying = false;
  _TextDelivery(this.text, this.scheduled, this.send);
}

class _ChatComposerState extends State<ChatComposer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  DateTime? _scheduled;
  bool _sending = false;
  String? _mediaStatus;
  final List<_TextDelivery> _failedTexts = [];
  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    if (!_validMediaDate()) return;
    try {
      final file = await Navigator.of(context).push<PlatformFile>(
        MaterialPageRoute(builder: (_) => const AttachmentPickerScreen()),
      );
      if (file == null || !mounted) return;
      final kind = attachmentViewKind({'name': file.name, 'kind': 'file'});
      if (kind == 'video' || kind == 'photo') {
        File? temporary;
        try {
          final path = file.path;
          if (path == null) {
            final folder = await getTemporaryDirectory();
            temporary = File(
              '${folder.path}/neural_media_input_${DateTime.now().microsecondsSinceEpoch}.mp4',
            );
            await file.readAsByteStream().cast<List<int>>().pipe(
              temporary.openWrite(),
            );
          }
          if (mounted) {
            await _capture(
              kind == 'video',
              selectedFile: XFile(path ?? temporary!.path, name: file.name),
            );
          }
        } finally {
          if (temporary != null && await temporary.exists()) {
            await temporary.delete();
          }
        }
        return;
      }
      final size = await file.length();
      if (!mounted) return;
      if (size == null || size > maxChatFileBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('En fazla 80 MB dosya gönderebilirsin.'),
          ),
        );
        return;
      }
      setState(() => _sending = true);
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Dosyayı gönder?'),
          content: Text(file.name),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Gönder'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.onSend(
        await ChatMedia.upload(
          bytes,
          file.name,
          'file',
          chatId: widget.chatId,
          coupleId: widget.coupleId,
        ),
        _scheduled,
      );
      if (mounted) {
        setState(() => _scheduled = null);
        widget.onCancelReply?.call();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dosya gönderilemedi. Yeniden dene.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _capture(
    bool video, {
    bool gallery = false,
    XFile? selectedFile,
  }) async {
    if (_sending) return;
    if (!_validMediaDate(video: video)) return;
    setState(() => _sending = true);
    List<XFile> parts = [];
    String? originalPath;
    var sentParts = 0;
    final navigator = Navigator.of(context);
    try {
      final picker = ImagePicker();
      final file =
          selectedFile ??
          (widget.pickMedia != null
              ? await widget.pickMedia!(video, gallery)
              : !gallery
              ? await navigator.push<XFile>(
                  MaterialPageRoute(
                    builder: (_) => CameraCaptureScreen(video: video),
                  ),
                )
              : video
              ? await picker.pickVideo(source: ImageSource.gallery)
              : await picker.pickImage(
                  source: ImageSource.gallery,
                  requestFullMetadata: false,
                ));
      if (file == null || !mounted) return;
      originalPath = file.path;
      if (!video && await file.length() > maxChatMediaBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fotoğraf en fazla 20 MB olabilir.')),
        );
        return;
      }
      final bytes = video ? null : await file.readAsBytes();
      if (!mounted) return;
      final send = widget.onSend;
      final scheduled = _scheduled;
      final chatId = widget.chatId;
      final coupleId = widget.coupleId;
      if (mounted && video) {
        setState(() => _mediaStatus = 'Video hazırlanıyor…');
      }
      parts = video ? await VideoParts.prepare(file) : [file];
      if (!mounted) return;
      final names = await navigator.push<List<String>>(
        MaterialPageRoute(
          builder: (_) => MediaNamesScreen(
            names: parts.length == 1
                ? [file.name]
                : List.generate(parts.length, (i) => 'Part ${i + 1}'),
            photo: bytes,
          ),
        ),
      );
      if (names == null) return;
      for (var i = 0; i < parts.length; i++) {
        if (mounted) {
          setState(
            () => _mediaStatus = parts.length == 1
                ? 'Gönderiliyor…'
                : '${i + 1}/${parts.length} video parçası gönderiliyor…',
          );
        }
        final name = names[i];
        final content = await ChatMedia.upload(
          bytes ?? await parts[i].readAsBytes(),
          name,
          video ? 'video' : 'photo',
          chatId: chatId,
          coupleId: coupleId,
        );
        await send(content, scheduled);
        sentParts++;
      }
      if (mounted) {
        setState(() => _scheduled = null);
        widget.onCancelReply?.call();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sentParts > 0
                  ? '$sentParts parça gönderildi, kalanlar gönderilemedi. Gönderilen parçalar sohbette duruyor.'
                  : userError(
                      error,
                      fallback:
                          'Kayıt hazırlanamadı veya gönderilemedi. Yeniden dene.',
                    ),
            ),
          ),
        );
      }
    } finally {
      if (originalPath != null) await VideoParts.cleanup(parts, originalPath);
      if (mounted) {
        setState(() {
          _sending = false;
          _mediaStatus = null;
        });
      }
    }
  }

  void _hideComposerKeyboard() {
    _focus.unfocus();
    _focus.canRequestFocus = false;
  }

  Future<void> _galleryBatch(bool video) async {
    if (_sending || !_validMediaDate(video: video)) return;
    setState(() => _sending = true);
    final prepared = <XFile>[];
    final originals = <String>{};
    var sent = 0;
    try {
      final List<XFile> files;
      if (widget.pickGallery != null) {
        files = await widget.pickGallery!(video);
      } else if (video) {
        final result = await FilePicker.pickFiles(type: FileType.video);
        files = result
            .where((file) => file.path != null)
            .map((file) => XFile(file.path!, name: file.name))
            .toList();
      } else {
        files = await ImagePicker().pickMultiImage(requestFullMetadata: false);
      }
      if (files.isEmpty || !mounted) return;
      final names = <String>[];
      for (final file in files) {
        originals.add(file.path);
        if (!video && await file.length() > maxChatMediaBytes) {
          throw Exception('Her fotoğraf en fazla 20 MB olabilir.');
        }
        final parts = video ? await VideoParts.prepare(file) : [file];
        prepared.addAll(parts);
        names.addAll(
          parts.length == 1
              ? [file.name]
              : List.generate(
                  parts.length,
                  (i) => '${file.name} · Part ${i + 1}',
                ),
        );
      }
      if (!mounted) return;
      final edited = await Navigator.push<List<String>>(
        context,
        MaterialPageRoute(
          builder: (_) => MediaNamesScreen(names: names, splitVideo: false),
        ),
      );
      if (edited == null || !mounted) return;
      for (var i = 0; i < prepared.length; i++) {
        if (!mounted) return;
        setState(
          () => _mediaStatus = '${i + 1}/${prepared.length} gönderiliyor…',
        );
        final content = await ChatMedia.upload(
          await prepared[i].readAsBytes(),
          edited[i],
          video ? 'video' : 'photo',
          chatId: widget.chatId,
          coupleId: widget.coupleId,
        );
        await widget.onSend(content, _scheduled);
        sent++;
      }
      if (mounted) setState(() => _scheduled = null);
      widget.onCancelReply?.call();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              sent > 0
                  ? '$sent ek gönderildi; kalanlar gönderilemedi. Gönderilenler sohbette duruyor.'
                  : userError(error),
            ),
          ),
        );
      }
    } finally {
      for (final part in prepared) {
        if (!originals.contains(part.path)) {
          try {
            await File(part.path).delete();
          } catch (_) {}
        }
      }
      if (mounted) {
        setState(() {
          _sending = false;
          _mediaStatus = null;
        });
      }
    }
  }

  Future<void> _selectMedia(String kind) async {
    _hideComposerKeyboard();
    try {
      if (kind == 'voice') {
        await _voiceMessage();
      } else if (kind == 'location') {
        await _shareLocation();
      } else if ((kind == 'galleryPhoto' || kind == 'galleryVideo') &&
          widget.pickMedia == null) {
        await _galleryBatch(kind == 'galleryVideo');
      } else {
        await _capture(
          kind == 'video' || kind == 'galleryVideo',
          gallery: kind == 'galleryPhoto' || kind == 'galleryVideo',
        );
      }
    } finally {
      if (mounted) _focus.canRequestFocus = true;
    }
  }

  Future<void> _voiceMessage() async {
    if (_sending || !_validMediaDate()) return;
    setState(() => _sending = true);
    final send = widget.onSend;
    final scheduled = _scheduled;
    final chatId = widget.chatId;
    final coupleId = widget.coupleId;
    try {
      final sent = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => VoiceNotesScreen(
            sendMessage: (path, title) async {
              final content = await ChatMedia.upload(
                await File(path).readAsBytes(),
                title,
                'audio',
                chatId: chatId,
                coupleId: coupleId,
              );
              await send(content, scheduled);
            },
          ),
        ),
      );
      if (sent == true && mounted) {
        setState(() => _scheduled = null);
        widget.onCancelReply?.call();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _schedule() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _scheduled ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduled ?? now),
    );
    if (time == null || !mounted) return;
    final selected = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    if (!selected.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'İleri bir tarih ve saat seç. Şimdi göndermek için zamanlamayı kaldır.',
          ),
        ),
      );
      return;
    }
    setState(() => _scheduled = selected);
  }

  bool _validMediaDate({bool video = false}) {
    if (_scheduled != null &&
        !_scheduled!.isBefore(
          DateTime.now().add(chatAttachmentLifetime(video ? 'video' : 'file')),
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bu ek yüklemeden 2 gün sonra silinir. Daha yakın bir gönderim zamanı seç.',
          ),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _shareLocation() async {
    if (_sending || widget.onShareLocation == null) return;
    setState(() => _sending = true);
    try {
      await widget.onShareLocation!();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konum paylaşılamadı. Tekrar dene.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    if (_scheduled != null && !_scheduled!.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Seçtiğin zaman geçti. Zamanlamayı kaldır veya yeni bir zaman seç.',
          ),
        ),
      );
      return;
    }
    final delivery = _TextDelivery(text, _scheduled, widget.onSend);
    _text.clear();
    setState(() => _scheduled = null);
    widget.onCancelReply?.call();
    await _deliverText(delivery);
  }

  Future<void> _deliverText(_TextDelivery delivery) async {
    if (delivery.retrying) return;
    setState(() => delivery.retrying = true);
    try {
      await delivery.send(delivery.text, delivery.scheduled);
      if (!mounted) return;
      setState(() => _failedTexts.remove(delivery));
    } catch (_) {
      if (mounted) {
        setState(() {
          if (!_failedTexts.contains(delivery)) _failedTexts.add(delivery);
        });
      }
    } finally {
      if (mounted) setState(() => delivery.retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_mediaStatus != null) Text(_mediaStatus!),
              if (_failedTexts.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 100),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final delivery in _failedTexts)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.error_outline),
                          title: const Text('Gönderilemedi'),
                          subtitle: Text(
                            messagePreview(delivery.text),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TextButton(
                            onPressed: delivery.retrying
                                ? null
                                : () => _deliverText(delivery),
                            child: Text(
                              delivery.retrying
                                  ? 'Bekleniyor…'
                                  : 'Tekrar gönder',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (widget.replyPreview != null)
                Row(
                  children: [
                    const Icon(Icons.reply, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        messagePreview(widget.replyPreview!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onCancelReply,
                      icon: const Icon(Icons.close),
                      tooltip: 'Yanıtı kaldır',
                    ),
                  ],
                ),
              if (_scheduled != null)
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Açılış: ${_scheduled!.day}.${_scheduled!.month}.${_scheduled!.year} ${_scheduled!.hour.toString().padLeft(2, '0')}:${_scheduled!.minute.toString().padLeft(2, '0')}',
                      ),
                    ),
                    IconButton(
                      onPressed: _sending
                          ? null
                          : () => setState(() => _scheduled = null),
                      icon: const Icon(Icons.close),
                      tooltip: 'Şimdi gönder',
                    ),
                  ],
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _sending ? null : _schedule,
                    icon: const Icon(Icons.schedule_outlined),
                    tooltip: 'Geleceğe gönder',
                  ),
                  Expanded(
                    child: TextField(
                      focusNode: _focus,
                      controller: _text,
                      minLines: 1,
                      maxLines: MediaQuery.viewInsetsOf(context).bottom > 0
                          ? 3
                          : 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Mesajını yaz…',
                        hintMaxLines: 1,
                        hintStyle: const TextStyle(fontSize: 14),
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLowest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _attach,
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Dosya gönder',
                  ),
                  PopupMenuButton<String>(
                    requestFocus: false,
                    onOpened: _hideComposerKeyboard,
                    onCanceled: () => _focus.canRequestFocus = true,
                    enabled: !_sending,
                    tooltip: 'Fotoğraf, video veya konum',
                    icon: const Icon(Icons.camera_alt_outlined),
                    onSelected: _selectMedia,
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'voice',
                        child: ConversationMenuLabel(
                          icon: Icons.mic_none_rounded,
                          label: 'Sesli mesaj kaydet',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'photo',
                        child: ConversationMenuLabel(
                          icon: Icons.photo_camera_outlined,
                          label: 'Fotoğraf çek',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'video',
                        child: ConversationMenuLabel(
                          icon: Icons.videocam_outlined,
                          label: 'Video çek',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'galleryPhoto',
                        child: ConversationMenuLabel(
                          icon: Icons.photo_library_outlined,
                          label: 'Galeriden fotoğraf seç',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'galleryVideo',
                        child: ConversationMenuLabel(
                          icon: Icons.video_library_outlined,
                          label: 'Galeriden video seç',
                        ),
                      ),
                      if (widget.onShareLocation != null)
                        const PopupMenuItem(
                          value: 'location',
                          child: ConversationMenuLabel(
                            icon: Icons.location_on_outlined,
                            label: 'Konum paylaş · 1 saat',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 2),
                  ConversationPressFeedback(
                    child: IconButton.filled(
                      onPressed: _sending ? null : _send,
                      tooltip: 'Gönder',
                      style: IconButton.styleFrom(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimaryContainer,
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
              if (_scheduled == null &&
                  MediaQuery.viewInsetsOf(context).bottom == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Ekler varsayılan 2 gün (uzatılabilir) • Dosya 80 MB • Video 100 MB',
                    style: TextStyle(fontSize: 10, color: Colors.blueGrey),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AttachmentPickerScreen extends StatefulWidget {
  const AttachmentPickerScreen({super.key});
  @override
  State<AttachmentPickerScreen> createState() => _AttachmentPickerScreenState();
}

class _AttachmentPickerScreenState extends State<AttachmentPickerScreen> {
  bool _picking = false;
  Future<void> _choose() async {
    setState(() => _picking = true);
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Dosya seç — vazgeçmek için geri dön',
      );
      if (mounted && file != null) Navigator.pop(context, file);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dosya seçici açılamadı. Yeniden dene.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Dosya gönder'),
      leading: IconButton(
        tooltip: 'Geri dön',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _picking ? null : _choose,
            icon: const Icon(Icons.folder_open),
            label: const Text('Dosya seç'),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç ve geri dön'),
          ),
        ],
      ),
    ),
  );
}
