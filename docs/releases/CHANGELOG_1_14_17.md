# 1.14.17 (2061) — ARM64 APK hazır, yayın onayı bekliyor

Kısa kamuya açık not: Görünüm ve kararlılık iyileştirmeleri.

## Release / startup validation
- Signed ARM64-only release: 38,202,641 bytes (38.20 MB / 36.43 MiB), version 1.14.17 / 2061. Previous package: 105.44 MiB; reduction approximately 65.5%.
- R8 minification, resource shrinking and icon tree shaking enabled. WebRTC JNI consumer keep rules preserved. PNG icons optimized losslessly; saved 2,617 bytes.
- No x86/emulator binaries or debug mode in this package. No universal APK generated. Existing historical artifacts were not deleted.
- Target below 30 MB was not achieved: native ARM64 libraries alone require over 32 MB compressed. Calls, media and offline maps retained.
- First frame no longer waits for notification plugin initialization. Native splash has a dark background; Flutter startup shows loading, an 8-second timeout, retry and continue-without-notifications actions. Expired-location cleanup does not block other startup tasks.
- iOS camera/microphone/photo selection/photo saving descriptions reviewed; Android merged manifest checked for conflicting services. iOS build not tested on Windows.
- ABI, non-debuggable flag and existing signing certificate verified. SHA-256: 1a17dc848df51cc4fbc12df0e6ec03885755ae1a2d977721c8258ff0b0920f2b.
- No connected physical device: S25 startup/background calls still require phone validation.

## Arka plan araması
- Ayarlara varsayılan kapalı, cihaz bazında uygulama kapalıyken arama alma seçeneği eklendi. FCM tokenı yalnızca açıldığında sahibine özel `callDevices` belgesine kaydedilir.
- Sunucu, gerçek iki kişilik sohbet üyeliğini, arayan kimliğini, 45 saniyelik pencereyi ve alıcının cihaz onayını denetler. Bildirimde kişi adı, sohbet adı veya içerik gönderilmez.
- Korunan yerel FCM alıcısı hesap, cihaz izni, güncel çağrı ve özel çift ayarını yeniden denetler. Görünür, adı gizli arama bildirimi Yanıtla/Reddet seçenekleriyle gelir. Tam ekran veya kilit ekranı atlatma yoktur.
- Yanıtla işlemi tek kullanımlık özel nonce ile doğrulanır. Başka uygulamaların dışarıdan Activity intenti göndererek mikrofon açtırması engellenir. Mikrofon ancak kullanıcı yanıtlayınca veya aramayı başlatınca kullanılır.
- Devam eden görüşme Android mikrofon ön plan servisi, sistem bildirimi ve sınırlı uyanık tutma kilidi ile arka planda sürdürülebilir. Arama kabulünden sonra üç dakika sınırı ve kapatma kontrolü korunur; gelen çağrı bildirimi en geç 45 saniyede sona erer.
- Firebase hazır olmadan çağrı dinleyicisinin başlatılmasına bağlı açılış yarışı giderildi. Açılışta otomatik bildirim izni isteme yerine ilgili ayarın açılması beklenir.
- Gerçek Samsung S25 üzerinde uygulama kapalıyken/alınırken, kilit ekranında ve görüşme sürerken cihaz testi yapılmadı. Zorla durdurma, pil kısıtları, internet ve TURN bulunmaması nedeniyle kesin teslim/bağlantı garantisi verilmez. AirDroid'e karşı kesin görünmezlik veya mikrofon tekeli iddia edilmez.

## Depolama
- 15 Ekim 2026 20:08 Türkiye saati ölçümü: veri ve indeksler dahil 73.981.343 bayt (70,6 MiB), ücretsiz 1 GiB alanın %6,89'u. Ölçüm Cloud Monitoring'den alınmıştır; mesaj veya medya içerikleri taranmadı ve bu kontrolde silinmedi.
- Cloudflare için her ayın ilk günü 09:00 Türkiye saati cron hazırlandı. Yalnızca boyut, örnek zamanı ve yüzde içeren en fazla 12 aylık özet ücretsiz Durable Object'te saklanır.
- Uygulama açıldığında/sunucu durumu görüntülendiğinde günde en fazla bir ek ölçüm yapılır. %80'de ayarlar simgesinde ve depolama kartında uyarı görünür; telefon bildirimleri açıksa günde en fazla bir genel kapasite bildirimi verilir. Hatalı ölçüm sıfır alan olarak raporlanmaz.
- Sunucuya yalnızca `monitoring.timeSeries.list` izni ekleyen özel rol betiği incelemeye hazırdır. Veri yazma/silme, faturalandırma veya ücretli plan yetkisi eklenmez. Mevcut iki günlük sohbet eki erişimi ve uygulama/arka plan fiziksel temizlik politikası sürer.
- Aylık ölçüm tek başına ay içinde alanın dolmasını garantiyle önlemez; günlük uygulama denetimi ve mevcut ek temizliği birlikte kullanılır.

## Doğrulama / bekleyenler
- 82 Flutter testi geçti; analiz temiz. 18 sunucu ve 10 izole Firestore erişim testi geçti. Android ARM64 release APK derlendi ve imzası doğrulandı; Worker paketi dry-run ile doğrulandı.
- Yeni Worker, aylık zamanlama, tek okuma rolü ve çağrı cihazı kuralları henüz canlıya alınmadı. 1.14.16 yayını korunur; ARM64 APK yerel olarak oluşturuldu; canlıya geçiş yayın onayı bekler.

## Publication complete
- User approved publication. ARM64 APK publicly downloaded; SHA-256 and byte count match the local verified artifact. config/app_version is 2061 / 1.14.17 with the ARM64 download URL.
- Worker 71752b93-67b2-4e3a-88b1-f0ccc628512d deployed; health and authorization checks passed. Monthly cron and limited metric-reader role activated; tested owner-only call-device rules deployed.
- Earlier pending-publication notes above describe the preparation stage; all listed release steps are now complete. Physical S25 validation remains unperformed.
