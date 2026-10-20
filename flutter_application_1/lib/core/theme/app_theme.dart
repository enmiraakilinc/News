import 'package:flutter/material.dart';
import 'news_theme.dart';

/// Uygulamanın pastel MAVİ, unisex renk paleti.
const Color kPrimary = Color(0xFF5E86AE); // pastel mavi (buton / kenar)
const Color kPrimaryDark = Color(0xFF294A6B); // koyu okunur mavi (yazı)
const Color kSoft = Color(0xFFE3EDF7); // açık kart zemini
const Color kSoftBorder = Color(0xFFC3D6E8); // kart kenarı

const Color kAppBar = Color(0xFFCFE0F0); // açık pastel mavi üst çubuk
const Color kOnAppBar = Color(0xFF294A6B); // üst çubuk yazısı

// Sıcak vurgu (kilitli hediye kutusu, gizleme modu) — maviyle güzel kontrast.
const Color kWarm = Color(0xFFC98B63);
const Color kWarmDark = Color(0xFF8A5A3B);
const Color kWarmSoft = Color(0xFFFAEFE4);
const Color kWarmBorder = Color(0xFFE8CFB4);

const Color kCoolSoft = Color(0xFFDCE8F4); // "senin cevabın" gibi ikinci ton
const Color kSurface = Color(0xFFF2F6FB); // hafif mavi-beyaz yüzey

ThemeData get newsTheme => NewsThemes.current;

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: kPrimary, primary: kPrimary),
    scaffoldBackgroundColor: kSurface,
    appBarTheme: const AppBarTheme(
      // Üst çubuk koyu gri (saf siyah değil); yazısı beyaz.
      backgroundColor: Color(0xFF373C42),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
  );
}

/// Pastel mavi gradyan + ince desen. Görsel dosyası kullanmaz (çizimle),
/// APK boyutunu artırmaz ve her ekran boyutuna uyar.
class PastelBackground extends StatelessWidget {
  final Widget child;
  const PastelBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.surfaceContainer,
          ],
        ),
      ),
      child: child,
    );
  }
}
