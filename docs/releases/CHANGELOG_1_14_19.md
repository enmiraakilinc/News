# 1.14.19 (2063) — Yayın onayı bekliyor

Kamuya açık kısa not: Görünüm ve kararlılık iyileştirmeleri.

- Genel haber ekranının üst çubuğu ve yan menüsünden genel ayarlar bağlantıları kaldırıldı. Haber bildirim ayarı kısayolu da kaldırıldı; yan menüde yalnızca Kendime Notlar ve Sudoku kalır.
- Genel ayarlar, gizli Kendi alanın sayfasının üst çubuğuna taşındı. Bildirim, arama, izin ve depolama ayarları buradan açılır.
- Gizleme modu kartının zemini, çerçevesi, simgesi ve metinleri yeniden seçili temanın renklerini kullanır. Gerçek Mod butonunun zemini de tema rengine döndü. Yalnızca seçili Gizle butonunun zemini sarıdır; devre dışı/seçili durumda koyu metin rengi korunur.
- Love temasının temel kırmızısı ve ana kırmızı alanı #4C0805 oldu. Koyu tema üzerinde okunabilir açık vurgu ve metin tonları korunur.
- Önceki ahize düzeltmesi korunur. Bu sürüm için sunucu veya Firestore kuralı değişikliği gerekmez.

Yayın öncesinde ARM64 release APK, aynı imza ve yeni sürüm koduyla doğrulanır. Haber menüsünün özel ayarlara giriş göstermediği regresyon testi ve mevcut haber/sohbet testleri çalıştırılır. Fiziksel S25 görünüm testi yapılmadı. Canlı sürüm 1.14.18 olarak korunur.

## Publication complete
- User approved publication. Public ARM64 APK downloaded and verified against the local SHA-256 and byte count. config/app_version is 2063 / 1.14.19; update URL verified publicly. No server code or access rules changed. Earlier pending notes describe preparation only.
