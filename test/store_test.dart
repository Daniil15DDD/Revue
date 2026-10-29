import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revue/ai.dart';
import 'package:revue/link_fetcher.dart';
import 'package:revue/models.dart';
import 'package:revue/progress_finder.dart';
import 'package:revue/store.dart';

final _png = List<int>.filled(500, 7); // fake image bytes (>100 so they count as a download)

http.Client _fakeWeb() => MockClient((req) async {
      final u = req.url;
      if (u.path == '/oembed') {
        return http.Response(jsonEncode({'title': 'Never Gonna Give You Up', 'author_name': 'Rick Astley'}), 200);
      }
      if (u.host == 'i.ytimg.com' || u.path.endsWith('.jpg')) return http.Response.bytes(_png, 200);
      if (u.host == 'openlibrary.org') {
        return http.Response(jsonEncode({'docs': [{'title': 'Project Hail Mary', 'number_of_pages_median': 496}]}), 200);
      }
      if (u.host == 'api.tvmaze.com') {
        return http.Response(jsonEncode({'name': 'Breaking Bad', '_embedded': {'episodes': [
          for (var e = 1; e <= 7; e++) {'season': 1, 'number': e},
          for (var e = 1; e <= 13; e++) {'season': 2, 'number': e},
        ]}}), 200);
      }
      if (u.host == 'www.tvmaze.com') {
        return http.Response('<meta property="og:title" content="Breaking Bad">', 200);
      }
      if (u.host == 'blog.example') {
        return http.Response('<meta property="og:title" content="Why sleep matters">'
            '<meta property="og:image" content="/cover.jpg">', 200);
      }
      return http.Response('nope', 404);
    });

class _FakeLlm implements Llm {
  @override
  Future<String> generate(String system, String prompt) async =>
      'TITLE: Receipt from cafe\nKIND: note\nSUMMARY: A coffee receipt.\nTAGS: coffee, receipt';
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('revue_test'));
  tearDown(() => dir.delete(recursive: true));

  Store make({Llm? llm}) => Store(dir,
      fetcher: LinkFetcher(_fakeWeb()), finder: ProgressFinder(_fakeWeb()), llm: () => llm, ocr: (_) async => 'CAFE LUNA\nFlat white 4.50\nhttps://cafeluna.example');

  test('a new library starts empty; folders and lists persist with colour and folder', () async {
    final s = make();
    await s.load();
    expect(s.lists, isEmpty);
    expect(s.folders, isEmpty);
    final f = await s.addFolder('Entertainment');
    final l = await s.addList('Anime', color: listPalette[4], folderId: f.id);
    final again = make();
    await again.load();
    expect(again.folders.single.name, 'Entertainment');
    expect((again.lists.single.name, again.lists.single.folderId, again.lists.single.color), ('Anime', f.id, listPalette[4]));
    await again.deleteFolder(again.folders.single);
    expect(again.lists.single.folderId, isNull); // lists survive their folder
    expect(l.name, 'Anime');
  });

  test('erase all deletes items, lists, folders and thumbnails, and stays erased', () async {
    final s = make();
    await s.load();
    await s.addFolder('Watching');
    await s.addList('Anime');
    await s.addText('https://youtu.be/dQw4w9WgXcQ'); // downloads a thumbnail
    expect(s.thumbsDir.listSync(), isNotEmpty);
    await s.eraseAll();
    expect((s.items.length, s.lists.length, s.folders.length, s.thumbsDir.listSync().length), (0, 0, 0, 0));
    final again = make();
    await again.load();
    expect((again.items.length, again.lists.length, again.folders.length), (0, 0, 0));
  });

  test('YouTube share text becomes a video with title, channel and thumbnail', () async {
    final s = make();
    await s.load();
    final item = await s.addText('Check this out https://youtu.be/dQw4w9WgXcQ?si=xyz');
    expect(item.kind, Kind.video);
    expect(item.title, 'Never Gonna Give You Up');
    expect(item.source, 'YouTube · Rick Astley');
    expect(await s.thumbFile(item)!.readAsBytes(), _png);
    expect(s.processing, isEmpty);

    // Sharing the same link twice doesn't duplicate it.
    await s.addText('https://youtu.be/dQw4w9WgXcQ?si=xyz');
    expect(s.items.length, 1);
  });

  test('generic page uses og tags; failures keep the item', () async {
    final s = make();
    await s.load();
    final ok = await s.addLink(Uri.parse('https://blog.example/post'));
    expect(ok.title, 'Why sleep matters');
    expect(ok.thumbnail, isNotNull);
    final bad = await s.addLink(Uri.parse('https://down.example/x'));
    expect(bad.title, 'down.example');
    expect(s.items.length, 2);
  });

  test('screenshot: OCR text, link detection and local-AI tags', () async {
    final s = make(llm: _FakeLlm());
    await s.load();
    final img = File('${dir.path}/shot.png')..writeAsBytesSync(_png);
    final item = await s.addScreenshot(img.path);
    expect(item.kind, Kind.image); // AI may not turn a screenshot into another kind
    expect(item.text, contains('Flat white'));
    expect(item.url, 'https://cafeluna.example');
    expect(item.title, 'Receipt from cafe');
    expect(item.tags, ['coffee', 'receipt']);
  });

  test('screenshot without a model is titled from its text', () async {
    final s = make();
    await s.load();
    final img = File('${dir.path}/shot.png')..writeAsBytesSync(_png);
    final item = await s.addScreenshot(img.path);
    expect(item.title, 'CAFE LUNA');
  });

  test('everything survives a reload; deleting a list keeps its items', () async {
    final s = make();
    await s.load();
    final list = await s.addList('Recipes');
    final note = await s.addNote('Grandma\'s pasta\nboil water', listId: list.id);
    note.rating = 5;
    await s.update(note);

    final again = make();
    await again.load();
    final back = again.items.single;
    expect(back.title, 'Grandma\'s pasta');
    expect(back.rating, 5);
    expect(back.listId, list.id);

    await again.deleteList(again.lists.firstWhere((l) => l.name == 'Recipes'));
    expect(again.items.single.listId, isNull);
  });

  test('appearance setting survives a reload', () async {
    final s = make();
    await s.load();
    await s.setAppearance('dark');
    final again = make();
    await again.load();
    expect(again.appearance, 'dark');
  });

  test('finds total pages for books and episodes per season for series', () async {
    final s = make();
    await s.load();
    final book = Item(title: 'Project Hail Mary by Andy Weir | Goodreads', kind: Kind.book);
    final show = Item(title: 'Breaking Bad (TV Series 2008–2013) - IMDb', kind: Kind.show);
    s.items.addAll([book, show]);
    expect(await s.findProgress(book), isTrue);
    expect(book.total, 496);
    expect(await s.findProgress(show), isTrue);
    expect(show.seasons, [7, 13]);
    expect(show.total, 20);
    expect(await s.findProgress(Item(title: 'x', kind: Kind.video)), isFalse);
  });

  test('a shared series link gets its seasons looked up even without an AI model', () async {
    final s = make();
    await s.load();
    final item = await s.addText('https://www.tvmaze.com/shows/169/breaking-bad');
    expect(item.kind, Kind.show);
    expect(item.seasons, [7, 13]);
    expect(item.total, 20);
  });

  test('screenshot titles skip status bars and back buttons', () {
    expect(screenshotTitle('9:41\n< Notes\nBooks to read this winter\n1. Dune'), 'Books to read this winter');
    expect(screenshotTitle('9:41\n< Messages\nRamen spots to try in Tokyo'), 'Ramen spots to try in Tokyo');
    expect(screenshotTitle('CAFE LUNA\nFlat white 4.50'), 'CAFE LUNA'); // falls back to the first line
    expect(screenshotTitle(''), '');
  });

  test('manual add: series with total, book finished, cover copied', () async {
    final s = make();
    await s.load();
    final l = await s.addList('Anime');
    final show = await s.addManual('  Rare OVA  ', kind: Kind.show, total: 6, listId: l.id);
    expect((show.title, show.total, show.status, show.listId), ('Rare OVA', 6, Status.planned, l.id));
    expect(show.seasons, [6]);
    final img = File('${dir.path}/c.png')..writeAsBytesSync(_png);
    final book = await s.addManual('Zine', kind: Kind.book, total: 40, status: Status.finished, imagePath: img.path);
    expect((book.progress, book.thumbnail != null), (40, true));
    expect(book.seasons, isEmpty);
    expect(s.items.first, book);
  });

  test('lists can be renamed, recoloured, and counted per period', () async {
    final s = make();
    await s.load();
    final l = await s.addList('Anime');
    await s.editList(l, name: 'Anime 2026', color: listPalette[4]);
    expect((l.name, l.color), ('Anime 2026', listPalette[4]));
    s.items.addAll([
      Item(title: 'new', kind: Kind.show, listId: l.id),
      Item(title: 'old', kind: Kind.show, listId: l.id, created: DateTime(2020)),
    ]);
    expect(s.count(Period.all, listId: l.id), 2);
    expect(s.count(Period.week, listId: l.id), 1);
    expect(s.count(Period.year), 1);
  });

  test('a corrupt library file is kept aside and the app still starts', () async {
    File('${dir.path}/revue.json').writeAsStringSync('{"items": [tru');
    final s = make();
    await s.load();
    expect(s.items, isEmpty);
    expect(dir.listSync().map((f) => f.path).any((p) => p.contains('revue.json.corrupt-')), isTrue);
  });

  test('delete removes the item and its thumbnail', () async {
    final s = make();
    await s.load();
    final item = await s.addText('https://youtu.be/dQw4w9WgXcQ');
    final thumb = s.thumbFile(item)!;
    expect(thumb.existsSync(), isTrue);
    await s.delete(item);
    expect(s.items, isEmpty);
    expect(thumb.existsSync(), isFalse);
  });
}
