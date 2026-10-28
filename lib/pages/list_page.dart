import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_page.dart';
import 'list_editor.dart';

/// Same slide + swipe-back on both platforms (part of Revue's own feel).
Route<T> revueRoute<T>(Widget page) => CupertinoPageRoute<T>(builder: (_) => page);

const _order = [Status.active, Status.planned, Status.paused, Status.finished, Status.dropped];

/// Status word that fits most of the items in a group ("Watching" for mostly series, "Reading" for books…).
String groupLabel(Status s, List<Item> items) {
  final counts = <Kind, int>{};
  for (final i in items) {
    counts[i.kind] = (counts[i.kind] ?? 0) + 1;
  }
  final kind = counts.entries.fold<MapEntry<Kind, int>?>(null, (a, b) => a == null || b.value > a.value ? b : a)?.key;
  return s.label(kind ?? Kind.link);
}

/// One list (or the Inbox when [list] is null): cover header, then items grouped by status.
class ListPage extends StatefulWidget {
  const ListPage({super.key, required this.store, required this.list});
  final Store store;
  final RevueList? list;

  @override
  State<ListPage> createState() => _ListPageState();
}

class _ListPageState extends State<ListPage> {
  Status? _only; // filter to one status

  Store get store => widget.store;

  List<Item> get _items {
    final l = widget.list;
    if (l == null) return store.items.where((i) => i.listId == null || store.lists.every((x) => x.id != i.listId)).toList();
    return store.items.where((i) => i.listId == l.id).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final list = widget.list;
        if (list != null && !store.lists.contains(list)) return const SizedBox(); // deleted while open
        final items = _items;
        final groups = {for (final s in _order) s: items.where((i) => i.status == s).toList()}..removeWhere((_, v) => v.isEmpty);
        if (_only != null && !groups.containsKey(_only)) _only = null;
        return Scaffold(
          body: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _header(context, list, items.length)),
            if (groups.length > 1)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 60,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    children: [
                      Tag(label: 'All', selected: _only == null, onTap: () => setState(() => _only = null)),
                      for (final e in groups.entries)
                        Tag(label: groupLabel(e.key, e.value), selected: _only == e.key, onTap: () => setState(() => _only = e.key)),
                    ],
                  ),
                ),
              ),
            if (items.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                  child: Column(children: [
                    Text('Nothing here yet', style: RvText.title(rv.text)),
                    const SizedBox(height: 8),
                    Text('Tap + to search for a show or book, paste a link, or import a screenshot.',
                        textAlign: TextAlign.center, style: RvText.body(rv.text2)),
                  ]),
                ),
              ),
            for (final e in groups.entries)
              if (_only == null || _only == e.key) ...[
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(child: SectionLabel(groupLabel(e.key, e.value), count: e.value.length)),
                ),
                SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 16), sliver: itemGrid(store, e.value)),
              ],
            const SliverToBoxAdapter(child: SizedBox(height: 60)),
          ]),
        );
      },
    );
  }

  Widget _header(BuildContext context, RevueList? list, int count) {
    final rv = Rv.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final onCover = list == null ? rv.text : Colors.white;
    final glassButton = BoxDecoration(
        color: list == null ? rv.raised : Colors.black.withValues(alpha: 0.28), shape: BoxShape.circle);
    Widget circle(IconData icon, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          child: Pressable(
            onTap: onTap,
            scale: 0.9,
            child: Container(width: 44, height: 44, decoration: glassButton, child: Icon(icon, color: onCover, size: 22)),
          ),
        );
    final content = Padding(
      padding: EdgeInsets.fromLTRB(20, top + 8, 16, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          circle(Icons.arrow_back_ios_new_rounded, 'Back', () => Navigator.maybePop(context)),
          const Spacer(),
          if (list != null) circle(Icons.more_horiz_rounded, 'List options', () => editListMenu(context, store, list)),
        ]),
        const Spacer(),
        Text(count == 1 ? '1 item' : '$count items',
            style: TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w500, color: list == null ? rv.text2 : Colors.white)),
        Text(list?.display ?? 'Inbox',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: font, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.4, height: 1.05, color: onCover)),
      ]),
    );
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: SizedBox(
        height: top + (list == null ? 170 : 250),
        child: list == null ? ColoredBox(color: rv.surface, child: content) : ListCover(store: store, list: list, child: content),
      ),
    );
  }
}

/// Two-up (or more on wide screens) grid of item cards.
Widget itemGrid(Store store, List<Item> items) => SliverLayoutBuilder(builder: (context, c) {
      final columns = (c.crossAxisExtent / 200).floor().clamp(2, 5);
      final w = (c.crossAxisExtent - 12 * (columns - 1)) / columns;
      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          mainAxisExtent: w * 1.25 + 74, // poster-ish image + title + meta
        ),
        delegate: SliverChildBuilderDelegate((context, i) => ItemCard(store: store, item: items[i]), childCount: items.length),
      );
    });

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.store, required this.item});
  final Store store;
  final Item item;

  /// Short progress for cards: "S3 · E4", "p. 212 / 496", or the source.
  String get _meta {
    final se = item.seasonEpisode;
    if (item.kind == Kind.show && se != null) return 'S${se.$1} · E${se.$2}';
    if (item.kind == Kind.book && item.progress > 0) return 'p. ${item.progress}${item.total == null ? '' : ' / ${item.total}'}';
    return item.progressLabel ?? (item.source.isNotEmpty ? item.source : item.kind.label);
  }

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    final thumb = store.thumbFile(item);
    final fraction = item.total == null || item.total == 0 ? null : item.progress / item.total!;
    return Semantics(
      button: true,
      label: '${item.title}, ${item.status.label(item.kind)}',
      child: Pressable(
        onTap: () => Navigator.push(context, revueRoute(ItemPage(store: store, item: item))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(fit: StackFit.expand, children: [
                thumb != null ? Image.file(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder(rv)) : _placeholder(rv),
                if (item.status == Status.finished)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: rv.ink, shape: BoxShape.circle),
                      child: Icon(Icons.check_rounded, size: 14, color: rv.onInk),
                    ),
                  ),
                if (fraction != null && item.status == Status.active)
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: ProgressTrack(value: fraction, color: Colors.white, height: 5, track: Colors.white24),
                  ),
                if (store.processing.contains(item.id))
                  const ColoredBox(
                    color: Colors.black38,
                    child: Center(
                        child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 9),
          Text(item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: font, fontSize: 15, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.2, color: rv.text)),
          const SizedBox(height: 3),
          Text(_meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: RvText.small(rv.text2)),
        ]),
      ),
    );
  }

  Widget _placeholder(Rv rv) => ColoredBox(
        color: rv.raised,
        child: Center(child: Icon(item.kind.materialIcon, size: 34, color: rv.text3)),
      );
}
