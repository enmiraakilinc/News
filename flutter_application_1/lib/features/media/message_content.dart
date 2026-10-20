import 'dart:convert';
import 'dart:async';
import 'chat_media.dart';
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../location/location_share.dart';
import 'media_viewer.dart';
import 'photo_gallery.dart';
import '../../core/utils/user_errors.dart';
import 'chat_audio_player.dart';
import '../chat/chat_downloads.dart';

const attachmentPrefix = 'NEURAL_FILE:';

Future<void> openChatPhoto(
  BuildContext context,
  String current,
  Uint8List bytes,
  List<String> messages, {
  Future<Uint8List> Function(String)? mediaLoader,
}) async {
  final photos = <String>[];
  for (final text in [...messages, if (!messages.contains(current)) current]) {
    if (photos.contains(text)) continue;
    try {
      if (!text.startsWith(mediaPrefix) && !text.startsWith(attachmentPrefix)) {
        continue;
      }
      final data = jsonDecode(text.substring(text.indexOf(':') + 1)) as Map;
      if (text == current || attachmentViewKind(data) == 'photo') {
        photos.add(text);
      }
    } catch (_) {
      /* Other messages are not gallery entries. */
    }
  }
  VoidCallback? save(String text) => text.startsWith(mediaPrefix)
      ? () => ChatDownloads.saveOrRequest(context, ChatMedia.idFrom(text))
      : null;
  if (photos.length <= 1) {
    await showPrivatePhoto(context, bytes, onSave: save(current));
    return;
  }
  final items = [
    for (final text in photos)
      PrivatePhotoItem(
        load: () async {
          if (text.startsWith(mediaPrefix)) {
            return (mediaLoader ?? ChatMedia.download)(ChatMedia.idFrom(text));
          }
          final data =
              jsonDecode(text.substring(attachmentPrefix.length)) as Map;
          final raw = base64Decode(data['bytes'] as String);
          if (raw.length >
              chatAttachmentLimit(data['kind'] as String? ?? 'file')) {
            throw Exception('Fotoğraf çok büyük.');
          }
          return raw;
        },
        onSave: save(text),
      ),
  ];
  if (context.mounted) {
    await showPrivateGallery(context, items, photos.indexOf(current), bytes);
  }
}

Future<bool> attachmentIsPhoto(Map data, Uint8List bytes) async {
  final kind = attachmentViewKind(data, bytes: bytes);
  if (kind == 'photo') return true;
  if (kind != 'file' || bytes.isEmpty) return false;
  // File metadata can be missing or changed by the sender. Ask Flutter's
  // actual image decoder before handing any unknown attachment to Android.
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1);
    codec.dispose();
    return true;
  } catch (_) {
    return false;
  }
}

String attachmentViewKind(Map data, {Uint8List? bytes}) {
  // Some file pickers preserve an inaccurate name/type. Recognize supported
  // image signatures before choosing an external file application.
  if (bytes != null &&
      ((bytes.length >= 3 &&
              bytes[0] == 0xff &&
              bytes[1] == 0xd8 &&
              bytes[2] == 0xff) ||
          (bytes.length >= 8 &&
              bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4e &&
              bytes[3] == 0x47 &&
              bytes[4] == 13 &&
              bytes[5] == 10 &&
              bytes[6] == 26 &&
              bytes[7] == 10) ||
          (bytes.length >= 6 &&
              ascii
                  .decode(bytes.sublist(0, 6), allowInvalid: true)
                  .startsWith('GIF8')) ||
          (bytes.length >= 12 &&
              ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
              ascii.decode(bytes.sublist(8, 12), allowInvalid: true) ==
                  'WEBP'))) {
    return 'photo';
  }
  final kind = data['kind'];
  if (kind == 'photo' || kind == 'video') return kind as String;
  final extension = (data['name'] as String? ?? '')
      .trim()
      .split('.')
      .last
      .toLowerCase();
  if (['mp4', 'mov', 'm4v', 'webm', 'mkv', '3gp', 'avi'].contains(extension)) {
    return 'video';
  }
  if ([
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
    'heic',
    'heif',
  ].contains(extension)) {
    return 'photo';
  }
  return 'file';
}

String messagePreview(String text) {
  if (text.startsWith(locationPrefix)) return '📍 Konum paylaşımı';
  if (text.startsWith(mediaPrefix)) {
    try {
      return '📎 ${jsonDecode(text.substring(mediaPrefix.length))["name"]}';
    } catch (_) {
      return '📎 Dosya';
    }
  }
  if (!text.startsWith(attachmentPrefix)) return text;
  try {
    return '📎 ${jsonDecode(text.substring(attachmentPrefix.length))['name']}';
  } catch (_) {
    return '📎 Dosya';
  }
}

class MessageContent extends StatelessWidget {
  final String text;
  final List<String> photoMessages;
  final Future<MediaPreview?> Function(String)? previewLoader;
  final Future<Uint8List> Function(String)? mediaLoader;
  const MessageContent({
    super.key,
    required this.text,
    this.photoMessages = const [],
    this.previewLoader,
    this.mediaLoader,
  });
  Future<void> _openFile(BuildContext context) async {
    try {
      final data =
          jsonDecode(text.substring(attachmentPrefix.length))
              as Map<String, dynamic>;
      final bytes = base64Decode(data['bytes'] as String);
      if (bytes.length >
          chatAttachmentLimit(data['kind'] as String? ?? 'file')) {
        throw Exception('Dosya sınırı');
      }
      if (await attachmentIsPhoto(data, bytes)) {
        if (context.mounted) {
          await openChatPhoto(
            context,
            text,
            bytes,
            photoMessages,
            mediaLoader: mediaLoader,
          );
        }
        return;
      }
      final name = (data['name'] as String).replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final folder = await getTemporaryDirectory();
      final file = File(
        '${folder.path}/neural_${DateTime.now().microsecondsSinceEpoch}_$name',
      );
      await file.writeAsBytes(bytes);
      if (attachmentViewKind(data) == 'video') {
        try {
          if (context.mounted) {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => PrivateVideoScreen(file: file)),
            );
          }
        } finally {
          if (await file.exists()) await file.delete();
        }
        return;
      }
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception('Bu dosyayı açabilecek bir uygulama bulunamadı.');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? 'Ek dosyanın verisi okunamadı. Gönderen kişiden fotoğrafı yeniden göndermesini iste.'
                  : userError(
                      error,
                      fallback:
                          'Ek okunamadı. Fotoğrafı yeniden göndermeyi dene. Başka bir uygulama yüklemen gerekmiyor.',
                    ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (text.startsWith(locationPrefix)) {
      final id = text.substring(locationPrefix.length);
      if (!RegExp(r'^[a-zA-Z0-9]{20}$').hasMatch(id)) {
        return const Text('📍 Geçersiz konum');
      }
      return LocationShareCard(key: ValueKey(id), id: id);
    }
    if (text.startsWith(mediaPrefix)) {
      try {
        final data = jsonDecode(text.substring(mediaPrefix.length)) as Map;
        if (data['kind'] == 'audio') {
          return ChatAudioPlayer(
            id: ChatMedia.idFrom(text),
            name: data['name'] as String,
          );
        }
      } catch (_) {}
      return _RemoteMedia(
        key: ValueKey(text),
        text: text,
        previewLoader: previewLoader,
        mediaLoader: mediaLoader,
        photoMessages: photoMessages,
      );
    }
    if (text.startsWith(attachmentPrefix)) {
      try {
        final data =
            jsonDecode(text.substring(attachmentPrefix.length))
                as Map<String, dynamic>;
        if (attachmentViewKind(data) == 'photo') {
          final bytes = base64Decode(data['bytes'] as String);
          if (bytes.length <= 409600) {
            return InkWell(
              onTap: () => _openFile(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  bytes,
                  height: 200,
                  fit: BoxFit.contain,
                  errorBuilder: (_, error, stack) => Text(messagePreview(text)),
                ),
              ),
            );
          }
        }
      } catch (_) {
        /* Older or malformed attachments use the file button. */
      }
      return TextButton.icon(
        onPressed: () => _openFile(context),
        icon: const Icon(Icons.attach_file),
        label: Text(messagePreview(text)),
      );
    }
    final spans = <Widget>[];
    final matches = RegExp(
      r'https?://[^\s<>]+',
      caseSensitive: false,
    ).allMatches(text);
    var offset = 0;
    for (final match in matches) {
      if (match.start > offset) {
        spans.add(
          Text(
            text.substring(offset, match.start),
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
        );
      }
      final url = match.group(0)!;
      spans.add(
        InkWell(
          onTap: () async {
            try {
              if (!await launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              )) {
                throw Exception();
              }
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link açılamadı.')),
                );
              }
            }
          },
          child: Text(
            url,
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      );
      offset = match.end;
    }
    if (offset < text.length) {
      spans.add(
        Text(
          text.substring(offset),
          style: const TextStyle(fontSize: 16, height: 1.4),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: spans,
    );
  }
}

class _RemoteMedia extends StatefulWidget {
  final String text;
  final List<String> photoMessages;
  final Future<MediaPreview?> Function(String)? previewLoader;
  final Future<Uint8List> Function(String)? mediaLoader;
  const _RemoteMedia({
    super.key,
    required this.text,
    this.photoMessages = const [],
    this.previewLoader,
    this.mediaLoader,
  });
  @override
  State<_RemoteMedia> createState() => _RemoteMediaState();
}

class _RemoteMediaState extends State<_RemoteMedia> {
  bool _busy = false;
  double _progress = 0;
  File? _videoFile;
  String? _videoScope;
  Uint8List? _photo;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    try {
      final data = jsonDecode(widget.text.substring(mediaPrefix.length)) as Map;
      if (attachmentViewKind(data) == 'photo') _loadPreview();
    } catch (_) {}
  }

  Future<void> _loadPreview() async {
    try {
      final preview = await (widget.previewLoader ?? ChatMedia.preview)(
        ChatMedia.idFrom(widget.text),
      );
      if (!mounted ||
          preview == null ||
          !preview.expiresAt.isAfter(DateTime.now())) {
        return;
      }
      setState(() => _photo = preview.bytes);
      _expiry = Timer(preview.expiresAt.difference(DateTime.now()), () {
        if (mounted) setState(() => _photo = null);
      });
    } catch (_) {
      /* Expired or offline previews retain the open button. */
    }
  }

  @override
  void dispose() {
    _expiry?.cancel();
    final file = _videoFile;
    if (file != null) unawaited(file.delete().catchError((_) => file));
    super.dispose();
  }

  Future<void> _viewVideo(File file) async {
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateVideoScreen(
          file: file,
          onSave: () => ChatDownloads.saveOrRequest(
            context,
            ChatMedia.idFrom(widget.text),
          ),
        ),
      ),
    );
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final data = jsonDecode(widget.text.substring(mediaPrefix.length)) as Map;
      final initialScope = widget.mediaLoader == null
          ? await ChatMedia.accessScope()
          : null;
      if (_videoFile != null && await _videoFile!.exists()) {
        if (initialScope != _videoScope) {
          try {
            await _videoFile!.delete();
          } catch (_) {}
          _videoFile = null;
          throw Exception(
            'Hesap veya sohbet bağlantısı değişti. Yeniden açmayı dene.',
          );
        }
        await ChatMedia.checkAccess(ChatMedia.idFrom(widget.text));
        if (await ChatMedia.accessScope() != initialScope) {
          throw Exception('Sohbet bağlantısı değişti. Yeniden aç.');
        }
        await _viewVideo(_videoFile!);
        return;
      }
      final bytes = widget.mediaLoader != null
          ? await widget.mediaLoader!(ChatMedia.idFrom(widget.text))
          : await ChatMedia.download(
              ChatMedia.idFrom(widget.text),
              onProgress: (value) {
                if (mounted) setState(() => _progress = value);
              },
            );
      final scope = widget.mediaLoader == null
          ? await ChatMedia.accessScope()
          : null;
      if (scope != initialScope) {
        throw Exception('Sohbet bağlantısı değişti. Yeniden aç.');
      }
      if (!mounted) return;
      if (await attachmentIsPhoto(data, bytes)) {
        if (!mounted) return;
        await openChatPhoto(
          context,
          widget.text,
          bytes,
          widget.photoMessages,
          mediaLoader: widget.mediaLoader,
        );
      } else {
        final name = (data['name'] as String).replaceAll(
          RegExp(r'[^a-zA-Z0-9._-]'),
          '_',
        );
        final folder = await getTemporaryDirectory();
        final file = File(
          '${folder.path}/neural_media_${ChatMedia.idFrom(widget.text)}_$name',
        );
        await file.writeAsBytes(bytes);
        if (attachmentViewKind(data) == 'video') {
          if (!mounted) {
            await file.delete();
            return;
          }
          _videoFile = file;
          _videoScope = scope;
          await _viewVideo(file);
          return;
        }
        if ((await OpenFilex.open(file.path)).type != ResultType.done) {
          throw Exception('Dosya açılamadı.');
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userError(
                error,
                fallback:
                    'Ek açılamadı. İnternetini kontrol edip yeniden dene.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_busy)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            _progress >= 1
                ? 'Hazırlanıyor…'
                : 'Yükleniyor · %${(_progress * 100).round()}',
          ),
        ),
      if (_photo != null)
        InkWell(
          onTap: _busy ? null : _open,
          child: Image.memory(
            _photo!,
            width: 160,
            height: 120,
            cacheWidth: 512,
            fit: BoxFit.contain,
          ),
        ),
      TextButton.icon(
        onPressed: _busy ? null : _open,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                widget.text.contains('"kind":"video"')
                    ? Icons.play_circle_outline
                    : Icons.open_in_full,
              ),
        label: Text(messagePreview(widget.text)),
      ),
      Text(
        widget.text.contains('"kind":"video"')
            ? '2 gün boyunca izlenebilir'
            : '2 gün boyunca görüntülenebilir',
        style: const TextStyle(fontSize: 11),
      ),
    ],
  );
}

Future<String?> editMessage(
  BuildContext context,
  String text, {
  String title = 'Mesajı düzenle',
}) async {
  final controller = TextEditingController(text: text);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        minLines: 2,
        maxLines: 8,
        autofocus: true,
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
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}
