# Oracle VPS ve PostgreSQL geçişi

Sunucudaki veri kopyası, canlı eşitleme ve okuma API'si hazırdır.
**Bu aşama Firebase'in tamamen kaldırılması değildir.** Eski APK'larla sohbetlerin
iki ayrı veri kaynağına bölünmesini önlemek için yazmalar ve canlı dinleyiciler
geçiş süresince mevcut Firebase bağlantısını kullanır.

## 24 Ekim 2026 durumu

- HTTPS: https://138.2.185.151. IP için güvenilir sertifika ve otomatik yenileme
  kuruldu; yenileme denemesi başarıyla doğrulandı.
- HTTP 80 yalnızca sertifika doğrulama ve HTTPS yönlendirmesidir.
- PostgreSQL 18 yerel bağlantılara açıktır. Node.js 22 API'si
  127.0.0.1:8080 üzerinde çalışır; 8080 ve 5432 internete açılmaz.
- 14:16:37 UTC anındaki 6.626 Firestore belgesi aktarıldı; her belge kaynakla
  ayrı ayrı karşılaştırılarak doğrulandı. Mevcut şifreli içerikler çözülmedi.
- Ardından ayrı ve yalnızca okuma yetkili hesapla 34 veri grubu için canlı
  eşitleme açıldı. Eski telefonların ekleme/değiştirme/silmeleri de yansıtılır.
- Mevcut Firebase yönetim anahtarı VPS'e gönderilmedi. Kullanıcının açık
  onayıyla ayrı neural-pg-reader hesabı oluşturuldu; yalnızca
  roles/datastore.viewer rolü verildi. Etkin okuma izinleri doğrulandı;
  oluşturma, değiştirme ve silme izinleri yoktur.
- Flutter okuma köprüsü kaynak kodda hazırdır. APK oluşturulmadı/yayınlanmadı;
  mevcut telefonların ayarları değiştirilmedi.

## Dosyalar

| Dosya | Görevi |
|---|---|
| sql/001_documents.sql | Firestore tipli belgeleri tutan tablolar, indeksler ve aktarım kayıtları |
| sql/002_read_access.sql | Ayrı API/eşitleme rolleri, kullanıcı ve üyelik temelli satır güvenliği |
| src/main.mjs | Okuma, sayım ve SSE canlı izleme API'si |
| src/auth.mjs | Firebase ID token doğrulaması; yönetim anahtarı gerektirmez |
| src/access.mjs | Belge yolu ve koleksiyon listeleme sınırları |
| src/query.mjs | Parametreli SQL; zaman, sayısal filtre, sıralama ve sayfalama |
| src/firestore_codec.mjs | Tarih hassasiyeti, 64 bit tam sayı ve ikili içerik dönüşümü |
| src/mirror.mjs | Kaynağa yazmadan PostgreSQL kopyasını güncel tutan servis |
| deploy/nginx.conf | IP sertifikası, HTTPS ve yerel API yönlendirmesi |
| deploy/backup.py | Günlük PostgreSQL yedeği; son yedi yedeği korur |
| test/access.test.mjs | Sorgu, yetki ve tür davranış testleri |
| test/rls.sql | Gerçek rollerle erişim ve eşitleme yazma kontrolleri; testler geri alınır |

## Uygulamadaki aşamalı okuma köprüsü

flutter_application_1/lib/core/data altında:

- oracle_client.dart: HTTPS ve oturum başlığı. Token URL'ye veya kalıcı dosyaya
  yazılmaz. Kesintide 30 saniye tekrar bekletmeden mevcut SDK'ya dönülür.
- oracle_codec.dart: Firestore'un tarih, ikili veri, 64 bit sayı, harita ve
  liste türleri; şifreli medya baytları değiştirilmez.
- oracle_firestore_bridge.dart: tek seferlik belge/geçmiş/medya okumaları ve
  sayımlarda PostgreSQL tercih edilir. Eksik yeni kayıt, desteklenmeyen sorgu
  veya bağlantı kesintisinde mevcut SDK kullanılır. Yeni yerel yazmalardan
  hemen sonra kaynak SDK tercih edilerek eşitleme gecikmesi korunur.

Canlı sohbet dinleyicileri, bekleyen mesajlar, çevrimdışı yazma kuyruğu,
işlemler, Firebase Auth, FCM ve Android arama/uyandırma alıcıları bu aşamada
mevcut SDK ile çalışır. Bu bilinçli bir uyumluluk aşamasıdır.

Yeni davranış NEURAL_POSTGRES_READS=true derleme seçeneğiyle açılır.
tools/releases/build.ps1 bunu yeni sürüm için ekler; -FirebaseReads seçeneği
geri dönüş derlemesi hazırlar. Normal debug çalıştırmada bu seçenek verilmezse
eski okuma davranışı sürer. Başlatma CoupleService._prepare içinden yapılır.

## API

POST /v1/read ve POST /v1/watch JSON gövde alır.
Oturum Authorization: Bearer başlığındadır; kullanıcı kimliği JSON gövdesinden
alınmaz. Belge örneği:

    {"kind":"document","path":"chats/<sohbet>"}

Sayım örneği:

    {"kind":"count","query":{"path":"couples/<çift>/letters"}}

Sorgular path, filters, orders, limit ve sayfa imleçleri alır. Alan adları
parça listeleri, değerler Firestore REST tipli nesnelerdir. Yanıtta bu tipler
korunur. SSE yalnızca yetkilendirilmiş sonuçları gönderir; diğer hesapların
belge yolları olay akışına yazılmaz.

Davet/kısa giriş kodları ve profil koleksiyonları toplu listelenemez.
API veritabanı rolünün INSERT, UPDATE ve DELETE izni yoktur.
Kodla eklenen sohbet üyeliği ortak çift alanına erişim sağlamaz.
Eşitlemenin ilk hazırlığı bitmediyse veya servis yaşam işareti 45 saniyeden
eskiyse /health ve okuma uçları 503 döndürür; uygulama mevcut SDK'ya döner.

## Servisler ve yedekler

- neural-api.service: kimlik doğrulamalı okuma API'si; ayrı Linux/DB hesabı.
- neural-sync.service: yalnızca okuma anahtarıyla canlı kopya; ayrı Linux/DB hesabı.
- neural-backup.timer: her gün 02:30 UTC civarı yerel yedek; ilk yedek alındı.
- neural-cert-renew.timer: IP sertifikası için günde iki yenileme kontrolü.

Kaynak PostgreSQL 13 kümesi ve geçiş öncesi SQL yedeği korunur.
PostgreSQL yedekleri aynı sunucudadır; dosya izinleriyle korunur. Mevcut şifreli
içerikler şifreli kalır; yedek dosyasının tamamı ayrıca şifrelenmiş değildir.
Sunucu diski kaybolursa bu yerel yedek de kaybolabilir.
Disk %80 dolunca yedek hata kaydı verir. Telefona depolama uyarısı gönderen
bir bildirim entegrasyonu henüz eklenmedi.

## Yönetim araçları

Repo kökündeki tools/server içinde:

| Araç | Görevi |
|---|---|
| ssh_admin.py | Anahtar içeriğini yazdırmadan SSH üzerinden incelenmiş bakım betiği |
| snapshot_firestore.py | Kısa ömürlü tokenla kaynağın değişmeyen anlık görüntüsünü başlatma |
| firestore_snapshot_remote.py | Sunucuda zaman sabitlenmiş, sıkıştırılmış Firestore dışa aktarımı |
| import_firestore.py | Seçilmiş anlık görüntüyü ve özetini içe aktarım aracına verme |
| import_snapshot_remote.py | İzole DB'ye aktarım ve her belgenin özetiyle doğrulama |
| create_reader_identity.py | Açıkça onaylanmış ayrı okuma hesabı; izinleri doğrular, anahtarı yazdırmaz |
| deploy_bridge.py | Kaynakları paketleme; yalnızca onaylı ayrı okuma kimliğini kabul eder |
| deploy_remote.py | SQL, Linux hesapları, nginx ve systemd servislerinin kurulumu |
| check_server.py | Geri alınan rol testleri ve günlük yerel yedek kurulumu |
| test_compiled_queries.py | Gerçek SQL üzerinde tarih/sayı/sıralama/sayfalama kontrolleri |
| verify_live_bridge.py | Geçici hesaplarla HTTPS, JWT, eşitleme, SSE ve izolasyon testi |

deploy_bridge.py --api-only anahtar aktarmadan API'yi günceller ve mevcut
eşitlemeyi durdurmaz. --read-only-credential yalnızca onaylı ayrı okuma hesabı
içindir. Anahtarlar, veri kopyaları ve özel raporlar private altında tutulur;
Git'e gönderilmez. Gerçek kişilere test mesajı/arama/alarm gönderilmez.

## Son geçiş

Önce test edilen okuma köprüsünü içeren APK için kullanıcı onayı alınır.
Telefonların yeni sürüme geçmesi izlenmeden Firebase yazma ve canlı dinleme
bağlantıları kesilmez. Sonrasında bağımsız PostgreSQL yazma işlemleri,
işlem/çevrimdışı davranış ve Android/Worker servisleri birlikte geçirilip
doğrulanır. Son aktarım ve geri dönüş planı olmadan Firestore verileri silinmez.
# 1.16.0 birincil sunucu hazırlığı

API artık okuma yanında yetkilendirilmiş yazma, canlı fark güncellemeleri,
işlem tekrarı koruması, kişisel alan, zamanlı uyandırma ve özel APK indirmesi
içerir. `primary_writes=false` iken eski eşitleme davranışı sürer; yeni yazmalar
kapalıdır. Aşağıdaki eski okuma köprüsü açıklamaları bu uyumluluk modu içindir.
Canlı geçiş planı: `docs/releases/1.16.0_MIGRATION_REVIEW.md`.

- `sql/003_primary_writes.sql`: ayrı yazıcı rolü, işlem makbuzları ve eşitlemenin
  yeni sunucu kayıtlarını ezmesini engelleyen koruma.
- `sql/004_retention.sql`: birincil modda süreli eklerin temizlenmesi.
- `sql/005_services.sql`: sınırlı servis rolü, deneme sayacı ve zamanlı işler.
- `src/commit.mjs`, `write_policy.mjs`, `write_codec.mjs`: atomik işlemler,
  erişim kuralları ve şifreli/binary değerlerin kayıpsız taşınması.
- `src/service_store.mjs`, `services.mjs`: hesap kodu, arama ve uyandırmanın
  PostgreSQL üzerinden kontrolü. Başka kullanıcının gizli verisi döndürülmez.
- `src/push_transport.mjs`: mevcut Worker'a imzalı FCM taşıma isteği; Google
  yönetim anahtarı VPS'e aktarılmaz.
- `src/legacy_wake.mjs`: eski sürümde zamanlanmış isteklerin geçişten sonra da
  güncel üyelik ve izinlerle yeniden kontrol edilmesi.
- `src/updates.mjs`: hesap erişimi doğrulanarak özel yerel APK dosyasını sunar.
