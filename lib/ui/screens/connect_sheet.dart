import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../services/cloud_sync.dart';
import '../../services/connect_service.dart';
import '../effects.dart';
import '../glass.dart';
import '../theme.dart';

IconData _iconFor(String platform) => switch (platform) {
      'ios' || 'android' => Icons.smartphone_rounded,
      'windows' || 'mac' || 'desktop' => Icons.laptop_windows_rounded,
      'web' => Icons.language_rounded,
      _ => Icons.devices_other_rounded,
    };

/// "Play on" button (like Spotify Connect). Purple while another device is
/// being controlled; shows a dot when other devices are online.
class ConnectButton extends StatelessWidget {
  const ConnectButton({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ConnectService>();
    final remote = c.target != null;
    final others = c.devices.isNotEmpty;
    return IconButton(
      tooltip: 'Play on another device',
      onPressed: () => showConnectSheet(context),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(remote ? Icons.speaker_group_rounded : Icons.devices_rounded, size: size, color: remote || others ? MColors.purple : MColors.textSecondary),
          if (others && !remote)
            Positioned(
              right: -2,
              top: -2,
              child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: MColors.lavender, shape: BoxShape.circle)),
            ),
        ],
      ),
    );
  }
}

/// The list of the user's devices: pick where the music plays.
void showConnectSheet(BuildContext context) {
  showGlassSheet(context, builder: (_) => const _ConnectSheet());
}

class _ConnectSheet extends StatelessWidget {
  const _ConnectSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ConnectService>();
    final signedIn = context.select<CloudSync, bool>((s) => s.signedIn);
    final target = c.target;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Play on', style: MText.h2),
          const SizedBox(height: 4),
          const Text('Control music on your other devices, or play on each one separately.', style: MText.caption),
          const SizedBox(height: 16),
          _DeviceRow(
            icon: _iconFor(c.platform),
            name: 'This ${c.platform == 'ios' || c.platform == 'android' ? 'phone' : 'device'} · ${c.deviceName}',
            detail: target == null ? 'Playing here' : 'Tap to play here instead',
            selected: target == null,
            onTap: () {
              c.playOn(null);
              Navigator.pop(context);
            },
          ),
          if (!signedIn)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Sign in (Settings → Account & sync) on your devices to control one from another.', style: MText.body),
            )
          else if (c.devices.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'No other devices online. Open Mutiny on your laptop or phone, signed in to the same account, and it shows up here.',
                style: MText.body,
              ),
            )
          else
            for (final d in c.devices)
              _DeviceRow(
                icon: _iconFor(d.platform),
                name: d.name,
                detail: switch (d.state) {
                  final s? when s.track != null => '${s.playing ? 'Playing' : 'Paused'} · ${s.track!.title}',
                  _ => 'Online',
                },
                selected: target?.id == d.id,
                onTap: () {
                  c.playOn(d);
                  Navigator.pop(context);
                  toast(context, 'Now controlling ${d.name}');
                },
              ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.icon, required this.name, required this.detail, required this.selected, required this.onTap});

  final IconData icon;
  final String name;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Pressable(
        onTap: onTap,
        child: Glass(
          radius: 16,
          tint: selected ? MColors.purple : null,
          strength: selected ? 1.8 : 1,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: selected ? MColors.lavender : MColors.text, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: MText.title.copyWith(color: selected ? MColors.lavender : MColors.text)),
                    const SizedBox(height: 2),
                    Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: MText.caption),
                  ],
                ),
              ),
              if (selected) const EqualizerBars(size: 14),
            ],
          ),
        ),
      ),
    );
  }
}
