# Neural Haber çalışma alanı

Projede neyin nerede olduğunu öğrenmek için: **[Ayrıntılı Türkçe dosya ve klasör rehberi](docs/DOSYA_REHBERI.md)**.

Flutter uygulaması: `flutter_application_1/`. Kaynaklar `lib/app`, `lib/core` ve `lib/features` altında özelliklere ayrılmıştır. Ayrıntılar: [Mimari ve veri sınırları](docs/ARCHITECTURE.md).

Çalışma alanı kökünden:

```powershell
cd flutter_application_1
flutter analyze
flutter test
cd ..
./tools/releases/build.ps1
```

Sürüm ve kod yalnızca `pubspec.yaml` içinde güncellenir. Derleme aracı imzayı, ARM64 mimarisini ve sürümü doğrular; APK ile raporu `artifacts/releases/<sürüm>/` altına koyar. Her sürüm için ayrı betik oluşturulmaz.

Kullanıcı yayın onayı verdikten sonra:

```powershell
python tools/releases/publish.py --version 1.14.24 --publish
```

Bu araç, yüklenen APK'nın hash/boyutunu doğrular ve uygulama içi güncelleme kaydını günceller. Firestore kurallarını değiştirmez. Aktif kurallar kökteki `firestore.rules` dosyasındadır; birleştirilmiş yerel emülatör ayarı `tools/testing/firebase.json` dosyasındadır.

Eski APK ve raporlar `artifacts/releases`, dahili sürüm notları `docs/releases`, eski betikler `archive`, yerel anahtarlar ve kullanıcı yedekleri `private` altındadır. `archive`, `artifacts` ve `private` Git'e dahil edilmez. Aktif yönetim araçları `tools/admin` altındadır ve çalışma alanı kökünden çalıştırılır.

Taşıma kayıtları ve kaynak yedeğinin konumu: [Mimari](docs/ARCHITECTURE.md). Mevcut editör ayarları, geliştirme ortamları ve uygulamanın cihazdaki kayıtları korunmuştur.
