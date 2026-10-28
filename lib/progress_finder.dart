import 'dart:convert';

import 'package:http/http.dart' as http;

class ProgressInfo {
  ProgressInfo({required this.title, this.pages, this.seasons = const [], this.source = ''});
  final String title; // matched title from the database
  final int? pages; // books
  final List<int> seasons; // series: episodes per season, index 0 = season 1
  final String source; // 'Open Library', 'TVmaze' or 'AniList'
  int? get episodes => seasons.isEmpty ? null : seasons.reduce((a, b) => a + b);
}

/// Looks up the real size of a saved item: page count for books (Open Library),
/// episodes per season for series (TVmaze, or AniList for anime). Never throws; null when nothing matches.
class ProgressFinder {
  ProgressFinder([http.Client? client]) : client = client ?? http.Client();
  final http.Client client;

  static const _headers = {'User-Agent': 'Revue/0.1 (personal library app)'};

  /// [ask] is an optional on-device LLM used only to extract the clean title; null = heuristics only.
  /// [url] adds a second search term from the link itself ("…/86-eighty-six/…" → "86 eighty six"),
  /// which rescues titles in other languages. [anime] tries AniList before TVmaze.
  Future<ProgressInfo?> find(String rawTitle,
      {required bool series, Future<String> Function(String prompt)? ask, Uri? url, bool anime = false}) async {
    final queries = {await _title(rawTitle, series, ask), if (url != null) slugQuery(url)}..remove('');
    final lookups = !series
        ? [_book]
        : anime
            ? [_anime, _series]
            : [_series, _anime];
    for (final query in queries) {
      for (final lookup in lookups) {
        try {
          final info = await lookup(query);
          if (info != null) return info;
        } catch (_) {/* try the next source */}
      }
    }
    return null;
  }

  static const _slugNoise = {'anime', 'release', 'releases', 'episodes', 'episode', 'watch', 'title', 'titles',
    'series', 'show', 'shows', 'tv', 'season', 'online', 'video', 'book', 'books', 'en', 'ru'};

  /// The most title-like path segment of a link: "/anime/releases/release/86-eighty-six/episodes" → "86 eighty six".
  static String slugQuery(Uri url) {
    String words(String seg) => seg.replaceAll(RegExp(r'\.(html?|php)$'), '').replaceAll(RegExp(r'[-_+]+'), ' ').trim();
    final candidates = url.pathSegments
        .map(words)
        .where((w) => RegExp(r'[a-zA-Z]{3,}').hasMatch(w) && !_slugNoise.contains(w.toLowerCase()))
        .toList();
    if (candidates.isEmpty) return '';
    return candidates.reduce((a, b) => b.split(' ').length > a.split(' ').length ? b : a);
  }

  Future<String> _title(String raw, bool series, Future<String> Function(String prompt)? ask) async {
    if (ask != null) {
      try {
        final answer = await ask('Reply with ONLY the ${series ? 'TV series' : 'book'} name in this title, '
            'without author, year or website: "$raw"');
        final line = answer.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
        final name = line.replaceAll(RegExp(r'''^["'“”‘’«»]+|["'“”‘’«»]+$'''), '').trim();
        if (name.isNotEmpty && name.length <= 80) return name;
      } catch (_) {/* fall back to heuristics */}
    }
    return cleanTitle(raw);
  }

  // shortcut: first doc with a page count wins, may pick the wrong edition or book; add a picker if users complain.
  Future<ProgressInfo?> _book(String query) async {
    final r = await client
        .get(
            Uri.https('openlibrary.org', '/search.json', {
              'q': query,
              'fields': 'title,author_name,number_of_pages_median,first_publish_year',
              'limit': '5',
            }),
            headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final docs = (jsonDecode(r.body) as Map<String, dynamic>)['docs'] as List? ?? const [];
    for (final d in docs.cast<Map<String, dynamic>>()) {
      final pages = d['number_of_pages_median'];
      if (pages is int && pages > 0) {
        return ProgressInfo(title: d['title'] as String? ?? query, pages: pages, source: 'Open Library');
      }
    }
    return null;
  }

  Future<ProgressInfo?> _series(String query) async {
    final r = await client
        .get(Uri.https('api.tvmaze.com', '/singlesearch/shows', {'q': query, 'embed': 'episodes'}), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final show = jsonDecode(r.body) as Map<String, dynamic>;
    final episodes = (show['_embedded'] as Map<String, dynamic>?)?['episodes'] as List? ?? const [];
    final perSeason = <int, int>{};
    for (final e in episodes.cast<Map<String, dynamic>>()) {
      final season = e['season'];
      if (season is int && season >= 1 && e['number'] != null) perSeason[season] = (perSeason[season] ?? 0) + 1;
    }
    if (perSeason.isEmpty) return null;
    final seasons = (perSeason.keys.toList()..sort()).map((s) => perSeason[s]!).toList();
    return ProgressInfo(title: show['name'] as String? ?? query, seasons: seasons, source: 'TVmaze');
  }

  static const _media = 'id episodes format title { romaji english } '
      'relations { edges { relationType node { id type format } } }';

  // shortcut: follows up to 6 TV sequels as "seasons"; spin-offs and movies are ignored.
  Future<ProgressInfo?> _anime(String query) async {
    Future<Map<String, dynamic>?> media(String args, Map<String, dynamic> vars) async {
      final r = await client
          .post(Uri.https('graphql.anilist.co', '/'),
              headers: {..._headers, 'Content-Type': 'application/json', 'Accept': 'application/json'},
              // Declare only the variable used: GraphQL rejects unused ones.
              body: jsonEncode({
                'query': 'query(${vars.containsKey('s') ? '\$s: String' : '\$id: Int'}) { Media($args) { $_media } }',
                'variables': vars,
              }))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      return ((jsonDecode(r.body) as Map<String, dynamic>)['data'] as Map<String, dynamic>?)?['Media']
          as Map<String, dynamic>?;
    }

    // Prefer the main TV series over OVAs/specials; links often spell numbers ("steins-gate-zero" → "0").
    Map<String, dynamic>? m;
    for (final q in {query, query.replaceAll(RegExp(r'\bzero\b', caseSensitive: false), '0')}) {
      final hit = await media('search: \$s, type: ANIME', {'s': q});
      if (hit != null && const ['TV', 'TV_SHORT', 'ONA'].contains(hit['format'])) {
        m = hit;
        break;
      }
      m ??= hit;
    }
    if (m == null) return null;
    final title = (m['title'] as Map?)?['english'] ?? (m['title'] as Map?)?['romaji'] ?? query;
    final seasons = <int>[];
    final seen = <int>{};
    for (var hop = 0; m != null && hop < 7 && seen.add(m['id'] as int); hop++) {
      final eps = m['episodes'];
      if (eps is! int || eps <= 0) break; // still airing or unknown: stop here
      seasons.add(eps);
      final edges = ((m['relations'] as Map?)?['edges'] as List? ?? const []).cast<Map<String, dynamic>>();
      final sequel = edges
          .where((e) => e['relationType'] == 'SEQUEL')
          .map((e) => e['node'] as Map<String, dynamic>)
          .where((n) => n['type'] == 'ANIME' && const ['TV', 'TV_SHORT', 'ONA'].contains(n['format']))
          .firstOrNull;
      m = sequel == null ? null : await media('id: \$id', {'id': sequel['id']});
    }
    if (seasons.isEmpty) return null;
    return ProgressInfo(title: title as String, seasons: seasons, source: 'AniList');
  }

  /// Strips site names and decorations from a page title, e.g.
  /// "Project Hail Mary by Andy Weir | Goodreads" → "Project Hail Mary". Plain titles pass through.
  static String cleanTitle(String raw) {
    var s = raw.trim().replaceFirst(RegExp(r'^(Amazon\.com\s*:\s*|Watch\s+)', caseSensitive: false), '');
    final site = RegExp(
        r'\s*[|\-–—:]\s*(Goodreads|Wikipedia|IMDb|Netflix[^|]*|Prime Video|Amazon[^|]*|Books|Apple TV\+?)\s*$',
        caseSensitive: false);
    for (var prev = ''; prev != s;) {
      prev = s;
      s = s.replaceFirst(site, '');
    }
    s = s.replaceAll(
        RegExp(r'\s*\((TV (Mini[ -])?Series|Mini[ -]?Series|novel|book|TV series)[^)]*\)', caseSensitive: false), '');
    final by = s.indexOf(' by ');
    if (by > 0 && s.substring(0, by).trim().split(RegExp(r'\s+')).length >= 2) s = s.substring(0, by);
    s = s.replaceAll(RegExp(r'\[[^\]]*\]'), '').replaceAll(RegExp(r'''^["'“”‘’«»]+|["'“”‘’«»]+$'''), '');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
