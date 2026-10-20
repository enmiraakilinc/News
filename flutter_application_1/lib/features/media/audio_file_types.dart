/// Supported audio file extensions and Android MIME types.
class AudioFileTypes {
  static const mimeTypes = <String, String>{
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
    'opus': 'audio/ogg',
    'flac': 'audio/flac',
    'amr': 'audio/amr',
    '3ga': 'audio/3gpp',
  };
  static String extension(String name) {
    final ext = name.trim().split('.').last.toLowerCase();
    return mimeTypes.containsKey(ext) ? ext : 'm4a';
  }

  static String mime(String name) => mimeTypes[extension(name)]!;
}
