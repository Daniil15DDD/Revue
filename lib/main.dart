import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'ai.dart';
import 'models.dart';
import 'pages/assistant_page.dart';
import 'pages/library_page.dart';
import 'pages/settings_page.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Debug-only: `flutter run --dart-define=REVUE_PLATFORM=ios` previews the iPhone UI on Android.
  if (const String.fromEnvironment('REVUE_PLATFORM') == 'ios') debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  await FlutterGemma.initialize(); // required before any model install/inference call
  final docs = await getApplicationDocumentsDirectory();
  final llm = GemmaLlm();
  final store = Store(Directory('${docs.path}/revue'), llm: () => llm.ready ? llm : null);
  await store.load();
  unawaited(llm.restore().catchError((Object e) => debugPrint('model restore failed: $e')));
  runApp(RevueApp(store: store, llm: llm));
}

class RevueApp extends StatefulWidget {
  const RevueApp({super.key, required this.store, required this.llm, this.listenForShares = true});
  final Store store;
  final GemmaLlm llm;
  final bool listenForShares; // off in widget tests (no platform channels)

  @override
  State<RevueApp> createState() => _RevueAppState();
}

class _RevueAppState extends State<RevueApp> {
  StreamSubscription? _shares;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    if (widget.listenForShares) {
      // Things shared into Revue from YouTube, Safari, Photos, etc. — while running and at cold start.
      _shares = ReceiveSharingIntent.instance.getMediaStream().listen(_onShared);
      ReceiveSharingIntent.instance.getInitialMedia().then((files) {
        _onShared(files);
        ReceiveSharingIntent.instance.reset();
      });
    }
  }

  void _onShared(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    setState(() => _tab = 0);
    for (final f in files) {
      final Future<Item>? future = switch (f.type) {
        SharedMediaType.image => widget.store.addScreenshot(f.path),
        SharedMediaType.text || SharedMediaType.url => widget.store.addText(f.path),
        _ => null,
      };
      if (future != null) {
        _messenger.currentState?.showSnackBar(const SnackBar(content: Text('Saved to Revue')));
        future.then<void>((_) {}, onError: (Object e) {
          _messenger.currentState?.showSnackBar(SnackBar(content: Text('Could not save: $e')));
        });
      }
    }
  }

  @override
  void dispose() {
    _shares?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = defaultTargetPlatform;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => MaterialApp(
      title: 'Revue',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messenger,
      theme: revueTheme(Brightness.light, platform),
      darkTheme: revueTheme(Brightness.dark, platform),
      themeMode: switch (widget.store.appearance) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: Scaffold(
        body: IndexedStack(index: _tab, children: [
          LibraryPage(store: widget.store),
          AssistantPage(store: widget.store, llm: widget.llm, openSettings: () => setState(() => _tab = 2)),
          SettingsPage(llm: widget.llm, store: widget.store),
        ]),
        bottomNavigationBar: platform == TargetPlatform.iOS
            ? CupertinoTabBar(
                currentIndex: _tab,
                onTap: (i) => setState(() => _tab = i),
                items: const [
                  BottomNavigationBarItem(icon: Icon(CupertinoIcons.square_grid_2x2), activeIcon: Icon(CupertinoIcons.square_grid_2x2_fill), label: 'Library'),
                  BottomNavigationBarItem(icon: Icon(CupertinoIcons.sparkles), label: 'Ask'),
                  BottomNavigationBarItem(icon: Icon(CupertinoIcons.gear), activeIcon: Icon(CupertinoIcons.gear_solid), label: 'Settings'),
                ],
              )
            : NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'Library'),
                  NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'Ask'),
                  NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Settings'),
                ],
              ),
      ),
      ),
    );
  }
}
