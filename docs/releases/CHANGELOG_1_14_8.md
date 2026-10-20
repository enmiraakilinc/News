# 1.14.8 (2052) — Kişisel sohbet hesabı

- Sohbetler üst çubuğunda “Kişisel sohbet hesabı”: mevcut anonim hesabı, otomatik oluşturulan 128 bit kişisel hesap kodu ve kullanıcının girdiği şifreyle Firebase Authentication'a bağlar. UID değişmez; sohbetler ve mesajlar korunur. Şifre kaynak koda veya tercihlere yazılmaz.
- Diğer cihazda kod ve şifreyle aynı UID'ye giriş yapılır. Şifre değiştirme mevcut şifreyle yeniden doğrulama ister. Hesap kodu gerçek bir e-posta değildir; e-posta üzerinden şifre kurtarma yoktur. Kod ve şifre kullanıcı tarafından saklanmalıdır.
- Henüz bağlanmamış ve sohbetleri bulunan anonim hesapta başka hesaba giriş engellenir: önce o hesabın kodu oluşturulmalıdır. Hesaplar ve cihazdaki eski sohbetler otomatik birleştirilmez.
- Kişi adları ve listeden kaldırma durumu `chatAccounts/{uid}/contacts` altında yalnızca hesap sahibine açık olarak saklanır. Önceki cihaz ayarları ilk sahibine aktarılır; yerel önbellek UID'ye göre ayrılır. Diğer cihaz ayarları sohbet listesi açılırken/yeniden yüklenirken alınır.
- Farklı hesaba girişte açık ekranlar yeniden kurulur, eski özel alanın yerel gizli kelimesi ve önbelleği kaldırılır. Ortak alan yeni cihazda kendi gizli kelimesiyle açılır. Sohbet kişilerine özel alan üyeliği verilmez.
- Firebase şifreli giriş etkinleştirildi. Mevcut güvenlik kuralları korunarak yalnızca sahibine açık kişi ayarı kuralı eklendi.
- 1.14.8 APK mevcut GitHub yayın kanalına yüklendi; indirilen dosyanın SHA-256 özeti yerel APK ile doğrulandı. `config/app_version` 2052 olarak güncellendi. Yalnızca bu herkese açık sürüm belgesine okuma izni eklenerek eski sürümlerin uygulama içi güncelleme ekranı yeniden çalışır hale getirildi.

## Doğrulama

- Flutter analyzer: sorun yok. 41 Flutter testi geçti.
- Gerçek Firebase üzerinde geçici hesaplarla UID korunması, ikinci cihazdan aynı sohbet ve kişi ayarlarına erişim, diğer kişinin ayarları okuyamaması/yazamaması, hatalı kod/şifre reddi, şifre değişiminde eski şifrenin reddi ve özel alan izolasyonu sınandı. Test kayıtları ve hesapları temizlendi.
- Release APK oluşturuldu (yaklaşık 66,7 MB); sürüm 1.14.8 / 2052 ve önceki sürümle aynı yayın imzası doğrulandı. Android cihaz/emülatör üzerinde uçtan uca arayüz testi yapılmadı.

## Teknik kaynaklar

- [Firebase hesap bağlama](https://firebase.google.com/docs/auth/flutter/account-linking)
- [Firebase SDK hesap bağlama isteği](https://github.com/firebase/firebase-js-sdk/blob/main/packages/auth/src/core/credentials/email.ts)
