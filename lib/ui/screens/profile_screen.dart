import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/library_store.dart';
import '../../services/player_controller.dart';
import '../glass.dart';
import '../theme.dart';
import '../widgets.dart';
import 'collection_screen.dart';
import 'account_sheet.dart';
import 'settings_sheet.dart';

/// Your profile: photo, name, listening stats, top artists and songs.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final top = MediaQuery.paddingOf(context).top;
    final topSongs = lib.topTracks(limit: 10, within: const Duration(days: 30));
    final topArtists = lib.topArtists();
    final minutes = lib.totalListenMinutes;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: EdgeInsets.only(top: top + 8, bottom: bottomInset(context)),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, iconSize: 17, onTap: () => Navigator.maybePop(context)),
                const Spacer(),
                const SyncBadge(),
                const SizedBox(width: 8),
                GlassIconButton(icon: Icons.settings_rounded, iconSize: 20, tooltip: 'Settings', onTap: () => showSettingsSheet(context)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Pressable(
              onTap: () => showEditProfile(context),
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: MColors.violet.withValues(alpha: 0.45), blurRadius: 50, offset: const Offset(0, 16))],
                    ),
                    child: ProfileAvatar(profile: lib.profile, size: 132),
                  ),
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: MColors.lavender, shape: BoxShape.circle),
                      child: const Icon(Icons.edit_rounded, size: 16, color: MColors.bg),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(lib.profile.name, style: MText.h1, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            '${lib.playlists.length} playlists · ${lib.followedArtists.length} following',
            style: MText.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Center(child: PillButton(label: 'Edit profile', icon: Icons.edit_rounded, compact: true, onTap: () => showEditProfile(context))),
          const SignInCard(),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _StatCard(value: compactNumber(minutes), label: 'minutes listened'),
                const SizedBox(width: 10),
                _StatCard(value: '${lib.liked.length}', label: 'liked songs'),
                const SizedBox(width: 10),
                _StatCard(value: '${lib.stats.values.where((s) => s.plays > 0 && !s.track.isLive).length}', label: 'songs played'),
              ],
            ),
          ),
          if (topArtists.isNotEmpty) ...[
            const SectionHeader('Top', accentWord: 'artists'),
            HorizontalList(
              height: 170,
              itemCount: topArtists.length,
              itemBuilder: (_, i) {
                final (name, id, art, mins) = topArtists[i];
                return CoverCard(
                  size: 112,
                  circle: true,
                  title: name,
                  subtitle: '$mins min',
                  artworkUrl: art,
                  icon: Icons.person_rounded,
                  onTap: id == null
                      ? () {}
                      : () => Navigator.of(context).push(FadeRoute(CollectionScreen.artist(artist: Artist(id: id, name: name, avatarUrl: art)))),
                );
              },
            ),
          ],
          if (topSongs.isNotEmpty) ...[
            const SectionHeader('Top songs', accentWord: 'this month'),
            for (final (i, st) in topSongs.indexed)
              TrackTile(
                track: st.track,
                index: i,
                showArtwork: true,
                onTap: () => player.playTracks([for (final s in topSongs) s.track], index: i, from: 'Your top songs'),
              ),
          ],
          if (topSongs.isEmpty && topArtists.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(40, 34, 40, 0),
              child: Text(
                'Play some music and your top songs and artists will show up here.',
                style: MText.body,
                textAlign: TextAlign.center,
              ),
            ),
          if (lib.playlists.isNotEmpty) ...[
            const SectionHeader('Your', accentWord: 'playlists'),
            HorizontalList(
              itemCount: lib.playlists.length,
              itemBuilder: (_, i) {
                final p = lib.playlists[i];
                return CoverCard(
                  title: p.name,
                  subtitle: '${p.tracks.length} songs',
                  cover: PlaylistCover(playlist: p, radius: 16),
                  onTap: () => Navigator.of(context).push(FadeRoute(CollectionScreen.userPlaylist(p))),
                );
              },
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Listening since ${_monthYear(lib.profile.since)}',
            style: MText.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static String _monthYear(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.year}';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Glass(
          radius: 18,
          blur: 16,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Column(
            children: [
              Text(value, style: MText.h2.copyWith(color: MColors.lilac)),
              const SizedBox(height: 4),
              Text(label, style: MText.caption, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

bool get _hasCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Sheet to change the profile photo and name.
void showEditProfile(BuildContext context) {
  final lib = context.read<LibraryStore>();
  final ctrl = TextEditingController(text: lib.profile.name);
  showGlassSheet(
    context,
    builder: (ctx) => ListenableBuilder(
      listenable: lib,
      builder: (ctx, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Edit profile', style: MText.h2),
            const SizedBox(height: 20),
            ProfileAvatar(profile: lib.profile, size: 110),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                PillButton(
                  label: 'Choose photo',
                  icon: Icons.photo_library_rounded,
                  compact: true,
                  onTap: () => lib.pickAvatar(),
                ),
                if (_hasCamera)
                  PillButton(
                    label: 'Take photo',
                    icon: Icons.photo_camera_rounded,
                    compact: true,
                    onTap: () => lib.pickAvatar(source: ImageSource.camera),
                  ),
                if (lib.profile.avatarPath != null)
                  PillButton(label: 'Remove', icon: Icons.delete_outline_rounded, compact: true, onTap: lib.removeAvatar),
              ],
            ),
            const SizedBox(height: 22),
            TextField(
              controller: ctrl,
              textAlign: TextAlign.center,
              maxLength: 30,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: MColors.text),
              decoration: const InputDecoration(
                labelText: 'Name',
                counterText: '',
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: MColors.glassBorder)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: MColors.lavender)),
              ),
            ),
            const SizedBox(height: 22),
            PillButton(
              label: 'Save',
              filled: true,
              onTap: () {
                lib.setProfileName(ctrl.text);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    ),
  );
}
