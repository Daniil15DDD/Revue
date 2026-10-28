import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'ai.dart';
import 'adaptive.dart';
import 'launch_splash.dart';
import 'models.dart';
import 'pages/add_menu.dart';
import 'pages/assistant_page.dart';
import 'pages/home_page.dart';
import 'pages/list_editor.dart';
import 'pages/list_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'pages/stats_page.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

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
  await precacheLaunchLogo(); // first frame must already show the logo
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
  final _nav = GlobalKey<NavigatorState>();
  int _tab = 0; // 0 Home · 1 Ask · 2 Stats · 3 Settings

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
    _nav.currentState?.popUntil((r) => r.isFirst);
    for (final f in files) {
      final Future<Item>? future = switch (f.type) {
        SharedMediaType.image => widget.store.addScreenshot(f.path),
        SharedMediaType.text || SharedMediaType.url => widget.store.addText(f.path),
        _ => null,
      };
      if (future != null) {
        _messenger.currentState?.showSnackBar(const SnackBar(content: Text('Saved to your Inbox')));
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

  void _toast(String text) => _messenger.currentState?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _onPlus(Rect from) async {
    final ctx = _nav.currentContext;
    if (ctx == null) return;
    final store = widget.store;
    // ignore: use_build_context_synchronously — ctx is the navigator's own context, read just above with no gap.
    switch (await showAddMenu(ctx, from: from)) {
      case AddAction.list:
        if (!ctx.mounted) return;
        final l = await showListEditor(ctx, store);
        if (l != null && ctx.mounted) Navigator.push(ctx, revueRoute(ListPage(store: store, list: l)));
      case AddAction.search:
        if (ctx.mounted) Navigator.push(ctx, revueRoute(SearchPage(store: store)));
      case AddAction.import:
        if (!ctx.mounted) return;
        final how = await pickOption<String>(ctx, [
          const SheetOption('link', 'Paste a Link', icon: Icons.link_rounded, subtitle: 'YouTube, articles, anime sites, anything'),
          const SheetOption('shots', 'Choose Screenshots', icon: Icons.photo_library_rounded, subtitle: 'Text is read on-device'),
        ], title: 'Import');
        if (how == 'link' && ctx.mounted) {
          final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
          if (!ctx.mounted) return;
          final text = await promptText(ctx, 'Paste a Link', initial: clip, hint: 'https://…');
          if (text != null && text.trim().isNotEmpty) {
            store.addText(text);
            _toast('Saved to your Inbox');
          }
        } else if (how == 'shots') {
          final picked = await ImagePicker().pickMultiImage();
          for (final p in picked) {
            store.addScreenshot(p.path);
          }
          if (picked.isNotEmpty) _toast(picked.length == 1 ? 'Reading your screenshot…' : 'Reading ${picked.length} screenshots…');
        }
      case AddAction.note:
        if (!ctx.mounted) return;
        final text = await promptText(ctx, 'Write a Thought', hint: 'Anything on your mind…', multiline: true);
        if (text != null && text.trim().isNotEmpty) {
          store.addNote(text);
          _toast('Saved to your Inbox');
        }
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final platform = defaultTargetPlatform;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => MaterialApp(
        title: 'Revue',
        debugShowCheckedModeBanner: false,
        navigatorKey: _nav,
        scaffoldMessengerKey: _messenger,
        builder: (context, child) => LaunchSplash(child: child!),
        theme: revueTheme(Brightness.light, platform),
        darkTheme: revueTheme(Brightness.dark, platform),
        themeMode: switch (widget.store.appearance) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        home: Scaffold(
          extendBody: true, // content scrolls under the floating glass bar
          body: IndexedStack(index: _tab, children: [
            HomePage(store: widget.store, onCreateList: () async {
              final ctx = _nav.currentContext;
              if (ctx != null) await showListEditor(ctx, widget.store);
            }),
            AssistantPage(store: widget.store, llm: widget.llm, openSettings: () => setState(() => _tab = 3)),
            StatsPage(store: widget.store),
            SettingsPage(llm: widget.llm, store: widget.store),
          ]),
          bottomNavigationBar: TabBarPill(tab: _tab, onTab: (i) => setState(() => _tab = i), onPlus: _onPlus),
        ),
      ),
    );
  }
}

/// Floating glass pill: Home · Ask · ( + ) · Stats · Settings.
class TabBarPill extends StatelessWidget {
  const TabBarPill({super.key, required this.tab, required this.onTab, required this.onPlus});
  final int tab;
  final ValueChanged<int> onTab;
  final ValueChanged<Rect> onPlus; // the + button's rect on screen, so the menu grows out of it

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    Widget item(int i, IconData icon, IconData active, String label) => Expanded(
          child: Semantics(
            button: true,
            selected: tab == i,
            label: label,
            child: Pressable(
              scale: 0.88,
              onTap: () => onTab(i),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutBack,
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(color: tab == i ? rv.raised : Colors.transparent, shape: BoxShape.circle),
                  child: Icon(tab == i ? active : icon, size: 27, color: tab == i ? rv.text : rv.text2),
                ),
              ),
            ),
          ),
        );
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Glass(
          radius: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: SizedBox(
            height: 62,
            child: Row(children: [
              item(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
              item(1, Icons.auto_awesome_outlined, Icons.auto_awesome, 'Ask'),
              Semantics(
                button: true,
                label: 'Add',
                child: Builder(builder: (context) => Pressable(
                  scale: 0.9,
                  onTap: () {
                    final box = context.findRenderObject()! as RenderBox;
                    onPlus(box.localToGlobal(Offset.zero) & box.size);
                  },
                  child: Container(
                    width: 76,
                    height: 54,
                    decoration: BoxDecoration(
                      color: rv.ink,
                      borderRadius: BorderRadius.circular(27),
                      boxShadow: [BoxShadow(color: rv.ink.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 4))],
                    ),
                    child: Icon(Icons.add_rounded, color: rv.onInk, size: 32),
                  ),
                )),
              ),
              item(2, Icons.bar_chart_rounded, Icons.bar_chart_rounded, 'Stats'),
              item(3, Icons.person_outline_rounded, Icons.person_rounded, 'Settings'),
            ]),
          ),
        ),
      ),
    );
  }
}
