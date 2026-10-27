import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../store.dart';
import 'item_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.store});
  final Store store;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String? _listId; // null = everything
  Kind? _kind;
  String _query = '';
  bool _searching = false;

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
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final items = _visible;
        final kinds = {for (final i in store.items) i.kind}.toList()..sort((a, b) => a.index.compareTo(b.index));
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddSheet(context),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
          body: CustomScrollView(slivers: [
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
            SliverToBoxAdapter(child: _listChips(context)),
            if (kinds.length > 1) SliverToBoxAdapter(child: _kindChips(kinds)),
            if (items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _empty(context))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
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

  Widget _listChips(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _chip('All', _listId == null, () => setState(() => _listId = null)),
          for (final l in store.lists)
            GestureDetector(
              onLongPress: () => _confirmDeleteList(context, l),
              child: _chip('${l.emoji} ${l.name}', _listId == l.id, () => setState(() => _listId = l.id)),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('New list'),
              onPressed: () => _newList(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kindChips(List<Kind> kinds) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final k in kinds)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(k.icon, size: 16),
                label: Text(k.label),
                selected: _kind == k,
                showCheckmark: false,
                onSelected: (on) => setState(() => _kind = on ? k : null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap(), showCheckmark: false),
      );

  Widget _empty(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.bookmarks_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(_query.isEmpty ? 'Nothing here yet' : 'No matches', style: t.headlineSmall),
        const SizedBox(height: 8),
        Text(
          _query.isEmpty
              ? 'In YouTube (or any app) tap Share → Revue.\nOr tap Add to paste a link or pick screenshots.'
              : 'Try different words — search covers titles, notes, tags and text inside screenshots.',
          textAlign: TextAlign.center,
          style: t.bodyMedium,
        ),
      ]),
    );
  }

  Future<void> _showAddSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.content_paste),
              title: const Text('Paste link or text'),
              subtitle: const Text('YouTube, articles, places, anything'),
              onTap: () async {
                Navigator.pop(ctx);
                final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
                if (context.mounted) _addTextDialog(context, clip);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Screenshots'),
              subtitle: const Text('Text is read on-device and auto-tagged'),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await ImagePicker().pickMultiImage();
                for (final p in picked) {
                  store.addScreenshot(p.path, listId: _listId);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Note'),
              onTap: () {
                Navigator.pop(ctx);
                _addTextDialog(context, '', note: true);
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _addTextDialog(BuildContext context, String initial, {bool note = false}) async {
    final c = TextEditingController(text: note ? '' : initial);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(note ? 'New note' : 'Add link'),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: note ? 3 : 1,
          maxLines: note ? 8 : 3,
          decoration: InputDecoration(hintText: note ? 'Write anything…' : 'https://…'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    note ? store.addNote(text, listId: _listId) : store.addText(text, listId: _listId);
  }

  Future<void> _newList(BuildContext context) async {
    final name = TextEditingController();
    final emoji = TextEditingController(text: '📌');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New list'),
        content: Row(children: [
          SizedBox(width: 56, child: TextField(controller: emoji, textAlign: TextAlign.center)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(controller: name, autofocus: true, decoration: const InputDecoration(hintText: 'Name')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      final l = await store.addList(name.text.trim(), emoji.text.trim());
      setState(() => _listId = l.id);
    }
  }

  Future<void> _confirmDeleteList(BuildContext context, RevueList l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${l.name}”?'),
        content: const Text('Items in it stay in your library.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
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
    final t = Theme.of(context).textTheme;
    final thumb = store.thumbFile(item);
    return Card(
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemPage(store: store, item: item))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: Stack(fit: StackFit.expand, children: [
              thumb != null
                  ? Image.file(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder(scheme))
                  : _placeholder(scheme),
              Positioned(
                left: 8,
                top: 8,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: Colors.black54,
                  child: Icon(item.kind.icon, size: 15, color: Colors.white),
                ),
              ),
              if (item.done)
                const Positioned(right: 8, top: 8, child: Icon(Icons.check_circle, color: Colors.white, size: 22)),
              if (store.processing.contains(item.id))
                const ColoredBox(
                  color: Colors.black38,
                  child: Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))),
                ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(height: 1.2)),
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
                    Icon(Icons.star, size: 13, color: scheme.primary),
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

  Widget _placeholder(ColorScheme scheme) => ColoredBox(
        color: scheme.primaryContainer,
        child: Center(child: Icon(item.kind.icon, size: 36, color: scheme.onPrimaryContainer)),
      );
}
