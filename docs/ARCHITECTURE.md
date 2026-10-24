# Proje düzeni

| Yol | Sorumluluk |
|---|---|
| `flutter_application_1/lib/main.dart` | Küçük giriş noktası ve eski WorkManager callback adı |
| `lib/app/` | Uygulama kabuğu, başlatma ve arka plan görevleri |
| `lib/core/` | Tema, izinler, bildirimler, ortak araçlar ve bileşenler |
| `lib/features/` | Sohbet, medya, arama, haber, dersler, hatırlatıcılar ve diğer özellikler |
| `flutter_application_1/test/` | Davranış testleri |
| `free-wakeup-worker/` | Mevcut ücretsiz uyandırma/arama bildirim sunucusu |
| `tools/releases/` | Sürümden bağımsız derleme ve yayın araçları |
| `tools/admin/` | Mevcut Firebase bakım araçları |
| `artifacts/releases/<sürüm>/` | APK ve doğrulama raporları |
| `docs/releases/` | Dahili sürüm notları |
| `private/` | Yerel anahtarlar, kullanıcı yedekleri ve özel dosyalar; Git dışında |
| `archive/` | Eski betikler, kural kopyaları ve refaktör öncesi kaynak yedeği; Git dışında |

64 Dart dosyasının ve arşivlenen çalışma alanı dosyalarının eski → yeni yolları `tools/refactor/*-path-migration.json` dosyalarındadır. Refaktör öncesi `lib` ve `test` kaynakları `archive/refactor/before-feature-folders/` altındadır. Tarihsel betikler eski dosya düzeninin kopyalarıdır; güncel yayın için `tools/releases/` kullanılır.

## Veri sınırları

- Ortak dersler mevcut `couples/<çift>/courses/<ders>/entries/` altında saklanır. Başlık ve içerik mevcut gizli kelime şifrelemesini kullanır. Kodla eklenen sohbet üyeliği bu alana erişim vermez.
- Kişisel dersler uygulamanın özel cihaz dizininde hesap kimliğinin özetiyle ayrılır; sunucuya gönderilmez ve başka cihazlara senkronlanmaz. Metin/kodlar JSON, görseller ayrı dosyalardır.
- Haber medyalı notlarının mevcut anahtarları korunur; hatırlatıcılar için yalnızca kararlı kimlik eklenir. Eski veriler silinmez.
- Yerel hatırlatıcılar cihaz AlarmManager'ı ile çalışır; internet gerekmez. Uyandırma hâlâ mevcut sunucudan gelir. Sistem bildirim, tam ekran ve kesin alarm izinleri ilgili işlemde açıklanır; Android kararları aşılmaz.
- Haber ve kişisel hatırlatıcı bildirimleri haber menüsündedir. Özel alan bildirim ayarları haber tercihlerini değiştirmez.

## Korunan davranışlar

Android paket kimliği, imza, Firebase yolları, eski kişisel hesap girişleri, SharedPreferences anahtarları ve medya saklama süreleri korunur. `main.dart` içindeki `callbackDispatcher` adı/kitaplığı eski WorkManager kayıtları için kalır. Medya hâlâ 48 saatte sona erer. Hazırlanan yeni değişiklikte seçilecek video en fazla 100 MiB olabilir; 20 MiB üstündeyse Android tarafında her biri en fazla 20 MiB olan ayrı videolara bölünür, kullanıcı her parçanın adını seçer. Kişisel ders görselleri sohbet eklerinden farklıdır; kullanıcı silene kadar cihazda kalır.

## Yeni arama ve ders işlemleri

Sohbet araması `lib/features/chat/search/message_search.dart` içindedir. Yalnızca açık mesajları tarar; çift mektuplarını mevcut şifre çözücüsüyle açar. Sonuçlar yerel bellekte filtrelenir, eski mesajlar kullanıcı isteğiyle 100'erli sayfalarda çekilir. Medyanın ikili içeriği aramaya alınmaz, dosya adı kullanılır; arama medyayı otomatik indirmez ve mesajları topluca okundu yapmaz.

Ders araması klasör ve alt klasörlerdeki başlık/not/kodları kapsar. Klasör sabitlemesi `pinned`, not sabitlemesi yerel not JSON'u veya ortak notun şifreli içeriği içinde tutulur. Kişisel ders yedeği JSON biçiminde dışa aktarılır; klasör ağacı, notlar, sabitlemeler ve base64 görseller aynı dosyadadır. Görseller toplamı için 50 MiB bellek sınırı vardır. Yedek şifreli değildir; dışa aktarım ekranı bunu açıklar. Ortak derslere yedek dışa aktarma eklenmedi.

Ön kamera flaşı ekran ışığı kullanır; Android pencere parlaklığı kamera kapanınca geri bırakılır. Kayıtta lens değiştirmek `CameraController.setDescription` ve persistent recording üzerinden yapılır; cihaz desteği başarısızsa kayıt korunmaya çalışılarak anlaşılır uyarı verilir. Fiziksel cihaz doğrulaması ayrıca gereklidir.

## Oracle sunucu geçişi

| Yol | Sorumluluk |
|---|---|
| server/ | PostgreSQL şeması, erişim kuralları, okuma API ve eşitleme |
| tools/server/ | SSH kurulumu, aktarım, doğrulama ve sunucu bakımı |
| docs/SUNUCU_GECISI.md | Gerçek geçiş durumu, kapasite ve kalan işler |

1.15.1, tek seferlik okumalar için PostgreSQL köprüsü içerir. Firebase yazma ve
canlı dinleme uyumluluğu sürer. Kullanıcının hedefi PostgreSQL'i ana veri
kaynağı yapmaktır; yazma geçişi henüz tamamlanmadı. Ayrıntılar
[sunucu rehberinde](../server/README.md).
