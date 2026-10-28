import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ai.dart';
import 'link_fetcher.dart';
import 'models.dart';

/// The whole library: one JSON file plus a folder of thumbnails, all on the device.
class Store extends ChangeNotifier {
  Store(this.dir, {LinkFetcher? fetcher, this.llm, Future<String> Function(String path)? ocr})
      : fetcher = fetcher ?? LinkFetcher(),
        ocr = ocr ?? Ocr.read;

  final Directory dir;
  final LinkFetcher fetcher;
  final Future<String> Function(String path) ocr;

  /// Returns the on-device model when one is ready, else null (AI steps are skipped).
  final Llm? Function()? llm;

  List<RevueList> lists = [];
  List<Item> items = [];
  final Set<String> processing = {};
  String appearance = 'system'; // 'system' | 'light' | 'dark'

  File get _file => File('${dir.path}/revue.json');
  Directory get thumbsDir => Directory('${dir.path}/thumbs');
  File? thumbFile(Item i) => i.thumbnail == null ? null : File('${thumbsDir.path}/${i.thumbnail}');

  Future<void> load() async {
    await thumbsDir.create(recursive: true);
    // A crash between write and rename leaves only the .tmp file: use it.
    final tmp = File('${_file.path}.tmp');
    if (!await _file.exists() && await tmp.exists()) await tmp.rename(_file.path);
    Map<String, dynamic>? j;
    if (await _file.exists()) {
      try {
        j = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      } catch (e) {
        // Keep the unreadable file for recovery instead of overwriting it, and start fresh.
        debugPrint('library unreadable, moved aside: $e');
        await _file.rename('${_file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      }
    }
    if (j != null) {
      lists = [for (final l in j['lists'] ?? []) RevueList.fromJson(l)];
      items = [for (final i in j['items'] ?? []) Item.fromJson(i)];
      appearance = (j['settings'] as Map?)?['appearance'] ?? 'system';
    } else {
      lists = [
        RevueList(name: 'Watch later', emoji: '🎬'),
        RevueList(name: 'To read', emoji: '📚'),
        RevueList(name: 'Places', emoji: '📍'),
      ];
      await save();
    }
    notifyListeners();
  }

  Future<void> _saving = Future.value();

  /// Saves are queued (background fetches save concurrently) and atomic: temp file + rename,
  /// so a crash mid-write never corrupts the library.
  Future<void> save() {
    _saving = _saving.then((_) async {
      try {
        final tmp = File('${_file.path}.tmp');
        await tmp.writeAsString(jsonEncode({
          'lists': [for (final l in lists) l.toJson()],
          'items': [for (final i in items) i.toJson()],
          'settings': {'appearance': appearance},
        }));
        await tmp.rename(_file.path);
      } catch (e) {
        debugPrint('save failed: $e'); // keep the queue alive; next save retries with full state
      }
    });
    return _saving;
  }

  Future<void> _commit() async {
    notifyListeners();
    await save();
  }

  // MARK: adding

  /// Text from a share sheet / paste: a URL becomes a link card, anything else a note.
  Future<Item> addText(String text, {String? listId}) {
    final url = LinkFetcher.firstUrl(text);
    if (url != null) return addLink(url, listId: listId);
    return addNote(text, listId: listId);
  }

  Future<Item> addNote(String text, {String? listId}) async {
    final firstLine = text.trim().split('\n').first;
    final item = Item(
      title: firstLine.length > 80 ? '${firstLine.substring(0, 80)}…' : firstLine,
      text: text.trim(),
      kind: Kind.note,
      listId: listId,
    );
    items.insert(0, item);
    await _commit();
    await _enrich(item, text);
    return item;
  }

  Future<Item> addLink(Uri url, {String? listId}) async {
    final existing = items.where((i) => i.url == url.toString()).firstOrNull;
    if (existing != null) return existing;
    final item = Item(title: url.host.replaceFirst('www.', ''), url: url.toString(), kind: Kind.guess(url), listId: listId);
    items.insert(0, item);
    processing.add(item.id);
    await _commit();
    try {
      final meta = await fetcher.fetch(url);
      if (meta.title.isNotEmpty) item.title = meta.title;
      item.summary = meta.summary;
      item.source = meta.source;
      if (meta.imageUrl != null) {
        final bytes = await fetcher.downloadImage(meta.imageUrl!);
        if (bytes != null) item.thumbnail = await _writeThumb(item.id, bytes);
      }
      await _commit();
      await _enrich(item, '${item.title}\n${item.source}\n${item.summary}\n$url', keepTitle: true);
    } catch (e) {
      debugPrint('fetch failed for $url: $e');
    } finally {
      processing.remove(item.id);
      await _commit();
    }
    return item;
  }

  /// Copies the image in, reads its text on-device, and lets the local model title and tag it.
  Future<Item> addScreenshot(String path, {String? listId}) async {
    final item = Item(title: 'Screenshot', kind: Kind.image, listId: listId);
    item.thumbnail = await _writeThumb(item.id, await File(path).readAsBytes());
    items.insert(0, item);
    processing.add(item.id);
    await _commit();
    try {
      item.text = (await ocr(thumbFile(item)!.path)).trim();
      final firstLine = item.text.split('\n').map((l) => l.trim()).firstWhere((l) => l.length > 3, orElse: () => '');
      if (firstLine.isNotEmpty) item.title = firstLine.length > 60 ? '${firstLine.substring(0, 60)}…' : firstLine;
      item.url = LinkFetcher.firstUrl(item.text)?.toString();
      await _commit();
      await _enrich(item, item.text);
    } finally {
      processing.remove(item.id);
      await _commit();
    }
    return item;
  }

  Future<void> _enrich(Item item, String content, {bool keepTitle = false}) async {
    final a = await Brain.analyze(llm?.call(), content);
    if (a == null) return;
    if (!keepTitle && a.title.isNotEmpty) item.title = a.title;
    if (item.summary.isEmpty) item.summary = a.summary;
    if (a.tags.isNotEmpty) item.tags = a.tags;
    // Only refine generic kinds; a YouTube URL stays a video whatever the model says.
    if (a.kind != null && (item.kind == Kind.link || item.kind == Kind.note)) item.kind = a.kind!;
    await _commit();
  }

  Future<String> _writeThumb(String id, List<int> bytes) async {
    final name = '$id.img';
    await File('${thumbsDir.path}/$name').writeAsBytes(bytes);
    return name;
  }

  // MARK: editing

  Future<void> update(Item item) => _commit();

  Future<void> setAppearance(String value) {
    appearance = value;
    return _commit();
  }

  Future<void> delete(Item item) async {
    items.removeWhere((i) => i.id == item.id);
    final f = thumbFile(item);
    if (f != null && await f.exists()) await f.delete();
    await _commit();
  }

  Future<RevueList> addList(String name, String emoji) async {
    final l = RevueList(name: name, emoji: emoji.isEmpty ? '📌' : emoji);
    lists.add(l);
    await _commit();
    return l;
  }

  Future<void> deleteList(RevueList list) async {
    lists.removeWhere((l) => l.id == list.id);
    for (final i in items.where((i) => i.listId == list.id)) {
      i.listId = null; // items survive, they just leave the list
    }
    await _commit();
  }
}
