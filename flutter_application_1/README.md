# Neural Haber — Flutter uygulaması

Bu klasör Android uygulamasının Flutter projesidir. Uygulama sohbet, sesli ve
görüntülü arama, kişisel notlar, Günün Sorusu, oyunlar ve bildirim özelliklerini
içerir. Sunucu/Worker ve yayın araçları proje kökündeki diğer klasörlerdedir;
bu klasörden yapılan bir derleme canlı sunucuya veya mağazaya yayın yapmaz.

## Geliştirme ve kontroller

Komutları bu klasörde çalıştır:

```sh
flutter pub get
flutter analyze
flutter test
```

Android debug APK:

```sh
flutter build apk --debug
```

İmzalı release APK için proje kökündeki `tools/releases/build.ps1` akışını ve
[yayın rehberini](../docs/PRIVATE_UPDATES.md) kullan. Sürüm numarası
`pubspec.yaml` içindeki `version` alanındadır. Release derlemek, dosyayı
yayımlamakla aynı şey değildir; yayın adımları ayrıca yetki ve açık onay ister.

## Kaynak yapısı

- `lib/app/`: uygulama başlangıcı ve çalışma zamanı.
- `lib/core/`: ortak veri, güvenlik, bildirim, tema ve yardımcı servisler.
- `lib/features/`: ekranlar ve özelliklere ait servisler.
- `android/`: Android izinleri ve Kotlin platform bağlantıları.
- `test/`: uygulama davranışlarını denetleyen Flutter testleri.

Detaylı dosya haritası ve yayın sınırları için proje kökündeki
[dosya rehberine](../docs/DOSYA_REHBERI.md) ve
[mimari belgesine](../docs/ARCHITECTURE.md) bak.
