import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revue/progress_finder.dart';

void main() {
  group('cleanTitle', () {
    const cases = {
      'Project Hail Mary by Andy Weir | Goodreads': 'Project Hail Mary',
      'Breaking Bad (TV Series 2008–2013) - IMDb': 'Breaking Bad',
      'Watch Stranger Things | Netflix Official Site': 'Stranger Things',
      'Dune (novel) - Wikipedia': 'Dune',
      'The Bear': 'The Bear',
      'Stand by Me': 'Stand by Me',
      'Amazon.com: Project Hail Mary: Books': 'Project Hail Mary',
      'Chernobyl (TV Mini Series 2019) | Prime Video': 'Chernobyl',
      '"Severance"  ': 'Severance',
    };
    cases.forEach((raw, want) => test(raw, () => expect(ProgressFinder.cleanTitle(raw), want)));
  });

  MockClient json(Object body, {List<Uri>? seen, int status = 200}) => MockClient((req) async {
        seen?.add(req.url);
        return http.Response(jsonEncode(body), status);
      });

  test('book: skips docs without pages, sends User-Agent', () async {
    String? ua;
    final client = MockClient((req) async {
      ua = req.headers['User-Agent'];
      expect(req.url.host, 'openlibrary.org');
      expect(req.url.queryParameters['q'], 'Project Hail Mary');
      return http.Response(
          jsonEncode({
            'docs': [
              {'title': 'Project Hail Mary (summary)'},
              {'title': 'Project Hail Mary', 'author_name': ['Andy Weir'], 'number_of_pages_median': 496},
            ]
          }),
          200);
    });
    final info = await ProgressFinder(client).find('Project Hail Mary by Andy Weir | Goodreads', series: false);
    expect(info!.pages, 496);
    expect(info.title, 'Project Hail Mary');
    expect(info.source, 'Open Library');
    expect(info.episodes, isNull);
    expect(ua, contains('Revue'));
  });

  test('series: counts per season, ignores season 0 and null numbers', () async {
    final seen = <Uri>[];
    final client = json({
      'name': 'Breaking Bad',
      '_embedded': {
        'episodes': [
          {'season': 0, 'number': 1},
          {'season': 1, 'number': 1},
          {'season': 1, 'number': 2},
          {'season': 1, 'number': null},
          {'season': 2, 'number': 1},
        ]
      }
    }, seen: seen);
    final info = await ProgressFinder(client).find('Breaking Bad (TV Series 2008–2013) - IMDb', series: true);
    expect(info!.seasons, [2, 1]);
    expect(info.episodes, 3);
    expect(info.source, 'TVmaze');
    expect(seen.single.queryParameters, {'q': 'Breaking Bad', 'embed': 'episodes'});
  });

  test('404, garbage, no pages and network errors return null', () async {
    expect(await ProgressFinder(json({}, status: 404)).find('Nope', series: true), isNull);
    expect(await ProgressFinder(MockClient((_) async => http.Response('<html>', 200))).find('X', series: false), isNull);
    expect(
        await ProgressFinder(json({
          'docs': [
            {'title': 'X'}
          ]
        })).find('X', series: false),
        isNull);
    expect(await ProgressFinder(MockClient((_) => throw Exception('offline'))).find('X', series: true), isNull);
  });

  group('ask', () {
    final book = {
      'docs': [
        {'title': 'Dune', 'number_of_pages_median': 604}
      ]
    };

    test('uses the LLM answer when sane', () async {
      final seen = <Uri>[];
      String? prompt;
      await ProgressFinder(json(book, seen: seen)).find('weird page title', series: false, ask: (p) async {
        prompt = p;
        return '\n  "Dune"\nextra chatter';
      });
      expect(prompt, contains('weird page title'));
      expect(seen.single.queryParameters['q'], 'Dune');
    });

    for (final entry in {
      'empty': () async => '   ',
      'too long': () async => 'x' * 81,
      'throws': () async => throw Exception('model unavailable'),
    }.entries) {
      test('falls back to cleanTitle when ${entry.key}', () async {
        final seen = <Uri>[];
        await ProgressFinder(json(book, seen: seen))
            .find('Dune (novel) - Wikipedia', series: false, ask: (_) => entry.value());
        expect(seen.single.queryParameters['q'], 'Dune');
      });
    }
  });

  group('anime', () {
    test('slugQuery takes the title-like part of a link', () {
      expect(ProgressFinder.slugQuery(Uri.parse('https://aniliberty.top/anime/releases/release/86-eighty-six/episodes')),
          '86 eighty six');
      expect(ProgressFinder.slugQuery(Uri.parse('https://www.tvmaze.com/shows/44933/severance')), 'severance');
      expect(ProgressFinder.slugQuery(Uri.parse('https://example.com/')), '');
    });

    test('AniList: follows TV sequels as seasons; foreign title falls back to the link slug', () async {
      final queries = <String>[];
      final client = MockClient((req) async {
        if (req.url.host == 'api.tvmaze.com') return http.Response('null', 404);
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final vars = body['variables'] as Map<String, dynamic>;
        if (vars['s'] != null) queries.add(vars['s'] as String);
        Map<String, dynamic> media(int id, int eps, int? sequel) => {
              'data': {
                'Media': {
                  'id': id, 'episodes': eps, 'format': 'TV',
                  'title': {'romaji': '86', 'english': '86 EIGHTY-SIX'},
                  'relations': {'edges': [
                    {'relationType': 'PREQUEL', 'node': {'id': 1, 'type': 'ANIME', 'format': 'TV'}},
                    if (sequel != null) {'relationType': 'SEQUEL', 'node': {'id': sequel, 'type': 'ANIME', 'format': 'TV'}},
                    {'relationType': 'ADAPTATION', 'node': {'id': 99, 'type': 'MANGA', 'format': 'MANGA'}},
                  ]},
                }
              }
            };
        if (vars['s'] == '86 eighty six') return http.Response(jsonEncode(media(1, 11, 2)), 200);
        if (vars['id'] == 2) return http.Response(jsonEncode(media(2, 12, null)), 200);
        return http.Response(jsonEncode({'data': {'Media': null}}), 200);
      });
      final info = await ProgressFinder(client).find('86 Восемьдесят-шесть',
          series: true, anime: true, url: Uri.parse('https://aniliberty.top/anime/releases/release/86-eighty-six/episodes'));
      expect(info?.seasons, [11, 12]);
      expect(info?.title, '86 EIGHTY-SIX');
      expect(info?.source, 'AniList');
      expect(queries, ['86 Восемьдесят-шесть', '86 eighty six']); // page title first, then the slug
    });
  });

  group('aniliberty', () {
    http.Response release(Map<String, dynamic> d) => http.Response(jsonEncode(d), 200);
    List<Map<String, int>> eps(int n) => [for (var i = 1; i <= n; i++) {'ordinal': i}];

    test('uses the site\'s own episode list before any database', () async {
      final seen = <Uri>[];
      final client = MockClient((req) async {
        seen.add(req.url);
        return release({'name': {'english': '86 EIGHTY-SIX'}, 'episodes': eps(12), 'episodes_total': 11, 'is_ongoing': false});
      });
      final info = await ProgressFinder(client).find('86 Восемьдесят-шесть',
          series: true, anime: true, url: Uri.parse('https://aniliberty.top/anime/releases/release/86-eighty-six/episodes'));
      expect(info?.episodes, 12);
      expect(info?.ongoing, isFalse);
      expect(info?.source, 'AniLiberty');
      expect(seen.single.path, '/api/v1/anime/releases/86-eighty-six');
    });

    test('airing shows report what is out now and are marked ongoing', () async {
      final client = MockClient((_) async =>
          release({'name': {'english': 'Steel Ball Run'}, 'episodes': eps(6), 'episodes_total': null, 'is_ongoing': true}));
      final info = await ProgressFinder(client).find('JoJo', series: true, anime: true,
          url: Uri.parse('https://aniliberty.top/anime/releases/release/steel-ball-run-jojo-no-kimyou-na-bouken/episodes'));
      expect(info?.episodes, 6);
      expect(info?.ongoing, isTrue);
    });
  });
}
