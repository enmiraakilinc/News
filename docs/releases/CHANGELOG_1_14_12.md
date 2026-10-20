# 1.14.12 hazırlığı (2056)

Kısa yayın notu: Görünüm ve kararlılık iyileştirmeleri.

- Sohbet videoları dış oynatıcı yerine uygulama içinde açılır; oynat/duraklat ve zaman çizgisinden gezinme vardır. Arka plana geçince durur, sayfa kapanınca oynatıcı serbest bırakılır ve geçici video dosyası silinir.
- Fotoğraflar uygulama içinde yakınlaştırılabilir. Eski gömülü ekler ve dosya olarak gönderilen yaygın fotoğraf/video uzantıları da iç görüntüleyiciye yönlenir.
- Android penceresindeki kalıcı FLAG_SECURE korunur; medya görüntüleyici de korumayı etkinleştirir ve kapatmaz. Dış oynatıcıya geçiş kaldırıldığı için uygulama penceresindeki koruma medya izlerken de sürer. Gerçek Samsung S25 üzerinde ekran görüntüsü/ekran kaydı henüz denenmedi (bağlı ADB cihazı yok).
- 20 MiB üzerindeki videolar cihazda Media3 Transformer ile zaman aralıklarına ayrılıp bağımsız MP4 dosyaları olarak sırayla gönderilir. Her çıktı 20 MiB altında doğrulanır; büyük kalan aralık tekrar bölünür. Kaynak video değiştirilmez. Hazırlık/gönderim durumu ve kısmi gönderim hatası gösterilir. Gerçek video kodekleriyle cihaz üstünde bölme henüz denenmedi; Kotlin/Java derlemesi geçti.
- Genel dosya sınırı 80 MiB; fotoğraf ve video parçası sınırı 20 MiB. Sunucu kurallarında yalnızca boyut/parça sayısı/kanonik parça kimliğinin hane sınırı artırıldı. Üyelik, özel alan yalıtımı ve 48 saatlik erişim korunuyor. En fazla 183 veri parçası tek silme grubuna sığar.
- 48 saat sonra erişim kapanır; fiziksel temizlik mevcut uygulama/arka plan görevi çalışınca yapılır. Ücretsiz plan kullanılır; kesin zamanlı sunucu silmesi veya kota alarmı eklenmedi. Büyük ekler fiziksel olarak silinene kadar kota tüketir.
- Günün soruları listesinin sonuna 60 yeni soru eklendi; önceki soruların sırası korundu.
- 59 Flutter testi geçti. Gerçek Firebase testlerinde 80 MiB sınırı, 20 MiB video sınırı, 182 numaralı parça, üye olmayanların reddi ve süre sonu erişim reddi doğrulandı; geçici test hesapları/kayıtları temizlendi.
- Kullanıcının yayın onayıyla 1.14.12 / 2056 APK oluşturuldu. Sürüm ve önceki uygulamayla aynı imza doğrulandı. GitHub yayını tamamlandı; indirilen dosyanın SHA-256 ve boyutu yerel APK ile eşleşti. Uygulama içi güncelleme kaydı 1.14.12 olarak etkinleştirildi ve oturum açmadan okunabildiği doğrulandı.
