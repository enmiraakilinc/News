# 1.14.10 (2054)

Yayın notu: “Görünüm ve kararlılık iyileştirmeleri.”

- Sohbette fotoğraf/video çekimi ayrı Android kamera uygulamasını açmak yerine resmi Flutter camera / CameraX eklentisini kullanır. Samsung S25'te bildirilen harici kamera çakışması yolu kaldırıldı; gerçek cihazdaki hata nedeni günlükler olmadan kesinleştirilmedi.
- Kamera açma/kapatma işlemleri sıraya alınır. Lens değişiminden önce önceki oturum kapatılır; arka plana geçişte ve ekrandan çıkışta kaynaklar bırakılır. Video kaydı arka planda sürdürülmez. Kamera/mikrofon izinleri ayrı ele alınır; fotoğrafta mikrofon açılmaz. Donanım hatası sonrası oturum bırakılır ve tekrar deneme sunulur.
- Kamera/galeri menüsü açıldığında yazma odağı kaldırılır. Seçim veya iptal sonrası klavye kendiliğinden açılmaz; gönderim sırasında klavyeyi açık tutma davranışı korunur.
- Galeriden fotoğraf ve video seçenekleri eklendi. Gönderim öncesi onay, 20 MiB sınırı ve iki günlük sohbet eki süresi korunur.
- Analyzer sorunsuz; 52 Flutter testi geçti. Kamera yaşam döngüsü, hızlı arka plan/dönüş, lens değişiminde en fazla bir oturum, donanım hatası/izin reddi sonrası tekrar deneme, video sonucu ve dört medya seçeneğinde klavye/taslak koruma test edildi. Android CameraX Java/Kotlin derlemesi başarılı.
- Bağlı telefon/emülatör bulunmadığından fiziksel Samsung S25 doğrulaması yapılmadı. Release APK oluşturuldu (yaklaşık 69,4 MB), sürüm kodu ve önceki sürümle aynı imza doğrulandı. GitHub yayın kanalına kısa notla yüklendi. İndirilen dosyanın SHA-256 özeti ve boyutu yerel APK ile eşleşti; uygulama içi güncelleme kaydı 2054 olarak yayınlandı ve okunabilirliği doğrulandı.
- Depolama için resmi `firestore.googleapis.com/storage/data_and_index_storage_bytes` metriğine erişim 403 döndü. Uyarı oluşturulmadı; ücretli plana geçilmedi veya veriler silinmedi. Önerilen eşikler 1 GiB sınırının %80 ve %90'ı.

Kaynaklar: [Flutter kamera yaşam döngüsü](https://pub.dev/packages/camera), [Firestore ücretsiz kota](https://firebase.google.com/docs/firestore/quotas), [Firestore veri ve indeks metriği](https://docs.cloud.google.com/monitoring/api/metrics_gcp_d_h#firestore).
