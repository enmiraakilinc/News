# Yerel test yapılandırması

`firebase.json` önce kökte farklı adlarla duran üç birebir aynı emülatör
yapılandırmasının tek kopyasıdır. Firestore emülatör portu 8181, kurallar
`../../firestore.rules` dosyasından alınır. Canlı sunucu yapılandırması değildir.

Flutter testleri `flutter_application_1/test/`, bildirim sunucusunun testleri
`free-wakeup-worker/`, Telegram bot testleri `tools/telegram-cloud-bot/` içindedir.
Bu testler APK'ya eklenmez. Her biri önceki hataları veya veri erişimini
denetlediğinden topluca silinmedi. `archive/` eski yedektir, aktif test değildir.

`tools/refactor/organize_workspace.py` geçmişte bir kere uygulanmış taşıma
betiğidir; eski dosya adlarını içerir, günlük test çalıştırıcısı değildir.
