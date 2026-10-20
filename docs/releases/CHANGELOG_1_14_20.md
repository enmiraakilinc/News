# 1.14.20 (2064) — Yayın onayı bekliyor

Kamuya açık kısa not: Kararlılık iyileştirmeleri.

- Sesli görüşme sınırı cevaplandıktan sonra 15 dakikadır. Ekrandaki metinler, Dart sayacı, Android mikrofon ön plan servisinin monoton zaman sınırı ve sınırlı uyanık tutma kilidi birlikte güncellendi. Yinelenen servis olayları süreyi uzatmaz.
- Yanıt bekleme süresi hâlâ 45 saniye; ahize varsayılanı ve ekran görüntüsü koruması korunur.
- Firestore arama sinyali erişimi ve terk edilmiş kayıt temizliği için oluşturma anından başlayan pencere 4 dakikadan 16 dakikaya çıkarıldı. Bu pencere yanıt için 45 saniyeyi ve görüşmenin 15 dakikasını kapsar; gerçek görüşme sınırı istemci ve native serviste 15 dakikadır.
- Üçüncü dakikada 12 dakika kaldığı, 15 dakikada bittiği ve negatif/saat geri alma durumunda sınırın aşılmadığı test edilir. Yerel Firestore testinde beşinci dakikada sinyal erişimi sürer, erken kayıt silme ve pencere sonrası aday ekleme reddedilir.
- Görüntülü arama bu sürümün kapsamına eklenmedi; kullanıcı bunun mümkün olup olmadığını sordu. Gelecekte WebRTC ile uygulanabilir; bazı ağlarda TURN aktarım sunucusu gerekir.

Yayın adımları: imzalı ARM64 APK ve firestore-1.14.20.pending.rules için kullanıcı onayı. Worker değişikliği gerekmez. Canlı sürüm onaya kadar 1.14.19 olarak kalır. Fiziksel S25 üzerinde 15 dakikalık görüşme testi yapılmadı.

## Publication complete
- User approved publication. Final ARM64 APK publicly downloaded and verified against local SHA-256 and byte count. config/app_version is 2064 / 1.14.20; public update metadata verified.
- Tested call signaling/abandoned cleanup window rules deployed and verified with previous source backed up. No Worker change. Both participants must update for fifteen-minute calls. Earlier pending notes describe preparation only.
