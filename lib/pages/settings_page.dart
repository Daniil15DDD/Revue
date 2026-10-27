import 'package:flutter/material.dart';

import '../ai.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.llm});
  final GemmaLlm llm;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: t.headlineSmall)),
      body: ListenableBuilder(
        listenable: llm,
        builder: (context, _) => ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
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
            leading: Icon(Icons.ios_share),
            title: Text('YouTube, Safari, Chrome, Photos…'),
            subtitle: Text('Tap Share, then pick Revue. The title and thumbnail are fetched automatically. '
                'On iPhone, if Revue isn\'t listed, tap More and turn it on.'),
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
      ),
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
          ? IconButton(
              tooltip: 'Remove model',
              icon: const Icon(Icons.delete_outline),
              onPressed: busy ? null : () => llm.remove(o),
            )
          : OutlinedButton(
              onPressed: busy
                  ? null
                  : () async {
                      try {
                        await llm.download(o);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
                        }
                      }
                    },
              child: const Text('Download'),
            ),
    );
  }
}
