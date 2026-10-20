# 1.14.21 (2065) — Yayın onayı bekliyor

Kamuya açık kısa not: Görünüm ve kararlılık iyileştirmeleri.

## Bildirimler

- Gizli bölümdeki Ayarlar'da sohbet, mektup, anı, soru, dilek, sesli not, resim/not, haber, güncelleme ve depolama bildirimleri ayrı görünür anahtarlar oldu. Eski dropdown kaldırıldı. Eski tercihler bir kez bağımsız anahtarlara aktarılır; Android bildirim izni özellikleri kendiliğinden açmaz.
- Gelen aramalar ile alarm/uyandırma ayrı anahtarlardır. Alarm anahtarı alıcıdaki native receiver ve serviste de denetlenir; kişi bazındaki izinler ayrıca gerekir. Arama anahtarı ön plan dinleyicisinde ve yerel FCM alıcısında kontrol edilir.
- Yalnızca alarm bildirimleri işlemi tüm içerik, arama ve sürekli sayaç bildirimlerini kapatır; alarmı açık bırakır. Kişi bazındaki uyandırma izinlerini değiştirmez. Güncelleme konusundan çıkılır; uygulama içi rozetler korunur.
- Eski ortak yeni-içerik anahtarı gizli ana sayfadan kaldırıldı. Mesaj bildirimini kapatmak bağımsız mektup bildirimini kaldırmaz.

## Aramalar

- Kişi menüsünde kalan 3 dakika metinleri 15 dakika oldu. Sesli arama ahizeden gelir; görüntülü görüşmede hoparlör kullanılır. Her iki görüşme 15 dakika ile sınırlıdır.
- Birebir görüntülü arama, mevcut WebRTC paketinde ön kamera, kamera kapatma/değiştirme ve yerel/uzak önizlemeyle eklendi. Mikrofon ve kamera ancak kullanıcı aramayı başlattığında veya açıkça yanıtladığında açılır. Aranan kişinin kamerası çalma ekranında açılmaz. İptal/sonlandırma sonrasında geç dönen medya kaynakları kapatılır.
- Ses/görüntü dosyası kaydı yoktur; normal geçici SDP/ICE sinyalleri önceki temizleme akışını kullanır. Video Firestore sohbet eki olarak yüklenmez. Ücretli plan, yeni servis veya TURN sunucusu eklenmedi; mevcut Google STUN ağı kullanılır. Bazı farklı ağlarda bağlantı kurulamaması mümkündür; internet veri tüketimi vardır.
- Android kamera ve mikrofon foreground-service türleri birlikte tanımlandı; video için gereken kamera türü yalnız görüntülü görüşme başlatılırken eklenir. Android izin ve arka plan kısıtları korunur.
- Gelen arama için dışa kapalı, FLAG_SECURE korumalı native tam ekran Activity eklendi. Hesap, arama kimliği, tek kullanımlık nonce, güncel arama durumu ve 45 saniyelik pencere kontrol edilir. Sesli/görüntülü olduğu yanıtlamadan önce açıkça gösterilir; isim/sohbet bilgisi kilit ekranına yazılmaz.
- Tam ekran tercihi Android 14+ özel erişimiyle çalışır. Sistem tam ekranı göstermediğinde bildirime dokunarak aynı korumalı ekran açılır. Bildirim eylemi kamerayı otomatik açmaz; açıkça Yanıtla gerekir. Ekran sonlandırma/iptal/hesap değişiminde kapanır.
- Arama ekranı görüntü koruması ayarlarda her zaman açık olarak gösterilir; sesli/görüntülü Flutter ekranı ve native gelen arama ekranı FLAG_SECURE kullanır. Normal Android ekran görüntüsü/kaydı engellenir; ayrıcalıklı/root uzaktan erişime karşı mutlak garanti iddia edilmez.

## Tema ve doğrulama

- Love temel kırmızısı #420303; koyu kırmızı alanlar üzerinde daha parlak #FF7979 vurgular ve okunur metinler kullanılır. Genel haber alanına ayar bağlantısı eklenmedi.
- 91 Flutter testi, 13 izole Firestore kural testi; Android Kotlin/Java release derlemesi başarılı. Son değişiklikler için ilgili bildirim/arama testleri ve analiz yeniden çalıştırılır. Fiziksel S25, kilit ekranı ve iki telefon arasında görüntülü görüşme henüz denenmedi.
- Yayın için yalnızca 1.14.21 ARM64 APK ve firestore-1.14.21.pending.rules gerekir. Yeni kural video alanını isteğe bağlı boolean olarak kabul eder; üyelik ve değiştirilemez arama türü test edildi. Eski sesli aramalar uyumludur. Worker/IAM değişikliği gerekmez. Video için iki tarafın yeni sürüme geçmesi gerekir.
- Canlı sürüm 1.14.20 korunur; kullanıcı yayın onayı beklenir. APK boyutu ve hash: ../release-1.14.21-build-report.json.

## Publication complete
- User approved publication. Final ARM64 APK publicly downloaded and verified against the local SHA-256 and byte count; config/app_version is 2065 / 1.14.21 with public metadata verified.
- Tested optional boolean video-call rule deployed and verified; previous source backed up. No Worker/IAM or paid-service change. Both participants must update for video calls. Earlier pending notes describe preparation only. Physical S25 validation remains unperformed.
