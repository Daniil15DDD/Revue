import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../store.dart';

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

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  void _change(VoidCallback fn) {
    setState(fn);
    widget.store.update(item);
  }

  Future<void> _open() async {
    final url = item.url == null ? null : Uri.tryParse(item.url!);
    if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final thumb = widget.store.thumbFile(item);
    return Scaffold(
      appBar: AppBar(actions: [
        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        if (thumb != null)
          GestureDetector(
            onTap: item.url != null ? _open : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(thumb, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            ),
          ),
        const SizedBox(height: 16),
        Row(children: [
          Icon(item.kind.icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(item.source.isNotEmpty ? item.source : item.kind.label,
                style: t.labelLarge?.copyWith(color: scheme.primary)),
          ),
          Text(MaterialLocalizations.of(context).formatMediumDate(item.created), style: t.labelMedium),
        ]),
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
        const SizedBox(height: 20),
        _section('Your review'),
        Row(children: [
          for (var s = 1; s <= 5; s++)
            IconButton(
              tooltip: '$s star${s > 1 ? 's' : ''}',
              icon: Icon(s <= item.rating ? Icons.star : Icons.star_border, color: scheme.primary),
              onPressed: () => _change(() => item.rating = item.rating == s ? 0 : s),
            ),
          const Spacer(),
          FilterChip(
            label: Text(item.kind == Kind.video ? 'Watched' : item.kind == Kind.place ? 'Visited' : 'Done'),
            selected: item.done,
            onSelected: (v) => _change(() => item.done = v),
          ),
        ]),
        TextField(
          controller: _note,
          maxLines: null,
          minLines: 2,
          decoration: const InputDecoration(hintText: 'Thoughts, why you saved it…', border: OutlineInputBorder()),
          onChanged: (v) => _change(() => item.note = v),
        ),
        const SizedBox(height: 20),
        _section('Filed under'),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          DropdownButton<String?>(
            value: widget.store.lists.any((l) => l.id == item.listId) ? item.listId : null,
            hint: const Text('No list'),
            onChanged: (v) => _change(() => item.listId = v),
            items: [
              const DropdownMenuItem(value: null, child: Text('No list')),
              for (final l in widget.store.lists) DropdownMenuItem(value: l.id, child: Text('${l.emoji} ${l.name}')),
            ],
          ),
          DropdownButton<Kind>(
            value: item.kind,
            onChanged: (v) => _change(() => item.kind = v ?? item.kind),
            items: [for (final k in Kind.values) DropdownMenuItem(value: k, child: Text(k.label))],
          ),
        ]),
        if (item.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final tag in item.tags)
              InputChip(
                label: Text('#$tag'),
                onDeleted: () => _change(() => item.tags = [...item.tags]..remove(tag)),
              ),
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

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this item?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.delete(item);
    if (mounted) Navigator.pop(context);
  }
}
