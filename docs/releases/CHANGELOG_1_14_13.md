# 1.14.13 hazırlığı (2057)

Kısa yayın notu: Görünüm ve kararlılık iyileştirmeleri.

- Sohbet videoları için süre yükleme anından itibaren 72 saat; diğer dosya ve fotoğraflar 48 saat olarak korunur. Süre kontrolü, zamanlama sınırı, otomatik temizleme ve kullanıcıya gösterilen metinler güncellendi. Fiziksel temizlik uygulama veya arka plan görevi çalışınca yapılır.
- Sunucu kuralları 72 saatlik video erişimini etkinleştirdi. Eski uygulamaların 48-72 saat arasındaki videoları otomatik silmesi engellenir; yeni istemcide kullanıcının açıkça mesaj silmesi için sunucu zamanlı silme isteği kullanılır. Üyelik, özel alan yalıtımı, şifreleme ve dosya boyutları korunur.
- Kullanıcının istediği 13 Ekim 2026 00:32 (Türkiye saati) videosunun sohbet mesajı bulundu. İlişkili chatMedia belgesi 404 ve kalan veri parçası yok; sunucudan tekrar erişime açılamadı. Diğer gerçek videolar değiştirilmedi veya silinmedi.
- Sesli not kaydı duraklatılıp devam ettirilebilir, baştan çekilebilir. Bitirme düğmesi doğrudan paylaşmaz; önce ön dinleme, zaman çizgisinden ileri/geri sarma ve açık kaydetme/gönderme onayı sunulur. Başarısız yüklemede taslak ekran açıkken korunur; vazgeçme ve yeniden çekme taslağı temizler. Ekrandan çıkarken kaynaklar kapatılır.
- Kayıtlı yerel ve ortak sesli notlarda duraklatıp aynı yerden devam etme ve zaman çizgisinden gezinme eklendi.
- Gerçek sunucu testleri: 60 saatlik video okunur; eski otomatik silme reddedilir; açık kullanıcı silmesi kabul edilir; 73 saatlik video erişimi reddedilir ve üye temizliği çalışır. Geçici hesap ve kayıtlar temizlendi.
- Kullanıcının onayıyla 1.14.13 / 2057 APK oluşturuldu ve yayınlandı. Sürüm, önceki uygulamayla aynı imza, yayındaki APK boyutu ve SHA-256 doğrulandı. Uygulama içi güncelleme kaydı etkinleştirildi ve oturum açmadan okunabildiği doğrulandı. Telefon üzerinde kayıt ve sarma ayrıca doğrulanmadı.
- Son doğrulama: Flutter analizinde sorun yok; tüm 62 test geçti. Ön dinleme/sarma ve açık onay öncesi kaydetmeme, kayıt duraklatma/devam etme, yeniden çekme/iptal ve 48-72 saatlik video sınırları test edildi.
