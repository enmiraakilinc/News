# Sohbet görünümü

Kullanıcının 25 Ekim 2026'da paylaştığı dört HTML ekranı ana görsel kaynaktır:
mesaj seçenekleri, kamera/medya menüsü, sohbet/planlı mesaj alanı ve kişi
ayrıntıları. Refero canlı araştırması abonelik gerektirdiği için kullanılmadı;
becerinin renk ve bileşen rehberleriyle kullanıcı örneği birlikte incelendi.

## Tasarım kararları

- Mor sohbet: açık lavanta zemin, beyaz gelen balon, koyu mor giden balon.
  Örnekteki `#614692` yalnızca mor sohbetin vurgu/giden balon rengidir.
- Diğer dokuz tema kendi paletini ve açık/koyu karakterini korur. Aynı balon,
  menü ve kart geometrisi bütün sohbetlerde kullanılır. Gövde metni, ikonlar
  ve gönder düğmesinin rengi aynı ColorScheme üzerinden üretilir.
- Uzun basma: tek seferlik flu arka plan, kişisel hızlı emoji şeridi, metin/
  alıntı önizlemesi, mevcut izinlerin elverdiği eylemler. Medya önizlemesi için
  dosya ikinci kez indirilmez; dosya adı kullanılır. Uzun menü kaydırılabilir.
- Kamera menüsünde ayrı, ikonlu fotoğraf/video/galeri/ses/konum eylemleri vardır.
  Dosya ve zamanlama düğmeleri ayrı tutulur. Göndermek klavyeyi kapatmaz.
- Profil ayrıntıları yuvarlatılmış kartlara ayrılır; avatar mevcut görüntüleyiciye
  bağlıdır. HTML'deki örnek kişi/çevrim içi durumu ve çalışmayan engelle/şikâyet
  işlemleri ürüne taşınmadı. Silme mevcut onay/erişim akışından geçer.

## Dosyalar

| Dosya | Görevi |
|---|---|
| `lib/core/theme/chat_theme.dart` | Sohbete özel tema; haber/genel sayfa teması bağımsız kalır |
| `lib/features/chat/conversation_style.dart` | Renk rolleri, odak menüsü, ayar kartı, medya menüsü satırı |
| `lib/features/chat/chat_widgets.dart` | Gerçek mesaj balonları ve mesaj yazma alanı |
| `lib/features/chat/reaction_picker.dart` | Hızlı şerit ve tam seçicinin ortak kişisel emoji listesi |
| `lib/features/contacts/contact_details_screen.dart` | Üst bar ve kişi kartları |
| `test/conversation_style_test.dart` | On temada kontrast, küçük ekran ve gerçek menü eylemleri |

Testlerde `CHAT_PREVIEW_DIR` verilirse yalnızca yerel görsel inceleme için PNG
üretilir. Bu seçenek Windows Arial/emoji ve Flutter ikon fontlarını yükler;
normal test çalışması bu yerel dosyalara bağımlı değildir. APK sürüm adı/kodu
kullanıcının seçimiyle 1.16.1+2082 olarak 25 Ekim 2026'da yayımlandı.

## Hafif hareket ve önceki özellikler

Menü açılışı 140 ms, kapanışı 100 ms; emoji ve gönder tuşunun basma tepkisi
90 ms ve yalnızca %4 ölçek farkıdır. Hareketi azalt sistem tercihi açıksa bu
ek geçişler kapatılır. Sürekli animasyon, tekrarlayan zamanlayıcı, mesaj listesi
animasyonu veya hareketli bulanıklık eklenmedi. Ayar kartı köşeleri 12, genel
kart/düğme köşeleri 14 birimdir. Ayar kartları uzun yazıları köşelerde kırpmaz;
Material yüzeyi dokunma geri bildirimini de gösterir.

1.15.1 kaynak commit'i `481bf678` ile karşılaştırmada 64 özellik dosyasının
tamamı korundu. Mesaj yazma bileşeninin alanları ve gönderme/yeniden deneme,
zamanlama, kamera, galeri, dosya, ses ve konum metotları hem 1.15.1 hem 1.16.0
ile aynıdır; yalnızca build içindeki görünüm düzenlendi. Sunucu, veri erişimi,
arama servisi ve medya yaşam süreleri bu tema değişikliğinde değiştirilmedi.
