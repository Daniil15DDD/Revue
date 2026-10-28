import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../adaptive.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'item_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.store});
  final Store store;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

enum _Add { paste, screenshots, note }

enum _ListAction { rename, color, delete }

const _colorNames = ['Blue', 'Orange', 'Amber', 'Lime', 'Purple', 'Teal', 'Pink', 'Grey'];

/// Status filter on the home page; "In progress" also covers on-hold items.
enum _Filter { all, planned, active, finished }

class _LibraryPageState extends State<LibraryPage> {
  String? _listId; // null = everything
  _Filter _filter = _Filter.all;
  Period _period = Period.all;
  String _query = '';
  bool _searching = false; // Android only; iPhone always shows its search field

  Store get store => widget.store;

  List<Item> get _visible {
    final q = _query.toLowerCase().trim();
    bool status(Item i) => switch (_filter) {
          _Filter.all => true,
          _Filter.planned => i.status == Status.planned,
          _Filter.active => i.status == Status.active || i.status == Status.paused,
          _Filter.finished => i.status == Status.finished,
        };
    return store.items
        .where((i) => _listId == null || i.listId == _listId)
        .where(status)
        .where((i) => q.isEmpty || i.haystack.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final ios = isIOS(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = _visible;
        final list = store.lists.where((l) => l.id == _listId).firstOrNull;
        return Scaffold(
          floatingActionButton: ios
              ? null
              : FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add')),
          body: CustomScrollView(slivers: [
            if (ios) ...[
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Revue'),
                border: null,
                transitionBetweenRoutes: false, // tab roots live side by side in an IndexedStack
                trailing: CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _add,
                  child: const Icon(CupertinoIcons.add_circled_solid, size: 28),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: CupertinoSearchTextField(onChanged: (v) => setState(() => _query = v)),
                ),
              ),
            ] else
              SliverAppBar.large(
                title: _searching
                    ? TextField(
                        autofocus: true,
                        decoration: const InputDecoration(hintText: 'Search everything…', border: InputBorder.none),
                        onChanged: (v) => setState(() => _query = v),
                      )
                    : const Text('Revue'),
                actions: [
                  IconButton(
                    tooltip: _searching ? 'Close search' : 'Search',
                    icon: Icon(_searching ? Icons.close : Icons.search),
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      _query = '';
                    }),
                  ),
                ],
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: StatsCard(
                  store: store,
                  period: _period,
                  selectedListId: _listId,
                  onSelectList: (id) => setState(() => _listId = id),
                  onPeriod: _pickPeriod,
                  onNewList: _newList,
                  onEditList: _editList,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _filterBar(context)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              sliver: SliverToBoxAdapter(child: _sectionTitle(context, list, items.length)),
            ),
            if (items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _empty(context))
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, (ios ? 32 : 96) + MediaQuery.paddingOf(context).bottom),
                sliver: SliverLayoutBuilder(builder: (context, c) {
                  final columns = (c.crossAxisExtent / 200).floor().clamp(2, 5);
                  final cardWidth = (c.crossAxisExtent - 12 * (columns - 1)) / columns;
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: cardWidth * 10 / 16 + 78, // image + two title lines + meta
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => ItemCard(store: store, item: items[i]),
                      childCount: items.length,
                    ),
                  );
                }),
              ),
          ]),
        );
      },
    );
  }

  Widget _filterBar(BuildContext context) {
    const labels = {_Filter.all: 'All', _Filter.planned: 'Planned', _Filter.active: 'In Progress', _Filter.finished: 'Finished'};
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: isIOS(context)
          ? CupertinoSlidingSegmentedControl<_Filter>(
              groupValue: _filter,
              onValueChanged: (v) => setState(() => _filter = v ?? _Filter.all),
              children: {for (final e in labels.entries) e.key: Text(e.value, style: const TextStyle(fontSize: 13))},
            )
          : SegmentedButton<_Filter>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
              segments: [
                for (final e in labels.entries)
                  ButtonSegment(value: e.key, label: FittedBox(fit: BoxFit.scaleDown, child: Text(e.value, maxLines: 1))),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
    );
  }

  Widget _sectionTitle(BuildContext context, RevueList? list, int count) {
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
      if (list != null) ...[
        Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(list.color), shape: BoxShape.circle)),
        const SizedBox(width: 8),
      ],
      Flexible(
        child: Text(list?.display ?? 'Everything',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: label)),
      ),
      const SizedBox(width: 8),
      Text('$count', style: TextStyle(fontSize: 17, color: secondary)),
      const Spacer(),
      if (list != null)
        GestureDetector(
          onTap: () => setState(() => _listId = null),
          child: Text('Show all', style: TextStyle(fontSize: 15, color: Theme.of(context).colorScheme.primary)),
        ),
    ]);
  }

  Widget _empty(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ios = isIOS(context);
    final filtered = _query.isNotEmpty || _filter != _Filter.all || _listId != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 32),
      child: Column(mainAxisAlignment: MainAxisAlignment.start, children: [
        Icon(ios ? CupertinoIcons.bookmark : Icons.bookmarks_outlined, size: 44, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(filtered ? 'Nothing matches' : 'Nothing here yet',
            style: t.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
          filtered
              ? 'Try another list, status or search.'
              : 'In YouTube (or any app) tap Share → Revue.\nOr tap ${ios ? '+' : 'Add'} to paste a link or pick screenshots.',
          textAlign: TextAlign.center,
          style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }

  Future<void> _pickPeriod() async {
    final p = await pickOption<Period>(context, [for (final p in Period.values) SheetOption(p, p.label)], title: 'Show stats for');
    if (p != null) setState(() => _period = p);
  }

  Future<void> _add() async {
    final ios = isIOS(context);
    final choice = await pickOption<_Add>(context, [
      SheetOption(_Add.paste, 'Paste Link', icon: ios ? CupertinoIcons.doc_on_clipboard : Icons.content_paste,
          subtitle: 'YouTube, articles, books, series, places'),
      SheetOption(_Add.screenshots, 'Choose Screenshots', icon: ios ? CupertinoIcons.photo_on_rectangle : Icons.photo_library_outlined,
          subtitle: 'Text is read on-device and auto-tagged'),
      SheetOption(_Add.note, 'New Note', icon: ios ? CupertinoIcons.square_pencil : Icons.edit_note),
    ]);
    if (!mounted || choice == null) return;
    switch (choice) {
      case _Add.paste:
        final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
        if (!mounted) return;
        final text = await promptText(context, 'Add Link', initial: clip, hint: 'https://…');
        if (text != null && text.trim().isNotEmpty) store.addText(text, listId: _listId);
      case _Add.screenshots:
        for (final p in await ImagePicker().pickMultiImage()) {
          store.addScreenshot(p.path, listId: _listId);
        }
      case _Add.note:
        final text = await promptText(context, 'New Note', hint: 'Write anything…', multiline: true);
        if (text != null && text.trim().isNotEmpty) store.addNote(text, listId: _listId);
    }
  }

  Future<void> _newList() async {
    final name = await promptText(context, 'New List', hint: 'Name it anything — Anime, Recipes, 2026 reads…', action: 'Create');
    if (name == null || name.trim().isEmpty) return;
    final l = await store.addList(name.trim());
    setState(() => _listId = l.id);
  }

  Future<void> _editList(RevueList l) async {
    final action = await pickOption<_ListAction>(context, [
      const SheetOption(_ListAction.rename, 'Rename'),
      const SheetOption(_ListAction.color, 'Change Colour'),
      const SheetOption(_ListAction.delete, 'Delete List', destructive: true),
    ], title: l.name);
    if (!mounted || action == null) return;
    switch (action) {
      case _ListAction.rename:
        final name = await promptText(context, 'Rename List', initial: l.name, action: 'Rename');
        if (name != null) await store.editList(l, name: name);
      case _ListAction.color:
        final c = await pickOption<int>(context, [
          for (var i = 0; i < listPalette.length; i++) SheetOption(listPalette[i], _colorNames[i]),
        ], title: 'Colour');
        if (c != null) await store.editList(l, color: c);
      case _ListAction.delete:
        if (!await confirm(context, 'Delete “${l.name}”?', message: 'Items in it stay in your library.')) return;
        if (_listId == l.id) setState(() => _listId = null);
        await store.deleteList(l);
    }
  }
}

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.store, required this.item});
  final Store store;
  final Item item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ios = isIOS(context);
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final thumb = store.thumbFile(item);
    final list = store.lists.where((l) => l.id == item.listId).firstOrNull;
    final showStatus = item.status != Status.planned;
    final fraction = item.total == null || item.total == 0 ? null : item.progress / item.total!;
    return Semantics(
      button: true,
      label: '${item.title}, ${item.status.label(item.kind)}',
      child: Pressable(
        onTap: () => Navigator.push(
            context,
            ios
                ? CupertinoPageRoute(builder: (_) => ItemPage(store: store, item: item))
                : MaterialPageRoute(builder: (_) => ItemPage(store: store, item: item))),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: surface(context, radius: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(fit: StackFit.expand, children: [
                thumb != null
                    ? Image.file(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder(context, scheme))
                    : _placeholder(context, scheme),
                if (showStatus)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(100)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (item.status == Status.finished) ...[
                          Icon(ios ? CupertinoIcons.checkmark_alt : Icons.check, size: 12, color: Colors.white),
                          const SizedBox(width: 3),
                        ],
                        Text(item.status.label(item.kind),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                      ]),
                    ),
                  ),
                if (fraction != null && item.status == Status.active)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ProgressTrack(value: fraction, color: scheme.primary, height: 4, track: Colors.black38),
                  ),
                if (store.processing.contains(item.id))
                  ColoredBox(
                    color: Colors.black38,
                    child: Center(
                      child: ios
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : const SizedBox.square(
                              dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: -0.2, color: label)),
                  const Spacer(),
                  Row(children: [
                    if (list != null) ...[
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: Color(list.color), shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                    ],
                    Expanded(
                      child: Text(
                        _progressShort ?? (item.source.isNotEmpty ? item.source : item.kind.label),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: secondary),
                      ),
                    ),
                    if (item.rating > 0) ...[
                      Icon(ios ? CupertinoIcons.star_fill : Icons.star, size: 11, color: scheme.primary),
                      const SizedBox(width: 2),
                      Text('${item.rating}', style: TextStyle(fontSize: 12, color: secondary)),
                    ],
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// Card-sized progress: "S3 · E4" for series (full count lives on the item page).
  String? get _progressShort {
    final se = item.seasonEpisode;
    return item.kind == Kind.show && se != null ? 'S${se.$1} · E${se.$2}' : item.progressLabel;
  }

  Widget _placeholder(BuildContext context, ColorScheme scheme) => ColoredBox(
        color: scheme.primaryContainer,
        child: Center(child: Icon(item.kind.icon(context), size: 34, color: scheme.onPrimaryContainer)),
      );
}
