import 'package:flutter/material.dart';

import '../adaptive.dart';
import '../theme.dart';
import '../widgets.dart';
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
    final rv = Rv.of(context);
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, top + 14, 20, 6),
          child: Row(children: [
            Text('Ask', style: RvText.display(rv.text)),
            const SizedBox(width: 10),
            Icon(Icons.auto_awesome, color: rv.accent),
          ]),
        ),
        ListenableBuilder(listenable: widget.llm, builder: (context, _) => widget.llm.ready ? const SizedBox() : _modelBanner(rv)),
        Expanded(
          child: _turns.isEmpty
              ? ListView(padding: const EdgeInsets.fromLTRB(24, 30, 24, 24), children: [
                  Text('Ask anything about what you\'ve saved.', style: RvText.title(rv.text)),
                  const SizedBox(height: 8),
                  Text('Runs entirely on your phone. Nothing is uploaded.', style: RvText.body(rv.text2)),
                  const SizedBox(height: 22),
                  Wrap(spacing: 8, runSpacing: 8, children: [
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
                      _bubble(rv, q, mine: true),
                      a.isEmpty
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: rv.text2)),
                              ),
                            )
                          : _bubble(rv, a, mine: false),
                    ]);
                  },
                ),
        ),
        // Input floats above the tab bar.
        Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, MediaQuery.paddingOf(context).bottom + 100),
          child: Row(children: [
            Expanded(child: RvField(controller: _input, hint: 'Ask about your library', onSubmitted: _ask)),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: 'Send',
              child: Pressable(
                scale: 0.88,
                onTap: _busy ? null : () => _ask(_input.text),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: rv.ink, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_upward_rounded, color: rv.onInk),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _modelBanner(Rv rv) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: surface(context, radius: 22),
          child: Row(children: [
            Icon(Icons.download_rounded, color: rv.accent),
            const SizedBox(width: 12),
            Expanded(child: Text('Get the on-device model to chat. Until then, answers are plain search.', style: RvText.small(rv.text2))),
            const SizedBox(width: 8),
            PillButton(label: 'Get', compact: true, onTap: widget.openSettings),
          ]),
        ),
      );

  Widget _bubble(Rv rv, String text, {required bool mine}) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          decoration: BoxDecoration(
            color: mine ? rv.ink : rv.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(mine ? 22 : 6),
              bottomRight: Radius.circular(mine ? 6 : 22),
            ),
          ),
          child: SelectableText(text, style: RvText.body(mine ? rv.onInk : rv.text)),
        ),
      );
}
