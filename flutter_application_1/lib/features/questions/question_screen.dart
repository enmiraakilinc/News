// Günün sorusunu ve iki cevabı gösterir.
import 'dart:async';
import 'package:flutter/material.dart';
import '../pair/couple_service.dart';
import '../pair/badge_service.dart';
import '../../core/notifications/notif_prefs.dart';
import '../pair/paired_gate.dart';

/// Her gün değişen, ikinizin de cevaplayacağı sorular.
const List<String> kSorular = [
  "Çocukken doğru sandığın ama sonradan değişen bir fikrin neydi?",
  "Küçükken ailenden öğrendiğin ve hâlâ kullandığın bir alışkanlık var mı?",
  "Çocukken zorlanıp bugün kolayca yapabildiğin bir şey ne?",
  "Bir yolculukta planların bozulsa, ilk neye göre karar verirsin?",
  "Hayatındaki en cesur kararın neydi?",
  "Birlikte gitmek istediğin bir yer neresi?",
  "Birlikte öğrenmeye başlasak, ilk haftada neyi üretmek isterdin?",
  "Sence 5 yıl sonra neredeyiz?",
  "Hayalindeki ev nasıl bir yer?",
  "Birlikte yaşarken işlerin adil paylaşıldığını hangi ölçüte göre anlarsın?",
  "Beraber bir iş kursak ne olurdu?",
  "Çocuğumuz olsa ona ne öğretmek isterdin?",
  "Yıllar sonra bugünü nasıl hatırlamak istersin?",
  "Bir kararını dışarıdan izleyebilseydin, kendine hangi soruyu sorardın?",
  "Bir hafta izin olsa nereye kaçardık?",
  "Bir sorunu çözmek için tek bir kuralı değiştirebilseydin, hangi kuralı seçerdin?",
  "Bir gün boyunca ben olsan ne yapardın?",
  "Bir zaman makinen olsa nereye giderdin?",
  "Bir günlüğüne bütün insanların seni dinleyeceğini bilsen ne söylemek isterdin?",
  "Bir hayvan olsan hangisi olurdun?",
  "Beraber bir hayvan besleyecek olsak ne olurdu?",
  "Bir sabah uyanıp her şeyi değiştirebilsen ne değişirdi?",
  "Sana göre mükemmel bir pazar günü nasıl geçer?",
  "Bir yemeği birlikte yeniden tasarlasak, hangi malzemeyi kesinlikle çıkarırdın?",
  "Beni tanıyan biri, hangi küçük ayrıntımdan hemen anlar?",
  "En sevdiğin şehir hangisi, neden?",
  "Hava planını bozduğunda günü kurtarmak için ne yaparsın?",
  "En sevdiğin sabah rutini ne?",
  "Günün en enerjik saatinde genellikle hangi işi erteliyorsun, neden?",
  "Dinlenirken yalnız kalmak mı, sevdiğin biriyle vakit geçirmek mi sana daha iyi gelir?",
  "Günün başında planın bozulursa kendini yeniden nasıl toparlarsın?",
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

final DateTime kQuestionScheduleStart = DateTime(2026, 11, 7);

int? questionIndexForDate(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final start = DateTime.utc(
    kQuestionScheduleStart.year,
    kQuestionScheduleStart.month,
    kQuestionScheduleStart.day,
  );
  final index = day.difference(start).inDays;
  return index >= 0 && index < kSorular.length ? index : null;
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

class _QuestionView extends StatefulWidget {
  final String coupleId;
  final String secret;
  const _QuestionView({required this.coupleId, required this.secret});

  @override
  State<_QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends State<_QuestionView> {
  DailyAnswers? _cached;
  bool _seen = false;

  @override
  void initState() {
    super.initState();
    CoupleService.readCachedTodayAnswers().then((value) {
      if (mounted && value != null) setState(() => _cached = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final qIndex = questionIndexForDate(DateTime.now());
    if (qIndex == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Günün Sorusu')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Günlük soru listesi tamamlandı.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
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
        stream: CoupleService.todayAnswersStream(
          widget.coupleId,
          widget.secret,
          qIndex,
        ),
        builder: (context, snap) {
          final live = snap.data;
          final data = live == null
              ? (_cached ?? DailyAnswers())
              : (live.myAnswer == null &&
                    live.partnerAnswer == null &&
                    _cached != null &&
                    (_cached!.myAnswer != null ||
                        _cached!.partnerAnswer != null))
              ? _cached!
              : live;
          if (data.myAnswer != null && data.partnerAnswer != null && !_seen) {
            _seen = true;
            unawaited(BadgeService.markQuestionSeen());
            unawaited(CoupleService.markQuestionSeen());
          }
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
