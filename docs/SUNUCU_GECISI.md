# Oracle sunucusu ve PostgreSQL geçişi

Ayrıntılı dosya görevleri, servisler, API ve yedekleme bilgileri
[server/README.md](../server/README.md) içindedir.

24 Ekim 2026'da 6.626 belgenin doğrulanmış kopyası PostgreSQL'e aktarıldı.
Kullanıcının açık onayıyla ayrı ve yalnızca Firebase okuma yetkili servis
hesabı oluşturuldu; 34 veri grubu için canlı eşitleme açıldı. Mevcut Firebase
yönetim anahtarı sunucuya aktarılmadı. HTTPS ve otomatik sertifika yenilemesi
doğrulandı.

## Kapasite ve yönetim

Boot diski yaklaşık 50 GB (46,6 GiB). Kök dosya sistemi 29,44 GiB,
kontrol anında 15,16 GiB boş; ayrıca /var/oled için 15 GiB ayrılmıştır.
PostgreSQL veritabanı yaklaşık 669 MB. Bu değerler 24 Ekim 2026 ölçümüdür;
yedekler ve sistem dosyaları da diskte yer kullanır.

Sunucunun sahibi/yöneticisi kullanıcıdır; SSH üzerinden sudo erişimi vardır.
neural_api ve neural_sync hesapları yalnızca uygulama servislerinin
yetkilerini sınırlar. Firebase okuyucu hesabı kullanıcıya veya PostgreSQL
yöneticisine salt okunur erişim zorunluluğu getirmez.

## 1.15.1 sürümünün gerçek kapsamı

Flutter tarafında tek seferlik okumaları PostgreSQL'den alan uyumluluk köprüsü
vardır. Mevcut telefonlar, canlı dinleyiciler, yazma kuyruğu, Firebase Auth/FCM,
Android arama/uyandırma alıcıları ve özel güncelleme geçidi bu aşamada mevcut
Firebase bağlantısını kullanır. Bu sürüm Firebase'den tam ayrılma değildir.

Kodla eklenen sohbet kişisi ortak çift alanına erişemez. Bu sınır gerçek
PostgreSQL rolleriyle ve geçici kullanıcıların uçtan uca testleriyle doğrulandı.

## Ana veri kaynağına geçişte kalan işler

Hedef PostgreSQL'in kalıcı veriler için ana kaynak olmasıdır; yalnızca ayna
veritabanı olarak bırakılması kullanıcı talebi değildir.

1. Firestore yazma kuralları; atomik davet katılımı, mesaj düzenleme/okundu,
   medya sahipliği ve kişisel/ortak alan sınırlarıyla PostgreSQL yazma API'sine
   taşınmalıdır. İstek kimliği ve tekrar deneme güvenliği eklenmelidir.
2. Flutter yazmaları, işlemleri, çevrimdışı kuyruk ve canlı abonelikleri aynı
   veri kaynağını kullanmalıdır. Yalnızca get çağrılarını değiştirmek yetmez.
3. Android IncomingCallActivity, VoiceCallSupport, WakeAlarmService ve
   Cloudflare servislerindeki doğrudan Firestore erişimleri geçirilmelidir.
   Firebase Auth ve FCM'nin veri depolamasından ayrı kalan görevleri ayrıca
   değerlendirilmelidir.
4. Eski telefonlar için tek yazma kaynağı korunmalıdır. Şimdiki eşitleme ilk
   açılışta Firebase'de bulunmayan PostgreSQL satırlarını temizler; sunucuya
   özgü yazmalar açılmadan bu davranış ve veri sahipliği değiştirilmelidir.
5. Son aktarım, yetki/yarış koşulu/çevrimdışı/arama testleri ve geri dönüş planı
   doğrulandıktan sonra yazma kaynağı değiştirilmelidir. Veri silmek ancak
   doğrulanmış geçiş ve korunan yedek sonrasında ele alınmalıdır.

Kaynak belgeler silinmedi. Testlerin oluşturduğu geçici kayıtlar temizlendi.
Günlük yedek aynı sunucudadır; sunucu dışı yedek henüz kurulmadı.
