import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/exercise_store.dart';
import '../data/session_store.dart';
import '../data/settings.dart';
import '../sync/apps_script_source.dart';
import '../sync/sheets_sync.dart';
import '../util/format.dart';
import '../widgets/section_header.dart';
import 'manage_exercises_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _url;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: context.read<Settings>().sheetUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    final settings = context.read<Settings>();
    final sync = context.read<SheetsSync>();
    final messenger = ScaffoldMessenger.of(context);
    final url = _url.text.trim();
    if (url.isNotEmpty && !url.startsWith('https://script.google.com/')) {
      messenger.showSnackBar(const SnackBar(
        content: Text('That doesn\'t look like an Apps Script web app URL '
            '(it should start with https://script.google.com/).'),
      ));
      return;
    }
    FocusScope.of(context).unfocus();
    await settings.setSheetUrl(url);
    if (url.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Sync turned off')));
      return;
    }
    final err = await sync.pushPending();
    messenger.showSnackBar(SnackBar(
      content: Text(err == null ? 'Connected to Google Sheet' : 'Could not connect: $err'),
    ));
  }

  Future<void> _restore() async {
    final sync = context.read<SheetsSync>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final added = await sync.pullAll();
      messenger.showSnackBar(SnackBar(
        content: Text(added == 0
            ? 'Nothing new in the sheet'
            : 'Restored $added session${added == 1 ? '' : 's'} from the sheet'),
      ));
    } on SyncException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final sessions = context.watch<SessionStore>();
    final exercises = context.watch<ExerciseStore>();
    final sync = context.watch<SheetsSync>();
    final theme = Theme.of(context);

    final lastSync = settings.lastSyncAt;
    final lastError = settings.lastSyncError;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            SectionHeader('Weight unit'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'lb', label: Text('Pounds (lb)')),
                  ButtonSegment(value: 'kg', label: Text('Kilograms (kg)')),
                ],
                selected: {settings.weightUnit},
                onSelectionChanged: (s) => settings.setWeightUnit(s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Past sets keep the unit you typed them in and are converted for display.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            SectionHeader('Exercises'),
            ListTile(
              leading: const Icon(Icons.list_alt_outlined),
              title: const Text('Manage exercises'),
              subtitle: Text(
                  '${exercises.all.length} exercises · add new ones, edit fields, reorder'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ManageExercisesScreen(),
              )),
            ),
            SectionHeader('Google Sheet sync'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Apps Script web app URL',
                  hintText: 'https://script.google.com/macros/s/…/exec',
                  suffixIcon: IconButton(
                    tooltip: 'Save',
                    icon: const Icon(Icons.save_outlined),
                    onPressed: _saveUrl,
                  ),
                ),
                onSubmitted: (_) => _saveUrl(),
              ),
            ),
            if (settings.syncEnabled) ...[
              ListTile(
                leading: Icon(
                  lastError != null
                      ? Icons.cloud_off_outlined
                      : sessions.pendingCount > 0
                          ? Icons.cloud_upload_outlined
                          : Icons.cloud_done_outlined,
                  color: lastError != null ? theme.colorScheme.error : null,
                ),
                title: Text(lastError != null
                    ? 'Last sync failed'
                    : sessions.pendingCount > 0
                        ? '${sessions.pendingCount} waiting to sync'
                        : 'Everything is synced'),
                subtitle: Text([
                  if (lastError != null)
                    sessions.pendingCount > 0
                        ? '$lastError Saved on this phone; will retry automatically.'
                        : lastError,
                  if (lastSync != null) 'Last successful sync ${fmtDateTime(lastSync)}',
                ].join('\n')),
                isThreeLine: lastError != null && lastSync != null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: sync.isSyncing
                            ? null
                            : () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final err = await sync.pushPending();
                                messenger.showSnackBar(SnackBar(
                                  content: Text(err == null
                                      ? 'Synced with Google Sheet'
                                      : 'Sync failed: $err'),
                                ));
                              },
                        icon: sync.isSyncing
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.sync),
                        label: const Text('Sync now'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: sync.isSyncing ? null : _restore,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('Restore from sheet'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ExpansionTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('How to set up the Google Sheet'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Step(1, 'Create a new Google Sheet (any name).'),
                const _Step(2, 'In the sheet, open Extensions ▸ Apps Script. '
                    'Delete the sample code and paste the script copied below.'),
                const _Step(3, 'Click Deploy ▸ New deployment. Choose type "Web app", '
                    'set "Execute as" to Me and "Who has access" to Anyone, then Deploy '
                    'and authorize.'),
                const _Step(4, 'Copy the Web app URL and paste it in the field above.'),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await Clipboard.setData(const ClipboardData(text: appsScriptSource));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Apps Script copied to clipboard')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy Apps Script code'),
                ),
                const SizedBox(height: 8),
                Text(
                  'The script writes three tabs: Sessions (one row per workout with '
                  'start time, end time, duration, every set, every field and notes), '
                  'Sets (one row per set) and Fields (one row per field value). '
                  'Anyone with the URL can add rows, so keep it to yourself.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.text);
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 11, child: Text('$n', style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
