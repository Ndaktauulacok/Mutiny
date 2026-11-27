import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'services/library_store.dart';
import 'services/player_controller.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    // Lock-screen / notification controls and background playback.
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.amreel.mutiny.playback',
      androidNotificationChannelName: 'Mutiny playback',
      androidNotificationOngoing: true,
      notificationColor: MColors.violet,
    );
  }
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    // Windows/Linux audio engine (libmpv via media_kit).
    JustAudioMediaKit.ensureInitialized(windows: true, linux: true);
    JustAudioMediaKit.title = 'Mutiny';
  }

  SystemChrome.setSystemUIOverlayStyle(lightStatusBar);
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  final library = LibraryStore();
  await library.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider(create: (_) => PlayerController(library)),
      ],
      child: const MutinyApp(),
    ),
  );
}

class MutinyApp extends StatelessWidget {
  const MutinyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mutiny',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: const Shell(),
    );
  }
}
