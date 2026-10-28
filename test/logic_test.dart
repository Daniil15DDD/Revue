import 'package:flutter_test/flutter_test.dart';
import 'package:revue/ai.dart';
import 'package:revue/link_fetcher.dart';
import 'package:revue/models.dart';

void main() {
  group('LinkFetcher', () {
    test('youTubeId handles watch, short links, shorts and embeds', () {
      expect(LinkFetcher.youTubeId(Uri.parse('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42')), 'dQw4w9WgXcQ');
      expect(LinkFetcher.youTubeId(Uri.parse('https://youtu.be/dQw4w9WgXcQ?si=abc')), 'dQw4w9WgXcQ');
      expect(LinkFetcher.youTubeId(Uri.parse('https://m.youtube.com/shorts/abc123')), 'abc123');
      expect(LinkFetcher.youTubeId(Uri.parse('https://www.youtube.com/embed/xyz')), 'xyz');
      expect(LinkFetcher.youTubeId(Uri.parse('https://www.youtube.com/@veritasium')), isNull);
      expect(LinkFetcher.youTubeId(Uri.parse('https://example.com/watch?v=1')), isNull);
    });

    test('parseHtml reads og tags in any attribute order and resolves relative images', () {
      const html = '''
        <html><head><title>Fallback &amp; title</title>
        <meta content="A &quot;great&quot; read" property="og:title">
        <meta name="description" content='Plain description'>
        <meta property="og:image" content="/img/cover.jpg" />
        <meta property="og:site_name" content="The Site">
        </head></html>''';
      final m = LinkFetcher.parseHtml(html, Uri.parse('https://example.com/posts/1'));
      expect(m.title, 'A "great" read');
      expect(m.summary, 'Plain description');
      expect(m.source, 'The Site');
      expect(m.imageUrl.toString(), 'https://example.com/img/cover.jpg');
    });

    test('parseHtml falls back to <title>', () {
      final m = LinkFetcher.parseHtml('<title>Just &lt;this&gt;</title>', Uri.parse('https://a.b'));
      expect(m.title, 'Just <this>');
      expect(m.imageUrl, isNull);
    });

    test("stripSiteSuffix removes only the site's own name", () {
      expect(LinkFetcher.stripSiteSuffix('Severance | TVmaze', 'www.tvmaze.com'), 'Severance');
      expect(LinkFetcher.stripSiteSuffix('Black hole - Wikipedia', 'en.wikipedia.org'), 'Black hole');
      expect(LinkFetcher.stripSiteSuffix('Spider-Man - Into the Spider-Verse', 'www.imdb.com'),
          'Spider-Man - Into the Spider-Verse');
      expect(LinkFetcher.stripSiteSuffix('Plain title', 'example.com'), 'Plain title');
    });

    test('decodeEntities does not double-decode', () {
      expect(LinkFetcher.decodeEntities('&amp;lt;'), '&lt;');
    });

    test('firstUrl pulls the link out of share-sheet text', () {
      expect(LinkFetcher.firstUrl('Watch this! https://youtu.be/abc123.').toString(), 'https://youtu.be/abc123');
      expect(LinkFetcher.firstUrl('(see https://example.com/a?b=c)').toString(), 'https://example.com/a?b=c');
      expect(LinkFetcher.firstUrl('no links here'), isNull);
    });
  });

  test('Kind.guess maps hosts to kinds', () {
    expect(Kind.guess(Uri.parse('https://youtu.be/x')), Kind.video);
    expect(Kind.guess(Uri.parse('https://open.spotify.com/track/1')), Kind.music);
    expect(Kind.guess(Uri.parse('https://www.imdb.com/title/tt1')), Kind.movie);
    expect(Kind.guess(Uri.parse('https://www.google.com/maps/place/x')), Kind.place);
    expect(Kind.guess(Uri.parse('https://www.google.com/search?q=x')), Kind.link);
    expect(Kind.guess(Uri.parse('https://www.amazon.com/dp/1')), Kind.product);
  });

  test('Item JSON round-trips', () {
    final i = Item(title: 'T', url: 'https://x.y', kind: Kind.show, tags: ['a'], rating: 4,
        status: Status.active, progress: 9, total: 20, seasons: [7, 13], listId: 'L');
    final back = Item.fromJson(i.toJson());
    expect(back.toJson(), i.toJson());
  });

  test('old libraries with a done flag migrate to a status', () {
    expect(Item.fromJson({'title': 'a', 'kind': 'book', 'done': true}).status, Status.finished);
    expect(Item.fromJson({'title': 'a', 'kind': 'book'}).status, Status.planned);
    expect(RevueList.fromJson({'id': 'x', 'name': 'Old', 'emoji': '🎬'}).display, '🎬 Old');
  });

  test('status wording fits the kind', () {
    expect(Status.planned.label(Kind.book), 'Plan to read');
    expect(Status.active.label(Kind.show), 'Watching');
    expect(Status.finished.label(Kind.place), 'Visited');
    expect(Status.paused.label(Kind.game), 'On hold');
  });

  test('progress moves the status along and clamps', () {
    final b = Item(title: 'Dune', kind: Kind.book, total: 500);
    b.setProgress(120);
    expect(b.status, Status.active);
    expect(b.progressLabel, 'Page 120 of 500');
    b.setProgress(900);
    expect(b.progress, 500);
    expect(b.status, Status.finished);
    expect(b.finishedAt, isNotNull);
    b.setProgress(-5);
    expect(b.progress, 0);
  });

  test('series progress maps to season and episode', () {
    final s = Item(title: 'Breaking Bad', kind: Kind.show, total: 62, seasons: [7, 13, 13, 13, 16]);
    expect(s.seasonEpisode, isNull);
    s.setProgress(7);
    expect(s.seasonEpisode, (1, 7));
    s.setProgress(8);
    expect(s.seasonEpisode, (2, 1));
    expect(s.progressLabel, 'S2 · E1 · 8 of 62 episodes');
    s.setStatus(Status.finished);
    expect(s.progress, 62);
  });

  group('Brain', () {
    test('parse reads the structured reply, tolerating markdown and junk', () {
      final a = Brain.parse('**TITLE:** "Pasta recipe"\nKIND: Note\nSUMMARY: <How to cook pasta.>\n'
          'TAGS: Food, #Cooking , italian,\nextra line');
      expect(a.title, 'Pasta recipe');
      expect(a.kind, Kind.note);
      expect(a.summary, 'How to cook pasta.');
      expect(a.tags, ['food', 'cooking', 'italian']);
    });

    test('parse ignores unknown kinds', () {
      expect(Brain.parse('KIND: podcast').kind, isNull);
    });

    test('relevant ranks keyword matches first, then newest', () {
      final old = Item(title: 'Old thing', kind: Kind.link, created: DateTime(2020));
      final cat = Item(title: 'Funny cat video', kind: Kind.video, created: DateTime(2021));
      final newest = Item(title: 'Newest', kind: Kind.note, created: DateTime(2026));
      final r = Brain.relevant([old, cat, newest], 'show me the cat video', limit: 3);
      expect(r.map((i) => i.title), ['Funny cat video', 'Newest', 'Old thing']);
    });

    test('answer without a model falls back to search results', () async {
      final items = [Item(title: 'Ramen spot in Tokyo', kind: Kind.place)];
      final a = await Brain.answer(null, 'ramen?', items, [], []);
      expect(a, contains('Ramen spot in Tokyo'));
      expect(await Brain.answer(null, 'pizza?', items, [], []), contains('Nothing in your library matches'));
      expect(await Brain.answer(null, 'x', [], [], []), contains('empty'));
    });

    test('answer sends library context and history to the model', () async {
      final llm = _FakeLlm('Try "Ramen spot".');
      final list = RevueList(name: 'Food');
      final items = [Item(title: 'Ramen spot', kind: Kind.place, listId: list.id, rating: 5)];
      final a = await Brain.answer(llm, 'where to eat?', items, [list], [('hi', 'hello')]);
      expect(a, 'Try "Ramen spot".');
      expect(llm.lastPrompt, contains('Ramen spot'));
      expect(llm.lastPrompt, contains('list: Food'));
      expect(llm.lastPrompt, contains('rated 5/5'));
      expect(llm.lastPrompt, contains('User: hi'));
    });
  });
}

class _FakeLlm implements Llm {
  _FakeLlm(this.reply);
  final String reply;
  String lastPrompt = '';
  @override
  Future<String> generate(String system, String prompt) async {
    lastPrompt = prompt;
    return reply;
  }
}
