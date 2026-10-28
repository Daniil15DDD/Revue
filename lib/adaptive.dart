import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// Platform check, still used for share-sheet wording and the iOS share extension.
bool isIOS(BuildContext context) => Theme.of(context).platform == TargetPlatform.iOS;

/// Revue-style dialog: frosted backdrop, rounded card that springs in from slightly smaller.
Future<T?> showRevueDialog<T>(BuildContext context, WidgetBuilder builder) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 340),
    pageBuilder: (ctx, _, _) => SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Material(type: MaterialType.transparency, child: builder(ctx)),
        ),
      ),
    ),
    transitionBuilder: (ctx, a, _, child) {
      final t = CurvedAnimation(parent: a, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(t), child: child),
      );
    },
  );
}

Widget _dialogCard(BuildContext context, {required String title, String? message, Widget? body, required List<Widget> actions}) {
  final rv = Rv.of(context);
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 400),
    child: Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
      decoration: BoxDecoration(color: rv.surface, borderRadius: BorderRadius.circular(30), border: Border.all(color: rv.stroke)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: RvText.title(rv.text)),
        if (message != null) ...[const SizedBox(height: 8), Text(message, style: RvText.body(rv.text2))],
        if (body != null) ...[const SizedBox(height: 16), body],
        const SizedBox(height: 20),
        Row(children: [for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: a)]]),
      ]),
    ),
  );
}

/// Yes/no question.
Future<bool> confirm(BuildContext context, String title,
    {String? message, String action = 'Delete', bool destructive = true}) async {
  final ok = await showRevueDialog<bool>(
    context,
    (ctx) => _dialogCard(ctx, title: title, message: message, actions: [
      PillButton(label: 'Cancel', primary: false, onTap: () => Navigator.pop(ctx, false)),
      PillButton(
          label: action,
          color: destructive ? const Color(0xFFE5484D) : null,
          onTap: () => Navigator.pop(ctx, true)),
    ]),
  );
  return ok ?? false;
}

/// Revue text field: soft filled capsule, no underline.
class RvField extends StatelessWidget {
  const RvField(
      {super.key, required this.controller, this.hint = '', this.multiline = false, this.autofocus = false, this.onChanged, this.onSubmitted, this.prefix});
  final TextEditingController controller;
  final String hint;
  final bool multiline;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefix;

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    return TextField(
      controller: controller,
      autofocus: autofocus,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 8 : 3,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: multiline ? TextInputAction.newline : TextInputAction.done,
      style: RvText.body(rv.text),
      cursorColor: rv.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: RvText.body(rv.text3),
        prefixIcon: prefix == null ? null : Icon(prefix, color: rv.text2),
        filled: true,
        fillColor: rv.raised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
    );
  }
}

/// Asks for text.
Future<String?> promptText(BuildContext context, String title,
    {String initial = '', String hint = '', bool multiline = false, String action = 'Save'}) {
  final c = TextEditingController(text: initial);
  return showRevueDialog<String>(
    context,
    (ctx) => _dialogCard(ctx,
        title: title,
        body: RvField(controller: c, hint: hint, multiline: multiline, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          PillButton(label: 'Cancel', primary: false, onTap: () => Navigator.pop(ctx)),
          PillButton(label: action, onTap: () => Navigator.pop(ctx, c.text)),
        ]),
  );
}

class SheetOption<T> {
  const SheetOption(this.value, this.label, {this.icon, this.subtitle, this.destructive = false, this.color});
  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;
  final bool destructive;
  final Color? color; // swatch dot (list colours)
}

/// Bottom sheet that floats above the edge, in Revue's own style. Scrolls when long.
Future<T?> showRevueSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    elevation: 0,
    sheetAnimationStyle: const AnimationStyle(duration: Duration(milliseconds: 380), reverseDuration: Duration(milliseconds: 240)),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, 0, 10, 10 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: Container(
            decoration: BoxDecoration(
                color: Rv.of(ctx).surface, borderRadius: BorderRadius.circular(32), border: Border.all(color: Rv.of(ctx).stroke)),
            child: builder(ctx),
          ),
        ),
      ),
    ),
  );
}

/// Pick one option.
Future<T?> pickOption<T>(BuildContext context, List<SheetOption<T>> options, {String? title}) {
  return showRevueSheet<T>(context, (ctx) {
    final rv = Rv.of(ctx);
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(10, 10, 10, 10), children: [
      Center(
        child: Container(
            width: 36, height: 5, decoration: BoxDecoration(color: rv.stroke, borderRadius: BorderRadius.circular(3))),
      ),
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
          child: Text(title, textAlign: TextAlign.center, style: RvText.headline(rv.text)),
        ),
      for (final o in options)
        Pressable(
          scale: 0.98,
          onTap: () => Navigator.pop(ctx, o.value),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              if (o.color != null) ...[
                Container(width: 22, height: 22, decoration: BoxDecoration(color: o.color, shape: BoxShape.circle)),
                const SizedBox(width: 14),
              ] else if (o.icon != null) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: rv.raised, borderRadius: BorderRadius.circular(13)),
                  child: Icon(o.icon, size: 20, color: o.destructive ? const Color(0xFFE5484D) : rv.text),
                ),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.label,
                      style: RvText.body(o.destructive ? const Color(0xFFE5484D) : rv.text).copyWith(fontWeight: FontWeight.w600)),
                  if (o.subtitle != null) Text(o.subtitle!, style: RvText.small(rv.text2)),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  });
}

/// Small filter capsule (search tabs, tags).
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.onLongPress});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final rv = Rv.of(context);
    final fg = selected ? rv.onInk : rv.text;
    return Pressable(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: selected ? rv.ink : rv.raised, borderRadius: BorderRadius.circular(100)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
          Text(label, style: TextStyle(fontFamily: font, fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
        ]),
      ),
    );
  }
}

Widget sectionHeader(BuildContext context, String text) => Text(text.toUpperCase(), style: RvText.label(Rv.of(context).text2));

Widget sectionFooter(BuildContext context, String text) => Text(text, style: RvText.small(Rv.of(context).text2));
