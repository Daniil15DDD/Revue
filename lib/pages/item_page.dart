import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../adaptive.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

class ItemPage extends StatefulWidget {
  const ItemPage({super.key, required this.store, required this.item});
  final Store store;
  final Item item;

  @override
  State<ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<ItemPage> {
  late final _title = TextEditingController(text: widget.item.title);
  late final _note = TextEditingController(text: widget.item.note);

  Item get item => widget.item;
  Store get store => widget.store;

  @override
  void initState() {
    super.initState();
    // Airing shows gain episodes: refresh the count quietly whenever the page opens.
    // After the first frame: findProgress notifies listeners, which must not happen mid-build.
    if (item.ongoing) WidgetsBinding.instance.addPostFrameCallback((_) => store.findProgress(item));
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  void _change(VoidCallback fn) {
    setState(fn);
    store.update(item);
  }

  Future<void> _open() async {
    final url = item.url == null ? null : Uri.tryParse(item.url!);
    if (url != null) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  String get _listName {
    final l = store.lists.where((l) => l.id == item.listId).firstOrNull;
    return l == null ? 'None' : l.display;
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete this item?')) return;
    await store.delete(item);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickList() async {
    final v = await pickOption<String>(context, [
      const SheetOption('', 'None'),
      for (final l in store.lists) SheetOption(l.id, l.display),
    ], title: 'Move to list');
    if (v != null) _change(() => item.listId = v.isEmpty ? null : v);
  }

  Future<void> _pickKind() async {
    final v = await pickOption<Kind>(context, [
      for (final k in Kind.values)
        SheetOption(k, k.label, icon: k.icon(context)),
    ], title: 'Type');
    if (v == null) return;
    _change(() => item.kind = v);
    if (v.progressUnit != null && item.total == null) _find();
  }

  Future<void> _setProgress(int v) async {
    await store.setProgress(item, v);
    if (mounted) setState(() {});
  }

  Future<void> _find() async {
    final found = await store.findProgress(item);
    if (!mounted) return;
    setState(() {});
    if (!found) await _enterTotal(notFound: true);
  }

  Future<void> _enterTotal({bool notFound = false}) async {
    final unit = item.kind.progressUnit!;
    final v = await promptText(
      context,
      notFound ? 'Couldn’t find it' : 'Total $unit',
      hint: notFound ? 'Enter total $unit yourself' : 'Number of $unit',
      initial: item.total?.toString() ?? '',
    );
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || n <= 0) return;
    item.total = n;
    item.seasons = [];
    await _setProgress(item.progress);
  }

  Future<void> _typeProgress() async {
    final unit = item.kind.progressUnit!;
    final v = await promptText(
      context,
      item.kind == Kind.show ? 'Episodes watched' : 'Current page',
      hint: item.total == null ? unit : 'of ${item.total} $unit',
      initial: '${item.progress}',
      action: 'Set',
    );
    final n = int.tryParse(v?.trim() ?? '');
    if (n != null) await _setProgress(n);
  }

  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) => Container(
    padding: padding,
    decoration: surface(context, radius: 26),
    child: child,
  );

  /// Pages read / episodes watched. Unknown total → look it up or type it.
  Widget _progress() {
    final rv = Rv.of(context);
    final unit = item.kind.progressUnit!;
    final busy = store.processing.contains(item.id);
    if (item.total == null || item.total! <= 0) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Track your progress', style: RvText.headline(rv.text)),
            const SizedBox(height: 4),
            Text(
              'Revue can look up the number of $unit for you.',
              style: RvText.body(rv.text2),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: busy ? 'Looking up…' : 'Find with AI',
                    icon: Icons.auto_awesome,
                    onTap: busy ? null : _find,
                    compact: true,
                  ),
                ),
                const SizedBox(width: 10),
                PillButton(
                  label: 'Enter',
                  primary: false,
                  compact: true,
                  onTap: _enterTotal,
                ),
              ],
            ),
          ],
        ),
      );
    }
    final se = item.seasonEpisode;
    final (big, small) = item.kind == Kind.show
        ? (
            se == null ? 'Not started' : 'Season ${se.$1} · Episode ${se.$2}',
            item.ongoing
                ? '${item.progress} of ${item.total} out so far · still airing'
                : '${item.progress} of ${item.total} episodes',
          )
        : (
            'Page ${item.progress}',
            'of ${item.total} pages · ${(item.progress * 100 / item.total!).round()}%',
          );
    final step = item.kind == Kind.book ? 10 : 1;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            scale: 0.98,
            onTap: _typeProgress,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(big, style: RvText.title(rv.text)),
                const SizedBox(height: 4),
                Text(
                  small,
                  style: RvText.small(rv.text2).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ProgressTrack(
            value: item.progress / item.total!,
            color: rv.accent,
            height: 10,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              RoundButton(
                icon: Icons.remove_rounded,
                tooltip: 'Back $step',
                onTap: () => _setProgress(item.progress - step),
              ),
              const SizedBox(width: 10),
              RoundButton(
                icon: Icons.add_rounded,
                tooltip: 'Forward $step',
                onTap: () => _setProgress(item.progress + step),
              ),
              const Spacer(),
              if (item.kind == Kind.show && item.progress < item.total!)
                PillButton(
                  label: 'Next Episode',
                  compact: true,
                  onTap: () => _setProgress(item.progress + 1),
                ),
              if (item.kind == Kind.book)
                PillButton(
                  label: 'Set Page',
                  compact: true,
                  primary: false,
                  onTap: _typeProgress,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statuses() {
    final rv = Rv.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in Status.values)
          Padding(
            padding: EdgeInsets.zero,
            child: Semantics(
              button: true,
              selected: item.status == s,
              child: Pressable(
                onTap: () async {
                  await store.setStatus(item, s);
                  if (mounted) setState(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: item.status == s ? rv.ink : rv.raised,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    s.label(item.kind),
                    style: TextStyle(
                      fontFamily: font,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: item.status == s ? rv.onInk : rv.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _stars() {
    final rv = Rv.of(context);
    return Row(
      children: [
        for (var s = 1; s <= 5; s++)
          Semantics(
            button: true,
            label: '$s star${s > 1 ? 's' : ''}',
            child: Pressable(
              scale: 0.8,
              onTap: () =>
                  _change(() => item.rating = item.rating == s ? 0 : s),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  s <= item.rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 34,
                  color: s <= item.rating ? rv.accent : rv.text3,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(String label, String value, IconData icon, VoidCallback onTap) {
    final rv = Rv.of(context);
    return Pressable(
      scale: 0.98,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: rv.raised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 19, color: rv.text),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: RvText.body(rv.text))),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: RvText.body(rv.text2),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: rv.text3),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store, // redraw while a progress lookup runs
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final rv = Rv.of(context);
    final thumb = store.thumbFile(item);
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            children: [
              // Cover with floating back / delete buttons.
              Stack(
                children: [
                  if (thumb != null)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(36),
                      ),
                      child: SizedBox(
                        height: top + 300,
                        width: double.infinity,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Hero(
                              tag: 'cover-${item.id}', // flies in from the list card
                              child: Image.file(
                                thumb,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => ColoredBox(color: rv.raised),
                              ),
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x59000000),
                                    Color(0x00000000),
                                  ],
                                  stops: [0, 0.4],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SizedBox(height: top + 64),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 60),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          item.kind.materialIcon,
                          size: 16,
                          color: rv.accent,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.source.isNotEmpty
                                ? item.source
                                : item.kind.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RvText.small(
                              rv.accent,
                            ).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(item.created),
                          style: RvText.small(rv.text2),
                        ),
                      ],
                    ),
                    TextField(
                      controller: _title,
                      maxLines: null,
                      style: RvText.display(rv.text).copyWith(fontSize: 30),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (v) => _change(() => item.title = v),
                    ),
                    if (item.summary.isNotEmpty)
                      Text(item.summary, style: RvText.body(rv.text2)),
                    if (item.url != null) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PillButton(
                          label: item.kind == Kind.video ? 'Watch' : 'Open',
                          icon: item.kind == Kind.video
                              ? Icons.play_arrow_rounded
                              : Icons.north_east_rounded,
                          // One prominent action per screen: for books/series that's the progress button.
                          primary: item.kind.progressUnit == null,
                          compact: true,
                          onTap: _open,
                        ),
                      ),
                    ],
                    if (item.kind.progressUnit != null) ...[
                      const SectionLabel('Progress'),
                      _progress(),
                    ],
                    const SectionLabel('Status'),
                    _statuses(),
                    const SectionLabel('Your review'),
                    _card(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _stars(),
                          const SizedBox(height: 8),
                          RvField(
                            controller: _note,
                            hint: 'Thoughts, why you saved it…',
                            multiline: true,
                            onChanged: (v) => _change(() => item.note = v),
                          ),
                        ],
                      ),
                    ),
                    const SectionLabel('Filed under'),
                    _card(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Column(
                        children: [
                          _row(
                            'List',
                            _listName,
                            Icons.collections_bookmark_outlined,
                            _pickList,
                          ),
                          Divider(height: 1, color: rv.stroke),
                          _row(
                            'Type',
                            item.kind.label,
                            item.kind.materialIcon,
                            _pickKind,
                          ),
                        ],
                      ),
                    ),
                    if (item.tags.isNotEmpty) ...[
                      const SectionLabel('Tags'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in item.tags)
                            Pill(
                              label: '#$tag',
                              selected: false,
                              onTap: () {},
                              onLongPress: () => _change(
                                () => item.tags = [...item.tags]..remove(tag),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (item.text.isNotEmpty) ...[
                      SectionLabel(
                        item.kind == Kind.note ? 'Note' : 'Text found in image',
                      ),
                      _card(
                        child: SelectableText(
                          item.text,
                          style: RvText.body(rv.text),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // Status-bar fade so scrolled text never sits under the clock, plus pinned buttons.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: top + 12,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      rv.bg.withValues(alpha: 0.9),
                      rv.bg.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _floating(
                  Icons.arrow_back_ios_new_rounded,
                  'Back',
                  () => Navigator.maybePop(context),
                  true,
                ),
                const Spacer(),
                _floating(
                  Icons.delete_outline_rounded,
                  'Delete',
                  _delete,
                  true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _floating(
    IconData icon,
    String label,
    VoidCallback onTap,
    bool overImage,
  ) {
    final rv = Rv.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        scale: 0.9,
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: overImage ? Colors.black.withValues(alpha: 0.38) : rv.raised,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 21,
            color: overImage ? Colors.white : rv.text,
          ),
        ),
      ),
    );
  }
}
