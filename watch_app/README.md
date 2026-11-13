# Saat uygulaması (Huawei Watch Fit 2)

Lite Wearable projesi, 336×480 ekran içindir.

1. DevEco Studio’da **File → Open** ile bu `watch_app` klasörünü aç.
2. `config.json` içinde `ohos.permission.INTERNET` ve `ohos.permission.VIBRATE` izinleri tanımlıdır. İmza için kendi debug sertifikanı seç.
3. `pages/index/index.js` başındaki `SERVER` adresini sunucunun `http://IP:PORT` değeriyle, `TOKEN` değerini `neural.watch_tokens` kaydıyla değiştir.
4. **Build → Build Hap(s)** ile `.hap` paketini üret.
5. Saati USB ile bilgisayara bağla. DevEco Assistant’ta cihazı seç, üretilen `.hap` dosyasını **Install** ile Huawei Watch Fit 2’ye yükle.
