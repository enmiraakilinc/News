# Özel güncellemeye geçiş

## Hazırlanan yapı

- Uygulama /updates/latest ve /updates/apk isteklerine Firebase oturum belirtecini ekler. Sunucu bunu Firebase ile doğrular.
- updateAccess/{uid}.enabled == true olmayan hesaplara sürüm notu veya APK verilmez. Bir Firebase hesabı açmak tek başına yetmez; yetkiyi yalnızca yönetici verir.
- config/private_app_version ve updateAccess mevcut kurallarda istemciye kapalıdır. İstemciye yeni bir Firestore okuma izni gerekmez.
- GitHub anahtarı yalnızca Cloudflare secret olur; uygulamaya veya GitHub dosya sunucusuna aktarılmaz. APK sunucu üzerinden akışla verilir, geçici GitHub URL'si istemciye verilmez; yanıt önbelleklenmez.
- İstemci APK SHA-256 özetini doğrulamadan kurulumu açmaz.
- Özel yayın: python tools/releases/publish.py --version X.Y.Z --publish --private. Depo public ise komut yayımlama yapmadan durur. Notlar yalnızca özel metadata belgesinde tutulur.

## Canlıya geçiş için eksik erişim

GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens bölümünden bir anahtar oluştur:

1. Resource owner: kendi hesabın.
2. Only select repositories → NeuralScope.
3. Contents → Read-only. GitHub zorunlu Metadata izni de ekleyebilir.
4. Son kullanma tarihi seç; dolmadan yenilenmeli.
5. Anahtarı sohbete, kaynak koda veya komut satırı argümanına yazma. free-wakeup-worker klasöründe aşağıdaki komutun gizli değer istemine gir:

```powershell
npx wrangler@4 secret put GITHUB_RELEASE_TOKEN
```

Mevcut gh oturumunun geniş depo yetkili anahtarı sunucuya taşınmadı. Dar kapsamlı anahtar henüz sağlanmadığından özel güncelleme canlıda çalışıyor sayılmaz.

18 Ekim Cloudflare secret listesi kontrolünde yalnızca SERVICE_ACCOUNT_JSON vardı; GITHUB_RELEASE_TOKEN henüz eklenmemiş. Çalışan sunucuya bu hazırlığın kodu henüz dağıtılmadı.

## Geçiş sırası

1. Secret ekle; node --test worker.test.mjs updates.test.mjs ve Flutter analiz/testlerini doğrula.
2. free-wakeup-worker içinden npx wrangler@4 deploy çalıştır. Mevcut servis hesabı ve bağlamalar korunur.
3. Salt okunur hazırlık: python tools/releases/prepare_private_updates.py --version 1.14.31. 18 Ekim kontrolünde mevcut sohbet/çift üyeliklerinde 10 hesap bulundu; bu kontrol herhangi bir yetki vermedi.
4. --apply ile mevcut sürüm ve mevcut üyeler için özel kayıtları oluştur. Önceki kayıtlar private/backups altında saklanır. Yeni üyeler otomatik yetkilenmez; yönetici ayrıca updateAccess kaydı vermelidir. Bu komut eski kapatılmış yetkileri yeniden açabilir, gelişigüzel tekrar çalıştırma.
5. Canlıda yetkisiz isteklerde 401/403, izinli hesapta metadata ve indirilen APK özeti doğrulanmalı.
6. Kullanıcı onayından sonra özel indirmeyi destekleyen geçiş APK'sını oluştur ve yalnızca yerel dosya olarak kullanıcıya ver. Mevcut 1.14.31 ve eski sürümler herkese açık link kullanır. Güncelleme alması gereken cihazlara geçiş sürümü bir kez kurulmalı.
7. Kurulum doğrulanınca NeuralScope private yapılır; oturumsuz notların/APK'nın kapalı olduğu ve izinli indirme yeniden doğrulanır.
8. Eski herkese açık config/app_version belgesindeki URL/notları yedekleyip temizle. Bu işlem eski sürümleri otomatik olarak özel indirmeye geçirmez.

Bu hazırlık depo görünürlüğünü, canlı Firestore kayıtlarını veya Worker dağıtımını değiştirmedi. Önceden alınan public kopyalar/forklar private'a geçince silinmez; APK verilmiş kişiler cihazlarındaki dosyayı kopyalayabilir.

## 1.14.32 geçiş durumu

Kullanıcı yeni GitHub anahtarını secret olarak eklediğini doğruladı. Worker dağıtıldı ve mevcut 10 sohbet/çift üyesi için updateAccess kayıtları oluşturuldu. Oturumsuz/yetkisiz istekler ve istemcinin kendine yetki vermesi canlıda reddedildi; yetkili APK akışı doğrulandı. Geçici doğrulama hesapları temizlendi.

Kullanıcı diğer telefonlara erişemediği için 1.14.32'nin mevcut açık güncelleme yolunda yayımlanmasını açıkça onayladı. Açık APK ve eski config/app_version bu geçişte korundu; private metadata da 1.14.32'ye güncellendi. Depo hâlâ public: eski telefonlar bu sürüme geçmeden private yapmak onların indirmesini keser. Private'a geçişin zamanı henüz kararlaştırılmadı. İleride metadata güncellerken prepare_private_updates.py --metadata-only kullanılabilir; böylece hesap yetkileri tekrar açılmaz.

Kaynaklar: https://docs.github.com/en/rest/releases/assets ve https://developers.cloudflare.com/workers/runtime-apis/streams/ .
