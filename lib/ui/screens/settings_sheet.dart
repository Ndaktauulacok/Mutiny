import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../services/library_store.dart';
import '../../services/updater.dart';
import '../glass.dart';
import '../theme.dart';
import 'account_sheet.dart';
import 'update_sheet.dart';

void showSettingsSheet(BuildContext context) {
  final lib = context.read<LibraryStore>();
  showGlassSheet(
    context,
    builder: (ctx) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Mutiny', style: MText.h1, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            const Text('Free music. No ads. No subscription.', style: MText.body, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            const _InfoRow(
              icon: Icons.graphic_eq_rounded,
              title: 'Audius',
              text: 'Streaming songs from independent artists, free and legal.',
            ),
            const _InfoRow(
              icon: Icons.radio_rounded,
              title: 'Radio Browser',
              text: 'Thousands of live radio stations worldwide.',
            ),
            const _InfoRow(
              icon: Icons.folder_rounded,
              title: 'Your files',
              text: 'Music you import stays on this device only.',
            ),
            const Divider(color: MColors.hairline, height: 28),
            SheetAction(
              icon: Icons.devices_rounded,
              label: 'Account & sync',
              onTap: () {
                Navigator.pop(ctx);
                showAccountSheet(context);
              },
            ),
            SheetAction(
              icon: Icons.system_update_rounded,
              label: 'Check for updates',
              onTap: () {
                Navigator.pop(ctx);
                manualCheckForUpdate(context);
              },
            ),
            SheetAction(
              icon: Icons.history_toggle_off_rounded,
              label: 'Clear listening & search history',
              onTap: () {
                lib.clearHistory();
                Navigator.pop(ctx);
                toast(context, 'History cleared');
              },
            ),
            const SizedBox(height: 10),
            FutureBuilder<(String, int)>(
              future: Updater.current(),
              builder: (_, snap) => Text(
                'Version ${snap.data?.$1 ?? '…'} · Made in Sungai Petani',
                style: MText.caption,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: MColors.lavender, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: MText.title),
                  const SizedBox(height: 2),
                  Text(text, style: MText.body),
                ],
              ),
            ),
          ],
        ),
      );
}
