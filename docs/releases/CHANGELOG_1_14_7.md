# 1.14.7 — APK oluşturuldu (2051)

- Fotoğraf, video ve dosyalarda 20 MiB sınırı. Dosyalar mesaj belgelerine gömülmez; 450 KiB parçalarla aktarılır ve yalnızca tıklanınca indirilir. Özel eşleşmenin dosya içeriği gizli kelimeyle şifrelenir; dosya adı da açık metadata içinde tutulmaz.
- Ek parçalarının sunucu üzerinden okunması 48 saat sonra engellenir. Fiziksel silme uygulama başlangıcında ve Android arka plan görevinde yapılır. Uygulamalar hiç çalışmazsa sunucuda fiziksel silmenin tam 48. saatte gerçekleşmesi garanti edilmez. Ücretsiz paket korunur.
- Normal mesajlarda açılma saati sunucu tarafından belirlenir; cihaz saat farkı yüzünden zamanlanmış gibi beklemez. Mektup çözme işlemi arayüzden ayrı çalışır.
- Kodlar sunucu saatiyle bir saat geçerlidir. Yapıştırılan kodlardaki boşluk ve tireler normalize edilir. Sohbet hesabı da yeni anonim hesap açılmadan önce mevcut oturumun geri yüklenmesini bekler.
- Kişi kayıt adları cihazda saklanır. Kodu kabul ederken veya yeni sohbet ilk açılırken kişi adı sorulur. Sohbet başlığında ve gelen mesajlarda bu ad kullanılır; karşı cihazın kayıt adı değişmez.
- Profil fotoğrafı/emoji her zaman değiştirilebilir. Karşı tarafın avatarına dokununca fotoğraf büyütülür.
- Sohbet listesinde ve sohbetler kartında canlı +N rozeti. Bildirim metni ve telefon bildirimi ayarları gizli kelime gerektirmez. Telefon bildirimleri Android arka plan kontrolüne bağlıdır; anlık kapalı-uygulama push altyapısı eklenmedi.
- Konum izni ve yakın tarihli konum alma akışı düzeltildi. Dış servise konum gönderilmez. Yaklaşık 206 KB Natural Earth haritası uygulamanın içinde bulunur; paylaşılan nokta gösterilir, sokak ayrıntısı ve yol tarifi bulunmaz. Paylaşım bir saatlik sabit konumdur.
- Haberler üçten yediye çıkarıldı. Eski haberlerin yorum kimlikleri korundu.
- Mesaj gönderirken klavye odağı korunur; gönderim sürerken yapılan taslak değişiklikleri silinmez. Klavye açıkken yazma kutusu en fazla üç satır olur ve ek bilgi satırı gizlenir. Sohbet düzeninde klavye boşluğunu yazma çubuğu yönetir.

## Yapılan sunucu temizliği

- Kullanıcının seçtiği eşleşmede 31 Ağustos 2026 00:00 Türkiye saatinden önceki 134 mektup silindi; 138 mektup korundu. Şifreli yerel kurtarma kopyası kaynak kontrolünden hariç tutuldu.
- İki günden eski 15 normal sohbet ekinin gömülü içeriği kaldırıldı, mesaj yerleri korundu. Yaklaşık 2 MB boşaldı. Gizli resimler ve anılar değiştirilmedi.
- Son belge boyutu tahmini: 19.065.282 bayt, yaklaşık 18,2 MiB. İndeksler, yedekler ve diğer hizmetler bu tahmine dahil değildir; tam Monitoring metriğine erişim 403 döndü.

## Doğrulama

- Flutter analyzer: sorun yok.
- 39 Flutter testi geçti; gönderimde klavye odağı/taslak korunması, klavyeli sohbet yerleşimi, tam 20 MiB şifreli dosyanın 46 parçada geri çözülmesi, profil önizlemesi/güncellemesi, cihaz kayıt adları, saat farkında okunmamış mesaj sayımı ve haritanın HTTP isteği yapmaması dahil.
- Yayınlanan Firestore kuralları sentetik hesaplarla sınandı: 400 KiB üstü aktarım, 20 MiB sınırı, yetkisiz/eksik/süresi dolmuş parçaya erişim, temizlik sorguları, özel alan izolasyonu, saat farkında geçerli davet ve kullanılmış/süresi dolmuş davetin reddi. Sentetik kayıtlar ve hesaplar temizlendi.
- Release APK derlemesi başarılı (Flutter 3.44.8). Sürüm 1.14.7 / 2051; önceki sürümle aynı yayın sertifikası doğrulandı. Güvenlik ayarları değiştirilmedi. Gerçek telefon/emülatör testi yapılmadı.

## Yeni haber kaynakları

- [SPHEREx — 8 Ekim 2026](https://www.nasa.gov/missions/spherex/nasas-spherex-telescope-sees-menagerie-of-brown-dwarfs/)
- [Curiosity — 6 Ekim 2026](https://www.nasa.gov/missions/mars-science-laboratory/curiosity-rover/nasas-curiosity-rover-catches-stunning-martian-dawn/)
- [Roman — 30 Ağustos 2026](https://www.nasa.gov/news-release/nasas-dark-universe-seeking-nancy-grace-roman-space-telescope-launches/)
- [DART — 6 Mart 2026](https://www.nasa.gov/missions/dart/nasas-dart-mission-changed-orbit-of-asteroid-didymos-around-sun/)
- [Çevrimdışı harita: Natural Earth, public domain](https://www.naturalearthdata.com/about/terms-of-use/)
