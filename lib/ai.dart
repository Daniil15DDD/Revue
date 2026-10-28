import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'models.dart';

/// A text-in/text-out language model. The real one runs on-device; tests use a fake.
abstract class Llm {
  Future<String> generate(String system, String prompt);
}

class ModelOption {
  const ModelOption(this.name, this.size, this.url);
  final String name;
  final String size;
  final String url;
  String get file => Uri.parse(url).pathSegments.last;
}

/// Public (no HuggingFace token) Qwen 2.5 builds in MediaPipe .task format — run on iOS and Android.
const modelOptions = [
  ModelOption('Qwen 2.5 · 1.5B (smarter)', '1.6 GB',
      'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv1280.task'),
  ModelOption('Qwen 2.5 · 0.5B (faster, smaller)', '0.5 GB',
      'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task'),
];

/// On-device LLM via flutter_gemma (MediaPipe LLM inference). Nothing leaves the phone.
class GemmaLlm extends ChangeNotifier implements Llm {
  InferenceModel? _model;
  Future<void> _queue = Future.value();
  String? activeFile;
  int? downloadProgress; // 0..100 while downloading

  bool get ready => activeFile != null;

  /// Re-activates a model downloaded in an earlier run (install() skips the download).
  Future<void> restore() async {
    for (final o in modelOptions) {
      if (await FlutterGemma.isModelInstalled(o.file)) {
        await FlutterGemma.installModel(modelType: ModelType.qwen).fromNetwork(o.url).install();
        activeFile = o.file;
        notifyListeners();
        return;
      }
    }
  }

  Future<void> download(ModelOption o) async {
    downloadProgress = 0;
    notifyListeners();
    try {
      await FlutterGemma.installModel(modelType: ModelType.qwen)
          .fromNetwork(o.url)
          .withProgress((p) {
            downloadProgress = p;
            notifyListeners();
          })
          .install();
      await _model?.close();
      _model = null;
      activeFile = o.file;
      // One model at a time: frees GBs and keeps restore() picking the one the user chose.
      for (final other in modelOptions.where((m) => m.file != o.file)) {
        if (await FlutterGemma.isModelInstalled(other.file)) await FlutterGemma.uninstallModel(other.file);
      }
    } finally {
      downloadProgress = null;
      notifyListeners();
    }
  }

  Future<void> remove(ModelOption o) async {
    await _model?.close();
    _model = null;
    await FlutterGemma.uninstallModel(o.file);
    if (activeFile == o.file) activeFile = null;
    notifyListeners();
  }

  @override
  Future<String> generate(String system, String prompt) {
    // MediaPipe runs one session at a time, so calls are queued.
    final result = _queue.then((_) async {
      // These .task builds have a 1280-token KV cache shared by prompt and reply, so prompts stay short.
      // GPU on Android needs OpenCL, which many phones (and emulators) lack, and MediaPipe
      // segfaults instead of falling back, so Android runs on CPU. iOS GPU uses Metal (always there).
      // shortcut: CPU for every Android phone; probe for libOpenCL.so to use the GPU where it exists.
      _model ??= await FlutterGemma.getActiveModel(
          maxTokens: 1280,
          preferredBackend: defaultTargetPlatform == TargetPlatform.iOS ? PreferredBackend.gpu : PreferredBackend.cpu);
      final chat = await _model!.createChat(temperature: 0.3, topK: 40, systemInstruction: system);
      try {
        await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
        final r = await chat.generateChatResponse();
        return r is TextResponse ? r.token.trim() : '';
      } finally {
        await chat.close();
      }
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// On-device OCR with Google ML Kit (bundled model, works offline).
class Ocr {
  static Future<String> read(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      return (await recognizer.processImage(InputImage.fromFilePath(imagePath))).text;
    } catch (e) {
      debugPrint('OCR failed: $e');
      return '';
    } finally {
      recognizer.close();
    }
  }
}

class Analysis {
  String title = '';
  Kind? kind;
  String summary = '';
  List<String> tags = [];
}

/// Prompting + retrieval logic, kept free of plugins so it is unit-testable.
class Brain {
  static const _analyzeSystem = 'You file things a person saved into their personal library. '
      'Reply in exactly this format and nothing else:\n'
      'TITLE: <short title, max 8 words>\n'
      'KIND: <one of: video, music, movie, book, article, place, product, link, image, note>\n'
      'SUMMARY: <one sentence>\n'
      'TAGS: <3 to 5 lowercase tags, comma separated>';

  static Future<Analysis?> analyze(Llm? llm, String content) async {
    if (llm == null || content.trim().isEmpty) return null;
    // shortcut: 1280-token context, so long text is cut; chunk + merge if quality suffers.
    final clipped = content.length > 1200 ? content.substring(0, 1200) : content;
    try {
      return parse(await llm.generate(_analyzeSystem, clipped));
    } catch (e) {
      debugPrint('analyze failed: $e');
      return null;
    }
  }

  static Analysis parse(String reply) {
    final a = Analysis();
    for (final line in reply.split('\n')) {
      final i = line.indexOf(':');
      if (i < 0) continue;
      final key = line.substring(0, i).replaceAll('*', '').trim().toUpperCase();
      final value = line.substring(i + 1).replaceAll(RegExp(r'^[\s<"*]+|[\s>"*]+$'), '');
      switch (key) {
        case 'TITLE':
          a.title = value;
        case 'KIND':
          a.kind = Kind.byName(value);
        case 'SUMMARY':
          a.summary = value;
        case 'TAGS':
          a.tags = value
              .split(',')
              .map((t) => t.trim().toLowerCase().replaceAll('#', ''))
              .where((t) => t.isNotEmpty)
              .take(5)
              .toList();
      }
    }
    return a;
  }

  static const _stop = {'the', 'and', 'for', 'what', 'which', 'did', 'have', 'that', 'this', 'with', 'about',
    'saved', 'save', 'any', 'my', 'are', 'was', 'you', 'can', 'show', 'from', 'all', 'how', 'many'};

  /// Items most related to the question by word overlap; tops up with the newest ones.
  // shortcut: keyword scoring, not embeddings; add an embedding model + vector search for big libraries.
  static List<Item> relevant(List<Item> items, String question, {int limit = 8, bool onlyMatches = false}) {
    final words = question
        .toLowerCase()
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.length > 2 && !_stop.contains(w))
        .toSet();
    int score(Item i) {
      final hay = i.haystack;
      return words.where(hay.contains).length;
    }
    final newest = [...items]..sort((a, b) => b.created.compareTo(a.created));
    final hits = newest.where((i) => score(i) > 0).toList()..sort((a, b) => score(b).compareTo(score(a)));
    return [...hits, if (!onlyMatches) ...newest.where((i) => !hits.contains(i))].take(limit).toList();
  }

  static String context(List<Item> items, List<RevueList> lists) {
    final names = {for (final l in lists) l.id: l.name};
    String clip(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;
    return items.map((i) {
      final b = StringBuffer('- [${i.kind.name}] ${i.title}');
      if (i.source.isNotEmpty) b.write(' (${i.source})');
      if (names[i.listId] != null) b.write(' · list: ${names[i.listId]}');
      b.write(' · saved ${i.created.toIso8601String().substring(0, 10)}');
      if (i.rating > 0) b.write(' · rated ${i.rating}/5');
      b.write(' · ${i.status.label(i.kind).toLowerCase()}');
      if (i.progressLabel != null) b.write(' (${i.progressLabel})');
      if (i.tags.isNotEmpty) b.write(' · tags: ${i.tags.join(', ')}');
      if (i.summary.isNotEmpty) b.write('\n  ${clip(i.summary, 120)}');
      if (i.note.isNotEmpty) b.write('\n  note: ${clip(i.note, 120)}');
      if (i.text.isNotEmpty) b.write('\n  text: ${clip(i.text.replaceAll('\n', ' '), 150)}');
      return b.toString();
    }).join('\n');
  }

  static Future<String> answer(
      Llm? llm, String question, List<Item> items, List<RevueList> lists, List<(String, String)> history) async {
    if (items.isEmpty) return 'Your library is empty. Share a link or add a screenshot first.';
    final picked = relevant(items, question, limit: 5);
    if (llm == null) {
      // No model downloaded yet: still useful as search.
      final hits = relevant(items, question, limit: 5, onlyMatches: true);
      const prefix = 'The on-device AI model isn\'t downloaded yet (Settings → AI model), so this is plain search.';
      if (hits.isEmpty) return '$prefix Nothing in your library matches those words.';
      return '$prefix Closest matches:\n${hits.map((i) => '• ${i.title}').join('\n')}';
    }
    final earlier = history.isEmpty ? history : [history.last];
    final prompt = StringBuffer()
      ..writeln('Library entries (${picked.length} of ${items.length} total):')
      ..writeln(context(picked, lists));
    if (earlier.isNotEmpty) {
      prompt.writeln('\nEarlier conversation:');
      for (final (q, a) in earlier) {
        prompt.writeln('User: $q\nAssistant: $a');
      }
    }
    prompt.write('\nQuestion: $question');
    return llm.generate(
        'You are Revue\'s assistant. Revue is the user\'s personal library of things they saved: '
        'videos, links, books, places, screenshots and notes. Answer using only the library entries given. '
        'Be brief and friendly. Use item titles exactly. If the library does not contain the answer, say so.',
        prompt.toString());
  }
}
