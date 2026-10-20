# 1.14.25 (2069) ile yayımlanan değişiklikler

## 1.14.32 ile yayımlandı — kişisel ifadeler ve özel güncelleme geçişi

- Uzun basma menüsünde İfade bırak; emoji listesi bu seçeneğe basınca açılır.
- Emojileri düzenle ile 12 favoriye kadar ekleme/çıkarma; klavyeden tek kullanımlık seçim korunur. Favoriler bu cihazdaki hesaba göre yerel kaydedilir.
- Yönetici yetkili özel güncelleme sunucusu, private metadata ve APK SHA-256 kontrolü hazırlandı. GitHub anahtarı istemciye konmaz; açık dağıtım deposu oluşturulmaz.
- 19 ilgili Flutter testi ve 12 Worker testi geçti. Özel güncelleme sunucusu, mevcut 10 üyenin erişimi ve yetkili APK indirmesi canlıda doğrulandı. Kullanıcı bu geçiş APK'sının açık dağıtımını onayladı; 1.14.32 mevcut uygulama içi güncelleme yolunda yayımlandı. Depo diğer telefonların güncellenebilmesi için şimdilik public kaldı; docs/PRIVATE_UPDATES.md durum bölümüne bak.

## 1.14.31 ile yayımlandı — klasör renkleri, not düzenleme ve toplu kopyalama

- Ortak ve kişisel ders klasörlerinde/alt konularda mavi, kırmızı, sarı, yeşil, mor, turuncu veya varsayılan tema rengi seçimi. Renk klasörle birlikte saklanır.
- Not, kod, duyuru ve medya açıklamalarını düzenleme. Asıl görsel/video, albüm, sabitleme, tarih ve sıralama korunur; ortak notlar aynı şifreli kayıtta işlemle güncellenir.
- Duyurulara belirgin çerçeve, duyuru simgesi ve “Önemli duyuru!” başlığı.
- Açık metin mesajlarında uzun bas → Toplu seç, diğer mesajlara dokun → Kopyala. Seçilenler konuşma sırasıyla, aralarında boş satır olacak şekilde kopyalanır. Kilitli mesajlar ve eklerin ham verileri seçilmez.
- Kullanıcıya gösterilecek kısa, genel notlar NEXT_PUBLIC_NOTES.txt içinde; yayın aracı hem GitHub hem uygulama güncelleme ekranında bu metni kullanır. Gizli bölüme özgü ayrıntılar yalnızca bu iç belgede tutulur. 1.14.31 (2075) yayımlandı; APK ve güncelleme kaydı doğrulandı.
- İlgili 30 test başarılı: renk kalıcılığı ve arayüzden seçim, not düzenleme ve mevcut ek/tarih/sıra korunması, duyuru görünümü, konuşma sırasıyla toplu kopyalama ve sohbet regresyonları. Yayın aracının Python sözdizimi doğrulandı.

## 1.14.31 ile yayımlandı — sohbetlerin ilk girişte boş kalması

- Sohbet listesi profil ve kişi eşitlemesi tamamlanmadan dinlenir; geciken veya hata veren profil isteği sohbetleri gizlemez.
- Arka planda gelen profil adı mevcut yükleme Future'ını değiştirmez; liste aboneliği korunur.
- Eksik üye bilgisi olan eski sohbet kayıtları ve henüz hazır olmayan kullanıcı kimliği için güvenli avatar görünümü.
- Profil yükleme durumu ve yeniden deneme mesajı listeyi kapatmadan gösterilir.
- İlk girişte geciken profil/kişi eşitlemesi ve başarısız profil isteği için widget regresyon testleri eklendi. Gerçek telefon bağlı olmadığından cihazdaki beyaz ekranın hata kaydı doğrulanamadı.
- Statik analiz temiz; ilgili sohbet, kişi adı ve akış testlerinde 19 test başarılı.

## Sonraki sürüm — sohbet fotoğrafları arasında kaydırma (henüz yayımlanmadı)

- Birebir/grup ve çift sohbetinde yüklenmiş geçmişteki açık fotoğraflar arasında tam ekran sağa/sola geçiş. Kilitli mesajlar dahil edilmez.
- Sayfa sayacı, 5 kata kadar yakınlaştırma, yakınlaştırılmış fotoğrafta sürüklerken sayfa değişmesini engelleme.
- Yalnızca görünen fotoğraf yüklenir; süre/erişim kontrolleri ve kaydetme isteği akışı korunur. Açılamayan sayfada yeniden deneme veya diğer fotoğrafa geçme mümkün.
- 26 ilgili medya/sohbet testi geçti; asıl JPG eski tür alanı desteği de bu sürümün bekleyen değişikliklerindendir. Sunucuda onarılan Defne ekleri mevcut sürümde açılır, yeni eklerin kalıcı uyumluluk düzeltmesi yeni APK ile gelir.

## Sonraki sürüm — Kendime Notlar metin ve alarm (henüz yayımlanmadı)

- Haber yan menüsündeki Kendime Notlar alanında Yazılı not ekleme; isteğe bağlı başlık, 20.000 karakter metin, dokunarak düzenleme.
- Metinler diğer kişisel notlar gibi yalnızca cihazda saklanır. Düzenleme alarm kimliğini korur; yeni görsel/ses/konum notları da ilk kayıtta kimlik alır.
- Küçük saat simgesi yerine her notta açıkça Alarm kur düğmesi. Var olan bildirim/tam ekran/alarmlar ve hatırlatıcılar izin akışından sonra tarih ve saat seçilir.
- Kişisel not izin veya kayıt hataları anlaşılır mesajla gösterilir. Defne'nin 6 eski JPG eki daha önce sunucuda onarılmıştır; bu iş ayrı bir uygulama yayını gerektirmez.

## Sonraki sürüm — sohbet video/ses açılışı (henüz yayımlanmadı)

- İndirmede 16 parça eşzamanlı alınır; şifreli parçalar parça başına ayrı compute yerine toplu işçiyle çözülür. Eski sunucu kurallarındaki tekil okuma izinleri korunur, yeni sorgu izni gerekmez.
- Video ve sesli mesajda indirme yüzdesi; veri indirme adımlarında 30 saniyelik yanıtsızlık sınırı ve anlaşılır hata.
- Aynı mesaj kartı açıkken büyük videonun geçici dosyası tekrar kullanılır; her açılışta sunucudan erişim/süre kontrolü yapılır. Kart kapanınca dosya silinir. Hesap/gizli kelime değişirse yerel kopya kullanılmaz.
- 100 MiB video temizliğindeki eski 80 MiB parça sayısı sınırı düzeltildi.
- 28 medya/ses/ek testi geçti. Gerçek telefonda indirme süresi ölçülmedi. İlk oynatma için dosyanın tamamının indirilmesi hâlâ gerekir; ağ ve ücretsiz Firestore sınırları etkili olur.

## Sonraki sürüm — sohbet listesi açılışı ve hata mesajları (henüz yayımlanmadı)

- Sohbet profili artık kişi adlarının uzak sunucuyla eşitlenmesini beklemez. Yerel profil önbelleği önce kullanılır; profil ve kişi bilgileri arka planda güncellenir.
- Yerel kişi adları/gizlenen kişiler hazır olduğunda liste yenilenir; değişim dinleyicisi ekran kapanınca kaldırılır.
- Kişi kaldırma/geri getirme hataları kullanıcıya açıklanır. Liste/profil yükleme hataları sebebe göre gösterilir.
- Dosya okuma, içerik biçimi, kapalı izin, oturum/şifre, zaman aşımı ve deneme sınırı hataları için ortak Türkçe yönlendirmeler. Teknik dosya yolu ve hata ayrıntıları kullanıcı metnine taşınmaz.
- Cihazdaki gerçek açılış süresi ölçülmedi; ilk girişte profil önbelleği yoksa bağlantı gereksinimi sürer.

## Sonraki sürüm — sohbet işlemleri ve ders videoları (henüz yayımlanmadı)

- Açık metin mesajına uzun basarak Kopyala; gönderilmeyi bekleyen kilitli içerik ve ham ek verisi kopyalanmaz.
- Galeriden çoklu fotoğraf/video seçimi, tek isim/onay ekranı ve sırayla gönderim. Video parçalama sınırı parça başına 100 MiB olarak korunur.
- Sohbet listesindeki açık Sil düğmeleri kaldırıldı; Kişiyi sil üç nokta menüsünde, onay korunur.
- Derslere en fazla 100 MiB video ekleme: kişisel dosya cihazdaki kişisel alanda, ortak video çifte özel şifreli parçalarda tutulur. Uygulama içi korumalı oynatıcı.
- Kullanıcının tercihiyle ders videosu 7 gün erişilebilir. Ders alanı açılınca süresi dolan videonun dosya/parçaları temizlenir; uygulama hiç çalışmazsa tam saatli sunucu silmesi yoktur. Klasör/not silme de video dosya/parçalarını temizler. Kişisel JSON yedeği video dosyalarını içermez.
- Kök dizindeki üç aynı Firebase test yapılandırması tools/testing/firebase.json olarak birleştirildi. Aktif testler APK'ya eklenmedikleri ve hata kontrolleri sağladıkları için korundu.

## Sonraki sürüm — turuncu tema ve ders gezinmesi (henüz yayımlanmadı)

- Turuncu temel/kap renkleri #CB5C0C.
- Not, duyuru ve fotoğraf grubunun açıklamalarındaki HTTP/HTTPS/www bağlantıları dokunarak tarayıcıda açılır. Kod blokları olduğu gibi seçilip kopyalanır.
- Konu klasörleri ders ekranında doğrudan listelenir, aynı yerden konu eklenir. Ek klasör ekranına girmek gerekmez. Eski silme/sabitleme işlemleri üstteki klasör yönetimi kısayolunda korunur.

## Sonraki sürüm — gerçek JPG hata nedeni ve fotoğraf oranları

- Defne sohbetindeki Instagram ekran görüntüsü eklerinde `kind` alanının bulunmadığı doğrulandı. Uygulama artık eski alanı dosya olarak varsayar, fotoğrafı uzantısından/içeriğinden açar. Eksik türün zorunlu cast hatası giderildi.
- Kullanıcının istediği 6 ek (3 ayrı JPG'nin kopyaları), özel yedek alınarak yalnızca eksik `kind: photo` alanı tamamlanıp sunucuda onarıldı. JPEG doğrulaması başarılı, 1080×2340; görsel baytları değişmedi. Mevcut sürümde açılabilir.
- Gizli resim/anı önizlemelerinde aynı genişlik-yükseklik çözme zorlaması kaldırıldı. Tam ekran görseller doğal çözünürlükte ve en-boy oranıyla açılır.
- Kamera önizlemesi mevcut yön ve kamera oranına göre ekran sınırlarına sığar.
- Anı kartları görünür oldukça oluşturulur. İlk veri indirmesi ve şifre çözme süresi ağ/veri boyutuna bağlı kalır.
- Sohbet fotoğrafları zaten orijinal baytlarla gönderiliyor. Kalıcı anı/gizli resimlerde 560000 bayta sığan fotoğraflar da aynen korunur. Büyük kalıcı fotoğraflarda tek Firestore belgesi sınırı nedeniyle sıkıştırma sürer; bunlar 2 günlük sohbet ekleri değildir.

## Sonraki sürüm — görsel çözücü ile fotoğraf açma (henüz yayımlanmadı)

- Türü ve uzantısı tanınmayan dosyalar dış uygulamaya verilmeden önce Flutter görsel çözücüsüyle kontrol edilir; çözülebilen görseller korumalı görüntüleyicide açılır.
- Gerçek JPG'nin uzak dosya eki olarak açılması ve uzantısız BMP'nin çözülmesi dahil 6 medya testi geçti. Kullanıcının sorunlu orijinal dosyası incelenmedi.

## 1.14.28 (2072) — JPG ekran görüntüsü açma yayımlandı

- Dosya olarak gelen fotoğraflarda JPG/PNG/GIF/WebP içerik imzasını kontrol ederek uygulama içi fotoğraf görüntüleyiciyi açma.
- Dosya adının sonundaki boşlukların uzantı algılamasını bozmasını önleme.
- Bozuk/eksik fotoğraf için anlaşılır görüntüleyici uyarısı.
- 4 medya testi geçti. Kullanıcının gönderdiği asıl ekin baytlarına erişilmedi; düzeltme tür algılamasını güçlendirir, bozuk veya süresi dolmuş ekleri kurtarmaz.

## 1.14.27 (2071) — ders ekranı ve fotoğraf grupları yayımlandı

- Derslerde aynı seçimle eklenen yeni fotoğraflar tek kartta 2 sütunlu grup olarak gösterilir. Dörtten fazlası +N ile belirtilir; tüm görseller grup ayrıntısından açılır.
- Görseller ayrı kayıtlar olarak korunur; albüm kimliği şifreli not verisinde/kişisel kayıtta saklanır. Eski tekil görseller değişmeden açılır.
- Arama üstte büyüteç ile açılır; konu klasörleri daha kısa satırda, notlara ayrılan alan daha geniştir.
- Statik analiz temiz; albüm verisi uyumluluğu dahil 7 ders notu testi geçti.

## 1.14.27 (2071) — arama bildirimleri yayımlandı

- Gizli bölümdeki bildirim tercihlerinde sesli/görüntülü aramalar için ayrı seçenekler.
- Uygulama kapalıyken gelen arama bildiriminin başlığı ve metni cihazda özelleştirilebilir; boş alanlar varsayılana döner.
- Eski arama tercihi yeni seçeneklere başlangıç değeri olur; yalnızca alarm profili ikisini de kapatır.
- Uygulama içi çağrı akışı ve Android arka plan/tam ekran akışı arama türüne göre tercihi uygular.
- Statik analiz temiz; 6 bağımsız bildirim testi geçti.

## 1.14.26 (2070) ile yayımlandı

- Ortak/kişisel ders notlarında daha geniş kart aralıkları ve rahat satır yüksekliği.
- Uzun not ve kodlarda 10 satır / 700 karakter önizleme; Devamını oku / Daha az göster. Kopyala her zaman tam metni kopyalar.
- Galeriden tek seferde birden fazla fotoğraf seçimi; her biri ayrı not olarak sırayla kaydedilir. Açıklama ilk görsele eklenir. Görsel başına mevcut 20 MB sınırı korunur.
- Not, kod ve duyurular eskiden yeniye sıralanır; en yeni içerik alttadır. Sabitleme kronolojik sırayı değiştirmez.
- Kontrol: statik analiz temiz, 6 ders notu testi geçti.
- Kullanıcı onayıyla yayımlandı; imzalı APK, indirme dosyası ve uygulama içi güncelleme kaydı doğrulandı.

## Yayımlanan içerik

- Haberlerde bağımsız tema seçimi.
- Ortak ve kişisel derslerde iç içe konu klasörleri.
- Ders/konu başlığı, not ve kod araması; klasör/not sabitleme.
- Kişisel dersleri görselleriyle JSON yedeği olarak dışa aktarma. Şifresiz dosya, görseller toplamı en fazla 50 MiB.
- Çift ve kişi sohbetlerinde açık mesajlar ile dosya adlarında arama; eski geçmiş için 100'erli sayfalama.
- Video izlerken yakınlaştırma ve sıfırlama.
- Arka kamera fotoğraf flaşı/video ışığı; ön kamerada ekran ışığı.
- Video kaydı sürerken kamera değiştirme; desteklemeyen cihazda anlaşılır uyarı.
- 100 MiB ve altındaki video tek gönderilir; daha büyük video en fazla 100 MiB parçalar olarak hazırlanır. Her parçaya ad verilebilir; varsayılanlar Part 1, Part 2…

Uygulama analiz sonucu temiz, önceki tam çalıştırmada 105 Flutter testi ve Android Release Kotlin derleme kontrolü geçti. Son video sınırı düzeltmesi 4 medya testiyle doğrulandı. Samsung S25 fiziksel kamera/lens değiştirme testi yapılmadı. Kullanıcı onayıyla 1.14.25 (2069) yayımlandı; imza, indirilen APK ve uygulama içi güncelleme kaydı doğrulandı.

Bot değişikliği ayrı olarak canlıya alındı: mülakat sorusu/cevabı ve düğmeleri kaldırıldı. Normal Telegram mesajları seçili projedeki yerel Codex'e görev gönderir. VS Code açık olmak zorunda değildir; PC ve ajan açık olmalıdır. Mevcut ChatGPT/Codex kotası kullanılır; ücretli API bağlanmadı. Bulut emülatörü yoktur.
