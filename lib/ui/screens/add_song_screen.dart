import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/library_store.dart';
import '../../services/lyrics_api.dart';
import '../glass.dart';
import '../theme.dart';
import '../widgets.dart';

/// Add your own song (audio file + name, artist, cover, lyrics), or edit
/// one you added before. Own songs stay private on this device.
class AddSongScreen extends StatefulWidget {
  const AddSongScreen({super.key, this.editing});

  /// The song being edited, or null to add a new one.
  final Track? editing;

  @override
  State<AddSongScreen> createState() => _AddSongScreenState();
}

class _AddSongScreenState extends State<AddSongScreen> {
  late final _title = TextEditingController(text: widget.editing?.title ?? '');
  late final _artist = TextEditingController(text: widget.editing?.artist ?? '');
  late final _lyrics = TextEditingController();

  String? _audioPath;
  String? _audioName;
  int? _durationSec;
  String? _coverPath;
  bool _coverRemoved = false;
  bool _busy = false;
  bool _saved = false;

  bool get _editing => widget.editing != null;
  bool get _hasCamera => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    final t = widget.editing;
    if (t != null) {
      _lyrics.text = context.read<LibraryStore>().lyricsFor(t) ?? '';
      _durationSec = t.durationSec;
    }
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    // Left without saving: don't keep the copied file / picked cover around.
    if (!_saved && !kIsWeb) {
      for (final path in [_audioPath, _coverPath]) {
        if (path == null) continue;
        try {
          final f = File(path);
          if (f.existsSync()) f.deleteSync();
        } catch (_) {}
      }
    }
    _title.dispose();
    _artist.dispose();
    _lyrics.dispose();
    super.dispose();
  }

  String? get _shownCover {
    if (_coverPath != null) return _coverPath;
    if (_coverRemoved) return null;
    return widget.editing?.artworkUrl;
  }

  Future<void> _pickAudio() async {
    final lib = context.read<LibraryStore>();
    setState(() => _busy = true);
    try {
      final picked = await lib.pickSongFile();
      if (picked == null) return;
      final (path, name) = picked;
      if (_audioPath != null) {
        try {
          File(_audioPath!).deleteSync();
        } catch (_) {}
      }
      _audioPath = path;
      _audioName = name;
      if (_title.text.trim().isEmpty || _artist.text.trim().isEmpty) {
        final (artist, title) = LibraryStore.parseFileName(name);
        if (_title.text.trim().isEmpty) _title.text = title;
        if (_artist.text.trim().isEmpty && artist != 'Unknown artist') _artist.text = artist;
      }
      _durationSec = await _readDuration(path);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Future<int?> _readDuration(String path) async {
    final p = AudioPlayer();
    try {
      final d = await p.setFilePath(path, preload: true).timeout(const Duration(seconds: 6));
      return d?.inSeconds;
    } catch (_) {
      return null;
    } finally {
      await p.dispose();
    }
  }

  Future<void> _pickCover(ImageSource source) async {
    final path = await context.read<LibraryStore>().pickSongCover(source: source);
    if (path != null) {
      setState(() {
        _coverPath = path;
        _coverRemoved = false;
      });
    }
  }

  void _save() {
    _saved = true;
    final lib = context.read<LibraryStore>();
    final nav = Navigator.of(context);
    if (_editing) {
      lib.updateOwnSong(
        widget.editing!,
        title: _title.text,
        artist: _artist.text,
        coverPath: _coverPath,
        removeCover: _coverRemoved && _coverPath == null,
        lyrics: _lyrics.text,
      );
      toast(context, 'Song updated');
      nav.pop();
      return;
    }
    final track = lib.addOwnSong(
      audioPath: _audioPath!,
      title: _title.text,
      artist: _artist.text,
      coverPath: _coverPath,
      lyrics: _lyrics.text,
      durationSec: _durationSec,
    );
    final parent = nav.context;
    nav.pop();
    toast(parent, 'Added to My songs');
    // Offer to put it straight into a playlist, like "Add to playlist".
    Future.delayed(const Duration(milliseconds: 350), () {
      if (parent.mounted) showAddToPlaylist(parent, track);
    });
  }

  void _delete() {
    final lib = context.read<LibraryStore>();
    showGlassSheet(
      context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Delete this song?', style: MText.h2),
            const SizedBox(height: 8),
            const Text(
              "It will be removed from My songs, Liked Songs and all your playlists. This can't be undone.",
              style: MText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PillButton(label: 'Cancel', onTap: () => Navigator.pop(ctx)),
                const SizedBox(width: 12),
                PillButton(
                  label: 'Delete',
                  icon: Icons.delete_outline_rounded,
                  filled: true,
                  onTap: () {
                    lib.removeLocal(widget.editing!);
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final canSave = !_busy && _title.text.trim().isNotEmpty && (_editing || _audioPath != null);
    final synced = LyricsApi.parseLrc(_lyrics.text).isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, top + 8, 20, bottomInset(context)),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Row(
              children: [
                GlassIconButton(icon: Icons.close_rounded, onTap: () => Navigator.maybePop(context)),
                Expanded(child: Text(_editing ? 'Edit song' : 'Add your song', style: MText.h2, textAlign: TextAlign.center)),
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: 22),

            // Cover / banner
            Center(
              child: Pressable(
                onTap: () => _coverMenu(),
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [BoxShadow(color: MColors.violet.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 16))],
                  ),
                  child: _shownCover == null
                      ? Glass(
                          radius: 22,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_photo_alternate_rounded, color: MColors.lavender, size: 44),
                                SizedBox(height: 8),
                                Text('Add cover', style: MText.title),
                                Text('optional', style: MText.caption),
                              ],
                            ),
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Artwork(url: _shownCover, radius: 22),
                            const Positioned(
                              right: 10,
                              bottom: 10,
                              child: CircleAvatar(
                                radius: 17,
                                backgroundColor: MColors.lavender,
                                child: Icon(Icons.edit_rounded, size: 17, color: MColors.bg),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Audio file
            if (!_editing)
              Pressable(
                onTap: _busy ? null : _pickAudio,
                child: Glass(
                  radius: 18,
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _audioPath == null ? const Color(0x22C4B5FD) : MColors.lavender,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _busy
                            ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(
                                _audioPath == null ? Icons.audio_file_rounded : Icons.check_rounded,
                                color: _audioPath == null ? MColors.lavender : MColors.bg,
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_audioName ?? 'Choose audio file', style: MText.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(
                              _audioPath == null
                                  ? 'MP3, M4A, WAV, FLAC…'
                                  : _durationSec == null
                                      ? 'Ready'
                                      : 'Length ${formatDuration(Duration(seconds: _durationSec!))} · tap to change',
                              style: MText.caption,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: MColors.textTertiary),
                    ],
                  ),
                ),
              ),
            if (!_editing) const SizedBox(height: 16),

            _Input(controller: _title, label: 'Song name', icon: Icons.music_note_rounded),
            const SizedBox(height: 12),
            _Input(controller: _artist, label: 'Artist / singer', icon: Icons.mic_rounded),
            const SizedBox(height: 12),
            _Input(
              controller: _lyrics,
              label: 'Lyrics (optional)',
              icon: Icons.lyrics_rounded,
              lines: 8,
              hint: 'Paste the lyrics here.\nFor lyrics that move with the song, start lines with the time:\n[00:12] First line\n[00:17] Second line',
              onChanged: (_) => setState(() {}),
            ),
            if (_lyrics.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  synced ? '✓ Timed lyrics: they will move with the song' : 'Plain lyrics: add [mm:ss] times to make them move with the song',
                  style: MText.caption.copyWith(color: synced ? MColors.lavender : MColors.textTertiary),
                ),
              ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.lock_rounded, size: 16, color: MColors.lavender),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only you can see this song. It stays on this device and is never published. You can add it to any playlist.',
                    style: MText.caption.copyWith(color: MColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Opacity(
                opacity: canSave ? 1 : 0.45,
                child: PillButton(
                  label: _editing ? 'Save changes' : 'Add song',
                  icon: _editing ? Icons.check_rounded : Icons.add_rounded,
                  filled: true,
                  onTap: canSave ? _save : null,
                ),
              ),
            ),
            if (_editing) ...[
              const SizedBox(height: 14),
              Center(
                child: TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF8FA3), size: 18),
                  label: const Text('Delete song', style: TextStyle(color: Color(0xFFFF8FA3), fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _coverMenu() {
    showGlassSheet(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          SheetAction(
            icon: Icons.photo_library_rounded,
            label: 'Choose from photos',
            onTap: () {
              Navigator.pop(ctx);
              _pickCover(ImageSource.gallery);
            },
          ),
          if (_hasCamera)
            SheetAction(
              icon: Icons.photo_camera_rounded,
              label: 'Take a photo',
              onTap: () {
                Navigator.pop(ctx);
                _pickCover(ImageSource.camera);
              },
            ),
          if (_shownCover != null)
            SheetAction(
              icon: Icons.hide_image_rounded,
              label: 'Remove cover',
              danger: true,
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _coverPath = null;
                  _coverRemoved = true;
                });
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Input extends StatelessWidget {
  const _Input({required this.controller, required this.label, required this.icon, this.lines = 1, this.hint, this.onChanged});

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int lines;
  final String? hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 20,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 16, color: MColors.text, fontWeight: FontWeight.w500, height: 1.4),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          alignLabelWithHint: lines > 1,
          hintStyle: const TextStyle(color: MColors.textTertiary, fontSize: 13.5),
          labelStyle: const TextStyle(color: MColors.textTertiary),
          prefixIcon: lines == 1 ? Icon(icon, color: MColors.lavender, size: 20) : null,
          filled: true,
          fillColor: const Color(0x14FFFFFF),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: MColors.glassBorder, width: 0.8),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: MColors.lavender),
          ),
        ),
      );
}
