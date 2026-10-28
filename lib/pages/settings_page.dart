import 'package:flutter/material.dart';

import '../ai.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.llm, required this.store});
  final GemmaLlm llm;
  final Store store;

  static const _appearances = {'system': 'System', 'light': 'Light', 'dark': 'Dark'};

  Future<void> _download(BuildContext context, ModelOption o) async {
    try {
      await llm.download(o);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([llm, store]),
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    final rv = Rv.of(context);
    final busy = llm.downloadProgress != null;
    Widget group(String title, List<Widget> children, {String? footer}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionLabel(title),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: surface(context, radius: 26),
              child: Column(children: children),
            ),
            if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(6, 8, 6, 0), child: Text(footer, style: RvText.small(rv.text2))),
          ]),
        );
    Widget row(IconData icon, String title, String? subtitle, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: rv.raised, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 19, color: rv.text),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: RvText.body(rv.text).copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null) Text(subtitle, style: RvText.small(rv.text2)),
              ]),
            ),
            ?trailing,
          ]),
        );
    return Scaffold(
      body: ListView(padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 14, 16, 130), children: [
        Text('Settings', style: RvText.display(rv.text)),
        group('Appearance', [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              for (final e in _appearances.entries)
                Expanded(
                  child: Pressable(
                    onTap: () => store.setAppearance(e.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                          color: store.appearance == e.key ? rv.ink : rv.raised, borderRadius: BorderRadius.circular(16)),
                      child: Text(e.value,
                          textAlign: TextAlign.center,
                          style: RvText.body(store.appearance == e.key ? rv.onInk : rv.text).copyWith(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
        group(
          'On-device AI model',
          [
            for (final o in modelOptions)
              row(Icons.auto_awesome, o.name, llm.activeFile == o.file ? 'Installed · in use' : o.size,
                  trailing: llm.activeFile == o.file
                      ? PillButton(label: 'Remove', primary: false, compact: true, onTap: busy ? null : () => llm.remove(o))
                      : PillButton(label: 'Get', compact: true, onTap: busy ? null : () => _download(context, o))),
            if (busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Downloading… ${llm.downloadProgress}% — keep Revue open', style: RvText.small(rv.text2)),
                  const SizedBox(height: 8),
                  ProgressTrack(value: llm.downloadProgress! / 100, color: rv.accent),
                ]),
              ),
          ],
          footer: 'Powers auto-tagging and the assistant. Downloaded once, then everything runs offline. '
              'Reading text in screenshots works without it.',
        ),
        group('Saving from other apps', [
          row(Icons.ios_share_rounded, 'Share → Revue', 'From YouTube, browsers, Photos… The title and cover are fetched for you.'),
          row(Icons.screenshot_monitor_rounded, 'Screenshots', 'Text inside is read on-device so you can search it.'),
        ]),
        group('Privacy', [
          row(Icons.lock_outline_rounded, 'Stays on this phone', 'Online only for link previews, lookups and the one-time model download.'),
        ]),
      ]),
    );
  }
}
