import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

enum CatalogKind {
  series('Series'),
  anime('Anime'),
  books('Books');

  const CatalogKind(this.label);
  final String label;
}

class CatalogResult {
  CatalogResult({
    required this.title,
    required this.kind,
    this.subtitle = '',
    this.imageUrl,
    this.url,
    this.pages,
    this.episodes,
    this.tvmazeId,
  });
  final String title;
  final Kind kind; // book or show
  final String subtitle; // "2022 · Hulu", "Frank Herbert · 1965"
  final Uri? imageUrl;
  final String? url;
  final int? pages;
  final int? episodes; // AniList gives it up front; TVmaze needs [Catalog.seasons]
  final int? tvmazeId;
}

/// Searches public databases (no keys): TVmaze for TV, AniList for anime, Open Library for books.
/// Never throws; an empty list means nothing found or offline.
class Catalog {
  Catalog([http.Client? client]) : client = client ?? http.Client();
  final http.Client client;

  static const _headers = {'User-Agent': 'Revue/0.1 (personal library app)'};

  Future<List<CatalogResult>> search(String query, CatalogKind kind) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      return switch (kind) {
        CatalogKind.series => await _tv(q),
        CatalogKind.anime => await _anime(q),
        CatalogKind.books => await _books(q),
      };
    } catch (_) {
      return const [];
    }
  }

  Future<List<CatalogResult>> _tv(String q) async {
    final r = await client
        .get(Uri.https('api.tvmaze.com', '/search/shows', {'q': q}), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return const [];
    return [
      for (final hit in (jsonDecode(r.body) as List).cast<Map<String, dynamic>>())
        if (hit['show'] case final Map<String, dynamic> s)
          CatalogResult(
            title: s['name'] as String? ?? '',
            kind: Kind.show,
            subtitle: [
              (s['premiered'] as String?)?.substring(0, 4),
              ((s['network'] ?? s['webChannel']) as Map?)?['name'],
            ].whereType<String>().join(' · '),
            imageUrl: _uri((s['image'] as Map?)?['medium']),
            url: s['url'] as String?,
            tvmazeId: s['id'] as int?,
          ),
    ];
  }

  /// Episodes per season for a TVmaze show (season 0 / specials skipped).
  Future<List<int>> seasons(int tvmazeId) async {
    try {
      final r = await client
          .get(Uri.https('api.tvmaze.com', '/shows/$tvmazeId/episodes'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return const [];
      final per = <int, int>{};
      for (final e in (jsonDecode(r.body) as List).cast<Map<String, dynamic>>()) {
        final s = e['season'];
        if (s is int && s >= 1 && e['number'] != null) per[s] = (per[s] ?? 0) + 1;
      }
      return (per.keys.toList()..sort()).map((s) => per[s]!).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<CatalogResult>> _anime(String q) async {
    final r = await client
        .post(Uri.https('graphql.anilist.co', '/'),
            headers: {..._headers, 'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'query': r'query($s: String) { Page(perPage: 15) { media(search: $s, type: ANIME, isAdult: false) '
                  '{ siteUrl episodes format seasonYear title { english romaji } coverImage { large } } } }',
              'variables': {'s': q},
            }))
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return const [];
    final media = (((jsonDecode(r.body) as Map)['data'] as Map?)?['Page'] as Map?)?['media'] as List? ?? const [];
    return [
      for (final m in media.cast<Map<String, dynamic>>())
        CatalogResult(
          title: (m['title'] as Map?)?['english'] ?? (m['title'] as Map?)?['romaji'] ?? '',
          kind: Kind.show,
          subtitle: [
            m['seasonYear']?.toString(),
            (m['format'] as String?)?.replaceAll('_', ' '),
            if (m['episodes'] is int) '${m['episodes']} episodes',
          ].whereType<String>().join(' · '),
          imageUrl: _uri((m['coverImage'] as Map?)?['large']),
          url: m['siteUrl'] as String?,
          episodes: m['episodes'] as int?,
        ),
    ];
  }

  Future<List<CatalogResult>> _books(String q) async {
    final r = await client
        .get(
            Uri.https('openlibrary.org', '/search.json', {
              'q': q,
              'fields': 'key,title,author_name,first_publish_year,number_of_pages_median,cover_i',
              'limit': '15',
            }),
            headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return const [];
    final docs = (jsonDecode(r.body) as Map<String, dynamic>)['docs'] as List? ?? const [];
    return [
      for (final d in docs.cast<Map<String, dynamic>>())
        CatalogResult(
          title: d['title'] as String? ?? '',
          kind: Kind.book,
          subtitle: [
            (d['author_name'] as List?)?.first as String?,
            d['first_publish_year']?.toString(),
            if (d['number_of_pages_median'] is int) '${d['number_of_pages_median']} pages',
          ].whereType<String>().join(' · '),
          imageUrl: d['cover_i'] is int ? Uri.parse('https://covers.openlibrary.org/b/id/${d['cover_i']}-M.jpg') : null,
          url: d['key'] is String ? 'https://openlibrary.org${d['key']}' : null,
          pages: d['number_of_pages_median'] as int?,
        ),
    ];
  }

  static Uri? _uri(Object? s) => s is String ? Uri.tryParse(s) : null;
}
