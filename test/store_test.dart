import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revue/ai.dart';
import 'package:revue/link_fetcher.dart';
import 'package:revue/models.dart';
import 'package:revue/store.dart';

final _png = List<int>.filled(500, 7); // fake image bytes (>100 so they count as a download)

http.Client _fakeWeb() => MockClient((req) async {
      final u = req.url;
      if (u.path == '/oembed') {
        return http.Response(jsonEncode({'title': 'Never Gonna Give You Up', 'author_name': 'Rick Astley'}), 200);
      }
      if (u.host == 'i.ytimg.com' || u.path.endsWith('.jpg')) return http.Response.bytes(_png, 200);
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
      fetcher: LinkFetcher(_fakeWeb()), llm: () => llm, ocr: (_) async => 'CAFE LUNA\nFlat white 4.50\nhttps://cafeluna.example');

  test('first load creates starter lists and persists them', () async {
    final s = make();
    await s.load();
    expect(s.lists.map((l) => l.name), contains('Watch later'));
    final again = make();
    await again.load();
    expect(again.lists.length, s.lists.length);
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
    final list = await s.addList('Recipes', '🍝');
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

  test('a corrupt library file is kept aside and the app still starts', () async {
    File('${dir.path}/revue.json').writeAsStringSync('{"items": [tru');
    final s = make();
    await s.load();
    expect(s.items, isEmpty);
    expect(s.lists, isNotEmpty);
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
