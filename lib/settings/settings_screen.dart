import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../google/backup.dart';
import '../google/google_auth.dart';
import '../ink/handwriting.dart';
import '../notify/notifier.dart';
import '../recording/transcriber.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = GoogleAuth.instance;
  bool _accurate = false;
  bool _includeRecordings = false;
  DateTime? _lastBackup;
  String? _busy;
  String? _inkStatus;

  @override
  void initState() {
    super.initState();
    _load();
    _auth.addListener(_rebuild);
  }

  @override
  void dispose() {
    _auth.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final a = await Transcriber.accurate();
    final b = await Backup.lastBackup();
    final ink = await Handwriting.isReady();
    if (mounted) {
      setState(() {
        _accurate = a;
        _lastBackup = b;
        _inkStatus = ink ? 'Ready' : 'Not downloaded yet';
      });
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg.replaceFirst('Exception: ', ''))));

  Future<void> _run(String label, Future<void> Function() job, {String? done}) async {
    setState(() => _busy = label);
    try {
      await job();
      if (done != null && mounted) _snack(done);
    } catch (e) {
      if (mounted) _snack('$e');
    }
    if (mounted) setState(() => _busy = null);
    _load();
  }

  Future<void> _restore() async {
    final ok = await confirmDelete(
      context,
      'everything on this tablet and restore the backup',
      detail: 'All modules, notes and drawings here will be replaced by the backup. '
          'The app will close afterwards; just open it again.',
    );
    if (!ok) return;
    await _run('Restoring…', Backup.restoreLatest);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Restored'),
        content: const Text('The app will now close. Open it again to see your restored work.'),
        actions: [
          FilledButton(onPressed: () => SystemNavigator.pop(), child: const Text('Close app')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: const SectionAppBar(title: 'Settings'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.l, 0, AppSpace.l, 140),
        children: [
          if (_busy != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.m),
              child: Row(children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: AppSpace.s),
                Text(_busy!),
              ]),
            ),

          // ── Google ──
          _Section(
            title: 'Google account',
            subtitle: 'Used for Google Calendar, turning PowerPoints into PDFs, and backups.',
            children: [
              if (!GoogleAuth.configured)
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Google isn\'t set up in this build yet'),
                  subtitle: Text('Add the client ID in lib/theme/app_theme.dart (see README).'),
                )
              else if (_auth.signedIn)
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined, color: AppPalette.moneyIn),
                  title: Text(_auth.email ?? 'Connected'),
                  subtitle: const Text('Connected'),
                  trailing: TextButton(
                    onPressed: _busy != null ? null : () => _run('Disconnecting…', _auth.signOut),
                    child: const Text('Disconnect'),
                  ),
                )
              else
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: const Text('Not connected'),
                  trailing: FilledButton(
                    onPressed: _busy != null
                        ? null
                        : () => _run('Opening Google…', () async {
                              final err = await _auth.signIn();
                              if (err != null) throw Exception(err);
                            }, done: 'Google connected!'),
                    child: const Text('Connect Google'),
                  ),
                ),
            ],
          ),

          // ── Backup ──
          _Section(
            title: 'Backup',
            subtitle: 'Saves modules, PDFs, notes, drawings and everything else to a private '
                'folder in your Google Drive that only this app can see.',
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_done_outlined),
                title: Text(_lastBackup == null
                    ? 'No backup yet'
                    : 'Last backup: ${friendlyDay(_lastBackup!)} ${hhmm(_lastBackup!)}'),
              ),
              SwitchListTile(
                title: const Text('Include recordings'),
                subtitle: const Text('Recordings are big (about 30 MB per hour).'),
                value: _includeRecordings,
                onChanged: (v) => setState(() => _includeRecordings = v),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.m, 0, AppSpace.m, AppSpace.m),
                child: Wrap(spacing: AppSpace.s, children: [
                  FilledButton.icon(
                    onPressed: (!_auth.signedIn || _busy != null)
                        ? null
                        : () => _run('Backing up…',
                            () => Backup.backUpNow(includeRecordings: _includeRecordings),
                            done: 'Backup saved to Google Drive'),
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Back up now'),
                  ),
                  OutlinedButton.icon(
                    onPressed: (!_auth.signedIn || _busy != null) ? null : _restore,
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore from backup'),
                  ),
                ]),
              ),
            ],
          ),

          // ── Transcription ──
          _Section(
            title: 'Transcribing recordings',
            subtitle: 'Runs on the tablet. The speech model downloads once, the first time.',
            children: [
              RadioGroup<bool>(
                groupValue: _accurate,
                onChanged: (v) async {
                  if (v == null) return;
                  await Transcriber.setAccurate(v);
                  setState(() => _accurate = v);
                },
                child: const Column(children: [
                  RadioListTile<bool>(
                    value: false,
                    title: Text('Quick'),
                    subtitle: Text('Faster, ~75 MB download. Good for clear lectures.'),
                  ),
                  RadioListTile<bool>(
                    value: true,
                    title: Text('Accurate'),
                    subtitle: Text('About twice as slow, ~142 MB download. Better with accents and noise.'),
                  ),
                ]),
              ),
            ],
          ),

          // ── Handwriting ──
          _Section(
            title: 'Handwriting to text',
            subtitle: 'In a note, pick the lasso tool, circle some writing, then tap "To text".',
            children: [
              ListTile(
                leading: const Icon(Icons.draw_outlined),
                title: Text('English model: ${_inkStatus ?? '…'}'),
                trailing: TextButton(
                  onPressed: _busy != null
                      ? null
                      : () => _run('Downloading handwriting model…', () async {
                            if (!await Handwriting.ensureModel()) {
                              throw Exception(
                                  'Couldn\'t download the handwriting model on this device. Check the internet connection.');
                            }
                          }, done: 'Handwriting model ready'),
                  child: const Text('Download / check'),
                ),
              ),
            ],
          ),

          // ── Notifications ──
          _Section(
            title: 'Notifications',
            subtitle: 'For the focus timer and to-do reminders.',
            children: [
              ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Send a test notification'),
                trailing: TextButton(
                  onPressed: () async {
                    await Notifier.askPermissionsOnce();
                    await Notifier.test();
                  },
                  child: const Text('Test'),
                ),
              ),
              const ListTile(
                leading: Icon(Icons.battery_alert_outlined),
                title: Text('If reminders arrive late'),
                subtitle: Text(
                    'In the tablet\'s Settings → Apps → Zee → Battery (or App launch), allow it to run in the background.'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.m),
          Text('Tip: long-press the hand icon in the drawing toolbar to check how the pen is detected.',
              style: t.bodySmall?.copyWith(color: AppPalette.muted)),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.subtitle, required this.children});
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.m),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.s),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.m, AppSpace.s, AppSpace.m, 2),
              child: Text(title, style: t.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.m, 0, AppSpace.m, AppSpace.s),
              child: Text(subtitle, style: const TextStyle(color: AppPalette.muted, fontSize: 13)),
            ),
            ...children,
          ]),
        ),
      ),
    );
  }
}
