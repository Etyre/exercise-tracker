import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/exercise.dart';
import 'exercise_catalog.dart';

/// The editable list of exercise kinds, persisted as JSON.
class ExerciseStore extends ChangeNotifier {
  ExerciseStore._(this._file);

  final File _file;
  final List<Exercise> _exercises = [];
  int _defaultsVersion = 0;

  static Future<ExerciseStore> load() async {
    final dir = await getApplicationDocumentsDirectory();
    return loadFrom(File('${dir.path}/exercises.json'));
  }

  static Future<ExerciseStore> loadFrom(File file) async {
    final store = ExerciseStore._(file);
    await store._read();
    if (store._exercises.isEmpty) {
      store._exercises.addAll(defaultExercises());
      store._defaultsVersion = kDefaultsVersion;
      await store._write();
    } else if (store._defaultsVersion < kDefaultsVersion) {
      // Existing install: add exercises introduced since it was seeded,
      // unless the user already has one with that id.
      final added = exercisesAddedInVersion();
      final updates = exerciseUpdatesInVersion();
      for (var v = store._defaultsVersion + 1; v <= kDefaultsVersion; v++) {
        for (final e in added[v] ?? const <Exercise>[]) {
          if (store.byId(e.id) == null) store._exercises.add(e);
        }
        final update = updates[v];
        if (update != null) store._exercises.forEach(update);
      }
      store._defaultsVersion = kDefaultsVersion;
      await store._write();
    }
    return store;
  }

  List<Exercise> get all => List.unmodifiable(_exercises);

  Exercise? byId(String id) {
    for (final e in _exercises) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Categories in display order: the two built-ins first, then any custom
  /// ones in the order they first appear.
  List<String> get categories {
    final seen = <String>[];
    for (final c in [kCardio, kStrength]) {
      if (_exercises.any((e) => e.category == c)) seen.add(c);
    }
    for (final e in _exercises) {
      if (!seen.contains(e.category)) seen.add(e.category);
    }
    return seen;
  }

  List<Exercise> inCategory(String category) =>
      _exercises.where((e) => e.category == category).toList();

  /// Make a unique, URL-safe id from a name.
  String newId(String name) {
    var base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (base.isEmpty) base = 'exercise';
    var id = base;
    var n = 2;
    while (byId(id) != null) {
      id = '${base}_${n++}';
    }
    return id;
  }

  Future<void> add(Exercise exercise) async {
    _exercises.add(exercise);
    await _write();
    notifyListeners();
  }

  /// Replace the exercise with the same id.
  Future<void> update(Exercise exercise) async {
    final i = _exercises.indexWhere((e) => e.id == exercise.id);
    if (i < 0) {
      _exercises.add(exercise);
    } else {
      _exercises[i] = exercise;
    }
    await _write();
    notifyListeners();
  }

  /// Remove an exercise kind. Past sessions for it are kept.
  Future<void> remove(String id) async {
    _exercises.removeWhere((e) => e.id == id);
    await _write();
    notifyListeners();
  }

  /// [to] is the final index (already adjusted for the removed item).
  Future<void> move(int from, int to) async {
    if (from == to) return;
    final e = _exercises.removeAt(from);
    _exercises.insert(to, e);
    await _write();
    notifyListeners();
  }

  Future<void> _read() async {
    if (!await _file.exists()) return;
    try {
      final data = jsonDecode(await _file.readAsString());
      final list = (data is Map ? data['exercises'] : data) as List? ?? const [];
      _defaultsVersion =
          data is Map ? ((data['defaultsVersion'] as num?)?.toInt() ?? 1) : 1;
      _exercises
        ..clear()
        ..addAll(list.map(
            (j) => Exercise.fromJson(Map<String, dynamic>.from(j as Map))));
    } catch (e) {
      debugPrint('Failed to read exercises file: $e');
    }
  }

  Future<void> _write() async {
    final payload = jsonEncode({
      'version': 1,
      'defaultsVersion': _defaultsVersion,
      'exercises': _exercises.map((e) => e.toJson()).toList(),
    });
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(payload, flush: true);
    await tmp.rename(_file.path);
  }
}
