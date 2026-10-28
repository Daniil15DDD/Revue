import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// iPhone gets Apple-style (Cupertino) controls; Android keeps Material.
bool isIOS(BuildContext context) => Theme.of(context).platform == TargetPlatform.iOS;

/// iOS grouped-list section header/footer: small grey caption (inside MaterialApp the
/// sections would otherwise inherit Material's large body text).
Widget sectionHeader(BuildContext context, String text) => Text(
      text.toUpperCase(),
      style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: -0.08,
          color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context)),
    );

Widget sectionFooter(BuildContext context, String text) => Text(
      text,
      style: TextStyle(fontSize: 13, color: CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context)),
    );

/// Yes/no question: CupertinoAlertDialog on iPhone, AlertDialog on Android.
Future<bool> confirm(BuildContext context, String title,
    {String? message, String action = 'Delete', bool destructive = true}) async {
  final ok = await showAdaptiveDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        _dialogAction(ctx, 'Cancel', () => Navigator.pop(ctx, false)),
        _dialogAction(ctx, action, () => Navigator.pop(ctx, true), destructive: destructive, primary: true),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for text. On iPhone uses a CupertinoAlertDialog with a CupertinoTextField.
Future<String?> promptText(BuildContext context, String title,
    {String initial = '', String hint = '', bool multiline = false, String action = 'Save'}) {
  final c = TextEditingController(text: initial);
  final ios = isIOS(context);
  return showAdaptiveDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title),
      content: Padding(
        padding: EdgeInsets.only(top: ios ? 12 : 0),
        child: ios
            ? CupertinoTextField(
                controller: c,
                autofocus: true,
                placeholder: hint,
                minLines: multiline ? 3 : 1,
                maxLines: multiline ? 8 : 3,
              )
            : TextField(
                controller: c,
                autofocus: true,
                minLines: multiline ? 3 : 1,
                maxLines: multiline ? 8 : 3,
                decoration: InputDecoration(hintText: hint),
              ),
      ),
      actions: [
        _dialogAction(ctx, 'Cancel', () => Navigator.pop(ctx)),
        _dialogAction(ctx, action, () => Navigator.pop(ctx, c.text), primary: true),
      ],
    ),
  );
}

Widget _dialogAction(BuildContext ctx, String label, VoidCallback onPressed,
    {bool destructive = false, bool primary = false}) {
  if (isIOS(ctx)) {
    return CupertinoDialogAction(
      onPressed: onPressed,
      isDestructiveAction: destructive,
      isDefaultAction: primary && !destructive,
      child: Text(label),
    );
  }
  return primary ? FilledButton(onPressed: onPressed, child: Text(label)) : TextButton(onPressed: onPressed, child: Text(label));
}

class SheetOption<T> {
  const SheetOption(this.value, this.label, {this.icon, this.subtitle, this.destructive = false});
  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;
  final bool destructive;
}

/// Pick one option: CupertinoActionSheet on iPhone, a bottom sheet list on Android.
Future<T?> pickOption<T>(BuildContext context, List<SheetOption<T>> options, {String? title}) {
  if (isIOS(context)) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (final o in options)
            CupertinoActionSheetAction(
              isDestructiveAction: o.destructive,
              onPressed: () => Navigator.pop(ctx, o.value),
              child: Text(o.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (title != null)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
        for (final o in options)
          ListTile(
            leading: o.icon == null ? null : Icon(o.icon),
            title: Text(o.label),
            subtitle: o.subtitle == null ? null : Text(o.subtitle!),
            onTap: () => Navigator.pop(ctx, o.value),
          ),
      ]),
    ),
  );
}

/// Filter capsule. iPhone: filled tint when selected, grey fill otherwise (like Photos/Music).
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.selected, required this.onTap, this.icon, this.onLongPress});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (!isIOS(context)) {
      return GestureDetector(
        onLongPress: onLongPress,
        child: icon == null
            ? ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap(), showCheckmark: false)
            : FilterChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(icon, size: 16),
                label: Text(label),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => onTap(),
              ),
      );
    }
    final accent = CupertinoTheme.of(context).primaryColor;
    final fill = CupertinoDynamicColor.resolve(CupertinoColors.tertiarySystemFill, context);
    final fg = selected ? CupertinoColors.white : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: selected ? accent : fill, borderRadius: BorderRadius.circular(100)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 15, color: fg), const SizedBox(width: 5)],
          Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: fg)),
        ]),
      ),
    );
  }
}
