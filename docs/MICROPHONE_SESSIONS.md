# Mikrofon oturumları — sonraki sürüm için hazır

Bu değişiklik henüz APK olarak yayımlanmadı. Canlı sürüm 1.14.33.

## Kullanım

Gizli bölümde Mikrofon oturumu kartı bulunur. Başlatmadan önce uygulama, Android'in yalnızca Mikrofon oturumları bildirim kanalına yönlendirir. Bu kanalı kullanıcı kapatır; uygulama ayarı kendisi değiştirmez. Diğer bildirim kanalları etkilenmez. Android 13+ kanal/uygulama bildirim izni kapalıysa servis bildirimi çekmecede görünmez. Mikrofonun yeşil göstergesi ve sistemin çalışan uygulamalar kaydı görünür kalır.

Sesli mesajlarda da aynı kanal kullanılır. Kayıt uygulama açıkken başlatılır; ekran kilitlenince devam eder. Durdurunca ön dinleme taslağına döner, kendiliğinden göndermez. Android 13'ten eski telefonlarda mevcut ses kaydı desteği korunur; bu eski sistemlerde servis bildirimi gösterilir.

## Sınırlar

- Meşgul tutma oturumu yerel AudioRecord girdisini küçük bellekte tüketip siler. Dosya veya ağ aktarımı oluşturmaz.
- Android 11+ privacySensitive ayarı kullanılır; AirDroid veya her uygulamayı kesin engelleme iddiası yoktur.
- Kullanıcı başlatır ve uygulamadaki Durdur düğmesinden bitirir. Bildirim kanalı açık tutulursa Android servis bildirimi de durdurma eylemi içerir.
- Ekranın kapanması veya ilgili sayfadan çıkılması meşgul tutma oturumunu bitirmez. Görev listesinden uygulama kaldırılırsa servis durur; yeniden başlatma/telefon açılışında otomatik başlatma yoktur.
- Açık meşgul tutma oturumu varken sesli mesaj kaydına geçmeden önce oturum durdurulur. Mikrofon kullanımı ayarlardan kapatılırsa açık oturuma durdurma isteği iletilir.
- Sesli mesaj ekranından tamamen çıkılması mevcut taslak/iptal davranışını korur; uygulamanın zorla durdurulmasından sonra kayıt sürmez.
- Samsung S25 üzerinde fiziksel ekran kilidi, kanal görünürlüğü, pil kısıtlaması ve AirDroid karşılaştırması henüz yapılmadı.

## Dosyalar

- android/app/src/main/kotlin/com/melek/stargaleri/MicrophoneSessionService.kt: bildirim kanalı, Android servis yaşam döngüsü, güç kilidi ve dosyasız mikrofon girdisi.
- lib/core/security/microphone_session.dart: Flutter platform köprüsü ve kullanıcı kanal ayarı yönlendirmesi.
- lib/features/voice_notes/microphone_session_screen.dart: başlatma/durdurma ve durum ekranı.
- lib/features/voice_notes/voice_notes_screen.dart: mevcut sesli kayıtla servis bağlantısı.
- test/microphone_session_test.dart ve test/voice_notes_test.dart: kullanıcı ayarı, ekran kilidi, sayfadan çıkış ve durdurma testleri.

Uygulama yolları flutter_application_1/ altındadır. Kontroller: ilgili 16 Flutter testi başarılı; Dart analizi temiz; Android release Kotlin derlemesi başarılı. Fiziksel telefon testi yerine geçmez.
