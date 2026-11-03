import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/session_store.dart';
import '../data/settings.dart';
import '../models/workout_session.dart';

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to the Google Apps Script web app that fronts the Google Sheet.
///
/// Protocol (see apps_script/Code.gs):
///   POST {action:'upsert', sessions:[...]}  -> {ok, count}
///   POST {action:'delete', ids:[...]}       -> {ok, count}
///   GET  ?action=export                     -> {ok, sessions:[...]}
class SheetsSync extends ChangeNotifier {
  SheetsSync({required this.store, required this.settings, http.Client? client})
      : _client = client ?? http.Client() {
    store.addListener(_onStoreChanged);
  }

  final SessionStore store;
  final Settings settings;
  final http.Client _client;

  bool _syncing = false;
  bool get isSyncing => _syncing;

  void _onStoreChanged() {
    // Push automatically whenever something new is waiting.
    if (settings.syncEnabled && store.pendingCount > 0 && !_syncing) {
      // Fire and forget; errors are recorded in settings for the UI.
      pushPending();
    }
  }

  /// Push every unsynced session and pending delete. Returns an error message
  /// or null on success.
  Future<String?> pushPending() async {
    if (!settings.syncEnabled) return 'No Google Sheet URL set.';
    if (_syncing) return null;
    _syncing = true;
    notifyListeners();
    try {
      final toPush = store.unsynced;
      if (toPush.isNotEmpty) {
        final res = await _post({
          'action': 'upsert',
          'sessions': toPush.map((s) => s.toJson()).toList(),
        });
        _expectOk(res);
        await store.markSynced(toPush.map((s) => s.id));
      }
      final toDelete = store.pendingDeletes;
      if (toDelete.isNotEmpty) {
        final res = await _post({'action': 'delete', 'ids': toDelete.toList()});
        _expectOk(res);
        await store.clearPendingDeletes(toDelete);
      }
      await settings.recordSyncResult();
      return null;
    } catch (e) {
      final msg = _describe(e);
      await settings.recordSyncResult(error: msg);
      return msg;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// Pull every session from the sheet and add any the phone doesn't have.
  /// Returns the number of sessions added, or throws [SyncException].
  Future<int> pullAll() async {
    if (!settings.syncEnabled) throw SyncException('No Google Sheet URL set.');
    _syncing = true;
    notifyListeners();
    try {
      final uri = Uri.parse(settings.sheetUrl)
          .replace(queryParameters: {'action': 'export'});
      final resp = await _client.get(uri).timeout(const Duration(seconds: 60));
      final body = _decode(resp);
      _expectOk(body);
      final list = (body['sessions'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => WorkoutSession.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      final added = await store.mergeRemote(list);
      await settings.recordSyncResult();
      return added;
    } catch (e) {
      final msg = _describe(e);
      await settings.recordSyncResult(error: msg);
      throw SyncException(msg);
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  /// POST to the web app. Apps Script answers a POST with a 302 to a
  /// one-time URL on googleusercontent.com, and Dart does not follow
  /// redirects for POST, so follow it by hand with a GET.
  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final req = http.Request('POST', Uri.parse(settings.sheetUrl))
      ..followRedirects = false
      ..headers['Content-Type'] = 'text/plain; charset=utf-8'
      ..body = jsonEncode(body);
    var streamed = await _client.send(req).timeout(const Duration(seconds: 60));
    var resp = await http.Response.fromStream(streamed);
    var hops = 0;
    while (resp.statusCode >= 300 && resp.statusCode < 400 && hops < 5) {
      final loc = resp.headers['location'];
      if (loc == null) break;
      resp = await _client
          .get(Uri.parse(loc))
          .timeout(const Duration(seconds: 60));
      hops++;
    }
    return _decode(resp);
  }

  Map<String, dynamic> _decode(http.Response resp) {
    if (resp.statusCode != 200) {
      throw SyncException('Sheet responded with HTTP ${resp.statusCode}.');
    }
    try {
      final data = jsonDecode(resp.body);
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {}
    final snippet = resp.body.trimLeft();
    if (snippet.startsWith('<')) {
      throw SyncException(
          'Sheet returned a web page instead of data. Check that the script '
          'is deployed as a web app with access set to "Anyone".');
    }
    throw SyncException('Unexpected response from sheet.');
  }

  void _expectOk(Map<String, dynamic> body) {
    if (body['ok'] != true) {
      throw SyncException((body['error'] as String?) ?? 'Sheet reported an error.');
    }
  }

  String _describe(Object e) {
    if (e is SyncException) return e.message;
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Failed host lookup')) {
      return 'No internet connection.';
    }
    if (s.contains('TimeoutException')) return 'Sheet took too long to respond.';
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    _client.close();
    super.dispose();
  }
}
