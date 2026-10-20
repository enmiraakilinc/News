# 1.14.11 hazırlığı (2055)

Yayın notu: “Görünüm ve kararlılık iyileştirmeleri.”

- Metin gönderimi, sunucu onayı beklerken yazma alanını ve gönder düğmesini kilitlemez. Metin hemen temizlenir; önceki mesajın onayı gelmeden sonraki mesaj gönderilebilir. Aynı boş taslağa çift dokunma ikinci bir kayıt oluşturmaz.
- Her gönderim kendi metnini, zamanlamasını ve yanıt bağlamını yakalar. Geç gelen başarı yeni taslağı silmez. Hatalı gönderimler sohbet ekranında ayrı yeniden deneme satırında tutulur; diğer mesajların onay sırası veya yeni taslak etkilenmez. Bekleyen mesajlar için mevcut Firestore yerel kuyruğu kullanılır; sunucu onayı alınmadan iletildi denmez.
- Özel sohbet, yeni mesaj/tepki/okundu olayında son 100 mektubu yeniden çözmek yerine yalnızca yeni/değişen şifreli içerikleri çözer. Akışa ait önbellek, kayıt silinince ve gizli kelime değişince temizlenir. Değişen içerik yine ayrı iş parçacığında çözülür.
- Özel mektuplarda sunucu zamanı henüz oluşmamış yerel kayda “İletildi” yerine “Gönderiliyor” gösterilir.
- Metin akışı iyileştirmesi gerçek ağ gecikmesini ortadan kaldırmaz; sunucu onayı ve alıcıya ulaşma bağlantıya bağlıdır. Medya yüklemesi, dosya boyutu sınırı ve saklama süresi değişmez.
- Analyzer sorunsuz. Art arda gönderim, sıra dışı onay/hata, özgün yanıt bağlamıyla yeniden deneme ve artımlı çözümleme testleri geçti. Gerçek telefon ağında gecikme ölçümü yapılmadı; 55 test geçti. İmzalı APK oluşturuldu; sürüm 1.14.11 / 2055 ve önceki sürümle aynı imza doğrulandı. GitHub yayını ile uygulama içi güncelleme kaydı etkinleştirildi; indirilen yayın dosyasının SHA-256 ve boyutu yerel APK ile eşleşti.
