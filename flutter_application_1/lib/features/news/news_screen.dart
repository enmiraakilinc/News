import '../../core/theme/app_theme.dart';
import '../../core/theme/news_theme.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../media/message_content.dart';
import 'news_notes.dart';
import '../games/sudoku_screen.dart';
import '../../core/notifications/notif_prefs.dart';
import '../study/course_screen.dart';
import '../../core/notifications/incoming_call_settings.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Route<T> _newsRoute<T>({required WidgetBuilder builder}) =>
    MaterialPageRoute<T>(
      builder: (_) => NewsThemeScope(child: Builder(builder: builder)),
    );

const _articles = [
  (
    "Bilim",
    "Webb, gezegen çarpışmalarının izlerini araştırdı",
    "James Webb Uzay Teleskobu, genç yıldızların çevresindeki sıcak toz disklerini inceleyerek büyük çarpışmaların izlerini araştırdı. Bulgular, kayalık gezegenlerin oluşumuna yeni bir pencere açıyor.\n\nAraştırmada Webb ve Spitzer verilerinden 21 disk incelendi. Tozun mineral yapısı, bazı sistemlerde daha yüksek enerjili çarpışmalar yaşanmış olabileceğini gösteriyor.\n\nBu gözlemler, Dünya ve Ay’ın erken dönemini anlamaya yardımcı olabilir. Araştırmacılar sonuçları daha fazla sistemle sınamak istiyor.",
    Icons.public,
    "1 Ekim 2026",
    "https://science.nasa.gov/missions/webb/nasas-webb-provides-crash-course-on-planet-shattering-collisions/",
    "assets/news/0.jpg",
  ),
  (
    "Uzay",
    "James Webb’in ilk görüntüleri evrene yeni bir pencere açtı",
    "NASA, James Webb Uzay Teleskobu’nun ilk bilim görüntülerini Temmuz 2022’de yayımladı. Görüntülerde yıldız oluşum bölgeleri, bulutsular ve uzak galaksiler yer aldı.\n\nKızılötesi gözlemler, görünür ışıkta fark edilmeyen ayrıntıların araştırılmasını sağlıyor. Bu sayede bilim insanları yıldızların doğuşunu ve evrenin geçmişini inceleyebiliyor.\n\nİlk görüntüler, uluslararası teleskop programının bilim çalışmalarındaki önemli başlangıç noktalarından biri oldu.",
    Icons.public,
    "12 Temmuz 2022 · Arşiv",
    "https://science.nasa.gov/mission/webb/webbs-first-images/",
    "assets/news/1.jpg",
  ),
  (
    "Keşif",
    "Perseverance, Mars’ta Jezero Krateri’ne indi",
    "NASA’nın Perseverance keşif aracı, 18 Şubat 2021’de Mars’a başarıyla indi. İniş noktası olarak Jezero Krateri seçildi.\n\nGörevin hedefleri arasında Mars’ın geçmiş ortamını araştırmak ve eski mikrobiyal yaşamın olası izlerini incelemek bulunuyor. Araç, bilimsel ölçümlerle birlikte kaya örnekleri toplamak için tasarlandı.\n\nBaşarılı iniş, Mars’ın jeolojik geçmişini daha yakından araştıracak uzun soluklu bir görevin başlangıcı oldu.",
    Icons.public,
    "18 Şubat 2021 · Arşiv",
    "https://www.nasa.gov/news-release/touchdown-nasas-mars-perseverance-rover-safely-lands-on-red-planet/",
    "assets/news/2.jpg",
  ),
  (
    'Bilim',
    'SPHEREx, kahverengi cücelerin atmosferlerini inceliyor',
    'SPHEREx verileriyle 37 yakın kahverengi cücenin atmosferleri karşılaştırıldı. Kızılötesi ölçümlerde su, metan ve karbon içeren moleküllerin izleri görüldü.\n\nBu gökcisimleri yıldızlar gibi oluşsa da çekirdeklerinde uzun süreli hidrojen füzyonu başlatacak kadar büyük değiller. Araştırmacılar, farklı sıcaklıklardaki örnekleri inceleyerek atmosferlerinin nasıl değiştiğini anlamaya çalışıyor.',
    Icons.auto_awesome,
    '8 Ekim 2026',
    'https://www.nasa.gov/missions/spherex/nasas-spherex-telescope-sees-menagerie-of-brown-dwarfs/',
    'assets/news/3.jpg',
  ),
  (
    'Keşif',
    'Curiosity, Mars sabahını yeni bir panoramayla gösterdi',
    'NASA, Curiosity’nin 11 Ağustos 2026’da çektiği altı kareden oluşturulan Mars panoramasını yayımladı. Görüntü, rüzgârın şekillendirdiği uzak kayalıkları sabah ışığında gösteriyor.\n\nSharp Dağı çevresindeki bu oluşumlar, Mars yüzeyinin geçmişini anlamak için inceleniyor. Yeni panorama, aracın yaklaşmayı sürdürdüğü kayalık tabakanın yapısını uzaktan değerlendirmeye yardımcı oluyor.',
    Icons.landscape,
    '6 Ekim 2026',
    'https://www.nasa.gov/missions/mars-science-laboratory/curiosity-rover/nasas-curiosity-rover-catches-stunning-martian-dawn/',
    'assets/news/4.jpg',
  ),
  (
    'Uzay',
    'Roman Uzay Teleskobu yolculuğuna başladı',
    'Nancy Grace Roman Uzay Teleskobu, 30 Ağustos 2026’da Florida’dan Falcon Heavy roketiyle fırlatıldı. Görevin hedefleri arasında karanlık enerji, karanlık madde ve Güneş Sistemi dışındaki gezegenlerin araştırılması bulunuyor.\n\nGeniş alanı kızılötesinde tarayacak teleskobun bilim gözlemleri öncesinde cihaz testleri ve kalibrasyonları yapılacak. Fırlatma, görevin hazırlık sürecindeki önemli bir aşamayı tamamladı.',
    Icons.rocket_launch,
    '30 Ağustos 2026',
    'https://www.nasa.gov/news-release/nasas-dark-universe-seeking-nancy-grace-roman-space-telescope-launches/',
    'assets/news/5.jpg',
  ),
  (
    'Keşif',
    'DART çarpışmasının Güneş çevresindeki yörüngeye etkisi ölçüldü',
    '2022’deki DART çarpışmasını inceleyen araştırmacılar, Didymos ve Dimorphos sisteminin Güneş çevresindeki hareketinde de çok küçük bir değişim ölçtü. Çiftin yaklaşık 770 günlük yörünge süresindeki fark 0,15 saniye olarak bildirildi.\n\nSonuçlar, bir gökcisminin hareketini çarpışmayla değiştirme yöntemini değerlendirmeye yardımcı oluyor. Bu asteroit sistemi Dünya’ya çarpışma rotasında değildi.',
    Icons.public,
    '6 Mart 2026',
    'https://www.nasa.gov/missions/dart/nasas-dart-mission-changed-orbit-of-asteroid-didymos-around-sun/',
    'assets/news/6.jpg',
  ),
];

class NewsScreen extends StatelessWidget {
  final bool Function(String) onComment;
  const NewsScreen({super.key, required this.onComment});
  @override
  Widget build(BuildContext context) =>
      NewsThemeScope(child: _NewsScreen(onComment: onComment));
}

class _NewsScreen extends StatefulWidget {
  final bool Function(String) onComment;
  const _NewsScreen({required this.onComment});
  @override
  State<_NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<_NewsScreen> {
  String? _category;
  @override
  void initState() {
    super.initState();
    NewsThemes.load();
    _newsNotifications().catchError((Object _) {});
  }

  Future<void> _newsNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getInt(kNotifNews.seenKey);
    await prefs.setInt(kNotifNews.seenKey, _articles.length);
    if (previous != null &&
        previous < _articles.length &&
        await contentNotificationEnabled(kNotifNews)) {
      await FlutterLocalNotificationsPlugin().show(
        kNotifNews.id,
        'Haberler',
        'Yeni haberler eklendi.',
        const NotificationDetails(
          android: AndroidNotificationDetails('news', 'Haberler'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context),
    child: Builder(
      builder: (context) => Scaffold(
        backgroundColor: newsTheme.scaffoldBackgroundColor,
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              children: [
                const DrawerHeader(
                  child: Text('Neural Haber', style: TextStyle(fontSize: 24)),
                ),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Tema'),
                  onTap: () {
                    Navigator.pop(context);
                    showNewsThemePicker(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.note_alt_outlined),
                  title: const Text('Kendime Notlar'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push<void>(
                      context,
                      _newsRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Kendime Notlar')),
                          body: const SingleChildScrollView(
                            padding: EdgeInsets.all(20),
                            child: NewsNotes(article: 0),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.grid_on),
                  title: const Text('Sudoku'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push<void>(
                      context,
                      _newsRoute(builder: (_) => const SudokuScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Ders Notlarım'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push<void>(
                      context,
                      _newsRoute(builder: (_) => const PersonalCoursesScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Haber ve hatırlatıcı ayarları'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push<void>(
                      context,
                      _newsRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(
                            title: const Text('Haber ve hatırlatıcı ayarları'),
                          ),
                          body: const ListViewNewsSettings(),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        appBar: AppBar(
          title: const Text('Neural Haber'),
          backgroundColor: newsTheme.colorScheme.surfaceContainer,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Gündeme bir bakış',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: newsTheme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Bilim • Uzay • Keşif',
              style: TextStyle(color: newsTheme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Tümü'),
                  selected: _category == null,
                  onSelected: (_) => setState(() => _category = null),
                ),
                for (final category
                    in _articles.map((article) => article.$1).toSet())
                  ChoiceChip(
                    label: Text(category),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < _articles.length; i++)
              if (_category == null || _articles[i].$1 == _category)
                Card(
                  color: newsTheme.colorScheme.surfaceContainer,
                  margin: const EdgeInsets.only(bottom: 18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      _newsRoute(
                        builder: (_) => Theme(
                          data: newsTheme,
                          child: _ArticlePage(
                            index: i,
                            onComment: widget.onComment,
                          ),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Image.asset(
                            _articles[i].$7,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'NASA • ${_articles[i].$5}',
                            style: TextStyle(
                              color: newsTheme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _articles[i].$1.toUpperCase(),
                            style: TextStyle(
                              color: newsTheme.colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _articles[i].$2,
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              color: newsTheme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Row(
                            children: [
                              Text('Devamını oku'),
                              Spacer(),
                              Icon(Icons.chat_bubble_outline, size: 18),
                              SizedBox(width: 6),
                              Text('Yorumlar'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

class ListViewNewsSettings extends StatelessWidget {
  const ListViewNewsSettings({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    children: const [
      FeatureNotificationSwitch(kind: kNotifNews),
      NotificationPreferenceSwitch(
        preference: 'personal_reminders_enabled',
        title: 'Not hatırlatıcıları',
        description:
            'Kendi notlarına kurduğun alarmlar. Sohbet ve ortak alan bildirimlerini değiştirmez.',
      ),
    ],
  );
}

class _ArticlePage extends StatefulWidget {
  final int index;
  final bool Function(String) onComment;
  const _ArticlePage({required this.index, required this.onComment});
  @override
  State<_ArticlePage> createState() => _ArticlePageState();
}

class _ArticlePageState extends State<_ArticlePage> {
  final _controller = TextEditingController();
  List<String> _comments = [];
  bool _ready = false;
  String get _key => 'neural_comments_${widget.index}';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _comments = prefs.getStringList(_key) ?? [];
        _ready = true;
      });
    }
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || !_ready) return;
    // PIN hiçbir zaman yorum olarak kaydedilmez veya gönderilmez.
    if (widget.onComment(text)) {
      _controller.clear();
      FocusScope.of(context).unfocus();
      Navigator.of(context).pop();
      return;
    }
    setState(() => _comments.add(text));
    _controller.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _comments);
  }

  Future<void> _changeComment(int index, bool remove) async {
    final original = _comments[index];
    final text = remove
        ? null
        : await editMessage(context, original, title: 'Yorumu düzenle');
    if (!mounted || (!remove && text == null)) return;
    // Düzenleme yoluyla da gizli giriş kodları yorumlara kaydedilmez.
    if (!remove && widget.onComment(text!)) {
      FocusScope.of(context).unfocus();
      Navigator.of(context).pop();
      return;
    }
    if (index >= _comments.length || _comments[index] != original) return;
    setState(() {
      if (remove) {
        _comments.removeAt(index);
      } else {
        _comments[index] = text!;
      }
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, List.of(_comments));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final article = _articles[widget.index];
    return Theme(
      data: newsTheme,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Neural Haber')),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.viewPaddingOf(context).bottom + 40,
            ),
            children: [
              Image.asset(article.$7, height: 220, fit: BoxFit.cover),
              const SizedBox(height: 16),
              Text(
                'NASA • ${article.$5}',
                style: TextStyle(color: newsTheme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text(
                article.$1,
                style: TextStyle(color: newsTheme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Text(
                article.$2,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                article.$3,
                style: const TextStyle(fontSize: 17, height: 1.7),
              ),
              const SizedBox(height: 16),
              const Text('Görsel: NASA / haber kaynağı. Türkçe özet.'),
              TextButton.icon(
                onPressed: () async {
                  final opened = await launchUrl(
                    Uri.parse(article.$6),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!opened && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kaynak açılamadı.')),
                    );
                  }
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Kaynağı oku • NASA'),
              ),
              const SizedBox(height: 32),
              const SizedBox(height: 24),
              const Divider(),
              const Text(
                'Yorumlar',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _comments.length; i++)
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline),
                  ),
                  title: const Text('Okuyucu'),
                  subtitle: Text(_comments[i]),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Yorumu sil',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _changeComment(i, true),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Yorum seçenekleri',
                        onSelected: (value) =>
                            _changeComment(i, value == 'delete'),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                          PopupMenuItem(value: 'delete', child: Text('Sil')),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_comments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('İlk yorumu sen yaz.'),
                ),
              TextField(
                controller: _controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Yorumunuzu yazın',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _ready ? _submit : null,
                child: const Text('Yorum gönder'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
