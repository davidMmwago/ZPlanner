import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'google_auth.dart';

/// A Google Calendar event.
class CalEvent {
  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  const CalEvent(this.id, this.title, this.start, this.end, this.allDay);
}

class GoogleApiException implements Exception {
  final String message;
  const GoogleApiException(this.message);
  @override
  String toString() => message;
}

/// Small REST client for the bits of Calendar and Drive the app uses.
class GoogleApi {
  static final _client = http.Client();
  static const _cal = 'https://www.googleapis.com/calendar/v3/calendars/primary/events';
  static const _drive = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  /// Sends a request with the access token; retries once after a refresh.
  static Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? jsonBody,
  }) async {
    Future<http.Response> attempt(String token) async {
      final req = http.Request(method, url)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers.addAll(headers ?? const {});
      if (jsonBody != null) {
        req.headers['Content-Type'] = 'application/json; charset=UTF-8';
        req.body = jsonEncode(jsonBody);
      }
      return http.Response.fromStream(await _client.send(req));
    }

    var res = await attempt(await GoogleAuth.instance.accessToken());
    if (res.statusCode == 401) {
      res = await attempt(await GoogleAuth.instance.accessToken(forceRefresh: true));
    }
    return res;
  }

  static void _check(http.Response r, String what) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    var msg = r.body;
    try {
      msg = (jsonDecode(r.body) as Map<String, dynamic>)['error']['message'] as String;
    } catch (_) {}
    throw GoogleApiException('$what failed (${r.statusCode}): $msg');
  }

  // ── Calendar ───────────────────────────────────────────────
  static Future<List<CalEvent>> events(DateTime from, DateTime to) async {
    final url = Uri.parse(_cal).replace(queryParameters: {
      'timeMin': from.toUtc().toIso8601String(),
      'timeMax': to.toUtc().toIso8601String(),
      'singleEvents': 'true',
      'orderBy': 'startTime',
      'maxResults': '250',
    });
    final r = await _send('GET', url);
    _check(r, 'Loading calendar');
    final items = (jsonDecode(r.body) as Map<String, dynamic>)['items'] as List? ?? [];
    final out = <CalEvent>[];
    for (final raw in items) {
      final e = raw as Map<String, dynamic>;
      if (e['status'] == 'cancelled') continue;
      final start = e['start'] as Map<String, dynamic>? ?? {};
      final end = e['end'] as Map<String, dynamic>? ?? {};
      final allDay = start['date'] != null;
      final s = DateTime.tryParse((start['dateTime'] ?? start['date'] ?? '') as String);
      if (s == null) continue;
      final en = DateTime.tryParse((end['dateTime'] ?? end['date'] ?? '') as String);
      out.add(CalEvent(e['id'] as String, (e['summary'] as String?) ?? '(no title)', s.toLocal(),
          en?.toLocal(), allDay));
    }
    return out;
  }

  static Map<String, dynamic> _eventBody(String title, DateTime due, bool hasTime) {
    String d(DateTime x) => '${x.year}-${_2(x.month)}-${_2(x.day)}';
    return hasTime
        ? {
            'summary': title,
            'start': {'dateTime': due.toUtc().toIso8601String()},
            'end': {'dateTime': due.add(const Duration(minutes: 30)).toUtc().toIso8601String()},
            'reminders': {
              'useDefault': false,
              'overrides': [
                {'method': 'popup', 'minutes': 10}
              ],
            },
          }
        : {
            'summary': title,
            'start': {'date': d(due)},
            'end': {'date': d(due.add(const Duration(days: 1)))},
          };
  }

  static String _2(int n) => n.toString().padLeft(2, '0');

  /// Creates an event and returns its id.
  static Future<String> createEvent(String title, DateTime due, bool hasTime) async {
    final r = await _send('POST', Uri.parse(_cal), jsonBody: _eventBody(title, due, hasTime));
    _check(r, 'Adding to calendar');
    return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as String;
  }

  static Future<void> updateEvent(String id, String title, DateTime due, bool hasTime) async {
    final r = await _send('PUT', Uri.parse('$_cal/$id'), jsonBody: _eventBody(title, due, hasTime));
    _check(r, 'Updating calendar event');
  }

  static Future<void> deleteEvent(String id) async {
    final r = await _send('DELETE', Uri.parse('$_cal/$id'));
    if (r.statusCode == 404 || r.statusCode == 410) return; // already gone
    _check(r, 'Deleting calendar event');
  }

  // ── Drive ──────────────────────────────────────────────────
  /// Uploads a (possibly large) file with Drive's resumable upload.
  /// Returns the new file's id.
  static Future<String> uploadFile(File file, Map<String, dynamic> metadata, {String? mimeType}) async {
    final length = await file.length();
    final start = await _send(
      'POST',
      Uri.parse('$_upload?uploadType=resumable'),
      headers: {
        'X-Upload-Content-Length': '$length',
        if (mimeType != null) 'X-Upload-Content-Type': mimeType,
      },
      jsonBody: metadata,
    );
    _check(start, 'Starting upload');
    final location = start.headers['location'];
    if (location == null) throw const GoogleApiException('Upload failed: no upload address.');

    final put = http.StreamedRequest('PUT', Uri.parse(location))
      ..headers['Authorization'] = 'Bearer ${await GoogleAuth.instance.accessToken()}'
      ..contentLength = length;
    if (mimeType != null) put.headers['Content-Type'] = mimeType;
    final sending = _client.send(put);
    await put.sink.addStream(file.openRead());
    await put.sink.close();
    final res = await http.Response.fromStream(await sending);
    _check(res, 'Uploading');
    return (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
  }

  static Future<void> deleteFile(String id) async {
    final r = await _send('DELETE', Uri.parse('$_drive/$id'));
    if (r.statusCode == 404) return;
    _check(r, 'Deleting file');
  }

  /// PowerPoint → PDF: upload to her Drive (Google converts it to Slides),
  /// download as PDF to [outPath], then delete the temporary copy.
  static Future<void> convertToPdf(File input, String name, String outPath) async {
    const pptxMime = 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    const pptMime = 'application/vnd.ms-powerpoint';
    final lower = input.path.toLowerCase();
    final id = await uploadFile(
      input,
      {'name': 'Zee temp - $name', 'mimeType': 'application/vnd.google-apps.presentation'},
      mimeType: lower.endsWith('.ppt') ? pptMime : pptxMime,
    );
    try {
      var r = await _send('GET', Uri.parse('$_drive/$id/export?mimeType=application/pdf'));
      if (r.statusCode == 403) {
        // Over Google's 10 MB export limit: use the file's export link instead.
        final meta = await _send('GET', Uri.parse('$_drive/$id?fields=exportLinks'));
        _check(meta, 'Reading export links');
        final links = (jsonDecode(meta.body) as Map<String, dynamic>)['exportLinks'] as Map<String, dynamic>?;
        final link = links?['application/pdf'] as String?;
        if (link == null) throw const GoogleApiException('This file is too big for Google to convert.');
        r = await _send('GET', Uri.parse(link));
      }
      _check(r, 'Converting to PDF');
      await File(outPath).writeAsBytes(r.bodyBytes, flush: true);
    } finally {
      try {
        await deleteFile(id);
      } catch (_) {}
    }
  }

  // ── Backup (private app folder in her Drive) ───────────────
  static const backupName = 'zee-backup.zip';

  /// Newest backup: (id, modified time, size in bytes), or null if none.
  static Future<(String, DateTime, int)?> latestBackup() async {
    final url = Uri.parse(_drive).replace(queryParameters: {
      'spaces': 'appDataFolder',
      'q': "name = '$backupName'",
      'orderBy': 'modifiedTime desc',
      'fields': 'files(id, modifiedTime, size)',
    });
    final r = await _send('GET', url);
    _check(r, 'Looking for backups');
    final files = (jsonDecode(r.body) as Map<String, dynamic>)['files'] as List? ?? [];
    if (files.isEmpty) return null;
    final f = files.first as Map<String, dynamic>;
    return (
      f['id'] as String,
      DateTime.parse(f['modifiedTime'] as String).toLocal(),
      int.tryParse('${f['size']}') ?? 0,
    );
  }

  static Future<void> uploadBackup(File zip) async {
    final old = await latestBackup();
    await uploadFile(zip, {
      'name': backupName,
      'parents': ['appDataFolder'],
    }, mimeType: 'application/zip');
    if (old != null) {
      try {
        await deleteFile(old.$1); // keep only the newest
      } catch (_) {}
    }
  }

  static Future<void> downloadFile(String id, File out) async {
    final req = http.Request('GET', Uri.parse('$_drive/$id?alt=media'))
      ..headers['Authorization'] = 'Bearer ${await GoogleAuth.instance.accessToken()}';
    final res = await _client.send(req);
    if (res.statusCode != 200) {
      throw GoogleApiException('Download failed (${res.statusCode}).');
    }
    final sink = out.openWrite();
    await res.stream.pipe(sink);
  }
}
