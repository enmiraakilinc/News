# 1.14.16 (2060)

Kullanıcıya açık kısa not: Görünüm ve kararlılık iyileştirmeleri.

## Hazırlanan değişiklikler
- Sohbet üst çubuğu yalnızca avatar ve adı gösterir. Avatara basınca yıldızlı mesajlar, kayıt adını değiştirme, kişiye özel fotoğraf/emoji, paylaşılan kayıt adı ve diğer kişi ayarları açılır menüde yer alır. Kişinin avatarını değiştirmek genel kullanıcı profilini değiştirmez.
- Love teması koyu bordo yüzeyler ve okunaklı açık metinlerle eklendi.
- Haber sayfasından Ayarlar > İzinler ekranı açılır. İzinlerin gerçek kullanım gerekçeleri görünür; izinleri gizleyen veya Android denetimlerini atlayan akış yoktur.
- Sohbet bildirimleri genel ayarlardan bağımsız açılıp kapanabilir. Uygulama açılışında otomatik bildirim izni isteme kaldırıldı. Uygulama içi yenilik rozetleri korunur.
- Medya yalnızca açılınca yüklenir; sınırlı bellek önbelleği, eşzamanlı aynı dosya isteğinin birleştirilmesi ve sekiz parçalık aktarım kullanılır. Önbellekten okumadan önce sunucuda erişim ve süre yeniden doğrulanır; hesap değişiminde içerikler temizlenir. Fotoğraf/video uygulama içinde açılır; indirme simgesi ve indirme adımı kaldırıldı.
- Kullanıcının tercihine göre profil fotoğraflarının mevcut küçük kayıt biçimi korundu; asıl fotoğrafın ayrıca ve kalıcı depolanması uygulanmadı. Fotoğraf seçicideki ek küçültme kaldırıldı, mevcut 24 KB önizleme sınırı devam eder.
- Haberler için cihazda tutulan görsel ve sesli notlar eklendi. Ses kaydı duraklatılıp dinlenir, ancak açık onaydan sonra kaydedilir. Notlar ve dosyaları silinebilir; sunucu alanı kullanılmaz.
- Uyandırmada beş dakikalık sunucu beklemesi ve alıcıdaki bir dakikalık bekleme kaldırıldı. Alıcının cihaz/kişi izni, bildirim izni denetimi, kapatma ve yinelenen olay kimliği koruması sürer. Ayarı açmak yeni bir sistem izin penceresi açmaz; bildirim izni kapalıysa anlaşılır yönlendirme yapılır.
- İsteğe bağlı kayıt adı paylaşımı eklendi. Kişisel rehber belgeleri sahibine özel kalır; kayıt adı ancak kişi paylaşmayı açarsa diğer üyeye gösterilir.

## Sesli arama kapsamı
- Birebir sohbetlerde en fazla üç dakika süren, mikrofonu kabulden sonra açan WebRTC sesli arama kodu eklendi. Grup ve görüntülü arama yoktur. Ses kaydı tutulmaz.
- İlk sürümde iki uygulama da ön planda açık olmalıdır. Uygulamadan çıkış, hesap değişimi, iptal ve üç dakika sınırında mikrofon/bağlantı kapatılır. Süre sınırı cihaz saatinin geri alınmasıyla uzamaz.
- Google STUN kullanımının ağ adresi paylaşımı aramadan önce açıklanır ve kullanıcı devam etmeyi seçer. TURN aktarım sunucusu yoktur; farklı mobil ağlarda bağlantı kurulamayabilir.
- Geçici SDP/ICE bağlantı bilgileri Firestore'dadır; normal görüşme sonunda arayan istemci bunları temizler. Uygulama zorla kapatılırsa fiziksel temizliğin kesin zamanlı olduğu iddia edilmez.
- Gerçek iki telefonda bağlantı/mikrofon/ses yönlendirme testi yapılmadı. Kullanıcıya AirDroid'e karşı kesin gizlilik ve kesintisizlik garantisi verilemediği açıklandı; kullanıcı bu sınırlarla yayına onay verdi. `config/voice_calls` etkinleştirildi ve girişsiz okunabilirliği doğrulandı.

## Yayın ve doğrulama
- Kullanıcının yayın onayıyla test edilmiş Firestore kuralları ve beklemesiz Cloudflare Worker canlıya uygulandı. Uyandırma sunucusu hazır olma/yetkisiz istek denetiminden geçti. Gerçek kullanıcıya test alarmı veya arama gönderilmedi.
- İzole Firestore emülatöründe 9 erişim testi, Worker'da 7 test ve APK oluşturmadan Android Kotlin/Java derlemesi geçti.
- Flutter kod analizi temiz; 77 uygulama testi geçti. Dar ekran menüsü, sınırlı önbellek, bağımsız bildirim tercihi ve haber sesli notunun onayla kaydedilip dosyasıyla silinmesi doğrulandı.
- 1.14.16 / 2060 APK oluşturuldu; önceki sürümle aynı imza doğrulandı. Sunucu/ağ ve gerçek cihaz sınırlamaları kullanıcıya açıkça belirtildi.
- GitHub sürümü yayımlandı. İndirilen APK'nın SHA-256 ve boyutu yerel dosyayla eşleşti; uygulama içi güncelleme kaydı 1.14.16 / 2060 olarak etkinleştirildi ve girişsiz okunabilirliği doğrulandı.
