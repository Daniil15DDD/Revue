import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../adaptive.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

class ItemPage extends StatefulWidget {
  const ItemPage({super.key, required this.store, required this.item});
  final Store store;
  final Item item;

  @override
  State<ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<ItemPage> {
  late final _title = TextEditingController(text: widget.item.title);
  late final _note = TextEditingController(text: widget.item.note);

  Item get item => widget.item;
  Store get store => widget.store;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  void _change(VoidCallback fn) {
    setState(fn);
    store.update(item);
  }

  Future<void> _open() async {
    final url = item.url == null ? null : Uri.tryParse(item.url!);
    if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  String get _listName {
    final l = store.lists.where((l) => l.id == item.listId).firstOrNull;
    return l == null ? 'None' : l.display;
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete this item?')) return;
    await store.delete(item);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickList() async {
    final v = await pickOption<String>(context, [
      const SheetOption('', 'None'),
      for (final l in store.lists) SheetOption(l.id, l.display),
    ], title: 'Move to list');
    if (v != null) _change(() => item.listId = v.isEmpty ? null : v);
  }

  Future<void> _pickKind() async {
    final v = await pickOption<Kind>(context, [for (final k in Kind.values) SheetOption(k, k.label, icon: k.icon(context))],
        title: 'Type');
    if (v == null) return;
    _change(() => item.kind = v);
    if (v.progressUnit != null && item.total == null) _find();
  }

  Future<void> _pickStatus() async {
    final v = await pickOption<Status>(context, [for (final s in Status.values) SheetOption(s, s.label(item.kind))],
        title: 'Status');
    if (v != null) {
      await store.setStatus(item, v);
      setState(() {});
    }
  }

  Future<void> _setProgress(int v) async {
    await store.setProgress(item, v);
    setState(() {});
  }

  Future<void> _find() async {
    final found = await store.findProgress(item);
    if (!mounted) return;
    setState(() {});
    if (!found) await _enterTotal(notFound: true);
  }

  Future<void> _enterTotal({bool notFound = false}) async {
    final unit = item.kind.progressUnit!;
    final v = await promptText(context, notFound ? 'Couldn’t find it' : 'Total $unit',
        hint: notFound ? 'Enter total $unit yourself' : 'Number of $unit', initial: item.total?.toString() ?? '');
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || n <= 0) return;
    item.total = n;
    item.seasons = [];
    await _setProgress(item.progress);
  }

  Future<void> _typeProgress() async {
    final unit = item.kind.progressUnit!;
    final v = await promptText(context, item.kind == Kind.show ? 'Episodes watched' : 'Current page',
        hint: item.total == null ? unit : 'of ${item.total} $unit', initial: '${item.progress}', action: 'Set');
    final n = int.tryParse(v?.trim() ?? '');
    if (n != null) await _setProgress(n);
  }

  Widget _roundButton(IconData icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        label: label,
        child: Pressable(
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemFill, context),
            ),
            child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          ),
        ),
      );

  /// Pages read / episodes watched, with steppers. Unknown total → look it up or type it.
  Widget _progressBody() {
    final ios = isIOS(context);
    final accent = Theme.of(context).colorScheme.primary;
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final unit = item.kind.progressUnit!;
    final busy = store.processing.contains(item.id);
    if (item.total == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Track how far you are. Revue can look up the number of $unit.',
              style: TextStyle(fontSize: 15, color: secondary)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ios
                  ? CupertinoButton.filled(
                      onPressed: busy ? null : _find,
                      child: busy
                          ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                          : const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(CupertinoIcons.sparkles, size: 18),
                              SizedBox(width: 6),
                              Text('Find with AI'),
                            ]),
                    )
                  : FilledButton.icon(
                      onPressed: busy ? null : _find,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: Text(busy ? 'Looking up…' : 'Find with AI'),
                    ),
            ),
            const SizedBox(width: 8),
            ios
                ? CupertinoButton(onPressed: _enterTotal, child: const Text('Enter'))
                : TextButton(onPressed: _enterTotal, child: const Text('Enter')),
          ]),
        ]),
      );
    }
    final se = item.seasonEpisode;
    final (big, small) = item.kind == Kind.show
        ? (se == null ? 'Not started' : 'Season ${se.$1} · Episode ${se.$2}', '${item.progress} of ${item.total} episodes')
        : ('Page ${item.progress}', 'of ${item.total} pages · ${(item.progress * 100 / item.total!).round()}%');
    final step = item.kind == Kind.book ? 10 : 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          onTap: _typeProgress,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(big, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: label)),
            const SizedBox(height: 2),
            Text(small, style: TextStyle(fontSize: 14, color: secondary, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
        const SizedBox(height: 12),
        ProgressTrack(value: item.progress / item.total!, color: accent),
        const SizedBox(height: 14),
        Row(children: [
          _roundButton(ios ? CupertinoIcons.minus : Icons.remove, 'Back $step', () => _setProgress(item.progress - step)),
          const SizedBox(width: 10),
          _roundButton(ios ? CupertinoIcons.plus : Icons.add, 'Forward $step', () => _setProgress(item.progress + step)),
          const Spacer(),
          if (item.kind == Kind.show && item.progress < item.total!)
            ios
                ? CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    onPressed: () => _setProgress(item.progress + 1),
                    child: const Text('Next Episode'),
                  )
                : FilledButton(onPressed: () => _setProgress(item.progress + 1), child: const Text('Next episode')),
          if (item.kind == Kind.book)
            ios
                ? CupertinoButton(onPressed: _typeProgress, child: const Text('Set Page'))
                : TextButton(onPressed: _typeProgress, child: const Text('Set page')),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store, // redraw while a progress lookup runs
        builder: (context, _) => isIOS(context) ? _buildIOS(context) : _buildMaterial(context),
      );

  // MARK: shared pieces

  Widget _hero() {
    final thumb = store.thumbFile(item);
    if (thumb == null) return const SizedBox();
    return GestureDetector(
      onTap: item.url != null ? _open : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isIOS(context) ? 14 : 16),
        child: Image.file(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
      ),
    );
  }

  Widget _sourceRow() {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(item.kind.icon(context), size: 15, color: scheme.primary),
      const SizedBox(width: 6),
      Expanded(
        child: Text(item.source.isNotEmpty ? item.source : item.kind.label,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelLarge?.copyWith(color: scheme.primary)),
      ),
      Text(MaterialLocalizations.of(context).formatMediumDate(item.created),
          style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
    ]);
  }

  Widget _stars() {
    final color = Theme.of(context).colorScheme.primary;
    final ios = isIOS(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var s = 1; s <= 5; s++)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _change(() => item.rating = item.rating == s ? 0 : s),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Semantics(
              label: '$s star${s > 1 ? 's' : ''}',
              button: true,
              child: Icon(
                s <= item.rating ? (ios ? CupertinoIcons.star_fill : Icons.star) : (ios ? CupertinoIcons.star : Icons.star_border),
                color: color,
                size: ios ? 24 : 28,
              ),
            ),
          ),
        ),
    ]);
  }

  // MARK: iPhone

  Widget _buildIOS(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Scaffold(
      extendBodyBehindAppBar: true, // content scrolls under the translucent bar
      appBar: CupertinoNavigationBar(
        previousPageTitle: 'Revue',
        border: null,
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _delete,
          child: const Icon(CupertinoIcons.trash),
        ),
      ),
      body: ListView(padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: 40), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _hero(),
            const SizedBox(height: 14),
            _sourceRow(),
            const SizedBox(height: 4),
            CupertinoTextField.borderless(
              controller: _title,
              maxLines: null,
              padding: EdgeInsets.zero,
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: label),
              onChanged: (v) => _change(() => item.title = v),
            ),
            if (item.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.summary, style: t.bodyLarge?.copyWith(color: secondary)),
            ],
            if (item.url != null) ...[
              const SizedBox(height: 14),
              // One prominent action per screen: for books/series that's the progress button below.
              (item.kind.progressUnit != null ? CupertinoButton.tinted : CupertinoButton.filled)(
                onPressed: _open,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(item.kind == Kind.video ? CupertinoIcons.play_fill : CupertinoIcons.arrow_up_right_square, size: 18),
                  const SizedBox(width: 8),
                  Text(item.kind == Kind.video ? 'Watch' : 'Open'),
                ]),
              ),
            ],
          ]),
        ),
        if (item.kind.progressUnit != null)
          CupertinoListSection.insetGrouped(
            header: sectionHeader(context, 'Progress'),
            children: [_progressBody()],
          ),
        CupertinoListSection.insetGrouped(
          header: sectionHeader(context, 'Your review'),
          children: [
            CupertinoListTile(
              title: const Text('Status'),
              additionalInfo: Text(item.status.label(item.kind)),
              trailing: const CupertinoListTileChevron(),
              onTap: _pickStatus,
            ),
            CupertinoListTile(title: const Text('Rating'), trailing: _stars()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: CupertinoTextField.borderless(
                controller: _note,
                placeholder: 'Thoughts, why you saved it…',
                minLines: 3,
                maxLines: null,
                onChanged: (v) => _change(() => item.note = v),
              ),
            ),
          ],
        ),
        CupertinoListSection.insetGrouped(
          header: sectionHeader(context, 'Filed under'),
          children: [
            CupertinoListTile(
              title: const Text('List'),
              additionalInfo: Text(_listName),
              trailing: const CupertinoListTileChevron(),
              onTap: _pickList,
            ),
            CupertinoListTile(
              title: const Text('Type'),
              additionalInfo: Text(item.kind.label),
              trailing: const CupertinoListTileChevron(),
              onTap: _pickKind,
            ),
            if (item.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final tag in item.tags)
                    Pill(
                      label: '#$tag',
                      selected: false,
                      onTap: () {},
                      onLongPress: () => _change(() => item.tags = [...item.tags]..remove(tag)),
                    ),
                ]),
              ),
          ],
        ),
        if (item.text.isNotEmpty)
          CupertinoListSection.insetGrouped(
            header: sectionHeader(context, item.kind == Kind.note ? 'Note' : 'Text found in image'),
            children: [Padding(padding: const EdgeInsets.all(14), child: SelectableText(item.text))],
          ),
      ]),
    );
  }

  // MARK: Android

  Widget _buildMaterial(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        _hero(),
        const SizedBox(height: 16),
        _sourceRow(),
        TextField(
          controller: _title,
          maxLines: null,
          style: t.headlineSmall,
          decoration: const InputDecoration(border: InputBorder.none),
          onChanged: (v) => _change(() => item.title = v),
        ),
        if (item.url != null)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _open,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Text(item.kind == Kind.video ? 'Watch' : 'Open'),
            ),
          ),
        if (item.summary.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(item.summary, style: t.bodyLarge),
        ],
        if (item.kind.progressUnit != null) ...[
          const SizedBox(height: 20),
          _section('Progress'),
          Container(decoration: surface(context, radius: 16), child: _progressBody()),
        ],
        const SizedBox(height: 20),
        _section('Your review'),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            _stars(),
            ActionChip(
              avatar: const Icon(Icons.flag_outlined, size: 18),
              label: Text(item.status.label(item.kind)),
              onPressed: _pickStatus,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          maxLines: null,
          minLines: 2,
          decoration: const InputDecoration(hintText: 'Thoughts, why you saved it…', border: OutlineInputBorder()),
          onChanged: (v) => _change(() => item.note = v),
        ),
        const SizedBox(height: 20),
        _section('Filed under'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(avatar: const Icon(Icons.folder_outlined, size: 18), label: Text(_listName), onPressed: _pickList),
          ActionChip(avatar: Icon(item.kind.icon(context), size: 18), label: Text(item.kind.label), onPressed: _pickKind),
        ]),
        if (item.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final tag in item.tags)
              InputChip(label: Text('#$tag'), onDeleted: () => _change(() => item.tags = [...item.tags]..remove(tag))),
          ]),
        ],
        if (item.text.isNotEmpty && item.kind != Kind.note) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Text found in image'),
            children: [SelectableText(item.text)],
          ),
        ],
        if (item.kind == Kind.note) ...[
          const SizedBox(height: 12),
          SelectableText(item.text, style: t.bodyLarge),
        ],
      ]),
    );
  }

  Widget _section(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(s.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing: 1.2)),
      );
}
