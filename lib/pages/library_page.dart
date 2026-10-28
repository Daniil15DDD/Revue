import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../adaptive.dart';
import '../models.dart';
import '../store.dart';
import 'item_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.store});
  final Store store;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

enum _Add { paste, screenshots, note }

class _LibraryPageState extends State<LibraryPage> {
  String? _listId; // null = everything
  Kind? _kind;
  String _query = '';
  bool _searching = false; // Android only; iPhone always shows its search field

  Store get store => widget.store;

  List<Item> get _visible {
    final q = _query.toLowerCase().trim();
    return store.items
        .where((i) => _listId == null || i.listId == _listId)
        .where((i) => _kind == null || i.kind == _kind)
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
        final kinds = {for (final i in store.items) i.kind}.toList()..sort((a, b) => a.index.compareTo(b.index));
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
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
            SliverToBoxAdapter(child: _listPills(context)),
            if (kinds.length > 1) SliverToBoxAdapter(child: _kindPills(context, kinds)),
            if (items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _empty(context))
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, ios ? 24 : 96),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => ItemCard(store: store, item: items[i]),
                    childCount: items.length,
                  ),
                ),
              ),
          ]),
        );
      },
    );
  }

  Widget _row(List<Widget> children, double height) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => Center(child: children[i]),
        ),
      );

  Widget _listPills(BuildContext context) => _row([
        Pill(label: 'All', selected: _listId == null, onTap: () => setState(() => _listId = null)),
        for (final l in store.lists)
          Pill(
            label: '${l.emoji} ${l.name}',
            selected: _listId == l.id,
            onTap: () => setState(() => _listId = l.id),
            onLongPress: () => _confirmDeleteList(context, l),
          ),
        Pill(label: 'New list', icon: isIOS(context) ? CupertinoIcons.plus : Icons.add, selected: false, onTap: () => _newList(context)),
      ], 48);

  Widget _kindPills(BuildContext context, List<Kind> kinds) => _row([
        for (final k in kinds)
          Pill(
            label: k.label,
            icon: k.icon(context),
            selected: _kind == k,
            onTap: () => setState(() => _kind = _kind == k ? null : k),
          ),
      ], 44);

  Widget _empty(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ios = isIOS(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(ios ? CupertinoIcons.bookmark : Icons.bookmarks_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(_query.isEmpty ? 'Nothing here yet' : 'No matches',
            style: ios ? t.titleLarge?.copyWith(fontWeight: FontWeight.w600) : t.headlineSmall),
        const SizedBox(height: 8),
        Text(
          _query.isEmpty
              ? 'In YouTube (or any app) tap Share → Revue.\nOr tap ${ios ? '+' : 'Add'} to paste a link or pick screenshots.'
              : 'Try different words — search covers titles, notes, tags and text inside screenshots.',
          textAlign: TextAlign.center,
          style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }

  Future<void> _add() async {
    final ios = isIOS(context);
    final choice = await pickOption<_Add>(context, [
      SheetOption(_Add.paste, 'Paste Link', icon: ios ? CupertinoIcons.doc_on_clipboard : Icons.content_paste,
          subtitle: 'YouTube, articles, places, anything'),
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

  Future<void> _newList(BuildContext context) async {
    final name = await promptText(context, 'New List', hint: 'Name — start with an emoji if you like', action: 'Create');
    if (name == null || name.trim().isEmpty) return;
    // "🍝 Recipes" → emoji 🍝, name Recipes
    final parts = name.trim().split(' ');
    final hasEmoji = parts.length > 1 && !RegExp(r'[A-Za-z0-9]').hasMatch(parts.first);
    final l = await store.addList(hasEmoji ? parts.skip(1).join(' ') : name.trim(), hasEmoji ? parts.first : '📌');
    setState(() => _listId = l.id);
  }

  Future<void> _confirmDeleteList(BuildContext context, RevueList l) async {
    if (!await confirm(context, 'Delete “${l.name}”?', message: 'Items in it stay in your library.')) return;
    if (_listId == l.id) setState(() => _listId = null);
    await store.deleteList(l);
  }
}

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.store, required this.item});
  final Store store;
  final Item item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ios = isIOS(context);
    final thumb = store.thumbFile(item);
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(
            context,
            ios
                ? CupertinoPageRoute(builder: (_) => ItemPage(store: store, item: item))
                : MaterialPageRoute(builder: (_) => ItemPage(store: store, item: item))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(fit: StackFit.expand, children: [
              thumb != null
                  ? Image.file(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder(context, scheme))
                  : _placeholder(context, scheme),
              Positioned(
                left: 8,
                top: 8,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: Colors.black54,
                  child: Icon(item.kind.icon(context), size: 14, color: Colors.white),
                ),
              ),
              if (item.done)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Icon(ios ? CupertinoIcons.checkmark_circle_fill : Icons.check_circle, color: Colors.white, size: 22),
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
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall?.copyWith(height: 1.2, fontWeight: ios ? FontWeight.w600 : null)),
                const Spacer(),
                Row(children: [
                  Expanded(
                    child: Text(
                      item.source.isNotEmpty ? item.source : item.kind.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  if (item.rating > 0) ...[
                    Icon(ios ? CupertinoIcons.star_fill : Icons.star, size: 12, color: scheme.primary),
                    const SizedBox(width: 2),
                    Text('${item.rating}', style: t.labelSmall),
                  ],
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _placeholder(BuildContext context, ColorScheme scheme) => ColoredBox(
        color: scheme.primaryContainer,
        child: Center(child: Icon(item.kind.icon(context), size: 36, color: scheme.onPrimaryContainer)),
      );
}
