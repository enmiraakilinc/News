# Neural Haber — dosya ve klasör rehberi

Bu belge uygulamayı kod yazarak geliştirmeye yeni başlayan biri için hazırlanmıştır. Dosya adlarını VS Code'da `Ctrl+P` ile aratabilirsin. Buradaki yollar, aksi söylenmedikçe `cosok` klasörüne göredir. Son kontrol: 17 Ekim 2026.

## 1. Düzen nasıl? Önce burayı oku

Aktif Flutter kaynakları artık özelliklerine göre ayrılmış durumda. Genel yapı düzenli: uygulama başlangıcı `app`, ortak parçalar `core`, kullanıcı özellikleri `features` altında. Bu, her dosyanın yalnızca tek küçük iş yaptığı anlamına gelmez. Özellikle sohbet, medya, arama ve eşleşme servisleri hâlâ geniş kapsamlıdır; tek bir özellik değişince birkaç dosyaya dokunmak gerekebilir.

En sık kullanacağın yer: **`flutter_application_1/lib/features/`**.

- Ekrandaki yazı, düğme, görünüm: genellikle `_screen.dart`, `_page.dart` veya `_widgets.dart`.
- Verinin kaydı, okunması, sunucu işlemleri: genellikle `_service.dart` veya `_repository.dart`.
- Telefonun Android davranışı: `android/` içindeki Kotlin ve manifest dosyaları.
- Uygulama kapalıyken sunucunun yapacağı iş: `free-wakeup-worker/`.
- Eski kopyalar: `archive/`; geliştirme burada yapılmaz.

Dosyalar taşındı. Örneğin eski `lib/wakeup_service.dart` yerine `lib/features/wakeup/wakeup_service.dart`, eski `lib/news_notes.dart` yerine `lib/features/news/news_notes.dart` kullanılır. Eski konumda açık bir editör sekmesini kaydetmek eski dosyayı yeniden oluşturabilir. Kendi kaydedilmemiş değişikliğin yoksa eski sekmeyi kaydetmeden kapat ve yeni dosyayı aç.

## 2. En üstteki klasörler

| Klasör / dosya | İçinde ne var? Ne zaman kullanılır? |
|---|---|
| `flutter_application_1/` | Telefon uygulamasının asıl Flutter projesi. Ekranlar, Android kodu, testler ve paketler burada. |
| `free-wakeup-worker/` | Cloudflare üzerinde çalışan bildirim, arama ve uyandırma sunucu kodu. Flutter uygulamasından ayrı yayınlanır. |
| `tools/` | Bilgisayarda çalışan derleme, yayın, bakım ve geçmiş taşıma araçları. Telefona ekran olarak eklenmezler. |
| `docs/` | Bu rehber, mimari açıklamalar ve sürüm notları. |
| `artifacts/releases/` | Hazırlanmış APK'lar ve derleme raporları; her sürüm ayrı klasörde. APK burada bulunuyor diye yayınlanmış sayılmaz. |
| `archive/` | Eski kaynak yedekleri, eski betikler, eski kural kopyaları ve kayıtlar. Aktif kod değildir. Dart analizi dışında tutulur. |
| `private/` | Yerel kimlik bilgileri, özel yedekler ve kişisel dosyalar. İçeriği paylaşılmaz, Git'e eklenmez. |
| `assets/`, `photo/` | Çalışma alanındaki görsel/dosya kaynakları. Buradaki her dosyanın uygulamada kullanıldığı varsayılmamalı; Flutter'ın paketlediği dosyaları `pubspec.yaml` belirler. |
| `.vscode/` | Bu çalışma alanının VS Code ayarları. Arşivi analiz dışında tutma ayarı da burada. |
| `.idea/` (proje içinde) | Android Studio / IntelliJ editör ayarları. |
| `.github/` | GitHub ile ilgili proje yapılandırmaları için ayrılmış dizin. |
| `.claude/`, `.mcp.json` | Geliştirme asistanı / araç bağlantısı yapılandırmaları; uygulama ekranları değildir. |
| `.git/` | Sürüm geçmişinin iç verileri. Elle düzenlenmez. Proje içinde ayrıca bir `.git` dizini de var; Git komutunu hangi klasörden çalıştırdığına dikkat et. |
| `.venv/` | Python bakım araçlarının yerel çalışma ortamı; uygulama kaynak kodu değildir. |
| `.gitignore` | Hangi dosyaların Git'e alınmayacağını belirler. |
| `firestore.rules` | Sunucudaki verileri kimin okuyup yazabileceğini tanımlayan aktif kural kaynağı. Yerel düzenleme tek başına canlı kuralları değiştirmez. |
| `tools/testing/firebase.json` | Aynı içerikteki üç eski yapılandırmanın birleştirildiği yerel Firebase emülatörü ayarı. Canlı uygulama verisi değildir. |
| `README.md` | Kısa başlangıç ve derleme/yayın yönlendirmesi. |

## 3. Flutter projesinin kökü

| Yol | Açıklama |
|---|---|
| `lib/` | Uygulamanın Dart kaynak kodu. Ayrıntılı haritası aşağıda. |
| `test/` | Özelliklerin beklenen davranışlarını kontrol eden testler. Kullanıcının gerçek kayıtları burada tutulmaz. |
| `assets/` | Uygulamanın kullanacağı yerel içerikler. Kullanımı `pubspec.yaml` üzerinden tanımlanır. |
| `android/` | Android izinleri, paket adı, Kotlin kodu, simgeler ve derleme ayarları. |
| `ios/`, `macos/`, `windows/`, `linux/`, `web/` | Diğer platformların proje dosyaları. Mevcut Android sürümünün hazırlanması bu platformlarda çalıştığı anlamına gelmez. |
| `pubspec.yaml` | Paketler, uygulama sürümü ve asset tanımları. `version` sürüm adı ve yapı numarasını içerir. |
| `pubspec.lock` | Çözümlenen paketlerin kesin sürümleri. Paket güncellemesinde değişebilir; elle gelişigüzel düzenlenmez. |
| `analysis_options.yaml` | Dart kod analizi ve kod yazım kuralları. |
| `devtools_options.yaml` | Flutter geliştirme araçlarının ayarları; uygulamanın kullanıcı ayarları değildir. |
| `.metadata`, `.flutter-plugins-dependencies` | Flutter'ın proje/eklenti bilgileri. İkincisi araçlar tarafından üretilir. |
| `build/` | Derleme sırasında oluşan çıktılar. Buradaki kaynak kopyaları düzenlenmez. |
| `.dart_tool/` | Dart/Flutter'ın ürettiği paket ve araç önbelleği. Elle kod yazılacak yer değildir. |
| `flutter_application_1.iml` | IntelliJ/Android Studio proje tanımı. |

## 4. Başlangıç ve ortak kod: `lib/main.dart`, `app`, `core`

Aşağıdaki yollar `flutter_application_1/lib/` içindedir.

| Dosya | Görevi |
|---|---|
| `main.dart` | Uygulamanın küçük giriş noktası. Eski kurulumlardaki WorkManager görevlerinin bulabilmesi için `callbackDispatcher` girişini de korur; bu adı gelişigüzel değiştirme. |
| `app/app_shell.dart` | Uygulamanın ana kabuğu, genel tema ve ekran kökü. |
| `app/app_runtime.dart` | Başlatma, ortak gezinme anahtarı, bildirim altyapısı ve arka plan görevlerinin koordinasyonu. |
| `core/theme/app_theme.dart` | Uygulamanın genel renk temaları. Love/Turuncu gibi tema değişikliklerinde ilk bakılacak yer. |
| `core/theme/chat_theme.dart` | Sohbete özgü görünüm ve tema yardımcıları. |
| `core/theme/news_theme.dart` | Haberler için bağımsız, kalıcı tema tercihi ve tema seçimi. Yan menüdeki Tema seçeneğiyle değiştirilir; gizli bölümün temasını değiştirmez. |
| `core/security/secure_screen.dart` | Hassas ekranlarda ekran görüntüsü koruması için ortak yapı. Android tarafındaki korumayla birlikte değerlendirilir. |
| `core/security/feature_access.dart` | Kamera, mikrofon, konum gibi özelliklerin uygulama içi erişim/izin yönetimi. Sistem izniyle uygulama içi tercih aynı şey değildir. |
| `core/notifications/notif_prefs.dart` | Özellik bazında bildirim tercihleri, açma/kapama kontrolleri ve ilgili ortak arayüzler. |
| `core/notifications/notification_permission.dart` | Sistem bildirim iznini gerektiği anda isteme/yönlendirme. |
| `core/notifications/incoming_call_settings.dart` | Gelen aramaya ait bildirim/izin ayarları. |
| `core/utils/user_errors.dart` | Teknik hataların kullanıcıya anlaşılır metinlerle gösterilmesi. |
| `core/utils/sync_state.dart` | Senkronizasyon durumunun ortak yönetimi. |
| `core/utils/refresh_stream.dart` | Yenileme/akış yardımcıları. |
| `core/utils/search_text.dart` | Türkçe harf farklarını tolere eden ortak arama metni normalleştirmesi. |
| `core/widgets/emoji_picker.dart` | Yeniden kullanılan emoji seçimi arayüzü. |
| `core/widgets/date_input.dart` | Elle tarih girişinin biçimlendirilmesi ve tarih alanı yardımcıları. |

## 5. Özellikler: `lib/features/`

Bu bölümdeki yollar `flutter_application_1/lib/features/` içindedir. Aynı klasördeki ekran ve servis genellikle birlikte çalışır.

### Giriş, hesap ve ortak alan

| Dosya | Görevi |
|---|---|
| `startup/startup_gate.dart` | Açılış hazırlığını kontrol eden yükleme/giriş geçidi. Açılışta takılma veya boş ekran için bakılacak yerlerden biri. |
| `home/entry_screen.dart` | Başlangıç/giriş ve genel bölümün ekran bağlantıları. |
| `home/private_home.dart` | Gizli bölümün ana ekranı ve özellik kartları. |
| `account/chat_account.dart` | Kişisel sohbet hesabının oturum ve hesap işlemleri. |
| `account/chat_account_screen.dart` | Kişisel hesap giriş/yönetim arayüzü. |
| `pair/couple_service.dart` | Gizli kelimeyle ortak eşleşme, Firebase hazırlığı ve ortak veri/şifreleme işlemlerinin merkezi. Geniş kapsamlı önemli bir servis. |
| `pair/paired_gate.dart` | Ortak eşleşme gerektiren ekranlara giriş kontrolü. |
| `pair/badge_service.dart` | Uygulama içi yeni içerik işareti/sayaç kontrolleri. Telefon simgesi rozetiyle aynı şey değildir. |

### Sohbetler ve kişiler

| Dosya | Görevi |
|---|---|
| `chat/chat_service.dart` | Sohbet verileri, mesaj gönderme/okuma ve ilgili veri işlemleri. |
| `chat/chat_widgets.dart` | Sohbetin tekrar kullanılan görsel parçaları. |
| `chat/message_selection.dart` | Mesajları çoklu seçme, seçimi kapatma ve konuşma sırasıyla panoya kopyalama. |
| `chat/reaction_picker.dart` | İfade bırak menüsü ve hesabın cihazdaki favori emoji listesini düzenleme. |
| `chat/chat_unread.dart` | Okunmamış mesajların kontrolü. |
| `chat/chat_downloads.dart` | Fotoğraf/video indirme isteği ve onay akışı. |
| `chat/search/message_search.dart` | Kişi ve çift sohbetlerinde mesaj/dosya adı araması. Kilitli içerik dışarıda kalır; eski mesajlar 100'erli sayfalarda kullanıcı isteğiyle taranır. |
| `chat/letters_screen.dart` | Mektup/mesaj ekranı ve yazışma arayüzünün ana parçaları. Mesaj kutusu ve klavye davranışında da incelenir. |
| `contacts/contacts_screen.dart` | Sohbet kişileri listesi, kodla kişi ekleme/katılma akışları. |
| `contacts/contact_details_screen.dart` | Kişi/profil ayrıntıları, kişi ayarları ve ilgili menüler. |
| `contacts/contact_names.dart` | Kişinin kendi tarafında verdiği kişi adlarını yönetir. |
| `contacts/shared_contact_label.dart` | Karşı tarafta kullanılan kayıt adı bilgisinin ilgili paylaşım/gösterim parçası. |
| `contacts/profile_avatar.dart` | Profil fotoğrafı/emoji gösterimi ve avatar yardımcıları. |
| `starred/starred_messages.dart` | Mesaj yıldızlama ve yıldızlı mesajlar ekranı/veri işlemleri. |

### Fotoğraf, video, ses ve konum

| Dosya | Görevi |
|---|---|
| `media/chat_media.dart` | Sohbet eklerinin yüklenmesi, okunması, parçalı saklanması ve süre yönetimi. Boyut sınırı değişikliği yalnızca buradan ibaret değildir; sunucu kuralları da kontrol edilir. |
| `media/message_content.dart` | Mesaj içeriğini türüne göre gösterme: metin, medya ve ilgili içerikler. |
| `media/media_viewer.dart` | Fotoğraf/video için uygulama içi görüntüleyici. |
| `media/full_image_screen.dart` | Tam ekran fotoğraf gösterimi ve ilgili fotoğraf aksiyonları. |
| `media/media_names_screen.dart` | Gönderilecek medyaya isim/açıklama verme ekranı. |
| `media/camera_capture_screen.dart` | Uygulama içi kamera, fotoğraf/video çekimi ve kamera yaşam döngüsü. |
| `media/image_util.dart` | Görsel boyutlandırma/sıkıştırma yardımcıları. Her görselin aynı kalitede saklandığı varsayılmamalı. |
| `media/video_parts.dart` | Video parçalara ayırma işleminin Dart–Android bağlantısı. Güncel 100 MiB tek mesaj gönderimiyle aynı işlem değildir. |
| `media/chat_audio_player.dart` | Sohbette ses oynatma ve oynatıcı kontrolleri. |
| `voice_notes/voice_notes_screen.dart` | Ortak alandaki sesli notlar ekranı; sohbet ses oynatıcısından ayrı. |
| `location/location_share.dart` | Konum paylaşımı ve ilgili veri/izin işlemleri. |
| `location/offline_location_map.dart` | Dış harita servisine konum göndermeden konumun uygulama içindeki gösterimi. |

### Aramalar, alarm ve hatırlatıcı

| Dosya | Görevi |
|---|---|
| `calls/voice_call.dart` | Sesli/görüntülü arama akışı, WebRTC bağlantısı ve arama arayüzü. |
| `calls/call_background.dart` | Arama olaylarının arka plandaki işlenmesi ve yerel Android bağlantıları. |
| `wakeup/wakeup_service.dart` | Karşı tarafı uyandırma ayarları, izin/onay ve uyandırma sunucusu bağlantısı. |
| `reminders/reminder_service.dart` | Kişisel nota tarih-saat seçerek yerel hatırlatıcı kurma, gerekli izinleri isteme ve iptal etme. |

Arama/alarm sorunlarında yalnızca Dart dosyasına bakmak yetmeyebilir: Kotlin servisleri, Android izinleri ve Worker da akışın parçasıdır. Android'in zorunlu sistem göstergeleri uygulama ayarıyla tamamen yok edilemez.

### Haberler, dersler ve diğer ekranlar

| Dosya | Görevi |
|---|---|
| `news/news_screen.dart` | Genel haber sayfası, yan menüsü ve haberle ilgili ayar ekranları. |
| `news/news_notes.dart` | Genel bölümdeki kişisel görsel/sesli notlar ve bunlara ait işlemler. |
| `study/course_screen.dart` | Ortak dersler ve kişisel dersler için klasör/not ekranları; kod kopyalama, görsel ve hatırlatıcı işlemleri. |
| `study/course_repository.dart` | Ders klasörlerinin/notlarının veri modelleri ve saklanması: ortak alan Firebase, kişisel alan cihaz dosyaları. |
| `study/course_folder_color.dart` | Ders ve konu klasörleri için hazır renk paleti ve renk seçme düğmesi. |
| `study/course_search_screen.dart` | Ders ve konu klasörleri içindeki not/kod/başlıklarda arama ekranı. |
| `study/course_note_text.dart` | Ders notu ve duyurularında seçilebilir metin; dokunarak HTTP/HTTPS bağlantısı açma ve anlaşılır bağlantı hataları. |
| `study/course_video.dart` | Ders videoları: bir haftalık erişim, kişisel yerel dosya veya çifte özel şifreli parçalar; uygulama içi oynatma için okuma ve temizlik. |
| `media/photo_gallery.dart` | Sohbet fotoğraflarında sağa/sola kaydırmalı, yakınlaştırmalı korumalı görüntüleyici. Yalnızca görüntülenen fotoğrafı yükler. |
| `questions/question_screen.dart` | Günün sorusu ekranı ve ilgili soru/cevap akışı. |
| `timeline/timeline_screen.dart` | Anılar/zaman çizelgesi ekranı. |
| `wishes/wishes_screen.dart` | Ortak dilekler ekranı. |
| `counter/counter_page.dart` | Gün/tarih sayacı ekranı. Tarih girişinin ortak parçası `core/widgets/date_input.dart` içindedir. |
| `games/sudoku_screen.dart` | Genel bölümdeki Sudoku oyunu. |
| `tools/tools_screen.dart` | Yardımcı/genel araç ekranları. Bilgisayardaki kök `tools/` klasörüyle karıştırma. |
| `tools/recipe_screen.dart` | Tarif ekranı. |
| `settings/app_settings_screen.dart` | Uygulama ayarları ekranı. İlgili ortak izin/bildirim kodlarını kullanır. |
| `storage/storage_monitor.dart` | Depolama durumunu/uyarılarını uygulamada takip etmeye yönelik işlemler. Kesin bulut kullanımının tamamı sadece telefondaki sayaçtan anlaşılmaz. |
| `updates/update_service.dart` | Yeni sürüm bilgisi kontrolü ve güncelleme işlemleri. |
| `updates/update_dialog.dart` | Güncelleme penceresinin görünümü ve yazıları. |

## 6. Android tarafında hangi dosya ne yapıyor?

Kotlin dosyaları `flutter_application_1/android/app/src/main/kotlin/com/melek/stargaleri/` içindedir.

| Dosya | Görevi |
|---|---|
| `MainActivity.kt` | Flutter ekranıyla Android arasında köprü; MethodChannel çağrılarını Android işlemlerine bağlar. |
| `VoiceCallSupport.kt` | Arama sırasında Android ses yönlendirme/arka plan desteği ve ilgili yerel işlemler. |
| `IncomingCallActivity.kt` | Gelen arama için Android ekranı. |
| `WakeAlarmService.kt` | Alarmın çalışmasını ve sesini yöneten Android servisi. |
| `WakeAlarmActivity.kt` | Tam ekran alarm/hatırlatma ve kapatma ekranı. |
| `LocalReminders.kt` | AlarmManager ile yerel hatırlatıcı planlama/iptal; yeniden başlatma sonrası planların kurulması ve alıcılar. |
| `VideoParts.kt` | Android tarafında video bölme işlemleri. |

`android/app/src/main/AndroidManifest.xml`: izinler, Activity/Service/Receiver kayıtları. Bir Dart özelliği eklenip Android kaydı unutulursa cihazda çalışmayabilir.

`android/app/src/main/res/`: açılış arka planı, Android stilleri ve farklı ekran yoğunluklarındaki simgeler. `values-night` karanlık sistem görünümüne, `values-v31` Android 12 ve üstü açılış davranışına özel kaynaklar içerir.

`android/` içindeki Gradle dosyaları: Android derleme sürümleri, paket/SDK ayarları, küçültme ve imzalama bağlantıları. İmza veya paket adını değiştirmen mevcut uygulamanın üzerine güncelleme yüklenmesini bozabilir. Yerel anahtar dosyalarını belgeye veya Git'e kopyalama.

## 7. Sunucu: `free-wakeup-worker/`

| Dosya | Görevi |
|---|---|
| `worker.mjs` | Worker'ın ana HTTP isteklerini karşılayan kodu; kimlik/onay kontrolleri ve bildirim akışının merkezi. |
| `calls.mjs` | Aramaya ait sunucu işlemleri. Görüşme videosunun kaydı anlamına gelmez. |
| `account_login.mjs` | Kişisel hesap girişine ait sunucu işlemleri. |
| `storage.mjs` | Depolama/bakım tarafındaki Worker yardımcıları. |
| `wrangler.toml` | Cloudflare Worker yapılandırması ve zamanlanmış görev ayarları. Gizli anahtarlar buraya düz metin yazılmaz. |
| `worker.test.mjs` | Worker'ın temel davranış testleri. |
| `background.test.mjs` | Arka plan akışlarının testleri. |
| `account_login.test.mjs` | Hesap giriş testleri. |
| `schedule.test.mjs` | Zamanlama/bakım testleri. |
| `rules.test.mjs` | Firestore erişim kurallarının yerel emülatör testleri. |
| `dry-run-output/`, `dry-run-1.14.17/` | Önceki hazırlık/derleme çıktıları. Aktif kaynak değişikliği burada yapılmaz. |
| `README.md` | İlk kurulumun tarihsel açıklamaları. İçindeki eski sürüm/kurulum komutları güncel düzenle birebir örtüşmeyebilir; güncel dosya yolları için bu rehberi kullan. |

APK yayınlamak Worker'ı otomatik güncellemez. Worker yayınlamak da telefondaki eski APK kodunu değiştirmez. Firestore kuralları üçüncü, ayrı bir yayın unsurudur.

## 8. Bilgisayarda kullanılan araçlar

| Dosya / klasör | Görevi |
|---|---|
| `tools/releases/build.ps1` | Sürümü `pubspec.yaml` üzerinden okuyup küçültülmüş ARM64 Release APK hazırlar; imza/mimari/sürüm kontrolleriyle rapor üretir. |
| `tools/releases/publish.py` | Onay sonrası APK yayınlar, doğrular ve uygulama içi güncelleme kaydını günceller. Çalıştırmak canlı sürümü etkileyebilir. |
| `tools/telegram-cloud-bot/` | Mevcut Telegram hesabına bağlanmış çoklu proje/görev/geçmiş temizleme botu ve kimlik doğrulamalı PC ajanı. Kullanım, ücretsiz sınırlar ve henüz bağlı olmayan AI/emülatör özellikleri kendi README dosyasında. |
| `tools/admin/firebase_config.py` | Yönetim betiklerinin ortak Firebase ayarları/yerel kimlik bilgisi bağlantısı. |
| `tools/admin/google_owner_session.py` | Yetkili Google oturumunu kullanan yönetim yardımcıları. |
| `tools/admin/audit_server_storage.py` | Sunucu depolama/veri durumunu inceleme aracı. |
| `tools/admin/check_storage_metric.py` | Depolama ölçümlerini kontrol etme aracı. |
| `tools/admin/cleanup_expired_chat_attachments.py` | Süresi geçmiş sohbet eklerini temizleme aracı; gerçek veri silebilir. |
| `tools/admin/find_requested_video.py` | Belirli videoyu incelemek/bulmak için hazırlanmış yönetim aracı. |
| `tools/admin/verify_media_access.py` | Medya erişimini kontrol etme aracı. |
| `tools/admin/verify_chat_accounts.py` | Sohbet hesaplarını kontrol etme aracı. |
| `tools/admin/fcm_send.py` | Yetkili FCM bildirim gönderme aracı. Denemek karşı tarafa gerçek bildirim gönderebilir. |
| `tools/admin/repair_firestore_pair.py` | Eşleşme verisini onarma amaçlı yönetim aracı. Normal uygulama kullanımı için çalıştırılmaz. |
| `tools/refactor/organize_dart.py` | Yapılan tek seferlik Dart dosya taşımasının betiği. Düzeni korumak için tekrar çalıştırılmaz. |
| `tools/refactor/organize_workspace.py` | Yapılan tek seferlik çalışma alanı düzenlemesinin betiği. |
| `tools/refactor/dart-path-migration.json` | Dart dosyalarının eski → yeni yol eşlemesi. Bir dosyayı bulamıyorsan buraya bak. |
| `tools/refactor/workspace-path-migration.json` | Diğer taşınan çalışma alanı dosyalarının eski → yeni yol eşlemesi. |
| `tools/__init__.py`, `tools/admin/__init__.py` | Python klasörlerinin paket olarak kullanılmasına yardımcı olan dosyalar. |

Yönetim betiklerinde önce kodun ne yaptığı ve varsa yardım/önizleme seçeneği okunmalıdır. Dosya adında “check” veya “repair” yazması tek başına risksiz olduğu anlamına gelmez. Bu rehber, bakım betiklerini çalıştırma talimatı değildir.

## 9. Testler nerede? Hangi testi açmalıyım?

Hepsi `flutter_application_1/test/` altında. Adı ilgili özelliğe göre seçilir:

| Test | Kapsam |
|---|---|
| `camera_capture_test.dart` | Kamera çekim akışı. |
| `chat_account_test.dart` | Kişisel sohbet hesabı. |
| `chat_delivery_test.dart` | Mesaj gönderim davranışı. |
| `chat_features_test.dart` | Sohbet özellikleri. |
| `chat_polish_test.dart` | Sohbet arayüzü ayrıntıları. |
| `chat_stream_regression_test.dart` | Sohbet veri akışında eski hataların geri gelmemesi. |
| `chat_update_test.dart` | Sohbet güncellemeleri. |
| `chat_widgets_test.dart` | Sohbet bileşenleri. |
| `message_selection_test.dart` | Toplu mesaj seçimi, sıralı kopyalama ve kilitli mesajların seçilememesi. |
| `reaction_picker_test.dart` | İfade menüsünün açılması ve kişisel emoji listesinin korunması. |
| `contact_names_test.dart` | Kişi adlarının ayrı yönetimi. |
| `counter_page_test.dart` | Sayaç ekranı. |
| `course_notes_test.dart` | Ders notları, kişisel/ortak saklama ve kod kopyalama. |
| `date_input_test.dart` | Tarih yazımı/biçimlendirme. |
| `independent_notifications_test.dart` | Özelliklerin bildirim tercihlerinin birbirinden bağımsız olması. |
| `media_polish_test.dart` | Medya arayüzü ayrıntıları. |
| `media_viewer_test.dart` | Uygulama içi medya gösterimi. |
| `message_search_test.dart` | Türkçe arama, kilitli mesajların dışarıda tutulması, dosya adı araması ve isteğe bağlı sayfalama. |
| `message_stars_test.dart` | Mesaj yıldızlama. |
| `news_screen_test.dart` | Haber sayfası ve menüleri. |
| `reminder_permissions_test.dart` | Hatırlatıcı için gerekli izin akışı. |
| `startup_gate_test.dart` | Açılış/yükleme geçidi. |
| `sudoku_and_settings_test.dart` | Sudoku ve ilgili ayar davranışları. |
| `update_dialog_test.dart` | Güncelleme penceresi. |
| `voice_notes_test.dart` | Sesli notlar. |
| `wakeup_settings_test.dart` | Uyandırma tercihleri ve cihaz/kişi ayrımı. |

Test adları başlangıç rehberidir; kesin olarak ne doğrulandığını dosyadaki test açıklamaları söyler. Testlerin geçmesi Samsung telefondaki tüm kamera/arama/bildirim davranışlarının fiziksel cihazda doğrulandığı anlamına gelmez.

## 10. Uygulamadaki veriler kod klasörlerinde mi tutuluyor?

Ders klasörleri konu alt klasörleri içerebilir: örneğin “Program Yapısı ve Anlamı → Tokenizer → Token türleri”. Dersin içindeki **Konu klasörleri** satırından alt klasörlere girilir, **Yeni konu klasörü** ile eklenir. Her seviyede ayrı not/kod/görsel tutulabilir. Ana klasör silinirse alt klasörleri ve notları da silinir. Veri modelindeki `parent` alanı üst klasör kimliğidir; eski, bu alanı olmayan dersler ana seviyede kalır. Ortak alanda da aynı yapı kullanılır ve erişim sınırları korunur.

Hayır. Projedeki `lib/` dosyaları uygulamanın tarifidir; kullanıcı mesajlarının yedeği değildir.

- Ortak alan verileri Firebase/Firestore'da ilgili çiftin alanındadır. Ortak dersler `couples/<çift>/courses/<ders>/entries/` altında, başlık/içerik şifrelenerek tutulur.
- Kodla eklenen sohbet kişisinin sohbet üyeliği, gizli çift alanına erişim sağlamaz.
- Kişisel dersler cihazın uygulamaya özel dizininde, hesap kimliğine göre ayrılır. **Şu anda başka telefona/emülatöre otomatik senkronlanmaz.** Metin/kodlar JSON, görseller ayrı dosyalardır. Uygulama verisini silmek bu yerel notları kaybettirebilir.
- Sohbet ekleriyle ders görsellerinin saklama kuralları farklıdır. Sohbet medyası 48 saatliktir; kişisel ders görselleri kullanıcı silene kadar cihazda kalır.
- Sohbet medyası Firestore'da teknik olarak parçalara ayrılabilir; bu, videonun kullanıcıya birden çok sohbet mesajı olarak gönderilmesi demek değildir.
- Yerel tercihler genellikle SharedPreferences, yerel dosyalar ise telefonun uygulama dizini üzerinden tutulur. Bilgisayardaki `private/` bunların tamamının otomatik kopyası değildir.

## 11. Arşiv ve dokümanların içi

| Yol | Açıklama |
|---|---|
| `archive/refactor/before-feature-folders/` | Klasör düzenlemesi öncesindeki `lib` ve `test` yedeği. Eski import yolları içerir; güncel kod değildir. |
| `archive/refactor/main-before-feature-folders.dart.txt` | Eski büyük `main.dart` dosyasının metin yedeği. |
| `archive/operations/`, `archive/releases/scripts/` | Önceki işlere/sürümlere özel tarihsel betikler. Eski yollar/işlemler içerebilir; güncel yayın araçlarının yerine kullanılmaz. |
| `archive/rules/` | Eski Firestore kural kopyaları/parçaları. Aktif kural kaynağı kökteki `firestore.rules`. |
| `archive/logs/`, `archive/generated/` | Eski çalışma kayıtları ve üretilmiş dosyalar. |
| `archive/analysis_options.yaml` | Arşivdeki Dart yedeklerini aktif kod analizi dışında tutar. |
| `artifacts/releases/<sürüm>/` | O sürümün APK'sı ve derleme raporu. Eski sürümlerin dosya adları farklı olabilir. |
| `private/credentials/` | Yerel yönetim kimlik bilgileri. İçeriği belgelere yazılmaz. |
| `private/backups/` | Özel veri/işlem yedekleri. |
| `private/local-files/` | Yerel kişisel dosyalar ve eski özel çalışma dosyaları. |
| `docs/DOSYA_REHBERI.md` | Okuduğun ayrıntılı, başlangıç seviyesindeki rehber. |
| `docs/ARCHITECTURE.md` | Mimari ve veri sınırlarının kısa teknik özeti. |
| `docs/WORKSPACE.md` | Çalışma alanı/derleme araçları için kısa başvuru. |
| `docs/releases/CHANGELOG_*.md` | Sürümlerin dahili değişiklik notları. Her dosya adına karşılık gelen sürümü anlatır. |
| `docs/project/` | Eski proje dokümanlarının yerel arşivi. |

Arşivdeki her tarihsel dosyayı güncel dosya gibi tek tek açıklamak yanıltıcı olur; hangi aktif dosyaya karşılık geldiğini taşıma kayıtları gösterir. Aynı şekilde üretilmiş binlerce derleme dosyasını düzenlemek yerine onu üreten kaynak düzenlenir.

## 12. “Şunu değiştirmek istiyorum, nereden başlayayım?”

| İstek / sorun | İlk bakılacak yerler |
|---|---|
| Love temasının rengi | `core/theme/app_theme.dart`; sohbete özgüyse `chat_theme.dart` |
| Mesaj gönderirken klavye kapanıyor | `features/chat/letters_screen.dart`, `chat_widgets.dart` |
| Mesaj yavaş gönderiliyor | `features/chat/chat_service.dart`; eklerde `features/media/chat_media.dart` |
| Profil fotoğrafı / kişi adı | `features/contacts/` |
| Günün sorusunun rengi/içeriği | `features/questions/question_screen.dart` |
| Haber menüsüne bir seçenek | `features/news/news_screen.dart` |
| Kişisel not / ders klasörü | `features/news/news_notes.dart` veya `features/study/` |
| Tek tek bildirim kapatma | `core/notifications/notif_prefs.dart`, ilgili özellik ve `app/app_runtime.dart` |
| Alarm tam ekran açılmıyor | `features/wakeup/`, `features/reminders/`, Android alarm dosyaları ve sistem izinleri |
| Arama sesi hoparlörden geliyor | `features/calls/voice_call.dart`, Android `VoiceCallSupport.kt` |
| Kamera kapanıyor | `features/media/camera_capture_screen.dart`, manifest ve fiziksel cihazdaki kaynak kullanımı |
| Açılışta beyaz ekran | `main.dart`, `app/`, `features/startup/startup_gate.dart` |
| Güncelleme penceresi okunmuyor | `features/updates/update_dialog.dart` |
| Video yükleme sınırı | `features/media/chat_media.dart`, `firestore.rules`, ilgili testler |
| APK hazırlamak/yayınlamak | `tools/releases/`; onay olmadan yayın komutu çalıştırılmaz |

## 13. Değişiklik yaparken basit çalışma sırası

1. İlgili özelliğin klasörünü bul. Eski arşiv kopyasını değil, `lib/features/` altındaki güncel dosyayı aç.
2. Değiştirmeden önce mevcut çalışmayı/yedeğini koru. Bir dosyanın adına bakarak gereksiz olduğuna karar verme.
3. Arayüz değişikliği için ekranı, veri davranışı için servisi incele. Gerekirse Android ve sunucu bağlantısını da kontrol et.
4. `flutter_application_1` klasöründe `flutter analyze` çalıştır. Ardından ilgili testi, kapsam genişse `flutter test` çalıştır.
5. Kamera, arama, alarm ve kilit ekranı gibi özellikleri gerçek telefonda da dene.
6. APK derlemek ve canlıya yayınlamak ayrı adımlardır. Sürüm onayı alındıktan sonra yayın yapılır.

Örnek, çalışma alanı kökünden:

```powershell
cd flutter_application_1
flutter analyze
flutter test test/course_notes_test.dart
```

Bu rehber şu anki düzeni anlatır. Yeni bir özellik veya dosya eklendiğinde ilgili tabloya bir satır eklemek, rehberin güncel kalması için yeterlidir.

## Private release repository migration

- `tools/releases/repository.py`: canonical source/APK repository.
- `free-wakeup-worker/release_asset.mjs`: credential-safe APK stream from private GitHub assets.
- `free-wakeup-worker/transition_update.mjs`: pinned 1.14.32-only legacy bootstrap, independently disableable.
- `free-wakeup-worker/transition_update.test.mjs`: public-transition boundary tests.
- `docs/PRIVATE_UPDATES.md`: live deployment and release workflow.

## 1.14.33 ses dosyaları

- lib/features/media/audio_file_types.dart: desteklenen ses uzantıları ve Android MIME türleri.
- lib/features/media/local_audio_dialog.dart: cihazdaki ses dosyasını dinleme ve ileri/geri sarma penceresi; haber notları ve ders notları ortak kullanır.
- lib/features/study/course_video.dart: mevcut şifreli parçalı ders videosu depolaması, artık ders ses dosyalarını da aynı erişim/süre modeliyle saklar.
- docs/releases/1.14.33.md: bu sürümün uygulama ayrıntıları, sınırlamaları ve doğrulamaları.

Bu listede lib/ yolları flutter_application_1/ klasörü içindedir.

## Mikrofon oturumu

Yeni mikrofon servisi, dosyaları, ayar davranışı ve doğrulama sınırları docs/MICROPHONE_SESSIONS.md içinde açıklanır. Bu özellik henüz APK olarak yayımlanmadı.

## Arama kontrolleri ve ses dosyası seçicisi (1.14.34)

- flutter_application_1/lib/features/calls/call_controls.dart: etiketli mikrofon, hoparlör, karşı ses ve kamera düğmeleri.
- flutter_application_1/lib/features/calls/call_audio.dart: yalnızca uzak ses izlerinin sesini açar/kapatır.
- flutter_application_1/lib/features/calls/voice_call.dart: bu kontrollerin WebRTC aramasına bağlanması ve arama ekranı.
- flutter_application_1/android/app/src/main/kotlin/com/melek/stargaleri/AppMessagingService.kt: uyandırma veri mesajını izin denetimleri yapan WakeMessageReceiver alıcısına iletir.
- flutter_application_1/android/app/src/main/kotlin/com/melek/stargaleri/AudioFilesBridge.kt: ders sesleri için Android Birlikte aç seçicisi; dosya alanı, türü ve boyutunu sınırlar.
- flutter_application_1/lib/features/media/local_audio_dialog.dart: derslerde açıkça izin verilen dış oynatıcı seçeneği ve paylaşım onayı.
- flutter_application_1/test/call_controls_test.dart ve test/local_audio_dialog_test.dart: bağımsız arama kontrolleri ve ses dosyası açma onayı testleri.
