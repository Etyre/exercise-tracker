/**
 * Exercise Tracker — Google Sheets sync endpoint.
 *
 * Setup (one time, about two minutes):
 *   1. Create a new Google Sheet.
 *   2. Extensions ▸ Apps Script. Delete the sample code, paste this whole file.
 *   3. Deploy ▸ New deployment ▸ type "Web app".
 *        Execute as: Me
 *        Who has access: Anyone
 *      Click Deploy, authorize, and copy the Web app URL.
 *   4. Paste that URL into the app: Settings ▸ Google Sheet URL.
 *
 * Optional, to limit the script to this one spreadsheet instead of all your
 * sheets: Project Settings (gear) ▸ tick "Show appsscript.json manifest file",
 * then replace that file with apps_script/appsscript.json (it requests only
 * the spreadsheets.currentonly scope). Do this before the first deploy.
 *
 * The script owns three tabs in the sheet:
 *   "Sessions" — one row per logged workout session
 *   "Sets"     — one row per strength set (handy for charts and pivot tables)
 *   "Fields"   — one row per logged field value (zone 2 time, mph, cycles…)
 * It creates them if they don't exist. Re-syncing the same session replaces
 * its rows, so the sheet never gets duplicates.
 */

var SESSIONS_SHEET = 'Sessions';
var SETS_SHEET = 'Sets';
var FIELDS_SHEET = 'Fields';

var SESSION_HEADERS = [
  'id', 'exercise_id', 'exercise', 'category', 'started_at', 'finished_at',
  'duration_min', 'sets_summary', 'fields_summary', 'notes', 'data_json',
];
var SET_HEADERS = [
  'session_id', 'exercise', 'started_at', 'set_number', 'warmup', 'reps',
  'weight', 'unit',
];
var FIELD_HEADERS = [
  'session_id', 'exercise', 'started_at', 'field', 'value', 'unit',
];

function doPost(e) {
  var lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    var body = JSON.parse(e.postData.contents || '{}');
    if (body.action === 'upsert') return json_(upsertSessions_(body.sessions || []));
    if (body.action === 'delete') return json_(deleteSessions_(body.ids || []));
    return json_({ ok: false, error: 'Unknown action: ' + body.action });
  } catch (err) {
    return json_({ ok: false, error: String(err) });
  } finally {
    lock.releaseLock();
  }
}

function doGet(e) {
  var action = (e && e.parameter && e.parameter.action) || 'ping';
  try {
    if (action === 'export') return json_({ ok: true, sessions: exportSessions_() });
    return json_({ ok: true, message: 'Exercise Tracker sync endpoint is live.' });
  } catch (err) {
    return json_({ ok: false, error: String(err) });
  }
}

// ---------------------------------------------------------------------------

function upsertSessions_(sessions) {
  var ids = sessions.map(function (s) { return s.id; });
  deleteSessions_(ids);

  var sessionsSheet = sheet_(SESSIONS_SHEET, SESSION_HEADERS);
  var setsSheet = sheet_(SETS_SHEET, SET_HEADERS);
  var fieldsSheet = sheet_(FIELDS_SHEET, FIELD_HEADERS);
  var sessionRows = [];
  var setRows = [];
  var fieldRows = [];

  sessions.forEach(function (s) {
    var sets = s.sets || [];
    var fields = s.fields || [];
    sessionRows.push([
      s.id, s.exerciseId, s.exerciseName || '', s.category || '',
      toDate_(s.startedAt), toDate_(s.finishedAt), minutes_(s.durationSec),
      setsSummary_(sets), fieldsSummary_(fields), s.notes || '',
      JSON.stringify(s),
    ]);
    sets.forEach(function (set, i) {
      setRows.push([
        s.id, s.exerciseName || '', toDate_(s.startedAt), i + 1,
        set.warmup ? 'yes' : 'no', nz_(set.reps), nz_(set.weight), set.unit || '',
      ]);
    });
    fields.forEach(function (f) {
      if (f.value == null || f.value === '') return;
      fieldRows.push([
        s.id, s.exerciseName || '', toDate_(s.startedAt), f.label || f.key,
        fieldValue_(f), fieldUnit_(f),
      ]);
    });
  });

  append_(sessionsSheet, sessionRows, SESSION_HEADERS.length);
  append_(setsSheet, setRows, SET_HEADERS.length);
  append_(fieldsSheet, fieldRows, FIELD_HEADERS.length);
  return { ok: true, count: sessions.length };
}

function append_(sheet, rows, width) {
  if (!rows.length) return;
  sheet.getRange(sheet.getLastRow() + 1, 1, rows.length, width).setValues(rows);
}

function deleteSessions_(ids) {
  var wanted = {};
  ids.forEach(function (id) { wanted[id] = true; });
  var removed = deleteRowsWhere_(sheet_(SESSIONS_SHEET, SESSION_HEADERS), wanted);
  deleteRowsWhere_(sheet_(SETS_SHEET, SET_HEADERS), wanted);
  deleteRowsWhere_(sheet_(FIELDS_SHEET, FIELD_HEADERS), wanted);
  return { ok: true, count: removed };
}

/** Delete every row whose first column is a key in `wanted`. */
function deleteRowsWhere_(sheet, wanted) {
  var last = sheet.getLastRow();
  if (last < 2) return 0;
  var values = sheet.getRange(2, 1, last - 1, 1).getValues();
  var removed = 0;
  // Walk from the bottom so row indexes stay valid while deleting.
  for (var i = values.length - 1; i >= 0; i--) {
    if (wanted[values[i][0]]) {
      sheet.deleteRow(i + 2);
      removed++;
    }
  }
  return removed;
}

function exportSessions_() {
  var sheet = sheet_(SESSIONS_SHEET, SESSION_HEADERS);
  var last = sheet.getLastRow();
  if (last < 2) return [];
  var col = SESSION_HEADERS.indexOf('data_json') + 1;
  var values = sheet.getRange(2, col, last - 1, 1).getValues();
  var out = [];
  values.forEach(function (row) {
    if (!row[0]) return;
    try { out.push(JSON.parse(row[0])); } catch (err) { /* skip bad row */ }
  });
  return out;
}

// ---------------------------------------------------------------------------

function sheet_(name, headers) {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(name);
  if (!sheet) {
    sheet = ss.insertSheet(name);
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    sheet.setFrozenRows(1);
    sheet.getRange(1, 1, 1, headers.length).setFontWeight('bold');
  }
  return sheet;
}

function setsSummary_(sets) {
  return sets.map(function (s) {
    var txt = (s.reps == null ? '?' : s.reps) + ' × ' +
      (s.weight == null ? '?' : s.weight) + ' ' + (s.unit || '');
    return (s.warmup ? 'W ' : '') + txt;
  }).join(', ');
}

function fieldsSummary_(fields) {
  var parts = [];
  fields.forEach(function (f) {
    if (f.value == null || f.value === '') return;
    var v = fieldValue_(f);
    var u = fieldUnit_(f);
    parts.push((f.label || f.key) + ': ' + v + (u ? ' ' + u : ''));
  });
  return parts.join('; ');
}

/** Durations are stored in seconds; show them in minutes in the sheet. */
function fieldValue_(f) {
  if (f.type === 'duration') return f.unit === 'sec' ? nz_(f.value) : minutes_(f.value);
  return nz_(f.value);
}

function fieldUnit_(f) {
  if (f.type === 'duration') return f.unit === 'sec' ? 'sec' : 'min';
  return f.unit || '';
}

function minutes_(sec) {
  if (sec == null || sec === '') return '';
  return Math.round(sec / 60 * 100) / 100;
}

function nz_(v) { return v == null ? '' : v; }

function toDate_(iso) {
  if (!iso) return '';
  var d = new Date(iso);
  return isNaN(d.getTime()) ? iso : d;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
