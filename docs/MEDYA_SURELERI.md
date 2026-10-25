# Sohbet eki süresini uzatma — 1.16.1

Gönderdiğin fotoğraf, video, ses veya dosya mesajına uzun basıp **Erişim süresini
uzat** seçilir. Yeni tarih/saat seçilip onaylanır. Süre dolmadan tekrar
uzatılabilir; tekrar sayısı sınırlandırılmaz. Tarih seçici 2100 sonuna kadar
tarih sunar. Varsayılan iki gün korunur; süreyi alıcı değiştiremez. Silinmiş
dosyayı bu işlem geri getirmez; süresi dolmuş dosya uzatılamaz.

Dosya yeniden yüklenmez veya kopyalanmaz; metadata içindeki `expiresAt`
değişir. Gönderilme tarihi, mesaj sırası ve içerik aynı kalır. Mevcut indirme
onaylarının bitişi de aynı işlemde uzatılır; onay durumu değiştirilmez.

## Dosyalar ve güvenlik

- `lib/features/media/media_expiry_dialog.dart`: tarih, saat ve kullanıcı onayı.
- `lib/features/media/chat_media.dart`: ortak bitiş hesabı, sunucu işlemi,
  önizleme/indirme önbelleği ve istemci temizliği.
- `lib/features/chat/chat_widgets.dart`: yalnızca gönderenin uzun basma eylemi.
- `server/src/write_policy.mjs`: gönderen + üyelik kontrolü; yalnızca süresi
  dolmamış, yüklemesi tamamlanmış eki daha ileri bir tarihe uzatır.
- `server/sql/006_media_expiry.sql`: mevcut kurulum için RLS ve temizlik geçişi.
  Eski kayıtlarda tarih yoksa oluşturulma tarihinden iki gün hesaplanır.
- `server/src/commit.mjs`: uzatma/silme, temizliğin kilitlediği ana dosya
  kaydıyla sıralanır. Süre dolma anındaki yarışta yarım dosya korunmaz.
- `tools/server/verify_media_expiry.py`: gerçek kullanıcıya dokunmadan geçici
  hesaplarla HTTPS uzatma, indirme onayı, eski temizliğin reddi ve açık silme.

Aktif uzatılmış dosyayı eski uygulamanın otomatik temizliği silemez. Açıkça silme
için yeni istemci gönderen adına kısa ömürlü `deleteRequestedAt` işareti koyar.
Süre dolduktan sonra sunucunun 15 dakikalık temizliği dosyayı kaldırabilir.

## Canlı durum — 25 Ekim 2026

Sunucu geçişi ve kuralları uygulandı. Kullanıcının onayladığı dünkü üç ek
(bir video, iki fotoğraf), tüm parçaları doğrulanarak **1 Kasım 2026 17.48
Türkiye saatine** kadar uzatıldı. Özgün metadata kopyası `private/` altında;
kimlikler, içerik ve yedek Git'e alınmaz. Firebase kaynakları değiştirilmedi.

Telefonundaki 1.16.0 sabit iki günlük kontrolü kullanır. Dosyalar sunucuda
korunsa da uzatılmış tarihle açma/seçme davranışı 1.16.1 APK kurulduğunda
çalışır. 1.16.1 APK 25 Ekim 2026'da yayımlandı. Uzun süre saklanan dosyalar, süreleri
doluncaya kadar sunucu diskini kullanmaya devam eder.
