import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class LinkMetadata {
  LinkMetadata({this.title = '', this.summary = '', this.source = '', this.imageUrl});
  String title;
  String summary;
  String source;
  Uri? imageUrl;
}

/// Pulls title, description and thumbnail for a URL. YouTube goes through oEmbed
/// (no cookie/consent pages); everything else reads Open Graph / Twitter meta tags.
class LinkFetcher {
  LinkFetcher([http.Client? client]) : client = client ?? http.Client();
  final http.Client client;

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1',
    'Accept-Language': 'en',
  };

  static String? youTubeId(Uri url) {
    final host = url.host.toLowerCase();
    final parts = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (host.endsWith('youtu.be')) return parts.firstOrNull;
    if (!host.contains('youtube.')) return null;
    final v = url.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    if (parts.length >= 2 && const ['shorts', 'embed', 'live', 'v'].contains(parts[0])) return parts[1];
    return null;
  }

  Future<LinkMetadata> fetch(Uri url) async {
    final ytId = youTubeId(url);
    if (ytId != null) {
      final meta = LinkMetadata(
        source: 'YouTube',
        imageUrl: Uri.parse('https://i.ytimg.com/vi/$ytId/hqdefault.jpg'),
      );
      try {
        final r = await client
            .get(Uri.https('www.youtube.com', '/oembed', {'url': url.toString(), 'format': 'json'}),
                headers: _headers)
            .timeout(const Duration(seconds: 15));
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          meta.title = j['title'] ?? '';
          if (j['author_name'] != null) meta.source = 'YouTube · ${j['author_name']}';
        }
      } catch (_) {/* fall through to HTML */}
      if (meta.title.isNotEmpty) return meta;
    }
    final r = await client.get(url, headers: _headers).timeout(const Duration(seconds: 15));
    final body = r.bodyBytes.length > 800000 ? r.bodyBytes.sublist(0, 800000) : r.bodyBytes;
    final meta = parseHtml(utf8.decode(body, allowMalformed: true), url);
    if (meta.source.isEmpty) meta.source = url.host.replaceFirst('www.', '');
    return meta;
  }

  /// Reads og:/twitter: meta tags and <title> out of raw HTML.
  static LinkMetadata parseHtml(String html, Uri base) {
    final tags = <String, String>{};
    final attrRe = RegExp(r'''([a-zA-Z_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
    for (final m in RegExp(r'<meta\s[^>]*>', caseSensitive: false).allMatches(html)) {
      final attrs = <String, String>{};
      for (final a in attrRe.allMatches(m.group(0)!)) {
        attrs[a.group(1)!.toLowerCase()] = a.group(2) ?? a.group(3) ?? '';
      }
      final key = (attrs['property'] ?? attrs['name'])?.toLowerCase();
      final content = attrs['content'];
      if (key != null && content != null) tags.putIfAbsent(key, () => decodeEntities(content));
    }
    final titleTag = RegExp(r'<title[^>]*>([^<]*)</title>', caseSensitive: false).firstMatch(html)?.group(1);
    final image = tags['og:image'] ?? tags['og:image:url'] ?? tags['twitter:image'] ?? tags['twitter:image:src'];
    return LinkMetadata(
      title: (tags['og:title'] ?? tags['twitter:title'] ?? decodeEntities(titleTag ?? '')).trim(),
      summary: (tags['og:description'] ?? tags['twitter:description'] ?? tags['description'] ?? '').trim(),
      source: tags['og:site_name'] ?? '',
      imageUrl: image == null ? null : base.resolve(image),
    );
  }

  static String decodeEntities(String s) {
    const map = {'&quot;': '"', '&#39;': "'", '&#x27;': "'", '&apos;': "'", '&lt;': '<', '&gt;': '>', '&nbsp;': ' '};
    var out = s;
    map.forEach((k, v) => out = out.replaceAll(k, v));
    return out.replaceAll('&amp;', '&'); // last, so "&amp;lt;" stays "&lt;"
  }

  Future<Uint8List?> downloadImage(Uri url) async {
    try {
      final r = await client.get(url, headers: _headers).timeout(const Duration(seconds: 20));
      if (r.statusCode < 400 && r.bodyBytes.length > 100) return r.bodyBytes;
    } catch (_) {}
    return null;
  }

  /// First http(s) URL inside free text, e.g. "Check this out https://youtu.be/xyz" from a share sheet.
  static Uri? firstUrl(String text) {
    final m = RegExp(r'https?://[^\s<>"]+').firstMatch(text);
    if (m == null) return null;
    final raw = m.group(0)!.replaceFirst(RegExp(r'[).,;!?\]]+$'), '');
    return Uri.tryParse(raw);
  }
}
