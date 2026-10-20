import 'package:flutter/material.dart';
import '../pair/couple_service.dart';
import '../../core/notifications/notif_prefs.dart';
import '../pair/paired_gate.dart';

/// Her gün değişen, ikinizin de cevaplayacağı sorular.
const List<String> kSorular = [
  "Bugün seni en çok ne mutlu etti?",
  "Bugün canını sıkan bir şey oldu mu?",
  "Bugün seni güldüren şey neydi?",
  "Bugünü bir emojiyle anlatsan?",
  "Bugün kendinle gurur duyduğun bir şey?",
  "Bugün beni özledin mi, ne zaman?",
  "Bugün için birbirimize teşekkür etsek, ne için?",
  "Bugün en çok neye şaşırdın?",
  "Bugün kendine nasıl iyi baktın?",
  "Bugün minnettar olduğun üç şey ne?",
  "Bugün en çok neyi ertelemek istedin?",
  "Bugün seni yoran şey neydi?",
  "Bugün kendini nasıl hissettin, tek cümleyle?",
  "Bugün birine iyilik yaptın mı, neydi?",
  "Bugünün en güzel 10 dakikası hangisiydi?",
  "Bugün seni düşündüren bir şey oldu mu?",
  "Bugün öğrendiğin yeni bir şey var mı?",
  "Bugün seni rahatlatan bir an oldu mu?",
  "Bugün bir şeyi başarmış hissettin mi?",
  "Bugün en çok neye güldük?",
  "Bugün en çok neyi merak ettin?",
  "Bugün kendini şanslı hissettin mi, neden?",
  "Bugün seni etkileyen bir söz duydun mu?",
  "Bugün pes etmek istedin mi, neden vazgeçmedin?",
  "Bugün seni gülümseten küçük bir detay?",
  "Bugün en çok neye ihtiyacın vardı?",
  "Bugün nefes aldığın bir an oldu mu?",
  "Bugün bir şeye üzüldün mü?",
  "Bugün küçük bir mutluluk yakaladın mı?",
  "Bugün bana sarılmak istedin mi, ne zaman?",
  "Bugün kendine ne söylemek istersin?",
  "Bugünü bir cümleyle özetlesen?",
  "Bugün seni en çok ne düşündürdü?",
  "Bugün seni şaşırtan bir insan oldu mu?",
  "Bugün en çok neyi kaçırdın?",
  "Bugün bana ne anlatmak istedin ama unuttun?",
  "Bugün kimi aradın, neden?",
  "Bugünün rengi ne olurdu?",
  "Bugün bir şeyi geri alabilseydin ne olurdu?",
  "Bugün hangi anı tekrar yaşamak isterdin?",
  "Bugün kendine bir hediye alsan ne alırdın?",
  "Bugün bana bir söz verecek olsan ne olurdu?",
  "Beni ilk gördüğünde ne düşünmüştün?",
  "İlk buluşmamızı hatırlıyor musun, nasıldı?",
  "İlk mesajımı hatırlıyor musun, ne yazmıştım?",
  "En güzel anımız hangisiydi?",
  "Beni en çok hangi anımızda sevdin?",
  "Sence beni en iyi anladığın an hangisiydi?",
  "Sence ilişkimizin en güçlü yanı ne?",
  "Sence birlikte en iyi kararımız neydi?",
  "Beraber en çok ne yaparken mutluyuz sence?",
  "Sence ilişkimizde neyi daha çok yapmalıyız?",
  "Birlikte izlediğimiz en güzel film hangisiydi?",
  "Şu an yanımda olsan ne yapardık?",
  "Sence en iyi anlaştığımız konu ne?",
  "Seni son ne zaman gerçekten dinlediğimi hissettin?",
  "Bana en çok hangi konuda güveniyorsun?",
  "Seni en çok ne zaman özlüyorum sence?",
  "Beni en çok hangi halimle sevdin?",
  "Sence beni en çok ne değiştirdi?",
  "Beni en çok hangi sözüm etkiledi sence?",
  "Seni en çok ne zaman huzurlu görüyorum sence?",
  "Seni en çok ne zaman özel hissettiriyorum?",
  "Beraber yapmadığımız ama yapmamız gereken ne?",
  "Beraber ilk kez ne yapmalıyız?",
  "Beraber bir gelenek başlatsak ne olsun?",
  "Birlikte bir alışkanlık edinsek ne olsun?",
  "Birlikte öğrenmek istediğin bir şey var mı?",
  "Bir şarkı bize ait olsa hangisi olurdu?",
  "Bir kitap olsak adı ne olurdu?",
  "Beraber bir liste yapsak ilk madde ne olur?",
  "Bende en sevdiğin özellik ne?",
  "Beni bir kelimeyle anlatsan?",
  "Sence beni en iyi tarif eden üç kelime?",
  "Beni bir renk yapsan hangi renk olurdum?",
  "Beni bir yemeğe benzetsen hangisi olurdum?",
  "Beni tarif eden bir şarkı olsa hangisi olurdu?",
  "Bana bir lakap taksan ne olurdu?",
  "Bana bir çiçek verseydin hangisi olurdu?",
  "Beni gülümseten hangi huyum var sence?",
  "Sence beni en iyi ne anlatır: sözlerim mi, halim mi?",
  "Bana bir tavsiye versen ne olurdu?",
  "Bana yazacağın kısa bir not olsa ne yazardın?",
  "Bana teşekkür etmek istediğin bir şey var mı?",
  "Bana kızdığın ama söylemediğin bir şey var mı?",
  "Bana söylemek isteyip de söyleyemediğin bir şey var mı?",
  "Bana sürpriz yapacak olsan ne yapardın?",
  "Bana bir gün ayırsan planın ne olurdu?",
  "Beni en çok ne zaman gururlandırıyorsun?",
  "Sana kendini özel hissettiren neydi?",
  "Seni en çok ne rahatlatıyor?",
  "Seni en çok ne motive ediyor?",
  "Seni en çok ne heyecanlandırıyor?",
  "Seni en çok ne üzer?",
  "Seni en çok kim güldürür?",
  "Seni en çok ne güldürür, saçma bile olsa?",
  "Seni en çok ne zaman güçlü hissediyorsun?",
  "Bir şeyden korkuyorsan, o ne?",
  "Hayatta en çok neye değer veriyorsun?",
  "Sence en romantik an nedir?",
  "En son ne zaman kahkaha attın?",
  "Çocukken hayalindeki meslek neydi?",
  "En sevdiğin çocukluk anın ne?",
  "En sevdiğin çocukluk yemeği ne?",
  "En sevdiğin çocukluk arkadaşın kimdi?",
  "Çocukken en sevdiğin oyun neydi?",
  "En sevdiğin aile anın hangisi?",
  "Hiç unutamadığın bir yolculuk var mı?",
  "En sevdiğin tatil anın hangisi?",
  "Hayatındaki en cesur kararın neydi?",
  "Birlikte gitmek istediğin bir yer neresi?",
  "Gelecekte beraber ne yapmak istersin?",
  "Küçük bir hayalin ne?",
  "Sence 5 yıl sonra neredeyiz?",
  "Hayalindeki ev nasıl bir yer?",
  "Beraber yaşasak evimizde ne olmalı?",
  "Beraber bir iş kursak ne olurdu?",
  "Çocuğumuz olsa ona ne öğretmek isterdin?",
  "Hiç kimseye anlatmadığın bir hayalin var mı?",
  "Hayatında değiştirmek istediğin bir alışkanlık var mı?",
  "Yıllar sonra bugünü nasıl hatırlamak istersin?",
  "Bir yıl sonra bugüne bakınca ne demek istersin?",
  "Bir hafta izin olsa nereye kaçardık?",
  "Bir süper gücün olsa ne olurdu?",
  "Bir gün boyunca ben olsan ne yapardın?",
  "Bir zaman makinen olsa nereye giderdin?",
  "Bir günlüğüne ünlü olsan ne yapardın?",
  "Bir hayvan olsan hangisi olurdun?",
  "Beraber bir hayvan besleyecek olsak ne olurdu?",
  "Bir sabah uyanıp her şeyi değiştirebilsen ne değişirdi?",
  "Sana göre mükemmel bir pazar günü nasıl geçer?",
  "En sevdiğin şarkı hangisi, neden?",
  "En sevdiğin mevsim hangisi, neden?",
  "En sevdiğin yemek hangisi, kim yapınca?",
  "En sevdiğin tatlı hangisi?",
  "En sevdiğin koku hangisi?",
  "En sevdiğin kokun hangisi bende?",
  "En sevdiğin şehir hangisi, neden?",
  "En sevdiğin kitap hangisi?",
  "En sevdiğin dizi karakteri kim, neden?",
  "En sevdiğin hava durumu nasıl?",
  "En sevdiğin oyun ya da hobin hangisi?",
  "En sevdiğin sabah rutini ne?",
  "En sevdiğin gece aktivitesi ne?",
  "En sevdiğin an: sabah mı, gece mi, neden?",
  "Sabah uyandığında aklına ilk ne gelir?",
  "Sence en iyi yaptığın şey ne?",
  "Birlikte bir zaman kapsülü hazırlasak içine hangi üç şeyi koyardın?",
  "İkimizin gelecekteki haline tek bir soru sorabilsen ne sorardın?",
  "Evimizde sadece bize ait bir köşe olsa nasıl düzenlerdik?",
  "Birlikte bir mahalle festivali düzenlesek hangi etkinliği sen üstlenirdin?",
  "Bir gün boyunca telefonlarımız olmasa beraber nasıl vakit geçirirdik?",
  "İkimiz bir bulmaca ekibi olsak hangi konuda sen, hangi konuda ben iyiyiz?",
  "Birbirimize öğretebileceğimiz en beklenmedik beceri ne olabilir?",
  "Birlikte yeni bir yemek icat etsek adını ne koyardık?",
  "Bana kendi şehrinde turist gibi gezdireceğin ilk sokak neresi?",
  "İkimizin kuracağı küçük kütüphanenin ilk beş kitabı ne olurdu?",
  "Bir oyunun kurallarını birlikte yazsak kazanmak için ne yapmak gerekirdi?",
  "Birlikte bir radyo programı sunsak ilk bölümün konusu ne olurdu?",
  "Birbirimiz için bir müze kursak hangi eşyayı sergilerdik?",
  "İkimize bir ay boyunca ücretsiz bir atölye verilse ne öğrenirdik?",
  "Beraber yaptığımız sıradan bir iş nasıl küçük bir eğlenceye dönüşebilir?",
  "Yağmura yakalandığımız bir yürüyüşü nasıl güzel bir anıya çevirirdik?",
  "Birlikte bir gökyüzü olayı izlesek yanımıza neler alırdık?",
  "Bir tren yolculuğunda cam kenarından bana göstermek istediğin manzara ne?",
  "İkimizin tasarlayacağı bir bahçede hangi bitkiler olurdu?",
  "Birlikte bir el işi yapıp saklasak ne yapmayı seçerdin?",
  "Birbirimize hazırlayacağımız gizli görevli bir günün ilk görevi ne olsun?",
  "Bana sevdiğin bir konuyu on dakikada anlatacak olsan hangisini seçersin?",
  "Bir kararı verirken benden nasıl destek görmeyi tercih edersin?",
  "Yoğun bir haftada birbirimize ayırabileceğimiz küçük bir zaman nasıl olsun?",
  "Yorgun olduğunda yanında konuşmam mı, sessizce durmam mı sana iyi gelir?",
  "Bir yanlış anlaşılmayı çözerken işimizi kolaylaştıran şey ne?",
  "Birlikte başarısız olsak bile denemekten keyif alacağımız şey ne olabilir?",
  "Senden öğrenip hayatıma katmamı istediğin bir bakış açısı var mı?",
  "Birbirimizin sınırlarını daha iyi anlamak için neyi konuşabiliriz?",
  "Kutlama yapmak için beklemememiz gereken küçük bir başarımız ne?",
  "İkimizin günlük hayatını kolaylaştıracak minicik bir değişiklik ne olurdu?",
  "Birbirimize birer dinlenme günü hazırlasak neleri üstlenirdik?",
  "Bir anımızın sesini saklayabilsek hangi sesi kaydetmek isterdin?",
  "İkimizin hikâyesini anlatan bir kartpostal çizsen üzerinde ne olurdu?",
  "Yalnızca ikimizin anlayacağı bir işaret tasarlasak neye benzerdi?",
  "Birlikte çektiğimiz bir fotoğrafın görünmeyen hikâyesini anlatır mısın?",
  "Sana verdiğim hangi küçük şeyin beklediğimden büyük bir anlamı oldu?",
  "Birlikte yaşadığımız bir aksilikten bugün gülerek söz edebiliyor muyuz?",
  "İlk kez beraber denediğimiz şeylerden hangisini tekrar denemek istersin?",
  "Birbirimizi daha iyi tanımamızı sağlayan beklenmedik bir an hangisiydi?",
  "İkimize özel bir takvimde hangi küçük günü işaretlemek isterdin?",
  "Birbirimize birer mektup yazıp yıllar sonra açsak ne anlatırdın?",
  "Birlikte bir iyilik projesine katılsak hangi konuda katkı verirdik?",
  "Bir sokak hayvanına yuva hazırlasak görevleri nasıl paylaşırdık?",
  "Çocuklara birlikte bir oyun öğretsek hangi oyunu seçerdik?",
  "Birlikte korumak istediğin bir doğa alanı neresi?",
  "İkimizin de bilmediği bir kültürden hangi geleneği öğrenmek isterdin?",
  "Bir müzik aletiyle birbirimize cevap verebilsek sen hangisini seçerdin?",
  "Birlikte çekeceğimiz kısa filmin ilk sahnesi nasıl başlardı?",
  "İkimiz bir masalın karakteri olsak hangi sorunu birlikte çözerdik?",
  "Bir kaçış odasında hangi ipucunu ilk sen fark ederdin?",
  "Birlikte bir çizgi roman yazsak yan karakterimiz kim olurdu?",
  "Birbirimize sadece çizerek bir günümüzü anlatabilir miydik?",
  "Beş malzemeyle birbirimize yemek hazırlasak neler seçerdik?",
  "Birlikte yeni bir rota keşfederken plan mı, doğaçlama mı tercih edersin?",
  "İkimize bir piknik sepeti hazırlasan içinde alışılmadık ne olurdu?",
  "Sabaha kadar yıldızları izlesek en çok hangi konuyu konuşurduk?",
  "Birlikte bir sergi açsak eserlerimiz hangi malzemeden olurdu?",
  "Birbirimiz için hazırladığımız bir bilmecenin cevabı ne olurdu?",
  "Ortak bir hayalimizin ilk küçük adımını bu hafta nasıl atabiliriz?",
];

int _todayQIndex() {
  final now = DateTime.now();
  final gunSayisi = now.difference(DateTime(now.year, 1, 1)).inDays;
  return gunSayisi % kSorular.length;
}

class QuestionScreen extends StatelessWidget {
  const QuestionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PairedGate(
      title: "Günün Sorusu",
      builder: (cid, sec) => _QuestionView(coupleId: cid, secret: sec),
    );
  }
}

class _QuestionView extends StatelessWidget {
  final String coupleId;
  final String secret;
  const _QuestionView({required this.coupleId, required this.secret});

  @override
  Widget build(BuildContext context) {
    final qIndex = _todayQIndex();
    final soru = kSorular[qIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Günün Sorusu"),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: "Bildirim yazısı",
            onPressed: () => editNotifText(context, kNotifQuestions),
          ),
        ],
      ),
      body: StreamBuilder<DailyAnswers>(
        stream: CoupleService.todayAnswersStream(coupleId, secret, qIndex),
        builder: (context, snap) {
          final data = snap.data ?? DailyAnswers();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text("❓", style: TextStyle(fontSize: 32)),
                      const SizedBox(height: 8),
                      Text(
                        soru,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Senin cevabın
                QuestionAnswerCard(
                  baslik: "Senin cevabın",
                  cevap: data.myAnswer,
                  bosMetin: "Henüz cevaplamadın.",
                  renk: Theme.of(context).colorScheme.primaryContainer,
                  onTap: () => _cevapla(context, data.myAnswer),
                ),
                const SizedBox(height: 12),

                // Gelen cevap — cevapladı mı bilgisi hep görünür,
                // ama METİN yalnızca ikimiz de cevaplayınca açılır.
                QuestionAnswerCard(
                  baslik: "Gelen cevap",
                  cevap: (data.myAnswer != null && data.partnerAnswer != null)
                      ? data.partnerAnswer
                      : null,
                  bosMetin: data.partnerAnswer == null
                      ? "Eşin henüz cevaplamadı."
                      : "Eşin cevapladı ✓ — sen de cevaplayınca görünecek 👀",
                  renk: Theme.of(context).colorScheme.secondaryContainer,
                  onTap: null,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _cevapla(BuildContext context, String? mevcut) async {
    final c = TextEditingController(text: mevcut ?? '');
    final messenger = ScaffoldMessenger.of(context);
    final kaydet = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cevabın"),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 4,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "Cevabını yaz...",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("İptal"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Kaydet"),
          ),
        ],
      ),
    );
    if (kaydet == true && c.text.trim().isNotEmpty) {
      try {
        await CoupleService.setTodayAnswer(c.text.trim());
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }
}

class QuestionAnswerCard extends StatelessWidget {
  final String baslik;
  final String? cevap; // null = kilitli/boş, "__bekliyor__" = özel durum
  final String bosMetin;
  final Color renk;
  final VoidCallback? onTap;

  const QuestionAnswerCard({
    super.key,
    required this.baslik,
    required this.cevap,
    required this.bosMetin,
    required this.renk,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bekliyor = cevap == "__bekliyor__";
    final bos = cevap == null || bekliyor;
    final foreground = renk.computeLuminance() > .179
        ? Colors.black
        : Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: renk,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  baslik,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.edit, size: 16, color: foreground),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              bos ? bosMetin : cevap!,
              style: TextStyle(
                fontSize: 15,
                color: foreground,
                fontStyle: bos ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
