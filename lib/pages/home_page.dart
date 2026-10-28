import 'package:flutter/material.dart';

import '../adaptive.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'list_editor.dart';
import 'list_page.dart';

/// Home: folder chips on top, then a big card per list (colour or photo), like a wallet of collections.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store, required this.onCreateList});
  final Store store;
  final VoidCallback onCreateList;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _folderId; // null = All
  bool _searching = false;
  final _query = TextEditingController();

  Store get store => widget.store;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, _query]),
      builder: (context, _) {
        if (_folderId != null && store.folders.every((f) => f.id != _folderId)) _folderId = null;
        final lists = store.lists.where((l) => _folderId == null || l.folderId == _folderId).toList();
        final inbox = store.items.where((i) => i.listId == null || store.lists.every((l) => l.id != i.listId)).length;
        final q = _query.text.trim().toLowerCase();
        return Scaffold(
          body: CustomScrollView(slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverToBoxAdapter(child: _chips(context)),
            ),
            if (_searching)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: RvField(controller: _query, hint: 'Search everything you saved', autofocus: true, prefix: Icons.search_rounded),
                ),
              ),
            if (q.isNotEmpty)
              ...searchResults(context, store, q)
            else ...[
              if (store.lists.isEmpty && inbox == 0)
                SliverFillRemaining(hasScrollBody: false, child: _empty(context))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverList.separated(
                    itemCount: lists.length + (_folderId == null && inbox > 0 ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, i) {
                      if (i == lists.length) return _InboxCard(store: store, count: inbox);
                      return ListCard(store: store, list: lists[i]);
                    },
                  ),
                ),
              if (_folderId != null && lists.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('No lists in this folder yet. Open a list’s ••• menu to move it here.',
                        textAlign: TextAlign.center, style: RvText.body(rv.text2)),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 130)), // room above the floating tab bar
            ],
          ]),
        );
      },
    );
  }

  Widget _chips(BuildContext context) {
    final rv = Rv.of(context);
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        children: [
          RoundButton(
            icon: _searching ? Icons.close_rounded : Icons.search_rounded,
            tooltip: _searching ? 'Close search' : 'Search',
            filled: false,
            onTap: () => setState(() {
              _searching = !_searching;
              _query.clear();
            }),
          ),
          const SizedBox(width: 4),
          Tag(label: 'All', selected: _folderId == null, onTap: () => setState(() => _folderId = null)),
          for (final f in store.folders)
            Tag(
              label: f.name,
              selected: _folderId == f.id,
              onTap: () => setState(() => _folderId = f.id),
              onLongPress: () => _folderMenu(f),
            ),
          Pressable(
            onTap: _addFolder,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Icon(Icons.add_rounded, size: 20, color: rv.text),
                const SizedBox(width: 4),
                Text('Add Folder', style: RvText.body(rv.text).copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final rv = Rv.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 140),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(color: rv.raised, borderRadius: BorderRadius.circular(28)),
          child: Icon(Icons.collections_bookmark_rounded, size: 38, color: rv.text2),
        ),
        const SizedBox(height: 20),
        Text('Start your first list', style: RvText.title(rv.text), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('Anime to watch, books for winter, places in Tokyo — name it anything.',
            style: RvText.body(rv.text2), textAlign: TextAlign.center),
        const SizedBox(height: 22),
        PillButton(label: 'Create a List', icon: Icons.add_rounded, onTap: widget.onCreateList),
      ]),
    );
  }

  Future<void> _addFolder() async {
    final name = await promptText(context, 'New Folder', hint: 'e.g. Entertainment, Travel, Study', action: 'Create');
    if (name == null || name.trim().isEmpty) return;
    final f = await store.addFolder(name);
    setState(() => _folderId = f.id);
  }

  Future<void> _folderMenu(Folder f) async {
    final a = await pickOption<String>(context, [
      const SheetOption('rename', 'Rename', icon: Icons.edit_rounded),
      const SheetOption('delete', 'Delete Folder', icon: Icons.delete_outline_rounded, destructive: true),
    ], title: f.name);
    if (!mounted || a == null) return;
    if (a == 'rename') {
      final n = await promptText(context, 'Rename Folder', initial: f.name, action: 'Rename');
      if (n != null) await store.renameFolder(f, n);
    } else if (await confirm(context, 'Delete “${f.name}”?', message: 'Its lists are kept, just moved out of the folder.')) {
      await store.deleteFolder(f);
    }
  }
}

/// A list as a big rounded card: folder label top-left, ••• top-right, count + name bottom-left.
class ListCard extends StatelessWidget {
  const ListCard({super.key, required this.store, required this.list});
  final Store store;
  final RevueList list;

  @override
  Widget build(BuildContext context) {
    final folder = store.folders.where((f) => f.id == list.folderId).firstOrNull;
    final n = store.itemCount(list);
    return Semantics(
      button: true,
      label: '${list.name}, $n items',
      child: Pressable(
        scale: 0.97,
        onTap: () => Navigator.push(context, revueRoute(ListPage(store: store, list: list))),
        child: AspectRatio(
          aspectRatio: 1.75,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: ListCover(
              store: store,
              list: list,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 10, 20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(folder == null ? Icons.collections_bookmark_outlined : Icons.folder_outlined, size: 20, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(folder?.name ?? 'List',
                          style: const TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                    Semantics(
                      button: true,
                      label: 'List options',
                      child: Pressable(
                        onTap: () => editListMenu(context, store, list),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(Icons.more_horiz_rounded, color: Colors.white, size: 28),
                        ),
                      ),
                    ),
                  ]),
                  const Spacer(),
                  Text(n == 1 ? '1 item' : '$n items',
                      style: const TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(list.display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: font, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1, color: Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Items not in any list yet (shared links, quick screenshots).
class _InboxCard extends StatelessWidget {
  const _InboxCard({required this.store, required this.count});
  final Store store;
  final int count;

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    return Pressable(
      scale: 0.97,
      onTap: () => Navigator.push(context, revueRoute(ListPage(store: store, list: null))),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: surface(context, radius: 28),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: rv.raised, borderRadius: BorderRadius.circular(16)),
            child: Icon(Icons.inbox_rounded, color: rv.text),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Inbox', style: RvText.headline(rv.text)),
              Text('$count not in a list yet', style: RvText.small(rv.text2)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: rv.text3),
        ]),
      ),
    );
  }
}

/// Search across every item; results as rows.
List<Widget> searchResults(BuildContext context, Store store, String q) {
  final hits = store.items.where((i) => i.haystack.contains(q)).toList();
  final rv = Rv.of(context);
  return [
    if (hits.isEmpty)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Nothing matches “$q”.', textAlign: TextAlign.center, style: RvText.body(rv.text2)),
        ),
      )
    else
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
        sliver: itemGrid(store, hits),
      ),
  ];
}
