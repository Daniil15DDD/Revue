import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../adaptive.dart';
import '../ai.dart';
import '../store.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key, required this.store, required this.llm, required this.openSettings});
  final Store store;
  final GemmaLlm llm;
  final VoidCallback openSettings;

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<(String, String)> _turns = []; // (question, answer); answer '' while thinking
  bool _busy = false;

  static const _suggestions = [
    'What should I watch tonight?',
    'What did I save this week?',
    'Summarize my screenshots',
    'Which places have I saved?',
  ];

  Future<void> _ask(String q) async {
    q = q.trim();
    if (q.isEmpty || _busy) return;
    _input.clear();
    final history = List.of(_turns);
    setState(() {
      _busy = true;
      _turns.add((q, ''));
    });
    _scrollDown();
    String answer;
    try {
      answer = await Brain.answer(
          widget.llm.ready ? widget.llm : null, q, widget.store.items, widget.store.lists, history);
      if (answer.isEmpty) answer = '…I couldn\'t come up with an answer. Try rephrasing?';
    } catch (e) {
      answer = 'Something went wrong running the on-device model: $e';
    }
    if (!mounted) return;
    setState(() {
      _turns[_turns.length - 1] = (q, answer);
      _busy = false;
    });
    _scrollDown();
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ios = isIOS(context);
    return Scaffold(
      appBar: ios
          ? CupertinoNavigationBar(
              middle: const Text('Ask Revue'),
              border: null,
              transitionBetweenRoutes: false,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            )
          : AppBar(title: Text('Ask Revue', style: t.headlineSmall)),
      body: Column(children: [
        ListenableBuilder(listenable: widget.llm, builder: (context, _) => widget.llm.ready ? const SizedBox() : _modelBanner(context)),
        Expanded(
          child: _turns.isEmpty
              ? ListView(padding: const EdgeInsets.all(24), children: [
                  const SizedBox(height: 24),
                  Icon(ios ? CupertinoIcons.sparkles : Icons.auto_awesome, size: 44, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text('Ask anything about what you\'ve saved.',
                      textAlign: TextAlign.center,
                      style: ios ? t.titleLarge?.copyWith(fontWeight: FontWeight.w600) : t.titleLarge),
                  const SizedBox(height: 6),
                  Text('Runs entirely on your phone. Nothing is uploaded.',
                      textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                    for (final s in _suggestions) Pill(label: s, selected: false, onTap: () => _ask(s)),
                  ]),
                ])
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _turns.length,
                  itemBuilder: (context, i) {
                    final (q, a) = _turns[i];
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _bubble(q, mine: true),
                      a.isEmpty
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: ios
                                    ? const CupertinoActivityIndicator()
                                    : const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                            )
                          : _bubble(a, mine: false),
                    ]);
                  },
                ),
        ),
        SafeArea(top: false, child: ios ? _iosInput(context) : _materialInput()),
      ]),
    );
  }

  Widget _modelBanner(BuildContext context) {
    if (!isIOS(context)) {
      return MaterialBanner(
        content: const Text('Download the on-device AI model to chat. Until then, answers are plain search.'),
        leading: const Icon(Icons.download_for_offline_outlined),
        actions: [TextButton(onPressed: widget.openSettings, child: const Text('Get model'))],
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(CupertinoIcons.arrow_down_circle, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        const Expanded(child: Text('Download the on-device model to chat. Until then, answers are plain search.',
            style: TextStyle(fontSize: 14))),
        CupertinoButton(onPressed: widget.openSettings, child: const Text('Get')),
      ]),
    );
  }

  Widget _iosInput(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: CupertinoTextField(
              controller: _input,
              placeholder: 'Ask about your library',
              textInputAction: TextInputAction.send,
              onSubmitted: _ask,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(CupertinoColors.secondarySystemGroupedBackground, context),
                border: Border.all(color: CupertinoDynamicColor.resolve(CupertinoColors.separator, context)),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.only(left: 6, bottom: 2),
            minimumSize: Size.zero,
            onPressed: _busy ? null : () => _ask(_input.text),
            child: Semantics(label: 'Send', child: const Icon(CupertinoIcons.arrow_up_circle_fill, size: 34)),
          ),
        ]),
      );

  Widget _materialInput() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              textInputAction: TextInputAction.send,
              onSubmitted: _ask,
              decoration: InputDecoration(
                hintText: 'Ask about your library…',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: _busy ? null : () => _ask(_input.text),
            icon: const Icon(Icons.arrow_upward),
          ),
        ]),
      );

  Widget _bubble(String text, {required bool mine}) {
    final scheme = Theme.of(context).colorScheme;
    final ios = isIOS(context);
    final other = ios ? CupertinoDynamicColor.resolve(CupertinoColors.systemGrey5, context) : scheme.surfaceContainerHighest;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(color: mine ? scheme.primary : other, borderRadius: BorderRadius.circular(18)),
        child: SelectableText(text,
            style: TextStyle(fontSize: ios ? 16 : null, color: mine ? scheme.onPrimary : scheme.onSurface)),
      ),
    );
  }
}
