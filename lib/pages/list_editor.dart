import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../adaptive.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// Create or edit a list: name, colour or photo, folder — with a live preview of its card.
Future<RevueList?> showListEditor(BuildContext context, Store store, {RevueList? list}) {
  return showRevueSheet<RevueList>(context, (ctx) => _ListEditor(store: store, list: list));
}

/// ••• menu on a list card.
Future<void> editListMenu(BuildContext context, Store store, RevueList list) async {
  final a = await pickOption<String>(context, [
    const SheetOption('edit', 'Edit List', icon: Icons.tune_rounded, subtitle: 'Name, colour, photo, folder'),
    const SheetOption('delete', 'Delete List', icon: Icons.delete_outline_rounded, destructive: true),
  ], title: list.name);
  if (!context.mounted || a == null) return;
  if (a == 'edit') {
    await showListEditor(context, store, list: list);
  } else if (await confirm(context, 'Delete “${list.name}”?', message: 'Its items stay in your library, in the Inbox.')) {
    await store.deleteList(list);
  }
}

class _ListEditor extends StatefulWidget {
  const _ListEditor({required this.store, this.list});
  final Store store;
  final RevueList? list;

  @override
  State<_ListEditor> createState() => _ListEditorState();
}

class _ListEditorState extends State<_ListEditor> {
  late final _name = TextEditingController(text: widget.list?.name ?? '');
  late int _color = widget.list?.color ?? listPalette[widget.store.lists.length % listPalette.length];
  late String? _folderId = widget.list?.folderId;
  String? _imagePath; // newly picked photo
  late bool _hasImage = widget.list?.image != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600);
    if (x != null) setState(() {
        _imagePath = x.path;
        _hasImage = true;
      });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final store = widget.store;
    final l = widget.list;
    if (l == null) {
      final created = await store.addList(name, color: _color, folderId: _folderId, imagePath: _imagePath);
      if (mounted) Navigator.pop(context, created);
    } else {
      await store.editList(l,
          name: name,
          color: _color,
          imagePath: _imagePath,
          clearImage: !_hasImage && l.image != null,
          folderId: _folderId,
          clearFolder: _folderId == null);
      if (mounted) Navigator.pop(context, l);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    final store = widget.store;
    final preview = RevueList(name: _name.text.isEmpty ? 'New list' : _name.text, color: _color);
    final existing = widget.list?.image;
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(18, 10, 18, 18), children: [
      Center(
        child: Container(width: 36, height: 5, decoration: BoxDecoration(color: rv.stroke, borderRadius: BorderRadius.circular(3))),
      ),
      const SizedBox(height: 14),
      Text(widget.list == null ? 'Create a List' : 'Edit List', textAlign: TextAlign.center, style: RvText.headline(rv.text)),
      const SizedBox(height: 16),
      // Live preview of the card.
      AspectRatio(
        aspectRatio: 2.1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(fit: StackFit.expand, children: [
            if (_hasImage && _imagePath != null)
              Image.file(File(_imagePath!), fit: BoxFit.cover)
            else if (_hasImage && existing != null)
              ListCover(store: store, list: widget.list!)
            else
              ListCover(store: store, list: preview),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(preview.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: font, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      RvField(controller: _name, hint: 'Name it anything', autofocus: widget.list == null, onChanged: (_) => setState(() {})),
      const SizedBox(height: 18),
      Text('COLOUR', style: RvText.label(rv.text2)),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 12, children: [
        for (final c in listPalette)
          Semantics(
            button: true,
            selected: c == _color && !_hasImage,
            label: 'Colour',
            child: Pressable(
              scale: 0.85,
              onTap: () => setState(() {
                _color = c;
                _hasImage = false;
                _imagePath = null;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: c == _color && !_hasImage ? rv.ink : Colors.transparent, width: 3),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: PillButton(
            label: _hasImage ? 'Change Photo' : 'Use a Photo',
            icon: Icons.image_outlined,
            primary: false,
            compact: true,
            onTap: _pickPhoto,
          ),
        ),
        if (_hasImage) ...[
          const SizedBox(width: 10),
          PillButton(
            label: 'Remove',
            primary: false,
            compact: true,
            onTap: () => setState(() {
              _hasImage = false;
              _imagePath = null;
            }),
          ),
        ],
      ]),
      if (store.folders.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text('FOLDER', style: RvText.label(rv.text2)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Pill(label: 'None', selected: _folderId == null, onTap: () => setState(() => _folderId = null)),
          for (final f in store.folders) Pill(label: f.name, selected: _folderId == f.id, onTap: () => setState(() => _folderId = f.id)),
        ]),
      ],
      const SizedBox(height: 22),
      PillButton(label: widget.list == null ? 'Create List' : 'Save', onTap: _name.text.trim().isEmpty ? null : _save),
    ]);
  }
}
