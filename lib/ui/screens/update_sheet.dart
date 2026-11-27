import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/updater.dart';
import '../glass.dart';
import '../theme.dart';

bool _checkedThisLaunch = false;

/// Quietly checks GitHub for a newer Mutiny once per launch.
Future<void> autoCheckForUpdate(BuildContext context) async {
  if (_checkedThisLaunch || kIsWeb) return;
  _checkedThisLaunch = true;
  try {
    final info = await Updater.check();
    if (info != null && context.mounted) showUpdateSheet(context, info);
  } catch (_) {
    // Offline or GitHub unreachable: try again next launch.
  }
}

/// "Check for updates" from Settings: always tells the user the result.
Future<void> manualCheckForUpdate(BuildContext context) async {
  toast(context, 'Checking for updates…');
  try {
    final info = await Updater.check();
    if (!context.mounted) return;
    if (info == null) {
      final (v, _) = await Updater.current();
      if (context.mounted) toast(context, "You're on the latest version ($v)");
    } else {
      showUpdateSheet(context, info);
    }
  } catch (_) {
    if (context.mounted) toast(context, "Couldn't check. Are you online?");
  }
}

void showUpdateSheet(BuildContext context, UpdateInfo info) {
  showGlassSheet(context, builder: (_) => _UpdateView(info: info));
}

class _UpdateView extends StatefulWidget {
  const _UpdateView({required this.info});
  final UpdateInfo info;

  @override
  State<_UpdateView> createState() => _UpdateViewState();
}

class _UpdateViewState extends State<_UpdateView> {
  double? _progress;
  String? _error;
  StreamSubscription<double>? _sub;

  bool get _isIOS => !kIsWeb && Platform.isIOS;
  bool get _canInstall => !kIsWeb && (Platform.isAndroid || Platform.isWindows) && widget.info.platformUrl != null;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _install() {
    final url = widget.info.platformUrl!;
    setState(() {
      _progress = 0;
      _error = null;
    });
    final stream = Platform.isAndroid ? Updater.installAndroid(url) : Updater.installWindows(url);
    _sub = stream.listen(
      (p) => setState(() => _progress = p),
      onError: (Object e) => setState(() {
        _progress = null;
        _error = Platform.isAndroid
            ? "Couldn't install. Allow Mutiny to install apps when Android asks, then try again."
            : "Couldn't update. Download it from the release page instead.";
      }),
      onDone: () {
        if (mounted && Platform.isAndroid) Navigator.maybePop(context);
      },
    );
  }

  Future<void> _openPage() => launchUrl(Uri.parse(widget.info.pageUrl), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final notes = info.notes.split('\n').where((l) => l.trim().isNotEmpty && !l.startsWith('Co-Authored') && !l.startsWith('Claude-Session')).take(6).join('\n');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/brand/mark.png', width: 56, height: 56),
          const SizedBox(height: 14),
          const Text('Update available', style: MText.h2),
          const SizedBox(height: 4),
          Text('Mutiny ${info.version}', style: MText.body.copyWith(color: MColors.lavender)),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 140),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(16)),
              child: SingleChildScrollView(child: Text(notes, style: MText.body)),
            ),
          ],
          if (_isIOS) ...[
            const SizedBox(height: 16),
            const Text(
              'On iPhone, download the new Mutiny-iOS.ipa on your laptop and install it with Sideloadly, '
              'just like the first time. Your likes and playlists stay.',
              style: MText.body,
              textAlign: TextAlign.center,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: MText.body.copyWith(color: const Color(0xFFFF8FA3)), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 20),
          if (_progress != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 6,
                backgroundColor: const Color(0x22FFFFFF),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _progress! >= 1
                  ? (Platform.isWindows ? 'Restarting Mutiny…' : 'Opening installer…')
                  : 'Downloading ${(_progress! * 100).round()}%',
              style: MText.caption,
            ),
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PillButton(label: 'Later', onTap: () => Navigator.maybePop(context)),
                const SizedBox(width: 12),
                if (_canInstall)
                  PillButton(label: 'Update now', icon: Icons.download_rounded, filled: true, onTap: _install)
                else
                  PillButton(label: 'Open download page', icon: Icons.open_in_new_rounded, filled: true, onTap: _openPage),
              ],
            ),
        ],
      ),
    );
  }
}
