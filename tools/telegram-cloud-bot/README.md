# Ücretsiz proje botu — etkin

## Basit yerel kod geliştirme (yeni)

`/start` → `/proje uygulama` → yapılacak işi normal mesaj olarak yaz.
PC ajanının `codex_projects` listesinde izin verilen projelerde, yerel ChatGPT
oturumlu Codex dosyaları düzenler. VS Code'da aynı klasör açıkken değişiklikleri
görebilirsin; editörün açık olması şart değildir. Bilgisayar ve ajan açık olmalı.
Bu bağlantı ayrıca ücretli API açmaz; mevcut Codex kullanım kotası geçerlidir.
`/eklenecek açıklama` yalnızca not kaydeder. `/ss` ayrıca ekran görüntüsü ister.
Kod görevleri workspace-write ve otomatik onay incelemesiyle çalışır; yayınlama
otomatik değildir. Python komutlarının ayrı `--allow-code` seçeneği kapalı kalır.
`codex_bridge.py` ChatGPT girişini doğrular, API anahtarlarını alt sürece aktarmaz,
15 dakika sınırı uygular ve uzun işler için kimlik doğrulamalı lease yeniler.
Bu bölümdeki bağlantı, özel PC yapılandırması etkinleştirilip ajan yeniden
başlatıldıktan ve Worker dağıtıldıktan sonra kullanılabilir; aşağıdaki eski
geçiş raporu önceki dağıtımı anlatır.

17 Ekim 2026: mevcut `daisyschuster_bot` hesabı bu Worker'a bağlandı. Telegram webhook'u, canlı durum yanıtı ve `uygulama`/`bot` PC bağlantıları doğrulandı. Kaynaklar özel `kunduracimelek/bot` deposunun `cloud/` klasörüne kaydedildi. Ücretli plan/abonelik açılmadı. Yerel ChatGPT oturumlu Codex bağlantısı hazırdır; bulut emülatörü bağlı değildir.

Kullanmak için Telegram'da `/start`, ardından `/projeler` veya `/proje uygulama` yaz. Windows'taki mevcut ajan başlatıcısı korunarak yeni kimlik doğrulamalı ajanla değiştirildi; eski sürüm özel yedek klasöründe. Python komutlarını her açılışta otomatik etkinleştirme güvenlik incelemesince reddedildi, bu nedenle çalışan ajanda `--allow-code` kapalıdır. İstenirse yalnızca açıkça izin verilen yerel oturumda açılabilir.

Canlı geçişte Render'ın kalıcı olmayan dosyalarından dışa aktarım yanıtında 0 not/0 özel komut bulundu. Yanıt özel yedek klasörüne kaydedildi; eski Telegram sohbeti veya Git geçmişi otomatik silinmedi. Render'daki eski polling, kimlik doğrulamasız PC ve geçici dışa aktarım kodlarının kaldırılması depoya işlendi. Render otomatik dağıtımı sonrasında eski `/pc/ping` ve `/legacy-export` 410 döner.

Bu paket mevcut Telegram bot hesabıyla çalışan ayrı bir Cloudflare Worker'dır. Render botu eski polling görevinden çıkarılmıştır. Neural Haber'in uyandırma Worker'ından tamamen ayrıdır. Aşağıdaki kurulum bölümü yeniden kurulum başvurusudur; çalışan bot için tekrar uygulanmaz.

## Hazır olanlar

- Aynı botta birden fazla proje; kısa proje koduyla seçim.
- Kalıcı D1 kayıtları: görevler bilgisayar kapalıyken de saklanır.
- Proje bazında listeleme, tek görevi görüntüleme ve silme.
- Silme öncesi 5 dakika geçerli, tek kullanımlık onay. Başka projeye geçilse de onayın hedefi değişmez.
- Botun takip ettiği Telegram mesajlarını silme talebi. Silme başarısızsa görev metni yine D1'den silinir; tekrar denenebilecek mesaj kimlikleri kalır.
- Mevcut bir GitHub Actions derleme workflow'unu onayla tetikleme.
- Yalnızca sahibinin özel sohbetine erişim; webhook secret kontrolü.
- Tokenlar kodda değil Cloudflare secrets içinde; metinleri yazdıran uygulama logu yok.
- Proje odaklı butonlu menü ve eski not komutunun `/eklenecek` takma adı. Gereksiz mülakat sorusu/cevabı kaldırıldı.
- Kimlik doğrulamalı PC ajanı: tek seferlik ekran görüntüsü, Git Pull, günlük/Python sözdizimi takibi ve projeye özel Python komutları.
- Kalıcı PC kuyruğu, 10 dakikalık teslim kirası ve sonuç onayı. Yerel günlük aynı işi bağlantı kesilince tekrar çalıştırmaz; yarıda kesilmiş işin etkisini belirsiz olarak bildirir.

## Hazır olmayanlar — önemli

Bu bot **serbest metin isteğinden kendi kendine kod geliştirmez**. Ücretsiz bir yapay zekâ ajanı bağlanmadı. Görev kaydetmek, kod değişikliği yapıldığı anlamına gelmez.

Android bulut emülatörü/ekran görüntüsü, otomatik APK teslimi ve derleme sonucu bildirimi henüz yok. `/ss` bunu açıkça söyler. `/derle` yalnızca mevcut workflow'u başlatır ve Actions bağlantısı verir. Cloudflare Worker Android SDK çalıştıran bir bilgisayar değildir.

PC ekranı, takip, Git Pull ve özel Python komutları korunur. Mülakat işlevleri kullanıcının isteğiyle kaldırıldı. Python kodu Cloudflare'da çalıştırılmaz; sahibinin PC'sinde çalışır. PC ajanının `--allow-code` seçeneği varsayılan olarak kapalıdır. Git Pull ve Python için Telegram'da ayrıca onay gerekir. Eski bot ve dosyaları korunur; geri dönüş mümkündür.

Eski PC ajanı yeni protokolle uyumlu değildir. Yeni `pc_agent.py` kullanılmalı; kimlik doğrulamasız eski `/pc/ping` bağlantısı korunmaz. Bu paketi hazırlamak eski PC ajanını otomatik güncellemez.

## Ücretsiz sınırlar ve gizlilik

Workers **Free** ve D1 **Free** kullanılır. Ücretli plana geçilmez. Kota dolarsa işlem durabilir; sınırsız veya kesintisiz hizmet garantisi yok. Mevcut Cloudflare hesabındaki diğer hizmetlerle bazı limitler ortaktır. Hesabın gerçekten Free olduğu panelden doğrulanmalıdır.

GitHub Actions özel depolarda plan kotasını kullanır. Sıfır ek harcama için ilgili GitHub bütçesi/harcama engeli doğrulanmadan derleme açılmamalı. `/derle` komutunun varlığı kaynak deposunun ve workflow'un hazır olduğu anlamına gelmez. Yalnızca derleme yapan workflow bağlanmalı; içinden otomatik yayın yapan bir workflow seçilmemeli.

Telegram bot API mesajları genellikle 48 saat içinde silebilir. Daha eski mesajlar ayrıca uygulamadan elle temizlenmeli. Bot eski sohbetin tamamını okuyamaz; yalnızca bu sürümün takip ettiği mesajları hedefler. Telegram toplu silmede eksik mesajları atlayabildiği için her bir mesajın silindiği iddia edilmez.

Tek görev silme, o görevin girdisini ve görüntüleme/cevap mesajlarını hedefler. Projeyi temizleme, o projeye ait bütün takip edilen mesajları hedefler. Proje seçmeden önceki genel komut/menü mesajları ayrı boş kapsamda kalır. İstek metinleri listelerde veya onaylarda tekrarlanmaz. Bot mesajlarında `protect_content` kullanılır; bu tam gizlilik garantisi değildir.

D1'de metinler düz veri olarak saklanır; uçtan uca şifreli kasa değildir. Silme aktif bot kayıtlarını kaldırır; sağlayıcının yedekleri, Telegram'ın iç kayıtları, Git geçmişi ve harici derleme kayıtları için anında fiziksel silme garantisi vermez. İmzalama anahtarı, şifre veya kişisel mesaj içeriğini görev metnine koyma.

Eski botun kayıtları yeni sisteme otomatik taşınmaz ve silinmez. Geçişten önce gerekiyorsa ayrıca güvenli dışa aktarım yapılır.

## Dosyalar

- `worker.mjs`: komutlar, Telegram webhook'u, proje/görev/silme ve GitHub derleme köprüsü.
- `schema.sql`: D1 tabloları ve indeksleri; görev metni ile teknik mesaj kimlikleri ayrıdır.
- `worker.test.mjs`: gerçek SQLite ile yerel testler; dış API çağrıları sahtedir, Telegram'a mesaj gönderilmez.
- `wrangler.toml`: yeni Worker/D1 ayarları; henüz gerçek D1 kimliği girilmedi.
- `setup.py`: yalnızca bu yeni Worker'ı kurar; ayrı adımda webhook etkinleştirir veya geri alır.
- `pc_agent.py`: PC tarafı; gizli köprü anahtarıyla bağlanır, yalnızca kayıtlı proje klasörlerinde işlem yapar. Bot tokenı gerekmez.
- `pc-config.example.json`: yerel proje klasörleri için örnek; kendi yollarını `pc-local.json` içine yaz.
- `test_pc_agent.py`: yol sınırı, gizli anahtarın alt sürece verilmemesi ve tekrar çalıştırma önlemleri için testler.

## Komut örneği

```text
/proje_ekle uygulama sahip/gercek-ozel-kaynak-deposu
/proje uygulama
/gorev Ders klasörlerinde arama ekle
/gorevler
/goster t123456
/sil t123456
/temizle
```

`/proje_ekle` yalnızca bir kayıt oluşturur; depoya yetki kazandırmaz. Uygulamanin kaynak ve APK deposu enschumacher/Neural-Haber ozel deposudur. Yerel anahtarlar kaynak koduna eklenmez.

## Etkinleştirme — onaydan sonra

1. Cloudflare hesabının Free planını doğrula; mevcut `neural-wakeup` Worker'ına dokunma. Wrangler oturumu gerekli.
2. Bot tokenını Cloudflare secrets olarak tanımlamak gerekir. Token sohbetten alınmaz. Eski kaynakta token varsa BotFather'dan yenilemek ve eski tokenı yeniden kullanmamak tercih edilir; bu eski servisi etkileyeceğinden geçişle birlikte yapılır.
3. `OWNER_ID` yalnızca bot sahibinin sayısal Telegram kullanıcı kimliği olmalı. `WEBHOOK_SECRET` en az 32 rastgele URL-güvenli karakter seçilmeli. Kurulumda aynı değer tekrar kullanılmalı. Bu değerler koda veya Git'e yazılmaz.

`PC_SECRET` de ayrı, en az 32 rastgele karakter olmalı. Yalnızca Cloudflare secret ve yerel ajan girişinde kullanılır; bot tokenıyla aynı anahtar kullanılmaz.
4. Kurulum betiği gizli giriş ister. Onay sonrası çalışma alanı kökünden:

```powershell
python tools/telegram-cloud-bot/setup.py --provision
```

Bu adım yeni D1 oluşturur, şemayı kurar, secrets tanımlar ve yeni Worker yayınlar. **Render'ı durdurmaz veya Telegram'ı taşımış olmaz.** D1 oluşturma çıktı ayrıştırması başarısızsa panelden kontrol et; tekrar tekrar veritabanı oluşturma.

5. Cloudflare panelinden yeni Worker'ın `https://...workers.dev` adresini al. Render'daki eski polling servisini durdur; aynı tokenla polling ve webhook aynı anda çalışamaz.
6. Aynı token ve webhook secret ile:

```powershell
python tools/telegram-cloud-bot/setup.py --activate https://YENI-WORKER.workers.dev --render-stopped
```

Betik yalnızca webhook adresini doğrular. Telegram'da `/start`, iki proje ekleme, bir görevi silme ve diğer projeyi koruma gerçek kullanım kontrolleri ayrıca yapılır.

7. Derleme istenirse yalnızca ilgili özel kaynak deposuna yetkili GitHub tokenı Cloudflare'da `GITHUB_TOKEN` secret olarak eklenir. GitHub Actions yazma yetkisi gerekir. Kaynak yazma, imza ve yayın yetkileri bu bota verilmemeli. İlgili workflow `workflow_dispatch` desteklemeli ve kodu kendi ortamında test/derlemeli.

```text
/derleme_ayarla build.yml main
/derle
```

## Geri dönüş

```powershell
python tools/telegram-cloud-bot/setup.py --rollback
```

Ardından eski Render servisi yeniden başlatılır. D1 verileri silinmez; bunlar Telegram sohbeti değildir. Token yenilendiyse Render secretı da yeni tokenla güncellenmelidir. Hiçbir APK bu paket üzerinden otomatik yayınlanmaz.

## PC bağlantısı

1. Örneği `pc-local.json` adıyla kopyala. Worker adresini ve proje kodlarının yerel klasörlerini yaz. Telegram'da tanımlanan proje kodlarıyla aynı olmalı. Projeler birbirinden ayrı kök klasörler olmalı; tüm diski kök yapma.
2. Bilgisayarda açık tutmak istediğin oturumda aşağıdaki komutu çalıştır. PC_SECRET gizli girişle istenir.

```powershell
python tools/telegram-cloud-bot/pc_agent.py --config tools/telegram-cloud-bot/pc-local.json
```

Python komutlarına ayrıca izin vermek istersen aynı komuta `--allow-code` ekle. Bu özel kodlar gerçek kullanıcı yetkilerinle çalışır; bir güvenli kod sandbox'ı değildir. Gizli anahtarlar alt sürecin ortamına verilmez, fakat bu tek başına yerel dosyaların erişilemez olduğu anlamına gelmez. Yalnızca kendi yazdığın/güvendiğin kodları çalıştır.

Ekran görüntüsü için yerel Python ortamında `Pillow` gerekir; mevcut PC'de kurulu olduğu doğrulandı. Kurulmadıysa diğer işler çalışabilir, ekran görüntüsü anlaşılır hata verir. Agent otomatik ekran görüntüsü almaz; yalnızca Telegram'dan açıkça istenmiş iş kuyruğa girince alır. Kilitli/etkileşimsiz oturumda veya korumalı uygulama ekranında görüntü alınamayabilir.

```text
/ss
/gitpull
/takip logs/app.log
/hatalar
/komut_ekle selam print('Merhaba')
/komutlar
/calistir selam
/komut_sil selam
```

`/takip` .log/.txt dosyasının son bölümünü yalnızca değişince raporlar. .py seçilirse yalnızca sözdizimini kontrol eder; programı çalıştırmaz ve çalışma zamanı hatası olmadığını iddia etmez. Takip seçimi PC ajanı yeniden başlatıldığında yeniden verilmelidir. `/hatalar` son takip raporunu gösterir; bunun bir test sonucu olmadığı açık tutulur.

PC kapalıysa PC'ye özel işler sırada kalır. Buluttaki görev kayıtları ve GitHub derleme tetikleme bundan bağımsızdır. Eski Render ajanı ile yeni ajanı birlikte çalıştırma. Yerel `.pc-agent-state.json` dosyasını işlemler beklerken silme: tekrar çalıştırmayı önleyen kayıt budur. Başarılı sonuç tesliminden sonra içerik/görüntü yerel günlükten kaldırılır, yalnızca tamamlanan iş kimliği kalır. Telegram teslimindeki ağ kesintileri nadiren yinelenen sonuç mesajına yol açabilir; tam olarak bir kez mesaj teslimi garantisi yok.

`/temizle` seçili projenin bot görevlerini, özel komutlarını, hata raporunu ve henüz çalışmamış PC işlerini kaldırır. Teslim edilmiş/çalışan işlem uzaktan geri alınamaz; bilgisayarda ayrıca durdurulmalıdır. Diğer projeler etkilenmez.

## Yerel doğrulama

```powershell
node --test tools/telegram-cloud-bot/worker.test.mjs
python tools/telegram-cloud-bot/test_pc_agent.py
```

Node 24 yerleşik SQLite kullanılır; yerel test için Cloudflare hesabı veya Telegram tokenı gerekmez.

Kaynaklar:
- https://developers.cloudflare.com/d1/platform/pricing/
- https://developers.cloudflare.com/workers/platform/pricing/
- https://core.telegram.org/bots/api#deletemessages
- https://docs.github.com/en/billing/concepts/product-billing/github-actions
