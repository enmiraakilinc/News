# 1.14.18 (2062) — Yayın onayı bekliyor

Kısa kamuya açık not: Arayüz ve kararlılık iyileştirmeleri.

- Son düzeltme: arayan ve yanıtlayan tarafın ortak ses hazırlığında Android voice-communication modu seçilir ve hoparlör kapatılarak varsayılan çıkış ahize olur. Gerçek S25 ses çıkışı testi yapılmadı; analiz ve mevcut altı arama/sohbet testi geçti.

- Love rengi #8A101C olarak değiştirildi. Tema özelleştirme menüsü kaldırıldı; kayıtlı özel vurgu/köşe değerleri yerine standart tema kullanılır. Gizleme kartı yumuşak sarı ve koyu, okunur metin kullanır.
- Genel haber alanındaki yan menüye Sudoku, Kendime Notlar ve haber bildirimleri eklendi. Sudoku tek çözümlü bulmaca üretir, çakışmaları gösterir ve ilerlemeyi cihazda saklar.
- Haber sayfalarındaki eski görsel/sesli notlar birleştirilir, tekrarlar ayıklanır ve mevcut dosyalar korunur. Yeni konum notları yalnız cihazda saklanır; çevrimdışı haritada görüntülenir. Konum dış harita servisine gönderilmez.
- Bölüm bildirimleri açılır menüden ayrı seçilir; kapatmak uygulama içi rozeti değiştirmez. Haber bildirimleri yeni paketle gelen haberleri uygulama fark ettiğinde çalışır. İçerik bildirimlerinin mevcut uygulama/arka plan denetim sıklığı değişmedi; anlık teslim iddiası yoktur.
- Kamera, mikrofon, konum ve aramalar için yerel kullanım anahtarları eklendi. Kapalıyken sensör işlemleri başlamaz; arka plan arama alıcısı da arama/mikrofon anahtarlarını kontrol eder. Bunlar Android izinlerini gizlemez veya sistem iznini iptal etmez; gerçek sistem durumu ayrıca gösterilir ve telefon ayarları açılabilir.
- Arama dahil ana uygulama penceresinin mevcut FLAG_SECURE koruması korunur. Yeni, dışa kapalı alarm Activity'sinde ayrıca FLAG_SECURE vardır.
- Uyandırma anında veya önümüzdeki 24 saat için zamanlanabilir. Gönderici/alıcı çifti başına tek Durable Object planı saklanır; yeni plan eskisini değiştirir, iptal edilebilir. Plan şifre, giriş tokenı veya konum saklamaz. Çalma anında gerçek sohbet üyeliği ve alıcı izni yeniden denetlenir. 90 saniyeden fazla geciken plan gönderilmez. FCM/internet/pil nedeniyle kesin teslim garantisi yoktur.
- Tam ekran alarm cihazda isteğe bağlıdır. Android 14+ özel erişim denetlenir ve kullanıcı isterse sistem ekranı açılır. İzin yoksa veya Android tam ekranı göstermiyorsa bildirime dokunmak alarm ekranını açar; üst bildirimde doğrudan kapatma eylemi yerine alarm ekranı kullanılır. Alarm en fazla 20 saniye çalar.
- Mevcut kişisel hesap UID'si, uzun kodu, şifresi ve sohbet üyeliği değişmez. Hesap ekranı 12 haneli kalıcı kısa kodu, yalnız sahibine açık/değiştirilemez iki belgeyle atomik oluşturur. Eski uzun kod yedek olarak görüntülenebilir ve girişte geçerlidir.
- Kısa kod çözümlemesi yeni sunucu ucunda kimlik denetimi ve IP/hesap/kod başına 10 dakikalık deneme sınırıyla yapılır. Eşleme belgeleri başka istemcilere okunamaz/listelenemez. Şifre Worker'a gönderilmez, Firebase Auth'ta doğrulanır; kısa kod tek başına erişim sağlamaz. Yeni kurallar/sunucu yayımlanana kadar eski kod kullanılır.

## Doğrulama

- 87 Flutter testi, temiz statik analiz, 26 sunucu testi, 11 izole Firestore kural testi başarılı. Yerel Android Kotlin/Java release derlemesi ve Worker dry-run başarılı.
- İmzalı, yalnız ARM64 release APK oluşturuldu; 2062 sürüm kodu, aynı imza sertifikası ve debug olmaması doğrulandı. Kesin boyut ve SHA-256: ../release-1.14.18-build-report.json.
- Bağlı fiziksel cihaz yok. S25 üzerinde tam ekran alarm, kilit ekranı ve uçtan uca kısa kod girişi henüz denenmedi.
- Canlı APK/güncelleme kaydı, Worker ve Firestore kuralları hâlâ 1.14.17. 1.14.18 APK yayını, Worker ve firestore-1.14.18.pending.rules dağıtımı kullanıcı yayın onayını bekler. Ek IAM veya ücretli plan değişikliği gerekmez.

## Publication complete
- User approved publication. Final ARM64 APK including earpiece routing is public. Downloaded bytes and SHA-256 match the verified artifact; config/app_version is 2062 / 1.14.18.
- Owner-only alias rules and Worker ac745d1b-89ba-4988-9c01-6acd9b549607 deployed; live health and unauthenticated endpoint denial checks passed. Earlier pending notes describe preparation only. Physical S25 audio/full-screen verification remains unperformed.
