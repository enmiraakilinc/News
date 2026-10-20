import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Firestore belge sınırı ~1 MB. Şifreleme + base64 boyutu yaklaşık 1.77 katına
/// çıkardığı için, ham fotoğrafın bu sınırın altında kalması gerekir.
const int kMaxRawBytes = 560000;

/// Çözünürlüğü korumak için kullanılan üst sınır. flutter_image_compress
/// yalnızca KÜÇÜLTÜR; bu kadar büyük bir değer verince fotoğraf olduğu
/// boyutta kalır (büyütme yapılmaz).
const int _kNoDownscale = 4096;

/// Ekran önizlemelerinde gereksiz yüksek çözünürlük kullanmaktan kaçınmak
/// için uygulamada gösterilecek küçük kartların en boy sınırı.
const int kThumbMaxSide = 320;

/// Daha büyük ayrıntı görünümü için hafif bir üst sınır.
const int kDetailMaxSide = 1200;

/// Fotoğrafı SIĞACAK EN İYİ kalitede hazırlar ve YÖNÜNÜ DÜZELTİR.
///
/// Telefonla yan çekilen fotoğraflarda dönüş bilgisi EXIF etiketinde durur;
/// Flutter bunu kendiliğinden uygulamadığı için fotoğraf yan görünür. Burada
/// fotoğraf yeniden kodlanarak dönüş kalıcı olarak uygulanır.
///
/// - Fotoğraf sınıra sığıyorsa yalnızca yönü düzeltilir, çözünürlük korunur.
/// - Sığmıyorsa yüksek çözünürlükten başlanıp sığana kadar kademeli düşürülür.
Future<Uint8List> compressToFit(Uint8List src) async {
  // Preserve files that already fit, including their original quality/EXIF.
  if (src.length <= kMaxRawBytes) return src;
  // 1) Yönü düzelt, çözünürlüğü koru (autoCorrectionAngle varsayılan olarak açık).
  Uint8List cur = src;
  try {
    final duzeltilmis = await FlutterImageCompress.compressWithList(
      src,
      minWidth: _kNoDownscale,
      minHeight: _kNoDownscale,
      quality: 95,
      format: CompressFormat.jpeg,
    );
    if (duzeltilmis.isNotEmpty) cur = duzeltilmis;
  } catch (_) {
    // Düzeltilemezse orijinalle devam et.
  }

  if (cur.length <= kMaxRawBytes) return cur;

  // 2) Sığmıyorsa: en iyiden başla, ilk sığan kazanır.
  const List<List<int>> denemeler = [
    [2560, 90],
    [2048, 88],
    [2048, 80],
    [1600, 80],
    [1440, 75],
    [1200, 70],
    [1080, 65],
    [1080, 50],
    [800, 45],
  ];

  for (final d in denemeler) {
    try {
      final out = await FlutterImageCompress.compressWithList(
        src,
        minWidth: d[0],
        minHeight: d[0],
        quality: d[1],
        format: CompressFormat.jpeg,
      );
      if (out.isNotEmpty && out.length <= kMaxRawBytes) return out;
    } catch (_) {
      // Bu kademe olmadı, bir alttakini dene.
    }
  }
  return cur; // hiçbiri sığmadıysa servis anlamlı bir hata verecek
}
