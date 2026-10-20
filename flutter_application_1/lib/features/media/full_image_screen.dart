import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

class FullImageScreen extends StatelessWidget {
  /// Cihazdaki dosya yolu (yerel resimler için).
  final String? imagePath;

  /// Bellekteki resim (paylaşımlı/şifresi çözülmüş resimler için).
  final Uint8List? bytes;

  /// Verilirse sag ustte bir cop kutusu cikar. Kullanici onaylarsa bu cagrilir
  /// ve ekran kapanir. Silme islemini cagiran ekran yapar (listeyi o tutuyor).
  final VoidCallback? onDelete;

  const FullImageScreen({super.key, this.imagePath, this.bytes, this.onDelete});

  Future<void> _confirmDelete(BuildContext context) async {
    final nav = Navigator.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Resmi sil"),
        content: const Text("Bu resim kalıcı olarak silinecek. Emin misin?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Vazgeç"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Sil", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      onDelete!();
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Bos alana dokununca kapanir; iki parmakla yakinlastirilabilir.
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: bytes != null
                    ? Image.memory(bytes!)
                    : Image.file(File(imagePath!)),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: PhotoActionButton(
              icon: Icons.close,
              onTap: () => Navigator.pop(context),
            ),
          ),
          if (onDelete != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: PhotoActionButton(
                icon: Icons.delete_outline,
                color: Colors.red,
                onTap: () => _confirmDelete(context),
              ),
            ),
        ],
      ),
    );
  }
}

/// Koyu daire zeminli buton — resim uzerinde her zaman okunur kalir.
class PhotoActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const PhotoActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color, size: 26),
        ),
      ),
    );
  }
}
