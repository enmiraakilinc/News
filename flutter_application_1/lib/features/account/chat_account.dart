import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../contacts/contact_names.dart';
import '../pair/couple_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../wakeup/wakeup_service.dart';

/// Passwords are handled by Firebase Auth, never stored in preferences/Firestore.
class ChatAccount {
  static final revision = ValueNotifier<int>(0);
  static const domain = 'accounts.neural.invalid';

  static String normalizeCode(String code) {
    final clean = code.replaceAll(RegExp(r'[\s-]'), '').toLowerCase();
    if (!RegExp(r'^([a-f0-9]{32}|[0-9]{12})$').hasMatch(clean)) {
      throw const FormatException(
        'Hesap kodu geçersiz. Kodun tamamını yapıştır.',
      );
    }
    return clean;
  }

  static String displayCode(String code) {
    final clean = normalizeCode(code);
    if (clean.length == 12) {
      return List.generate(
        3,
        (i) => clean.substring(i * 4, i * 4 + 4),
      ).join('-');
    }
    return List.generate(4, (i) => clean.substring(i * 8, i * 8 + 8)).join('-');
  }

  static String emailForCode(String code) => '${normalizeCode(code)}@$domain';

  static String newCode() {
    final random = Random.secure();
    return displayCode(
      List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join(),
    );
  }

  /// Immutable owner-only alias. Existing Firebase identity/password remain intact.
  /// Resolver throttling and owner-only rules are verified separately before release.
  static Future<String?> shortCode() async {
    final legacy = currentCode;
    if (legacy == null) return null;
    final user = FirebaseAuth.instance.currentUser!;
    final db = FirebaseFirestore.instance;
    final own = db.doc('accountLoginCodes/${user.uid}');
    final random = Random.secure();
    final candidate = List.generate(12, (_) => random.nextInt(10)).join();
    return db
        .runTransaction<String>((transaction) async {
          final saved = await transaction.get(own);
          if (saved.exists) return displayCode(saved.data()!['code'] as String);
          // No read of other users' alias documents. Rules allow only atomic creation,
          // prohibit collisions/updates and bind the email to request.auth.token.email.
          transaction.set(db.doc('accountCodeAliases/$candidate'), {
            'owner': user.uid,
            'email': user.email,
          });
          transaction.set(own, {'code': candidate});
          return displayCode(candidate);
        })
        .timeout(const Duration(seconds: 15));
  }

  static Future<String> _loginEmail(String code) async {
    final clean = normalizeCode(code);
    if (clean.length == 32) return emailForCode(clean);
    final endpoint = await WakeupService.endpoint();
    if (endpoint == null) {
      throw const FormatException(
        'Kısa kod hizmetine bağlanılamadı. Eski uzun kodunu da kullanabilirsin.',
      );
    }
    final token = await FirebaseAuth.instance.currentUser!.getIdToken();
    // Password is intentionally absent: it goes directly to Firebase Auth below.
    final r = await http
        .post(
          Uri.parse('$endpoint/account/resolve'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'code': clean}),
        )
        .timeout(const Duration(seconds: 15));
    final data = jsonDecode(r.body) as Map;
    if (r.statusCode != 200) {
      if (r.statusCode == 429) {
        throw FirebaseAuthException(code: 'too-many-requests');
      }
      throw const FormatException(
        'Hesap kodu veya şifre yanlış. Eski uzun kodunu da kullanabilirsin.',
      );
    }
    final email = data['email'];
    if (email is! String ||
        !RegExp(r'^[a-f0-9]{32}@accounts\.neural\.invalid$').hasMatch(email)) {
      throw const FormatException('Hesap bağlantısı kurulamadı.');
    }
    return email;
  }

  static void validatePassword(String password) {
    if (password.length < 8 || password.length > 128) {
      throw const FormatException('Şifre 8–128 karakter olmalı.');
    }
  }

  static String? get currentCode {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null || !email.endsWith('@$domain')) return null;
    return displayCode(email.split('@').first);
  }

  static Future<String> protect(String password) async {
    validatePassword(password);
    await CoupleService.ensureReady();
    final user = FirebaseAuth.instance.currentUser!;
    if (currentCode case final String code) {
      try {
        return await shortCode() ?? code;
      } catch (_) {
        return code;
      }
    }
    if (!user.isAnonymous) {
      throw StateError('Bu hesap zaten başka bir giriş yöntemiyle bağlı.');
    }
    final code = newCode();
    final before = user.uid;
    final result = await user.linkWithCredential(
      EmailAuthProvider.credential(
        email: emailForCode(code),
        password: password,
      ),
    );
    if (result.user?.uid != before) {
      throw StateError('Hesap kimliği korunamadı.');
    }
    // Linking preserves the original UID and every existing chat membership.
    try {
      return await shortCode() ?? code;
    } catch (_) {
      return code;
    }
  }

  static Future<void> signIn(String code, String password) async {
    normalizeCode(code);
    validatePassword(password);
    await CoupleService.ensureReady();
    final previous = CoupleService.uid;
    final user = FirebaseAuth.instance.currentUser!;
    if (user.isAnonymous &&
        (await FirebaseFirestore.instance
                .collection('chats')
                .where('members', arrayContains: previous)
                .limit(1)
                .get())
            .docs
            .isNotEmpty) {
      throw const FormatException(
        'Bu cihazdaki sohbetlerini kaybetmemek için önce mevcut hesabını şifreyle bağla ve kodunu sakla.',
      );
    }
    final email = await _loginEmail(code);
    final result = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    if (result.user?.uid != previous) {
      // The shared private area still requires its own secret on this device.
      await CoupleService.unpairLocal();
      await (await SharedPreferences.getInstance()).setString(
        'my_uid',
        result.user!.uid,
      );
      ContactNames.reset();
      CoupleService.resetConnection();
      revision.value++;
    }
  }

  static Future<void> changePassword(
    String oldPassword,
    String password,
  ) async {
    validatePassword(password);
    final user = FirebaseAuth.instance.currentUser!;
    final code = currentCode;
    if (code == null) throw StateError('Önce kişisel hesabını oluştur.');
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(
        email: emailForCode(code),
        password: oldPassword,
      ),
    );
    await user.updatePassword(password);
  }

  static String errorMessage(Object error) {
    if (error is FormatException) return error.message;
    if (error is FirebaseAuthException) {
      return switch (error.code) {
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' => 'Hesap kodu veya şifre yanlış.',
        'too-many-requests' =>
          'Çok fazla deneme yapıldı. Biraz sonra tekrar dene.',
        'network-request-failed' =>
          'Bağlantı kurulamadı. İnternetini kontrol et.',
        'operation-not-allowed' => 'Şifreli giriş henüz sunucuda etkin değil.',
        'weak-password' => 'Daha güçlü bir şifre belirle.',
        _ => 'İşlem tamamlanamadı. Tekrar dene.',
      };
    }
    return 'İşlem tamamlanamadı. Tekrar dene.';
  }
}
