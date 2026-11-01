# APK yayınları ve uygulama içi güncellemeler

Uygulamanın kaynak deposu **enmiraakilinc/News** (public). GitHub Releases
dosyaları herkese açık olduğundan APK doğrudan da indirilebilir.

## Yayın akışı

1. Kullanıcı onayıyla testleri çalıştır; imzalı ARM64 release derlemesini
   `--dart-define=NEURAL_POSTGRES_PRIMARY=true` ile üret.
2. Doğrulanmış APK'yı ve build report'u `artifacts/releases/X.Y.Z/` altına koy.
3. GitHub Releases'e yükle; Oracle'a `tools/releases/stage_vps.py` ile APK'yı
   aktar ve SHA-256 özetini doğrula.
4. `tools/releases/publish_primary.py --version X.Y.Z` hedef repository ID'sini,
   kaynak dalını, release asset'ini ve VPS kopyasını doğrular. Ardından yalnızca
   `/updates/latest` ve `/updates/apk` üzerinden kullanılan sürüm kaydını
   PostgreSQL-primary metadata'sında yayımlar ve üye erişim kayıtlarını korur.
5. Uygulama güncelleme uç noktası oturum ve `updateAccess` yetkisini denetler;
   APK'nın SHA-256 özeti kurulmadan önce doğrulanır. GitHub deposu public
   olduğundan doğrudan release indirmesi bu uygulama içi yetki denetiminden
   bağımsızdır.

Yeni istemciler, özel güncelleme kaynağı erişilemezse `enmiraakilinc/News`
üzerindeki herkese açık son sürümü yedek olarak kontrol eder. Bu sürümün
release açıklamasında `Build code: N` satırı bulunmalı; ARM64 dosyası
`Neural-Haber-X.Y.Z-arm64.apk` olarak eklenmeli ve GitHub'ın asset SHA-256
özeti kullanılmalıdır. Bu biçim sağlanmazsa istemci yayımlamayı güncelleme
olarak sunmaz.

Yayın aracı GitHub CLI oturumunu yalnızca release asset'ini doğrulamak için
kullanır; token CDN'ye veya VPS'ye gönderilmez. Google ve SSH erişim bilgileri
yerel kalır; kaynak koda veya sohbete eklenmez.

## Eski telefonlar için tek sürümlük geçiş

1.14.32'den önceki istemciler oturum belirteci ekleyerek APK indiremez. Kullanıcının daha önce açık dağıtımına izin verdiği, özeti sabit **1.14.32** dosyası bu yüzden ayrı geçiş yolundan sunulur:

`/updates/transition/1.14.32.apk`

Firebase'in herkese açık `config/app_version` kaydı bu geçiş adresini gösterir. Dosyanın kendisi yeni private depodadır. Sunucu hem sürümünü hem bilinen dosya özetini kontrol eder; başka veya sonraki bir sürüm bu açık yoldan sunulamaz. Yeni sürümler özel güncelleme yolundan gelir. Tüm cihazlar geçince geçiş `UPDATE_BOOTSTRAP_ENABLED` ile kapatılabilir; kendiliğinden kapatılmaz.

## 20 Ekim 2026 geçiş doğrulaması

- Cloudflare GITHUB_RELEASE_REPO yeni depoya alındı.
- Firebase özel sürüm kaydındaki repository/assetId yeni depoya taşındı; eski istemci URL'si doğrulanmış geçiş yoluna alındı.
- Telegram botunun D1 içindeki uygulama projesi yeni kaynak depoya yönlendirildi.
- Yetkisiz metadata/APK erişimi, kendine yetki verme ve doğrudan özel Firebase metadata okuması canlıda reddedildi.
- Yeni repodan hem yetkili APK indirmesi hem açık geçiş dosyası SHA-256/boyut kontrolüyle doğrulandı.
- Supabase istemcisi, yapılandırması veya uygulamayla bağlı Supabase repo kaydı bulunmadı; kullanılmayan bir servis eklenmedi.
- Firebase projesi ve kullanıcı verileri değiştirilmedi; bu çalışma repo/yayın bağlantılarını taşır.
- 11 eski uygulama sürümü yeni private deponun Releases bölümüne, dosya boyutu ve SHA-256 özeti korunarak kopyalandı. En güncel sürüm v1.14.32 olarak kaldı. Aktarım sonuçları artifacts/release-migration/migration-report.json içinde tutulur.
- 34 sunucu testi geçti; Android imza dosyaları şifreli yedekten geri yüklendi ve Git dışında tutuldu.

## Yerel erişim ve güvenlik

Yayın araçları private/credentials altında yerel yönetim anahtarı varsa onu, yoksa mevcut yetkili Firebase CLI oturumunu kullanabilir. GitHub, Google veya Cloudflare erişim belirteçleri çıktılara veya kaynak kontrolüne yazılmaz. Eski config ve bot kayıtları private/migrations altında yedeklendi.

Geçiş APK'sı ek olarak UPDATE_BOOTSTRAP_ASSET_ID ile GitHub'daki doğrulanmış ve değişmez dosya kimliğine sabitlenir. Metadata yanlışlıkla başka bir asset kimliği gösterirse açık indirme reddedilir.
