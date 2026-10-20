# Mevcut Telegram botunun bulut geliştirmeye hazırlanması

İncelenen kaynak: `C:\Users\mkund\Desktop\telegram-bulut-bot`.
İnceleme tarihi: 17 Ekim 2026. Bot çalıştırılmadı, Telegram'a mesaj gönderilmedi, dış klasördeki kaynaklar değiştirilmedi. Gizli değerler bu belgeye alınmadı.

## Şu an ne var?

- `bot.py`: python-telegram-bot ile Telegram komutları ve Flask ile bilgisayar bağlantı adresleri.
- `requirements.txt`: Python paketleri; sürümler sabitlenmemiş.
- `Procfile`: `python bot.py` başlangıcı. Bu dosyanın bulunması botun gerçekten sunucuda çalıştığını kanıtlamaz.
- Telegram tarafında kullanıcı kimliğiyle yönetici kontrolü var.
- Bilgisayar ajanı `/pc/ping` adresine bağlanınca bekleyen kod/git/ekran görüntüsü görevlerini alıyor.
- Bu klasörde `pc_agent.py` yok. Bilgisayardaki ekran görüntüsünü üretecek ajan burada bulunamadı.
- Kod değişiklikleri yapan bir yapay zekâ, GitHub derleme akışı veya bulut Android emülatörü mevcut değil.
- Bilgisayar kapalıyken gelen görevler bilgisayarın açılmasını bekliyor. Bot kendi kendine Flutter projesini geliştirip APK hazırlamıyor.

## Somut düzeltme ihtiyaçları

1. `/ss` komutu bir CallbackQuery işleyicisine yönlendirilmiş. Normal komutta callback_query bulunmadığı için hata oluşabilir. Komut ve düğme ayrı girişlerden ortak fonksiyona bağlanmalı.
2. `/kilavuz` komutunda yönetici kontrolü yok. Tüm komutlar aynı yetki kontrolünden geçmeli.
3. `/pc/ping` kimlik doğrulaması yapmadan görev kuyruğunu okuyup temizliyor. Bilgisayar ajanına ayrı kimlik doğrulama eklenmeli.
4. Bekleyen görevler Python belleğinde. Sunucu yeniden başlarsa kayboluyor. Görevler kalıcı kayıt, durum ve kimlik taşımalı.
5. Görevler teslim alındığı anda siliniyor; tamamlanma onayı yok. Ağ kesilmesi görev kaybına yol açabilir. Teslim ve tamamlanma ayrı durumlar olmalı.
6. Dinamik Python komutları botun kendi sürecinin yetkileriyle alt süreçte çalışıyor; yalıtılmış bir geliştirme ortamı değil. Geliştirme işi ayrı, sınırlı yetkili ortamda yapılmalı.
7. Eşzamanlı Flask ve Telegram işlemleri ortak bellek/dosyalara erişiyor. Kalıcı, eşzamanlı işlem güvenliği olan bir görev kaydı gerekir.
8. Bot tokenı için kaynak içinde varsayılan değer var. Dağıtımda token yalnızca gizli ortam değişkeninden okunmalı; eksikse program açık hata ile başlamamalı.

## Hedef akış

Telegram görevi → yalnızca sahibini kabul eden bot → kalıcı görev kaydı → bulut kod geliştirme ortamı → ayrı dalda değişiklik → analiz/test → emülatör görüntüsü ve APK → sahibine sonuç → ayrıca onay verilirse yayın.

Bot arayüzü için önerilen komutlar:

| Komut | Davranış |
|---|---|
| `/gorev <açıklama>` | Yeni geliştirme işi oluşturur; görev kimliği döner. |
| `/durum <kimlik>` | Bekliyor, çalışıyor, test, derleme, tamamlandı veya başarısız durumunu gösterir. |
| `/ekran <kimlik>` | O işin buluttaki test ortamından üretilmiş son görüntüsünü döner; çekilme zamanı gösterilir. |
| `/sonuc <kimlik>` | Değişiklik özeti, test sonucu ve varsa APK'yı getirir. |
| `/iptal <kimlik>` | İşi iptal etmeyi talep eder; başlamış yayının geri alındığı anlamına gelmez. |
| Yayın onayı düğmesi | Yalnızca hazırlanmış ve doğrulanmış belirli sürüm/hash için yayın başlatır. |

Bu komutlar öneridir; henüz uygulanmadı veya Telegram'a kaydedilmedi.

## Ekran görüntüsü neyi gösterebilir?

Kapalı fiziksel bilgisayarın ekranından canlı görüntü alınamaz. Bulutta çalışan emülatörün ekranı veya o görev için oluşturulmuş ilerleme raporu alınabilir. Her ekran görüntüsü gerçek yakalama zamanıyla sunulmalı; eski görüntü canlı gibi gösterilmemeli. Uygulamanın ekran görüntüsü koruması bulunan ekranları siyah/boş sonuç verebilir. Bu otomasyon için üretim uygulamasının ekran koruması kaldırılmaz. Test verileri kullanılmalı, gerçek kullanıcı mesajları veya yönetim anahtarları görüntülere girmemeli.

## Altyapı seçenekleri

- Telegram giriş noktası için mevcut Python botu uygun bir sunucuda çalıştırılabilir veya küçük bir webhook hizmeti hazırlanabilir.
- GitHub Actions, dışarıdan tetiklenen test/derleme işlerini bilgisayardan bağımsız çalıştırabilir. Özel depolarda dakika ve depolama kotaları kontrol edilmeli.
- Kod yazacak ajan ayrı kurulmalı. Bir API tabanlı ajan kullanılırsa model kullanımı ve ortam için ücret oluşabilir.
- Küçük bir Cloudflare Worker komutları karşılayabilir; tek başına Flutter/Android SDK derleme ortamının yerine geçmez.
- İmzalama ve yayın kimlik bilgileri kod değiştiren ajana verilmemeli; ayrı derleme/yayın aşamalarında tutulmalı.
- Uygulamanın kaynak deposu, APK indirme deposuyla aynı olmak zorunda değil. Kaynaklar ve özel dosyalar kontrol edilmeden mevcut yayın deposuna topluca yüklenmez.

## Etkinleştirme için eksik bilgiler

1. Mevcut bot şu anda nerede çalışıyor? Yerel bilgisayar mı, bir hosting hizmeti mi?
2. Yapay zekâ API hesabı/bütçesi var mı, yoksa tüm akışın ücretsiz olması mı gerekiyor?
3. Kaynak kod için kullanılacak özel depo ve bulut çalışma ortamı seçimi.

Bot tokenı, API anahtarı ve imzalama anahtarları sohbetten istenmez. Altyapı seçildikten sonra ilgili hizmetin gizli değişken alanından tanımlanır.

## Başvuru

- Telegram webhook: https://core.telegram.org/bots/api#setwebhook
- GitHub dış tetikleyiciler: https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
- GitHub kullanım kotaları: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- OpenAI bulut ajanı ve ücretlendirme: https://developers.openai.com/api/docs/guides/agents-api/overview
