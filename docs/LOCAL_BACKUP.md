# Yerel dosyaların şifreli yedeği — 20 Ekim 2026

Private deponun Releases bölümündeki `backup-2026-10-20` sürümünde 12 şifreli parça (`local-backup-20261020.zip.enc.part001`–`part012`) ve `local-backup-20261020.parts.json` manifesti bulunur. Tüm parçalar aynı klasöre indirilmelidir.

269 dosya; özgün toplam 425.323.417 bayt; şifreli arşiv 246.931.629 bayt.

Şifreli dosyanın SHA-256 özeti:
`dde75f21342d6b7f6c50c8739e07a02fee9d1d5312d0104353f637a6c77de6c6`

Kapsam: private/ içindeki erişim bilgileri ve yedekler, artifacts/releases/ çıktıları, archive/ arşivi, yerel ekran görüntüleri, Android imza anahtarı ve key.properties, yerel yapılandırma dosyaları ve son APK çıktıları. Yeniden üretilebilir bağımlılıklar, ara derleme önbellekleri ve aktarımın geçici dosyaları dahil edilmez. Kaynak kodları main dalındadır.

AES-256-GCM kullanılır. Gizli anahtar GitHub'a eklenmedi. Bu bilgisayardaki konumu:
`D:\Neural-Haber-Backup-20261020.key`

**Bu anahtarı parola yöneticisi veya güvenli başka bir konumda ayrıca sakla. Kaybolursa yedek açılamaz.** Windows DPAPI kayıtları ayrıca özgün Windows hesabına/makinesine bağlı olabilir.

## Geri açma

Python ve cryptography paketi gerekir:

```powershell
py -m pip install cryptography
py tools/repository/decrypt_backup.py local-backup-20261020.parts.json --key-file "D:\Neural-Haber-Backup-20261020.key" --output "$env:USERPROFILE\Documents\Neural-Haber-restored.zip"
```

Doğrulama başarısızsa ZIP oluşturulmaz. Başarılıysa ZIP'i güvenli bir konuma aç. İçindeki BACKUP-MANIFEST.json göreli dosya yollarını, boyutlarını ve SHA-256 özetlerini içerir. Açılmış dosyaları Git'e ekleme. Geri yüklemek canlı sunucuya kendiliğinden veri yazmaz.
