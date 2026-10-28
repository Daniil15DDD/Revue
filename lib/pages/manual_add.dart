import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../adaptive.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Types people add by hand when the databases don't have it.
const _kinds = [Kind.show, Kind.book, Kind.movie, Kind.game, Kind.music, Kind.place, Kind.note];

/// "Add Manually": title, type, episodes/pages, cover, status and list in one sheet.
Future<Item?> showManualAdd(BuildContext context, Store store, {String title = '', Kind kind = Kind.show, String? listId}) {
  return showRevueSheet<Item>(context, (ctx) => _ManualAdd(store: store, title: title, kind: kind, listId: listId));
}

class _ManualAdd extends StatefulWidget {
  const _ManualAdd({required this.store, required this.title, required this.kind, this.listId});
  final Store store;
  final String title;
  final Kind kind;
  final String? listId;

  @override
  State<_ManualAdd> createState() => _ManualAddState();
}

class _ManualAddState extends State<_ManualAdd> {
  late final _title = TextEditingController(text: widget.title);
  final _total = TextEditingController();
  late Kind _kind = widget.kind;
  Status _status = Status.planned;
  late String? _listId = widget.listId;
  String? _image;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _total.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    final total = int.tryParse(_total.text.trim());
    final item = await widget.store.addManual(_title.text,
        kind: _kind, status: _status, listId: _listId, total: total != null && total > 0 ? total : null, imagePath: _image);
    if (mounted) Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    final unit = _kind.progressUnit;
    Widget label(String t) => Padding(padding: const EdgeInsets.fromLTRB(2, 18, 2, 10), child: Text(t, style: RvText.label(rv.text2)));
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(18, 10, 18, 18), children: [
      Center(child: Container(width: 36, height: 5, decoration: BoxDecoration(color: rv.stroke, borderRadius: BorderRadius.circular(3)))),
      const SizedBox(height: 14),
      Text('Add Manually', textAlign: TextAlign.center, style: RvText.headline(rv.text)),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Cover: tap to pick a photo.
        Semantics(
          button: true,
          label: _image == null ? 'Add a cover' : 'Change cover',
          child: Pressable(
            onTap: () async {
              final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200);
              if (x != null) setState(() => _image = x.path);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 74,
                height: 104,
                color: rv.raised,
                child: _image == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_photo_alternate_outlined, color: rv.text2),
                        const SizedBox(height: 4),
                        Text('Cover', style: RvText.small(rv.text2)),
                      ])
                    : Image.file(File(_image!), fit: BoxFit.cover),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(children: [
            RvField(controller: _title, hint: 'Title', autofocus: widget.title.isEmpty, onChanged: (_) => setState(() {})),
            if (unit != null) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _total,
                keyboardType: TextInputType.number,
                style: RvText.body(rv.text),
                decoration: InputDecoration(
                  hintText: 'Total $unit (optional)',
                  hintStyle: RvText.body(rv.text3),
                  filled: true,
                  fillColor: rv.raised,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                ),
              ),
            ],
          ]),
        ),
      ]),
      label('TYPE'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in _kinds)
          Pill(
            label: k == Kind.show ? 'Series / Anime' : k.label,
            icon: k.materialIcon,
            selected: _kind == k,
            onTap: () => setState(() => _kind = k),
          ),
      ]),
      label('STATUS'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in [Status.planned, Status.active, Status.finished])
          Pill(label: s.label(_kind), selected: _status == s, onTap: () => setState(() => _status = s)),
      ]),
      if (widget.store.lists.isNotEmpty) ...[
        label('LIST'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pill(label: 'Inbox', selected: _listId == null, onTap: () => setState(() => _listId = null)),
          for (final l in widget.store.lists) Pill(label: l.display, selected: _listId == l.id, onTap: () => setState(() => _listId = l.id)),
        ]),
      ],
      const SizedBox(height: 24),
      PillButton(label: _saving ? 'Adding…' : 'Add', onTap: _title.text.trim().isEmpty || _saving ? null : _save),
    ]);
  }
}
