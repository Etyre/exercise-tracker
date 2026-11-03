# Exercise Tracker

A Flutter app (iPhone + Android) for logging workouts. Data lives on the phone
and mirrors to a Google Sheet.

## What it does

- **Home screen** lists exercises by category (Cardio, Strength Training, plus
  any you add). Exercises can sit inside a collapsible group, e.g.
  *Pull Ups & Chin Ups ▸ Pull Ups / Chin Ups*.
- **Logging screen** starts a clock the moment you open it. Strength exercises
  show five set rows (warm-up checkbox, reps, weight) with an **Add set**
  button. Cardio exercises show their own fields (Zone 2 time; or for interval
  training: ramp up time, stable intense work time, less intense time, ramp up
  speed, stable speed, cycles, zone 5 time). Every exercise ends with a Notes
  box and a **Submit** button, which records start time, end time and duration.
- **History** per exercise (clock icon on the logging screen), with delete.
- **Settings**: lb/kg toggle, Google Sheet sync, and **Manage exercises**,
  where you can add a new exercise or edit an existing one: name, category,
  group, whether it tracks sets, and its list of fields (number, whole number,
  time in minutes, or text, each with an optional unit). Drag to reorder.
- **Offline first.** Every session is written to the phone the moment you
  hit Submit, whether or not there is internet. The Google Sheet is a mirror.
- **Google Sheet sync** pushes each session as soon as it is saved. If that
  fails (no signal, sheet unreachable) the session is flagged as pending and
  the app retries on launch, whenever it comes back to the foreground, and
  every 45 seconds while it is open, until the sheet confirms it. The cloud
  icon on the home screen shows how many are waiting. The sheet gets three tabs:
  `Sessions` (one row per workout: start, end, duration, every set, every
  field, notes), `Sets` (one row per set) and `Fields` (one row per field
  value). **Restore from sheet** pulls everything back onto a new phone.

## Run it on your iPhone

1. Plug the iPhone in with a cable (or have it on the same Wi-Fi with
   Developer Mode on), unlock it, and trust the Mac if asked.
2. Open `ios/Runner.xcworkspace` in Xcode once, select the *Runner* target ▸
   *Signing & Capabilities*, tick **Automatically manage signing** and pick
   your personal team (a free Apple ID works). Change the bundle identifier if
   Xcode says it is taken.
3. Then, from this folder:

   ```sh
   flutter devices          # confirm the phone is listed
   flutter run --release    # installs and launches on the phone
   ```

   The first time, iOS will ask you to trust the developer certificate under
   Settings ▸ General ▸ VPN & Device Management.

With a free Apple ID the install expires after 7 days; just run `flutter run`
again. A paid developer account removes that limit.

Android: install Android Studio (for the SDK), then `flutter run` with the
phone connected.

### Note on the build directory

This project lives in `~/Documents`, which iCloud Drive syncs. iCloud adds
extended attributes to `build/ios/.../Flutter.framework` that make codesign
fail with "resource fork, Finder information, or similar detritus not
allowed". To avoid that, `build/` is a symlink to
`~/Library/Caches/flutter-builds/exercise-tracker`, which iCloud ignores. If
the symlink is ever lost, recreate it:

```sh
mkdir -p ~/Library/Caches/flutter-builds/exercise-tracker
rm -rf build && ln -s ~/Library/Caches/flutter-builds/exercise-tracker build
```

## Set up the Google Sheet (about two minutes)

1. Create a new Google Sheet.
2. Extensions ▸ Apps Script. Delete the sample code and paste the contents of
   [`apps_script/Code.gs`](apps_script/Code.gs). (The app's Settings screen has
   a **Copy Apps Script code** button with the same contents.)
3. Deploy ▸ New deployment ▸ type **Web app**. *Execute as:* Me. *Who has
   access:* Anyone. Deploy, authorize, and copy the **Web app URL**.
4. In the app: Settings ▸ *Apps Script web app URL* ▸ paste ▸ save icon.
   To bake a URL into the build instead, copy `lib/config.example.dart` to
   `lib/config.dart` and set `kDefaultSheetUrl`. That file is gitignored
   because the URL lets anyone append rows to your sheet.

To limit the script's permission to this one spreadsheet (instead of all
your Google Sheets): before deploying, open Project Settings (gear icon),
tick **Show "appsscript.json" manifest file in editor**, open that file and
replace it with [`apps_script/appsscript.json`](apps_script/appsscript.json).
It requests only the `spreadsheets.currentonly` scope, which is all the
script needs.

Anyone holding that URL can append rows to your sheet, so don't share it.
If you ever edit `Code.gs`, redeploy (Deploy ▸ Manage deployments ▸ edit ▸
new version) and run `bash tool/embed_apps_script.sh` so the in-app copy
matches.

## Development

```sh
flutter pub get
flutter analyze
flutter test
```

Layout:

```
lib/
  main.dart                     app entry, theme, providers
  models/exercise.dart          Exercise + FieldDef (the editable schema)
  models/workout_session.dart   WorkoutSession, StrengthSet, FieldValue
  data/exercise_catalog.dart    default exercises seeded on first launch
  data/exercise_store.dart      editable exercise list (exercises.json)
  data/session_store.dart       logged sessions + sync queue (sessions.json)
  data/settings.dart            unit, sheet URL, last sync (SharedPreferences)
  sync/sheets_sync.dart         push/pull against the Apps Script endpoint
  screens/                      home, exercise (logging), history, settings,
                                manage_exercises, edit_exercise
apps_script/Code.gs             the Google Sheet side of the sync
```

Planned next: interval timers on the logging screen, and possibly Bluetooth
heart-rate monitor support. Both would hang off `ExerciseScreen` and add
values via the existing field mechanism.
