import 'dart:convert';

import 'package:http/http.dart' as http;

class ProgressInfo {
  ProgressInfo({required this.title, this.pages, this.seasons = const [], this.source = ''});
  final String title; // matched title from the database
  final int? pages; // books
  final List<int> seasons; // series: episodes per season, index 0 = season 1
  final String source; // 'Open Library' or 'TVmaze'
  int? get episodes => seasons.isEmpty ? null : seasons.reduce((a, b) => a + b);
}

/// Looks up the real size of a saved item: page count for books (Open Library),
/// episodes per season for series (TVmaze). Never throws; null when nothing matches.
class ProgressFinder {
  ProgressFinder([http.Client? client]) : client = client ?? http.Client();
  final http.Client client;

  static const _headers = {'User-Agent': 'Revue/0.1 (personal library app)'};

  /// [ask] is an optional on-device LLM used only to extract the clean title; null = heuristics only.
  Future<ProgressInfo?> find(String rawTitle,
      {required bool series, Future<String> Function(String prompt)? ask}) async {
    final query = await _title(rawTitle, series, ask);
    if (query.isEmpty) return null;
    try {
      return series ? await _series(query) : await _book(query);
    } catch (_) {
      return null;
    }
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
