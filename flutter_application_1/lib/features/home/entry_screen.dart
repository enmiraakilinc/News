import 'package:flutter/material.dart';
import '../news/news_screen.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../pair/couple_service.dart';
import '../../core/theme/chat_theme.dart';
import '../updates/update_service.dart';
import '../updates/update_dialog.dart';

import '../../app/app_runtime.dart';
import 'private_home.dart';
import '../tools/tools_screen.dart';

class FakeGalleryPage extends StatefulWidget {
  const FakeGalleryPage({super.key});
  @override
  State<FakeGalleryPage> createState() => _FakeGalleryPageState();
}

class _FakeGalleryPageState extends State<FakeGalleryPage> {
  final DateTime _baslangicTarihi = kBaslangicTarihi;

  String _gercekSifre = "1703";
  String _sahteSifre = "0000";
  int _screenMode = 0;

  bool _isNotificationActive = false;
  bool _isDisguised = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    ChatThemes.load();
    // Firebase'in açılışta hazır olması için biraz bekleyip güncelleme kontrolü.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    await Future.delayed(const Duration(seconds: 3));
    final info = await UpdateService.checkForUpdate();
    if (info == null || !mounted) return;

    // "Sonra" denen sürümü tekrar tekrar sorma; daha yeni sürüm gelince sor.
    final prefs = await SharedPreferences.getInstance();
    final int skip = prefs.getInt('skip_update_code') ?? 0;
    if (info.code <= skip) return;

    if (!mounted) return;
    final bool? res = await showDialog<bool>(
      context: context,
      builder: (_) => UpdateDialog(info: info),
    );
    if (res == false) {
      await prefs.setInt('skip_update_code', info.code);
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _gercekSifre = prefs.getString('real_pin') ?? "1703";
      _sahteSifre = prefs.getString('fake_pin') ?? "0000";
      _isNotificationActive = prefs.getBool('notif_active') ?? false;
      _isDisguised = prefs.getBool('notif_disguised') ?? false;
    });
    _updateNotification();
    unawaited(CoupleService.enableSecretLogin().catchError((Object _) {}));
  }

  // Ayarlar prefs'e yazıldıktan sonra bildirimi ortak fonksiyonla tazeler.
  Future<void> _updateNotification() => showCounterNotification();

  @override
  Widget build(BuildContext context) {
    if (_screenMode == 1) {
      return CounterScreen(
        startDate: _baslangicTarihi,
        isNotifActive: _isNotificationActive,
        isDisguised: _isDisguised,
        onSettingsChanged: (active, disguised) async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('notif_active', active);
          await prefs.setBool('notif_disguised', disguised);
          setState(() {
            _isNotificationActive = active;
            _isDisguised = disguised;
          });
          _updateNotification();
        },
        onBack: () {
          _loadData();
          setState(() => _screenMode = 0);
        },
      );
    }
    if (_screenMode == 2) {
      return DecoyHomeScreen(onBack: () => setState(() => _screenMode = 0));
    }

    return NewsScreen(
      onComment: (value) {
        if (value == _gercekSifre) {
          setState(() => _screenMode = 1);
          return true;
        }
        if (value == _sahteSifre) {
          setState(() => _screenMode = 2);
          return true;
        }
        return false;
      },
    );
  }
}

// ─────────────────────────────────────────
//  GİZLİ EKRAN
// ─────────────────────────────────────────
