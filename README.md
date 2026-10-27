# Revue

A review of everything you experience. Save videos, links, places, books and screenshots
into lists, rate them, and ask an on-device AI about them. Runs on **iPhone and Android**
(Flutter).

## What it does

- **Share → Revue** from YouTube, Chrome, Safari, TikTok and so on. Revue fetches the title,
  channel or site, and thumbnail automatically. YouTube uses oEmbed; other sites use their
  Open Graph tags.
- **Screenshots.** Share one to Revue, or use Add → Screenshots. Google ML Kit reads the text
  **on the device**. The local LLM then gives it a title, a one-line summary and tags. Any link
  in the screenshot is detected.
- **Lists** (Watch later, To read, Places, plus your own), kind filters, and search across
  titles, notes, tags and the text inside screenshots.
- **Review**: star ratings, a watched/read/visited flag, and notes.
- **Ask Revue**: chat with an on-device LLM (Qwen 2.5 via flutter_gemma/MediaPipe) about
  your library. Before the model is downloaded, the chat works as plain search.

Nothing is uploaded. The network is only used to fetch link previews and download the model once.

## Run

```bash
flutter pub get
flutter run            # Android device/emulator, or iPhone
flutter test           # logic, storage and widget tests
```

- **Android**: works out of the box (minSdk 24). Share → Revue appears automatically.
- **iOS**: requires Xcode. Follow [docs/IOS_SETUP.md](docs/IOS_SETUP.md) once to add the share extension.
- **AI model**: in the app, go to Settings → On-device AI model → Download.
  The 1.5B model is about 1.6 GB and the 0.5B model about 0.5 GB.

## Layout

| File | What |
|---|---|
| `lib/models.dart` | `Item`, `RevueList`, `Kind` (guessed from the URL host) |
| `lib/link_fetcher.dart` | YouTube oEmbed, Open Graph parsing, thumbnail download |
| `lib/store.dart` | JSON library + thumbnails on disk; add link / screenshot / note |
| `lib/ai.dart` | On-device LLM (flutter_gemma), OCR (ML Kit), prompts and retrieval |
| `lib/pages/` | Library grid, item page, assistant chat, settings |
| `ios/ShareExtension/` | iOS share-sheet extension (see the setup doc) |

## Known limits

- `flutter_gemma` is pinned at 0.13.6. Newer versions (renamed `flutter_edge_ai`) need Dart 3.12,
  and this machine has Flutter 3.41.4 / Dart 3.11.
- The assistant picks relevant items by keyword overlap, not embeddings. That works well up to a
  few hundred items.
- OCR covers Latin scripts only (`TextRecognitionScript.latin`).
