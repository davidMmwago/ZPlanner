import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../theme/app_theme.dart';

/// Google sign-in through the browser (works without Google Play Services).
/// Tokens are kept in the tablet's secure storage.
class GoogleAuth extends ChangeNotifier {
  GoogleAuth._();
  static final GoogleAuth instance = GoogleAuth._();

  static const _appAuth = FlutterAppAuth();
  static const _store = FlutterSecureStorage();
  static const _discovery = 'https://accounts.google.com/.well-known/openid-configuration';

  static const scopes = [
    'openid',
    'email',
    'https://www.googleapis.com/auth/calendar.events', // read + add events
    'https://www.googleapis.com/auth/drive.file', // PowerPoint → PDF (only files the app creates)
    'https://www.googleapis.com/auth/drive.appdata', // private backup folder
  ];

  /// e.g. 1234-abcd.apps.googleusercontent.com → com.googleusercontent.apps.1234-abcd
  static String get _redirect {
    final id = AppConfig.googleClientId.replaceAll('.apps.googleusercontent.com', '');
    return 'com.googleusercontent.apps.$id:/oauth2redirect';
  }

  static bool get configured => !AppConfig.googleClientId.startsWith('PASTE_');

  String? email;
  String? _access;
  String? _refresh;
  DateTime? _expiry;

  bool get signedIn => _refresh != null;

  Future<void> load() async {
    try {
      _refresh = await _store.read(key: 'g_refresh');
      _access = await _store.read(key: 'g_access');
      email = await _store.read(key: 'g_email');
      final exp = await _store.read(key: 'g_expiry');
      _expiry = exp == null ? null : DateTime.tryParse(exp);
    } catch (e) {
      debugPrint('Could not read Google sign-in: $e');
    }
    notifyListeners();
  }

  /// Opens Google's sign-in page in the browser. Returns an error message,
  /// or null on success.
  Future<String?> signIn() async {
    if (!configured) return 'Google isn\'t set up yet (add the client ID in app_theme.dart).';
    try {
      final r = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          AppConfig.googleClientId,
          _redirect,
          discoveryUrl: _discovery,
          scopes: scopes,
          promptValues: const ['consent'], // makes sure Google returns a refresh token
        ),
      );
      _access = r.accessToken;
      _refresh = r.refreshToken ?? _refresh;
      _expiry = r.accessTokenExpirationDateTime;
      email = _emailFromIdToken(r.idToken);
      await _save();
      notifyListeners();
      return _refresh == null ? 'Google didn\'t return a refresh token. Please try again.' : null;
    } on FlutterAppAuthUserCancelledException {
      return 'Sign-in cancelled.';
    } catch (e) {
      return 'Sign-in failed: $e';
    }
  }

  Future<void> signOut() async {
    final token = _refresh ?? _access;
    if (token != null) {
      try {
        await http.post(Uri.parse('https://oauth2.googleapis.com/revoke?token=$token'));
      } catch (_) {}
    }
    _access = _refresh = email = null;
    _expiry = null;
    await _store.delete(key: 'g_refresh');
    await _store.delete(key: 'g_access');
    await _store.delete(key: 'g_email');
    await _store.delete(key: 'g_expiry');
    notifyListeners();
  }

  /// A valid access token, refreshed if it's about to expire.
  Future<String> accessToken({bool forceRefresh = false}) async {
    final exp = _expiry;
    final fresh = _access != null &&
        exp != null &&
        exp.isAfter(DateTime.now().add(const Duration(minutes: 2)));
    if (fresh && !forceRefresh) return _access!;
    final refresh = _refresh;
    if (refresh == null) throw const GoogleAuthException('Not signed in to Google.');
    try {
      final r = await _appAuth.token(TokenRequest(
        AppConfig.googleClientId,
        _redirect,
        refreshToken: refresh,
        discoveryUrl: _discovery,
        scopes: scopes,
      ));
      _access = r.accessToken;
      _expiry = r.accessTokenExpirationDateTime;
      if (r.refreshToken != null) _refresh = r.refreshToken;
      await _save();
      return _access!;
    } catch (e) {
      throw GoogleAuthException('Google sign-in expired. Please connect again in Settings. ($e)');
    }
  }

  Future<void> _save() async {
    await _store.write(key: 'g_refresh', value: _refresh);
    await _store.write(key: 'g_access', value: _access);
    await _store.write(key: 'g_email', value: email);
    await _store.write(key: 'g_expiry', value: _expiry?.toIso8601String());
  }

  static String? _emailFromIdToken(String? idToken) {
    if (idToken == null) return null;
    try {
      final payload = idToken.split('.')[1];
      final json = utf8.decode(base64Url.decode(base64Url.normalize(payload)));
      return (jsonDecode(json) as Map<String, dynamic>)['email'] as String?;
    } catch (_) {
      return null;
    }
  }
}

class GoogleAuthException implements Exception {
  final String message;
  const GoogleAuthException(this.message);
  @override
  String toString() => message;
}
