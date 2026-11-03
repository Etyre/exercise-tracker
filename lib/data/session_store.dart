import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/workout_session.dart';

/// All logged sessions, kept in memory and persisted to a JSON file in the
/// app's documents directory. The phone is the source of truth; the Google
/// Sheet is a mirror that is kept up to date by [SheetsSync].
class SessionStore extends ChangeNotifier {
  SessionStore._(this._file);

  final File _file;
  final List<WorkoutSession> _sessions = [];

  /// IDs of synced sessions deleted locally while offline. They are removed
  /// from the sheet on the next successful sync.
  final Set<String> _pendingDeletes = {};

  static Future<SessionStore> load() async {
    final dir = await getApplicationDocumentsDirectory();
    final store = SessionStore._(File('${dir.path}/sessions.json'));
    await store._read();
    return store;
  }

  /// For tests: an in-memory store backed by a temp file.
  @visibleForTesting
  static Future<SessionStore> loadFrom(File file) async {
    final store = SessionStore._(file);
    await store._read();
    return store;
  }

  List<WorkoutSession> get all => List.unmodifiable(_sessions);

  List<WorkoutSession> forExercise(String exerciseId) {
    final list = _sessions.where((s) => s.exerciseId == exerciseId).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list;
  }

  WorkoutSession? lastFor(String exerciseId) {
    final list = forExercise(exerciseId);
    return list.isEmpty ? null : list.first;
  }

  List<WorkoutSession> get unsynced =>
      _sessions.where((s) => !s.synced).toList();

  Set<String> get pendingDeletes => Set.unmodifiable(_pendingDeletes);

  int get pendingCount => unsynced.length + _pendingDeletes.length;

  Future<void> add(WorkoutSession session) async {
    _sessions.add(session);
    await _write();
    notifyListeners();
  }

  Future<void> delete(WorkoutSession session) async {
    _sessions.removeWhere((s) => s.id == session.id);
    if (session.synced) _pendingDeletes.add(session.id);
    await _write();
    notifyListeners();
  }

  Future<void> markSynced(Iterable<String> ids) async {
    final set = ids.toSet();
    for (final s in _sessions) {
      if (set.contains(s.id)) s.synced = true;
    }
    await _write();
    notifyListeners();
  }

  Future<void> clearPendingDeletes(Iterable<String> ids) async {
    _pendingDeletes.removeAll(ids);
    await _write();
    notifyListeners();
  }

  /// Merge sessions pulled from the sheet. Existing local sessions win;
  /// anything new is added and marked synced. Returns how many were added.
  Future<int> mergeRemote(Iterable<WorkoutSession> remote) async {
    final known = _sessions.map((s) => s.id).toSet();
    var added = 0;
    for (final r in remote) {
      if (known.contains(r.id) || _pendingDeletes.contains(r.id)) continue;
      r.synced = true;
      _sessions.add(r);
      added++;
    }
    if (added > 0) {
      await _write();
      notifyListeners();
    }
    return added;
  }

  Future<void> _read() async {
    if (!await _file.exists()) return;
    try {
      final data = jsonDecode(await _file.readAsString());
      final map = data is Map ? data : {'sessions': data};
      _sessions
        ..clear()
        ..addAll(((map['sessions'] as List?) ?? const []).map(
            (j) => WorkoutSession.fromJson(Map<String, dynamic>.from(j as Map))));
      _pendingDeletes
        ..clear()
        ..addAll(((map['pendingDeletes'] as List?) ?? const []).cast<String>());
    } catch (e) {
      debugPrint('Failed to read sessions file: $e');
    }
  }

  Future<void> _write() async {
    final payload = jsonEncode({
      'version': 1,
      'sessions': _sessions.map((s) => s.toJson()).toList(),
      'pendingDeletes': _pendingDeletes.toList(),
    });
    // Write to a temp file and rename so a crash mid-write can't corrupt data.
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(payload, flush: true);
    await tmp.rename(_file.path);
  }
}
