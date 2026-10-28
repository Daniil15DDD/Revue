import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum Kind {
  video(Icons.play_circle_fill, CupertinoIcons.play_rectangle_fill, 'Video'),
  music(Icons.music_note, CupertinoIcons.music_note, 'Music'),
  movie(Icons.movie, CupertinoIcons.film, 'Movie'),
  book(Icons.menu_book, CupertinoIcons.book_fill, 'Book'),
  article(Icons.article, CupertinoIcons.doc_text_fill, 'Article'),
  place(Icons.place, CupertinoIcons.map_pin_ellipse, 'Place'),
  product(Icons.shopping_bag, CupertinoIcons.bag_fill, 'Product'),
  link(Icons.link, CupertinoIcons.link, 'Link'),
  image(Icons.image, CupertinoIcons.photo, 'Screenshot'),
  note(Icons.notes, CupertinoIcons.doc_plaintext, 'Note');

  const Kind(this.materialIcon, this.iosIcon, this.label);
  final IconData materialIcon;
  final IconData iosIcon; // SF Symbols look-alikes for the iPhone UI
  final String label;

  IconData icon(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.iOS ? iosIcon : materialIcon;

  static Kind? byName(String? name) =>
      Kind.values.where((k) => k.name == name?.trim().toLowerCase()).firstOrNull;

  /// Guess what a URL points to from its host.
  static Kind guess(Uri url) {
    final host = url.host.toLowerCase();
    bool has(List<String> parts) => parts.any(host.contains);
    if (has(['youtube.', 'youtu.be', 'vimeo.', 'twitch.', 'tiktok.'])) return video;
    if (has(['spotify.', 'music.apple.', 'soundcloud.', 'bandcamp.'])) return music;
    if (has(['imdb.', 'letterboxd.', 'themoviedb.', 'netflix.'])) return movie;
    if (has(['goodreads.', 'books.google.', 'openlibrary.'])) return book;
    if (has(['maps.apple.', 'yelp.', 'tripadvisor.', 'maps.app.goo.gl']) ||
        (has(['google.']) && url.path.startsWith('/maps'))) {
      return place;
    }
    if (has(['amazon.', 'ebay.', 'etsy.'])) return product;
    if (has(['medium.', 'substack.', 'wikipedia.', 'nytimes.'])) return article;
    return link;
  }
}

class RevueList {
  RevueList({String? id, required this.name, this.emoji = '📌'})
      : id = id ?? _newId();
  final String id;
  String name;
  String emoji;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'emoji': emoji};
  factory RevueList.fromJson(Map<String, dynamic> j) =>
      RevueList(id: j['id'], name: j['name'] ?? '', emoji: j['emoji'] ?? '📌');
}

class Item {
  Item({
    String? id,
    required this.title,
    this.url,
    required this.kind,
    this.listId,
    this.source = '',
    this.summary = '',
    this.text = '',
    List<String>? tags,
    this.note = '',
    this.rating = 0,
    this.done = false,
    this.thumbnail,
    DateTime? created,
  })  : id = id ?? _newId(),
        tags = tags ?? [],
        created = created ?? DateTime.now();

  final String id;
  String title;
  String? url;
  Kind kind;
  String? listId;
  String source; // "YouTube · Veritasium"
  String summary; // page description or AI summary
  String text; // OCR text of a screenshot
  List<String> tags;
  String note;
  int rating; // 0 = unrated, 1..5
  bool done; // watched / read / visited
  String? thumbnail; // file name inside Store.thumbsDir
  final DateTime created;

  /// Everything searchable about the item, lowercased.
  String get haystack => [title, source, summary, text, note, tags.join(' '), kind.name, url ?? '']
      .join(' ')
      .toLowerCase();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'kind': kind.name,
        'listId': listId,
        'source': source,
        'summary': summary,
        'text': text,
        'tags': tags,
        'note': note,
        'rating': rating,
        'done': done,
        'thumbnail': thumbnail,
        'created': created.toIso8601String(),
      };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'],
        title: j['title'] ?? '',
        url: j['url'],
        kind: Kind.byName(j['kind']) ?? Kind.link,
        listId: j['listId'],
        source: j['source'] ?? '',
        summary: j['summary'] ?? '',
        text: j['text'] ?? '',
        tags: List<String>.from(j['tags'] ?? const []),
        note: j['note'] ?? '',
        rating: j['rating'] ?? 0,
        done: j['done'] ?? false,
        thumbnail: j['thumbnail'],
        created: DateTime.tryParse(j['created'] ?? ''),
      );
}

int _counter = 0;
String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_counter++).toRadixString(36)}';
