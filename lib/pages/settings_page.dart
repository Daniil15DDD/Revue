import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../adaptive.dart';
import '../ai.dart';
import '../store.dart';

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
        builder: (context, _) => isIOS(context) ? _buildIOS(context) : _buildMaterial(context),
      );

  // MARK: iPhone — grouped lists like the Settings app

  Widget _buildIOS(BuildContext context) {
    final secondary = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final busy = llm.downloadProgress != null;
    Widget icon(IconData i, Color c) => Container(
          width: 29,
          height: 29,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(7)),
          child: Icon(i, color: CupertinoColors.white, size: 18),
        );
    return Scaffold(
      body: CustomScrollView(slivers: [
        const CupertinoSliverNavigationBar(largeTitle: Text('Settings'), border: null, transitionBetweenRoutes: false),
        SliverList.list(children: [
          CupertinoListSection.insetGrouped(
            header: sectionHeader(context, 'Appearance'),
            children: [
              for (final e in _appearances.entries)
                CupertinoListTile(
                  title: Text(e.value),
                  trailing: store.appearance == e.key
                      ? Icon(CupertinoIcons.checkmark_alt, color: CupertinoTheme.of(context).primaryColor)
                      : null,
                  onTap: () => store.setAppearance(e.key),
                ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: sectionHeader(context, 'On-device AI Model'),
            footer: sectionFooter(context, 'Powers auto-tagging and the assistant. Downloaded once over Wi-Fi, then '
                'everything runs offline on your iPhone. Reading text in screenshots works without it.'),
            children: [
              for (final o in modelOptions)
                CupertinoListTile(
                  leading: icon(CupertinoIcons.sparkles, CupertinoColors.systemPurple),
                  title: Text(o.name),
                  subtitle: Text(llm.activeFile == o.file ? 'Installed · in use' : o.size),
                  trailing: llm.activeFile == o.file
                      ? CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: busy ? null : () => llm.remove(o),
                          child: const Text('Remove', style: TextStyle(color: CupertinoColors.destructiveRed)),
                        )
                      : CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: busy ? null : () => _download(context, o),
                          child: const Text('Get'),
                        ),
                ),
              if (busy)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Downloading… ${llm.downloadProgress}% — keep Revue open', style: TextStyle(color: secondary)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: llm.downloadProgress! / 100, borderRadius: BorderRadius.circular(4)),
                  ]),
                ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: sectionHeader(context, 'Saving From Other Apps'),
            children: [
              CupertinoListTile(
                leading: icon(CupertinoIcons.share, CupertinoColors.systemBlue),
                title: const Text('Share → Revue'),
                subtitle: const Text('From YouTube, Safari, Photos… If Revue isn\'t listed, tap More.', maxLines: 2),
              ),
              CupertinoListTile(
                leading: icon(CupertinoIcons.photo_on_rectangle, CupertinoColors.systemGreen),
                title: const Text('Screenshots'),
                subtitle: const Text('Text inside is read on-device so you can search it.', maxLines: 2),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: sectionHeader(context, 'Privacy'),
            children: [
              CupertinoListTile(
                leading: icon(CupertinoIcons.lock_fill, CupertinoColors.systemGrey),
                title: const Text('Stays on this iPhone'),
                subtitle: const Text('Online only for link previews and the one-time model download.', maxLines: 2),
              ),
            ],
          ),
          SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
        ]),
      ]),
    );
  }

  // MARK: Android

  Widget _buildMaterial(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: t.headlineSmall)),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        _header(context, 'Appearance'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<String>(
            segments: [for (final e in _appearances.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {store.appearance},
            onSelectionChanged: (s) => store.setAppearance(s.first),
          ),
        ),
        const Divider(height: 32),
        _header(context, 'On-device AI model'),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Powers auto-tagging and the assistant. Downloaded once over Wi-Fi, '
              'then everything runs offline on your phone. Screenshot text reading works without it.'),
        ),
        for (final o in modelOptions) _modelTile(context, o),
        if (llm.downloadProgress != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Downloading… ${llm.downloadProgress}% — keep Revue open'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: llm.downloadProgress! / 100),
            ]),
          ),
        const Divider(height: 32),
        _header(context, 'Saving from other apps'),
        const ListTile(
          leading: Icon(Icons.share),
          title: Text('YouTube, Chrome, Photos…'),
          subtitle: Text('Tap Share, then pick Revue. The title and thumbnail are fetched automatically.'),
        ),
        const ListTile(
          leading: Icon(Icons.screenshot_monitor),
          title: Text('Screenshots'),
          subtitle: Text('Share a screenshot to Revue, or use Add → Screenshots. '
              'Text inside is read on-device so you can search and ask about it.'),
        ),
        const Divider(height: 32),
        _header(context, 'Privacy'),
        const ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Your library stays on this device'),
          subtitle: Text('Revue only goes online to fetch a link\'s title and thumbnail, and to download the AI model.'),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context, String s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(s, style: Theme.of(context).textTheme.titleLarge),
      );

  Widget _modelTile(BuildContext context, ModelOption o) {
    final active = llm.activeFile == o.file;
    final busy = llm.downloadProgress != null;
    return ListTile(
      leading: Icon(active ? Icons.check_circle : Icons.memory, color: active ? Theme.of(context).colorScheme.primary : null),
      title: Text(o.name),
      subtitle: Text(active ? 'Installed · in use' : o.size),
      trailing: active
          ? IconButton(tooltip: 'Remove model', icon: const Icon(Icons.delete_outline), onPressed: busy ? null : () => llm.remove(o))
          : OutlinedButton(onPressed: busy ? null : () => _download(context, o), child: const Text('Download')),
    );
  }
}
