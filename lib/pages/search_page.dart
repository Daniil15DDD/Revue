import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../adaptive.dart';
import '../catalog.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

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
  Timer? _debounce;
  int _searchId = 0; // ignore answers from older searches that arrive late

  Store get store => widget.store;

  @override
  void dispose() {
    _debounce?.cancel();
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
    final ios = isIOS(context);
    final hint = switch (_kind) {
      CatalogKind.series => 'Search TV series',
      CatalogKind.anime => 'Search anime',
      CatalogKind.books => 'Search books or authors',
    };
    return Scaffold(
      appBar: ios
          ? const CupertinoNavigationBar(middle: Text('Search'), previousPageTitle: 'Revue', border: null)
          : AppBar(title: const Text('Search & add')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: ios
              ? CupertinoSearchTextField(autofocus: true, placeholder: hint, onChanged: _onQuery)
              : TextField(
                  autofocus: true,
                  onChanged: _onQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: hint,
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ios
                ? CupertinoSlidingSegmentedControl<CatalogKind>(
                    groupValue: _kind,
                    onValueChanged: (k) {
                      setState(() => _kind = k ?? _kind);
                      _search();
                    },
                    children: {for (final k in CatalogKind.values) k: Text(k.label)},
                  )
                : SegmentedButton<CatalogKind>(
                    showSelectedIcon: false,
                    segments: [for (final k in CatalogKind.values) ButtonSegment(value: k, label: Text(k.label))],
                    selected: {_kind},
                    onSelectionChanged: (s) {
                      setState(() => _kind = s.first);
                      _search();
                    },
                  ),
          ),
        ),
        Expanded(child: _body(context)),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    final secondary = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    if (_loading && _results.isEmpty) {
      return Center(child: isIOS(context) ? const CupertinoActivityIndicator() : const CircularProgressIndicator());
    }
    if (_results.isEmpty) {
      final source = switch (_kind) {
        CatalogKind.series => 'TVmaze',
        CatalogKind.anime => 'AniList',
        CatalogKind.books => 'Open Library',
      };
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          _query.trim().isEmpty ? 'Type a title. Results come from $source.' : 'Nothing found on $source.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: secondary),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _row(context, _results[i]),
    );
  }

  Widget _row(BuildContext context, CatalogResult r) {
    final ios = isIOS(context);
    final label = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondary = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final accent = Theme.of(context).colorScheme.primary;
    final added = _added.contains(r.url ?? r.title);
    return Semantics(
      button: true,
      label: added ? '${r.title}, added' : 'Add ${r.title}',
      child: Pressable(
        onTap: added ? null : () => _add(r),
        child: Container(
          decoration: surface(context, radius: 14),
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 52,
                height: 76,
                child: r.imageUrl == null
                    ? ColoredBox(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(r.kind.icon(context), color: Theme.of(context).colorScheme.onPrimaryContainer),
                      )
                    : Image.network(r.imageUrl.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => ColoredBox(color: Theme.of(context).colorScheme.primaryContainer)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: label)),
                if (r.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(r.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: secondary)),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Icon(
              added
                  ? (ios ? CupertinoIcons.checkmark_circle_fill : Icons.check_circle)
                  : (ios ? CupertinoIcons.plus_circle_fill : Icons.add_circle),
              color: added ? secondary : accent,
              size: 28,
            ),
          ]),
        ),
      ),
    );
  }
}
