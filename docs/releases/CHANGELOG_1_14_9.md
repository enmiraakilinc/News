# 1.14.9 (2053)

Uygulamada gösterilecek kısa not: “Görünüm ve kararlılık iyileştirmeleri.”

- Güncelleme penceresi, kartı, başlıkları ve notları aynı ColorScheme üzerinden zemin/yazı renklerini kullanır. Sabit açık renkli kart ile koyu tema yazı renginin karışması giderildi.
- Yayındaki 1.14.8 uygulama içi notu ve GitHub açıklaması ayrıntı içermeyen kısa metinle değiştirildi; mevcut sürüm kodu ve APK korunur.
- Analyzer sorunsuz. Açık ve koyu temada başlık/not renkleri için en az 4,5:1 kontrastı doğrulayan iki widget testi geçti.
- Mesaj bildirimleri mevcut sürümde saatlik WorkManager kontrolüne bağlıdır. Mesajlara özgü FCM gönderen güvenilir sunucu yoktur. Ücretsiz paket tercihi korunmuş, anlık arka plan bildirimi eklenmemiştir. Firebase Cloud Functions yayını Blaze gerektirir; FCM alternatif olarak kullanıcının sağlayacağı sürekli çalışan güvenilir sunucudan gönderilebilir.
- Release APK oluşturuldu; sürüm kodu 2053 ve önceki sürümle aynı yayın imzası doğrulandı. GitHub kanalına kısa notla yayınlandı; herkese açık APK'nın boyutu ve SHA-256 özeti yerel dosyayla eşleşti. Uygulama içi güncelleme kaydı 1.14.9 olarak yayınlandı ve okunabildiği doğrulandı.

Kaynaklar: [FCM mimarisi](https://firebase.google.com/docs/cloud-messaging), [Cloud Functions dağıtım gereksinimleri](https://firebase.google.com/docs/functions/get-started).
