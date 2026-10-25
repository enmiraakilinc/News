# Sohbet ve medya iyileştirmeleri — yayımlanmayı bekliyor

Bu çalışma yayımlanmış 1.16.1+2082 APK'sını değiştirmez. Kullanıcı sonraki
sürümü 1.16.2+2083 olarak belirledi ve yayımlanmasını onayladı.

## Kullanıcıya görünen değişiklikler

- Sohbet başlığında fotoğraf, kişi adının solunda yer alır.
- Tam ekran alarm açıklaması kısa tutulur; ayrıntılar açılarak okunur.
- Gönderen ve alıcı, fotoğraf/video ekinin erişim bitiş tarihini görür.
  Gönderen süreyi uzatınca açık sohbetin etiketi güncellenir.
- Sesli mesajlarda ve video oynatıcıda 1x, 1.5x ve 2x seçilir.
- Düzenlenmiş mesajda teslim/okundu tiki ile düzenlendi bilgisi birlikte kalır.
- Gelen mesaj balonu karanlık temalarda daha açık yüzey rengi kullanır.
- Son görülme varsayılan kapalıdır. Kişi ayrıntılarından belirli kişilerle
  paylaşılır. İzin listesi sahibine özeldir; diğer kişiler okuyamaz.

## Aktarım ve depolama

`media_binary.mjs` ek parçalarını kimlik doğrulaması, üyelik ve süre kuralları
altında ikili NMC1 yanıtında taşır. Base64 JSON yükü kaldırılır. Eski sunucu
404 döndürürse istemci eski JSON yolunu kullanabilir. Tam indirmede üç adet
16 parçalık grup paralel alınabilir. Görsel/ses/video kalitesi azaltılmaz.

`private_media_stream.dart`, şifre çözmeyi telefonda yapar ve yalnızca rastgele
anahtarlı 127.0.0.1 adresinden yerel oynatıcıya HTTP Range sunar. Video,
tam dosyanın indirilmesini beklemeden gerekli bölümleri isteyebilir. Önbellek
en fazla sekiz parçadır; tam açık video dosyası üretmez. Erişim denetimi ve
süre dolması korunur. Android'de açık HTTP izni yalnızca 127.0.0.1 içindir.
Görüntüleyicinin ekran görüntüsü koruması ve kaydetme onayı devam eder.

Son görülme tek zaman damgasını günceller; sürekli etkinlik geçmişi tutmaz.
Ön planda yaklaşık dakikalık kontrol ve sunucuda 30 saniyelik yazma sınırı
vardır. Bu işlem mesaj kuyruğunda/işlem makbuzlarında kayıt biriktirmez.
Kişi başına izin listesi ayrıca tutulur. Arka plan takip servisi eklenmez.

## Doğrulama — 25 Ekim 2026

- Flutter analizinde sorun yok; 199 uygulama testi başarılı.
- 45 Node testi ve izole PostgreSQL'de 52 kontrol başarılı.
- Gerçek HTTP Range, çapraz parça/sonek aralıkları, yetkisiz erişim,
  ikili veri bütünlüğü, süre etiketi ve hız seçimi test edildi.
- Sunucu modülleri ve 007_presence.sql yedek alınarak uygulandı; birincil
  PostgreSQL modu ve Firebase geçiş durumu değiştirilmedi.
- Canlı deneme yalnızca silinen geçici hesaplar/veriler kullandı. Gerçek
  kullanıcı medyası okunmadı veya değiştirilmedi.
- Yaklaşık 1,84 MB test verisinde JSON yanıtı 2.458.186 bayt, ikili yanıt
  1.843.226 bayttı. Son denemede süreler 2,265 sn ve 1,532 sn; ilk 450 KiB
  video parçası 0,515 sn idi. Önceki ölçümde ağ süreleri ters yönde değişti;
  bunlar her bağlantıda hız garantisi değildir. Esas kazanım tam dosyayı
  beklemeyen video başlangıcıdır.
- Fiziksel telefonda yeni video oynatma yolu henüz denenmedi. Yayın durumu
  `docs/releases/1.16.2.md` içinde tutulur.

İlgili kaynaklar `lib/features/media`, `lib/features/contacts/chat_presence.dart`,
`lib/features/chat/delivery_status.dart`, `server/src/media_binary.mjs`,
`server/src/presence.mjs` ve `server/sql/007_presence.sql` içindedir.
