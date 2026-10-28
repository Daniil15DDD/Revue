import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum Kind {
  video(Icons.play_circle_fill, CupertinoIcons.play_rectangle_fill, 'Video'),
  movie(Icons.movie, CupertinoIcons.film, 'Movie'),
  show(Icons.live_tv, CupertinoIcons.tv, 'Series'),
  book(Icons.menu_book, CupertinoIcons.book_fill, 'Book'),
  music(Icons.music_note, CupertinoIcons.music_note, 'Music'),
  game(Icons.sports_esports, CupertinoIcons.game_controller_solid, 'Game'),
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

  /// Pages for books, episodes for series; other kinds don't track progress.
  String? get progressUnit => switch (this) {
        book => 'pages',
        show => 'episodes',
        _ => null,
      };

  /// Anime sites: saved links become series, and episode lookups go to AniList first.
  static bool isAnimeSite(Uri url) => const [
        'aniliberty.', 'anilibria.', 'crunchyroll.', 'myanimelist.', 'anilist.', 'shikimori.', 'animego.',
        'animevost.', 'jut.su', 'kitsu.', 'hianime.', 'aniwave.', '9anime.', 'animelib.',
      ].any(url.host.toLowerCase().contains);

  /// Guess what a URL points to from its host.
  static Kind guess(Uri url) {
    final host = url.host.toLowerCase();
    bool has(List<String> parts) => parts.any(host.contains);
    if (has(['youtube.', 'youtu.be', 'vimeo.', 'twitch.', 'tiktok.'])) return video;
    if (isAnimeSite(url) || has(['tvmaze.', 'tvtime.'])) return show;
    if (has(['spotify.', 'music.apple.', 'soundcloud.', 'bandcamp.'])) return music;
    if (has(['imdb.', 'letterboxd.', 'themoviedb.', 'netflix.'])) return movie;
    if (has(['goodreads.', 'books.google.', 'openlibrary.'])) return book;
    if (has(['steampowered.', 'store.playstation.', 'xbox.', 'nintendo.', 'igdb.', 'itch.io'])) return game;
    if (has(['maps.apple.', 'yelp.', 'tripadvisor.', 'maps.app.goo.gl']) ||
        (has(['google.']) && url.path.startsWith('/maps'))) {
      return place;
    }
    if (has(['amazon.', 'ebay.', 'etsy.'])) return product;
    if (has(['medium.', 'substack.', 'wikipedia.', 'nytimes.'])) return article;
    return link;
  }
}

enum Status {
  planned,
  active,
  finished,
  paused,
  dropped;

  static Status? byName(String? name) => Status.values.where((s) => s.name == name).firstOrNull;

  /// Wording that fits the thing: "Plan to read", "Watching", "Visited"…
  String label(Kind kind) {
    final (plan, doing, done) = switch (kind) {
      Kind.book || Kind.article => ('Plan to read', 'Reading', 'Read'),
      Kind.video || Kind.movie || Kind.show => ('Plan to watch', 'Watching', 'Watched'),
      Kind.music => ('Plan to listen', 'Listening', 'Listened'),
      Kind.game => ('Plan to play', 'Playing', 'Played'),
      Kind.place => ('Want to go', 'Going', 'Visited'),
      _ => ('Saved', 'In progress', 'Done'),
    };
    return switch (this) {
      planned => plan,
      active => doing,
      finished => done,
      paused => 'On hold',
      dropped => 'Dropped',
    };
  }
}

/// List colours (match the Stats bars). Stored as ARGB ints.
const listPalette = [
  0xFF2F5BEA, // blue
  0xFFF0582A, // red-orange
  0xFFF5A33B, // amber
  0xFFA8CF45, // lime
  0xFFB13CF0, // purple
  0xFF2BB5B0, // teal
  0xFFFF4F79, // pink
  0xFF8E8E93, // grey
];

class RevueList {
  RevueList({String? id, required this.name, int? color, this.emoji = ''})
      : id = id ?? _newId(),
        color = color ?? listPalette[_colorCounter++ % listPalette.length];
  final String id;
  String name;
  int color;
  String emoji; // optional, older lists have one

  String get display => emoji.isEmpty ? name : '$emoji $name';

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color, 'emoji': emoji};
  factory RevueList.fromJson(Map<String, dynamic> j) =>
      RevueList(id: j['id'], name: j['name'] ?? '', color: j['color'], emoji: j['emoji'] ?? '');
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
    this.status = Status.planned,
    this.progress = 0,
    this.total,
    List<int>? seasons,
    this.thumbnail,
    DateTime? created,
    this.finishedAt,
  })  : id = id ?? _newId(),
        tags = tags ?? [],
        seasons = seasons ?? [],
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
  Status status;
  int progress; // pages read / episodes watched
  int? total; // total pages / episodes, null = unknown
  List<int> seasons; // series: episodes per season (index 0 = season 1)
  String? thumbnail; // file name inside Store.thumbsDir
  final DateTime created;
  DateTime? finishedAt;

  bool get done => status == Status.finished;

  /// Sets progress and moves the status along: started → active, reached the end → finished.
  void setProgress(int value) {
    progress = value.clamp(0, total ?? 1 << 30);
    if (total != null && progress >= total!) {
      setStatus(Status.finished);
    } else if (progress > 0 && (status == Status.planned || status == Status.finished)) {
      setStatus(Status.active);
    }
  }

  void setStatus(Status s) {
    if (s == Status.finished && status != Status.finished) finishedAt = DateTime.now();
    if (s != Status.finished) finishedAt = null;
    status = s;
    if (s == Status.finished && total != null) progress = total!;
  }

  /// For series: the last watched episode as (season, episode), from [progress].
  (int, int)? get seasonEpisode {
    if (progress <= 0 || seasons.isEmpty) return null;
    var left = progress;
    for (var s = 0; s < seasons.length; s++) {
      if (left <= seasons[s]) return (s + 1, left);
      left -= seasons[s];
    }
    return (seasons.length, seasons.last);
  }

  /// "Page 212 of 496", "S2 · E5 · 18 of 62 episodes", or null when nothing is tracked.
  String? get progressLabel {
    final unit = kind.progressUnit;
    if (unit == null || (progress == 0 && total == null)) return null;
    if (kind == Kind.book) return total == null ? 'Page $progress' : 'Page $progress of $total';
    final se = seasonEpisode;
    final count = total == null ? '$progress episodes' : '$progress of $total episodes';
    return se == null ? count : 'S${se.$1} · E${se.$2} · $count';
  }

  /// Everything searchable about the item, lowercased.
  String get haystack => [title, source, summary, text, note, tags.join(' '), kind.name, status.label(kind), url ?? '']
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
        'status': status.name,
        'progress': progress,
        'total': total,
        'seasons': seasons,
        'thumbnail': thumbnail,
        'created': created.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
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
        // Libraries saved before statuses existed only had a done flag.
        status: Status.byName(j['status']) ?? (j['done'] == true ? Status.finished : Status.planned),
        progress: j['progress'] ?? 0,
        total: j['total'],
        seasons: List<int>.from(j['seasons'] ?? const []),
        thumbnail: j['thumbnail'],
        created: DateTime.tryParse(j['created'] ?? ''),
        finishedAt: DateTime.tryParse(j['finishedAt'] ?? ''),
      );
}

int _counter = 0;
int _colorCounter = 0;
String _newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_counter++).toRadixString(36)}';
