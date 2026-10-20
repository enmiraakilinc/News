# 1.14.15 (2059)

Kullanıcıya açık kısa not: Görünüm ve kararlılık iyileştirmeleri.

## Uygulama
- Fotoğraflar ve bölünmüş videolar gönderilmeden önce ayrı ayrı adlandırılabilir.
- Yeni fotoğraflar küçük önizlemeyle gösterilir; açıldığında asıl dosya kullanılır.
- Kamera ve medya görüntüleyicisi ekran yakalama korumasını kullanır.
- Kişiye özel fotoğraf/emoji kişi ayrıntılarından düzenlenir; yıldızlı mesajlara buradan erişilir.
- Sohbette ses kaydı, duraklatma, tekrar kayıt, göndermeden dinleme ve oynatırken ileri/geri sarma bulunur.
- Hatalar kullanıcıya anlaşılır metinlerle sunulur.
- Kişi ve cihaz bazında izinli uyandırma, alıcının ses düzeyi ve kapatma denetimleri hazırdır.

## Yayın doğrulamaları
- Kullanıcının açık onayıyla canlı Firestore erişim kuralları uygulandı; mevcut sohbet üyelik sınırları korundu.
- Ayrı sunucu hesabına yalnızca Firestore okuma ve FCM gönderme yetkisi verildi; yeni anahtar Cloudflare sırrı olarak saklandı. Mevcut yönetim anahtarı aktarılmadı.
- Ücretsiz Cloudflare Worker hazır olma denetimi geçti; yetkisiz istekler reddedildi. Uyandırma yapılandırması etkinleştirildi. Gerçek kullanıcıya deneme alarmı gönderilmedi.
- APK 1.14.15 / 2059 oluşturuldu; önceki sürümle aynı imza doğrulandı.
- GitHub sürümü yayımlandı; kamuya açık APK dosyasının SHA-256 ve boyutu yerel dosyayla eşleşti. Uygulama içi güncelleme kaydı 1.14.15 / 2059 olarak etkinleştirildi ve girişsiz okunabilirliği doğrulandı.
- Android yerel derlemesi, Worker 7 testi ve izole Firestore emülatöründe 6 erişim testi geçti.
- Flutter analizi temiz; 72 uygulama testi geçti.
- Gerçek Samsung S25 üzerinde kamera, bildirim ve uygulama kapalıyken uyandırma ayrıca doğrulanmalıdır.
- Uyandırma görünür sistem bildirimi gerektirir; zorla durdurma, ağ, pil ve rahatsız etmeyin koşullarında kesin teslim garantisi verilmez.
- Sesli/görüntülü arama ve bildirim çubuğu olmadan standart Android simge rozeti bu sürümde eklenmedi.
