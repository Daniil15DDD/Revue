import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:revue/catalog.dart';
import 'package:revue/link_fetcher.dart';
import 'package:revue/models.dart';
import 'package:revue/store.dart';

http.Client fakeDbs() => MockClient((req) async {
      final u = req.url;
      if (u.path == '/search/shows') {
        return http.Response(jsonEncode([
          {'show': {'id': 54198, 'name': 'The Bear', 'premiered': '2022-06-23', 'url': 'https://www.tvmaze.com/shows/54198',
            'network': null, 'webChannel': {'name': 'Hulu'}, 'image': {'medium': 'https://img/bear.jpg'}}},
        ]), 200);
      }
      if (u.path == '/shows/54198/episodes') {
        return http.Response(jsonEncode([
          for (var e = 1; e <= 8; e++) {'season': 1, 'number': e},
          {'season': 1, 'number': null}, // special
          for (var e = 1; e <= 10; e++) {'season': 2, 'number': e},
        ]), 200);
      }
      if (u.host == 'graphql.anilist.co') {
        return http.Response(jsonEncode({'data': {'Page': {'media': [
          {'siteUrl': 'https://anilist.co/anime/5114', 'episodes': 64, 'format': 'TV', 'seasonYear': 2009,
            'title': {'english': 'Fullmetal Alchemist: Brotherhood', 'romaji': 'Hagane'}, 'coverImage': {'large': 'https://img/fma.jpg'}},
        ]}}}), 200);
      }
      if (u.host == 'openlibrary.org') {
        return http.Response(jsonEncode({'docs': [
          {'key': '/works/OL893414W', 'title': 'Dune', 'author_name': ['Frank Herbert'], 'first_publish_year': 1965,
            'number_of_pages_median': 608, 'cover_i': 11481354},
        ]}), 200);
      }
      if (u.host == 'img' || u.host == 'covers.openlibrary.org') return http.Response.bytes(List.filled(400, 1), 200);
      return http.Response('', 404);
    });

void main() {
  final catalog = Catalog(fakeDbs());

  test('series search reads TVmaze and counts episodes per season later', () async {
    final r = (await catalog.search('the bear', CatalogKind.series)).single;
    expect((r.title, r.kind, r.subtitle, r.tvmazeId), ('The Bear', Kind.show, '2022 · Hulu', 54198));
    expect(await catalog.seasons(54198), [8, 10]);
  });

  test('anime search reads AniList with episodes up front', () async {
    final r = (await catalog.search('fma', CatalogKind.anime)).single;
    expect((r.title, r.episodes, r.subtitle), ('Fullmetal Alchemist: Brotherhood', 64, '2009 · TV · 64 episodes'));
  });

  test('book search reads Open Library with pages and cover', () async {
    final r = (await catalog.search('dune', CatalogKind.books)).single;
    expect((r.title, r.pages, r.subtitle), ('Dune', 608, 'Frank Herbert · 1965 · 608 pages'));
    expect(r.imageUrl.toString(), 'https://covers.openlibrary.org/b/id/11481354-M.jpg');
  });

  test('empty query and offline give no results', () async {
    expect(await catalog.search('  ', CatalogKind.books), isEmpty);
    expect(await Catalog(MockClient((_) => throw Exception('offline'))).search('x', CatalogKind.series), isEmpty);
  });

  test('adding a result files it with status, list, totals and cover', () async {
    final dir = await Directory.systemTemp.createTemp('revue_catalog');
    addTearDown(() => dir.delete(recursive: true));
    final store = Store(dir, catalog: catalog, fetcher: LinkFetcher(fakeDbs()), ocr: (_) async => '');
    await store.load();
    final list = await store.addList('Watching now');

    final bear = (await catalog.search('the bear', CatalogKind.series)).single;
    final show = await store.addFromCatalog(bear, status: Status.active, listId: list.id);
    expect((show.kind, show.status, show.listId, show.total), (Kind.show, Status.active, list.id, 18));
    expect(show.seasons, [8, 10]);
    expect(show.thumbnail, isNotNull);

    final dune = (await catalog.search('dune', CatalogKind.books)).single;
    final book = await store.addFromCatalog(dune, status: Status.finished);
    expect((book.total, book.progress, book.done), (608, 608, true));

    // Adding the same one twice doesn't duplicate it, but applies the new choice.
    await store.addFromCatalog(dune, status: Status.planned, listId: list.id);
    expect(store.items.length, 2);
    expect((book.status, book.listId), (Status.planned, list.id));
  });
}
