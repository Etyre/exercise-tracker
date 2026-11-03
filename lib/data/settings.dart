import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// User preferences, persisted with SharedPreferences.
class Settings extends ChangeNotifier {
  Settings._(this._prefs);

  static const _kUnit = 'weightUnit';
  static const _kSheetUrl = 'sheetUrl';
  static const _kLastSync = 'lastSyncAt';
  static const _kLastSyncError = 'lastSyncError';
  static const _kLastTimeExpanded = 'lastTimeExpanded';

  final SharedPreferences _prefs;

  static Future<Settings> load() async =>
      Settings._(await SharedPreferences.getInstance());

  /// 'lb' or 'kg'. Weights are displayed in this unit.
  String get weightUnit => _prefs.getString(_kUnit) ?? 'lb';
  Future<void> setWeightUnit(String unit) async {
    await _prefs.setString(_kUnit, unit);
    notifyListeners();
  }

  /// Google Apps Script web-app URL. Empty means sync is off. Starts as
  /// [kDefaultSheetUrl] until the user saves something else (or clears it).
  String get sheetUrl => _prefs.getString(_kSheetUrl) ?? kDefaultSheetUrl;
  bool get syncEnabled => sheetUrl.trim().isNotEmpty;
  Future<void> setSheetUrl(String url) async {
    await _prefs.setString(_kSheetUrl, url.trim());
    notifyListeners();
  }

  /// Whether the "Last time" panel on the logging screen starts open.
  bool get lastTimeExpanded => _prefs.getBool(_kLastTimeExpanded) ?? true;
  Future<void> setLastTimeExpanded(bool v) async {
    await _prefs.setBool(_kLastTimeExpanded, v);
    notifyListeners();
  }

  DateTime? get lastSyncAt {
    final s = _prefs.getString(_kLastSync);
    return s == null ? null : DateTime.tryParse(s)?.toLocal();
  }

  String? get lastSyncError => _prefs.getString(_kLastSyncError);

  Future<void> recordSyncResult({String? error}) async {
    if (error == null) {
      await _prefs.setString(_kLastSync, DateTime.now().toIso8601String());
      await _prefs.remove(_kLastSyncError);
    } else {
      await _prefs.setString(_kLastSyncError, error);
    }
    notifyListeners();
  }
}
