import 'dart:async';

import 'package:flutter/material.dart';

import '../adaptive.dart';
import '../catalog.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'manual_add.dart';

/// Search TVmaze / AniList / Open Library and add a result with its status and list in two taps.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.store, this.listId});
  final Store store;
  final String? listId; // list currently open on the home page, offered first

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  CatalogKind _kind = CatalogKind.series;
  String _query = '';
  List<CatalogResult> _results = [];
  bool _loading = false;
  final Set<String> _added = {};
  final _field = TextEditingController();
  Timer? _debounce;
  int _searchId = 0; // ignore answers from older searches that arrive late

  Store get store => widget.store;

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _query = q;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _search() async {
    final id = ++_searchId;
    if (_query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    final results = await store.catalog.search(_query, _kind);
    if (!mounted || id != _searchId) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  Future<void> _add(CatalogResult r) async {
    final status = await pickOption<Status>(
      context,
      [for (final s in [Status.planned, Status.active, Status.finished]) SheetOption(s, s.label(r.kind))],
      title: r.title,
    );
    if (status == null || !mounted) return;
    final current = store.lists.where((l) => l.id == widget.listId).firstOrNull;
    final listId = await pickOption<String>(context, [
      if (current != null) SheetOption(current.id, current.display),
      for (final l in store.lists.where((l) => l.id != current?.id)) SheetOption(l.id, l.display),
      const SheetOption('', 'No list'),
    ], title: 'Add to list');
    if (listId == null || !mounted) return;
    await store.addFromCatalog(r, status: status, listId: listId.isEmpty ? null : listId);
    if (!mounted) return;
    setState(() => _added.add(r.url ?? r.title));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added “${r.title}”')));
  }

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    final hint = switch (_kind) {
      CatalogKind.series => 'Search TV series',
      CatalogKind.anime => 'Search anime',
      CatalogKind.books => 'Search books or authors',
    };
    return Scaffold(
      appBar: const TopBar(title: 'Find'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: RvField(controller: _field, hint: hint, autofocus: true, prefix: Icons.search_rounded, onChanged: _onQuery),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final k in CatalogKind.values)
              Tag(
                label: k.label,
                selected: _kind == k,
                onTap: () {
                  setState(() => _kind = k);
                  _search();
                },
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(child: _body(context, rv)),
      ]),
    );
  }

  Widget _body(BuildContext context, Rv rv) {
    if (_loading && _results.isEmpty) {
      return Center(child: SizedBox.square(dimension: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: rv.text2)));
    }
    if (_results.isEmpty) {
      final source = switch (_kind) {
        CatalogKind.series => 'TVmaze',
        CatalogKind.anime => 'AniList',
        CatalogKind.books => 'Open Library',
      };
      return ListView(padding: const EdgeInsets.all(32), children: [
        Text(_query.trim().isEmpty ? 'Type a title. Results come from $source.' : 'Nothing found on $source.',
            textAlign: TextAlign.center, style: RvText.body(rv.text2)),
        const SizedBox(height: 18),
        Center(child: PillButton(label: 'Add Manually', icon: Icons.edit_rounded, primary: _query.trim().isNotEmpty, onTap: _manual)),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      itemCount: _results.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => i < _results.length ? _row(context, rv, _results[i]) : _manualRow(rv),
    );
  }

  /// The kind the current tab suggests for a hand-made item.
  Kind get _manualKind => _kind == CatalogKind.books ? Kind.book : Kind.show;

  Future<void> _manual() async {
    final item = await showManualAdd(context, store, title: _query.trim(), kind: _manualKind, listId: widget.listId);
    if (item != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added “${item.title}”')));
    }
  }

  /// Last row under results: for when the right one isn't there.
  Widget _manualRow(Rv rv) => Pressable(
        scale: 0.98,
        onTap: _manual,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: rv.stroke)),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: rv.raised, borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.edit_rounded, color: rv.text),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Can’t find it?', style: RvText.headline(rv.text).copyWith(fontSize: 16)),
                Text('Add manually — title, cover, episodes or pages', style: RvText.small(rv.text2)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: rv.text3),
          ]),
        ),
      );

  Widget _row(BuildContext context, Rv rv, CatalogResult r) {
    final added = _added.contains(r.url ?? r.title);
    return Semantics(
      button: true,
      label: added ? '${r.title}, added' : 'Add ${r.title}',
      child: Pressable(
        scale: 0.98,
        onTap: added ? null : () => _add(r),
        child: Container(
          decoration: surface(context, radius: 24),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 58,
                height: 84,
                child: r.imageUrl == null
                    ? ColoredBox(color: rv.raised, child: Icon(r.kind.materialIcon, color: rv.text3))
                    : Image.network(r.imageUrl.toString(),
                        fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: rv.raised)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: RvText.headline(rv.text).copyWith(fontSize: 16)),
                if (r.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(r.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: RvText.small(rv.text2)),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Container(
                key: ValueKey(added),
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: added ? rv.raised : rv.ink, shape: BoxShape.circle),
                child: Icon(added ? Icons.check_rounded : Icons.add_rounded, color: added ? rv.text2 : rv.onInk, size: 24),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
