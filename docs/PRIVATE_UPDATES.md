# Özel APK yayınları ve güncellemeler

Uygulamanın kaynak ve APK yayın deposu **enschumacher/Neural-Haber** (private).

## Yayın akışı

1. Kullanıcının sürüm oluşturma/yayımlama onayına göre testleri ve imzalı ARM64 release derlemesini tamamla.
2. `tools/releases/build.ps1` APK ve doğrulanmış build-report.json üretir.
3. `python tools/releases/publish.py --version X.Y.Z --publish` artık varsayılan olarak private yayın yapar. Repo tek yerden, `tools/releases/repository.py` içinden alınır.
4. Yayın aracı APK'yı yeni private repo Releases bölümüne koyar; dosya özetini doğrular ve Firebase `config/private_app_version` kaydını günceller.
5. Telefon aynı Cloudflare adresine Firebase oturumuyla bağlanır. Sunucu updateAccess yetkisini denetleyip private GitHub APK'sını akışla iletir. Notlar ve normal APK indirmeleri oturumsuz verilmez. Telefon APK'nın SHA-256 özetini kurulumdan önce doğrular.

GitHub anahtarı yalnızca Cloudflare secret `GITHUB_RELEASE_TOKEN` alanında saklanır. Bu anahtar enschumacher hesabında yalnızca Neural-Haber deposuna **Contents: Read-only** izni vermelidir. Süresi dolarsa yenilenir; kaynak koda veya sohbete yazılmaz.

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
- Önceki yayınların aktarım sonuçları yerelde artifacts/release-migration/migration-report.json içinde tutulur.

## Yerel erişim ve güvenlik

Yayın araçları private/credentials altında yerel yönetim anahtarı varsa onu, yoksa mevcut yetkili Firebase CLI oturumunu kullanabilir. GitHub, Google veya Cloudflare erişim belirteçleri çıktılara veya kaynak kontrolüne yazılmaz. Eski config ve bot kayıtları private/migrations altında yedeklendi.

Geçiş APK'sı ek olarak UPDATE_BOOTSTRAP_ASSET_ID ile GitHub'daki doğrulanmış ve değişmez dosya kimliğine sabitlenir. Metadata yanlışlıkla başka bir asset kimliği gösterirse açık indirme reddedilir.
