import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ai.dart';
import 'link_fetcher.dart';
import 'models.dart';
import 'progress_finder.dart';

/// The whole library: one JSON file plus a folder of thumbnails, all on the device.
class Store extends ChangeNotifier {
  Store(this.dir, {LinkFetcher? fetcher, ProgressFinder? finder, this.llm, Future<String> Function(String path)? ocr})
      : fetcher = fetcher ?? LinkFetcher(),
        finder = finder ?? ProgressFinder(),
        ocr = ocr ?? Ocr.read;

  final Directory dir;
  final LinkFetcher fetcher;
  final ProgressFinder finder;
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
        RevueList(name: 'Movies & TV', color: listPalette[0]),
        RevueList(name: 'Books', color: listPalette[3]),
        RevueList(name: 'Places', color: listPalette[1]),
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
      final firstLine = screenshotTitle(item.text);
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
    if (a != null) {
      if (!keepTitle && a.title.isNotEmpty) item.title = a.title;
      if (item.summary.isEmpty) item.summary = a.summary;
      if (a.tags.isNotEmpty) item.tags = a.tags;
      // Only refine generic kinds; a YouTube URL stays a video whatever the model says.
      if (a.kind != null && (item.kind == Kind.link || item.kind == Kind.note)) item.kind = a.kind!;
      await _commit();
    }
    // Runs with or without the model: the lookup itself is Open Library / TVmaze.
    if (item.kind.progressUnit != null && item.total == null) await findProgress(item);
  }

  /// Looks up total pages (books) or episodes per season (series). The on-device model, when
  /// downloaded, first turns a messy page title into the plain book/series name.
  Future<bool> findProgress(Item item) async {
    if (item.kind.progressUnit == null) return false;
    final model = llm?.call();
    processing.add(item.id);
    notifyListeners();
    try {
      final info = await finder.find(item.title,
          series: item.kind == Kind.show,
          ask: model == null ? null : (prompt) => model.generate('You extract names. Reply with the name only.', prompt));
      if (info == null) return false;
      item.seasons = info.seasons;
      item.total = info.pages ?? info.episodes;
      if (item.total != null && item.progress > item.total!) item.progress = item.total!;
      return item.total != null;
    } finally {
      processing.remove(item.id);
      await _commit();
    }
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

  Future<RevueList> addList(String name, {int? color}) async {
    final l = RevueList(name: name, color: color);
    lists.add(l);
    await _commit();
    return l;
  }

  Future<void> editList(RevueList list, {String? name, int? color}) {
    if (name != null && name.trim().isNotEmpty) list.name = name.trim();
    if (color != null) list.color = color;
    return _commit();
  }

  Future<void> setStatus(Item item, Status s) {
    item.setStatus(s);
    return _commit();
  }

  Future<void> setProgress(Item item, int value) {
    item.setProgress(value);
    return _commit();
  }

  /// Items saved in [period], optionally only one list — the numbers on the Stats card.
  int count(Period period, {String? listId}) {
    final from = period.start(DateTime.now());
    return items.where((i) => (listId == null || i.listId == listId) && (from == null || !i.created.isBefore(from))).length;
  }

  Future<void> deleteList(RevueList list) async {
    lists.removeWhere((l) => l.id == list.id);
    for (final i in items.where((i) => i.listId == list.id)) {
      i.listId = null; // items survive, they just leave the list
    }
    await _commit();
  }
}

/// Title for a screenshot from its OCR text: the first line that reads like a heading,
/// skipping status-bar clocks ("9:41"), back buttons ("< Notes") and other short chrome.
String screenshotTitle(String text) {
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final letter = RegExp(r'[A-Za-z\u00C0-\uFFFF]');
  bool heading(String l) =>
      letter.allMatches(l).length >= 8 &&
      l.split(RegExp(r'\s+')).where((w) => letter.allMatches(w).length >= 2).length >= 2; // "< Messages" is one word
  return lines.firstWhere(heading, orElse: () => lines.firstOrNull ?? '');
}

enum Period {
  week('This week'),
  month('This month'),
  year('This year'),
  all('All time');

  const Period(this.label);
  final String label;

  DateTime? start(DateTime now) => switch (this) {
        week => DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1)),
        month => DateTime(now.year, now.month),
        year => DateTime(now.year),
        all => null,
      };
}
