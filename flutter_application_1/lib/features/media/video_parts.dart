import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'chat_media.dart';

class VideoParts {
  static const partBytes = maxChatVideoBytes;
  static const _channel = MethodChannel('app/video_parts');
  static Future<List<XFile>> prepare(XFile source) async {
    if (await source.length() <= partBytes) return [source];
    final paths = await _channel.invokeListMethod<String>('split', {
      'path': source.path,
      'maxBytes': partBytes,
    });
    if (paths == null || paths.length < 2) {
      throw Exception('Video parçalara ayrılamadı. Yeniden dene.');
    }
    final parts = paths.map(XFile.new).toList();
    try {
      for (final part in parts) {
        final size = await part.length();
        if (part.path == source.path || size == 0 || size > partBytes) {
          throw Exception('Video parçaları hazırlanamadı. Yeniden dene.');
        }
      }
      return parts;
    } catch (_) {
      await cleanup(parts, source.path);
      rethrow;
    }
  }

  static Future<void> cleanup(List<XFile> parts, String originalPath) async {
    for (final part in parts) {
      if (part.path != originalPath) {
        try {
          await File(part.path).delete();
        } catch (_) {}
      }
    }
  }
}
