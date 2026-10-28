import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revue/ai.dart';
import 'package:revue/main.dart';
import 'package:revue/models.dart';
import 'package:revue/store.dart';

void main() {
  late Directory dir;
  late Store store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('revue_widget');
    store = Store(dir, ocr: (_) async => '');
    await store.load();
  });
  tearDown(() => dir.delete(recursive: true));

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 4200); // tall phone so everything is laid out
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RevueApp(store: store, llm: GemmaLlm(), listenForShares: false));
    await tester.pumpAndSettle();
  }

  testWidgets('empty library invites you to create a list', (tester) async {
    await pumpApp(tester);
    expect(find.text('Start your first list'), findsOneWidget);
    expect(find.text('Create a List'), findsOneWidget);
  });

  testWidgets('list cards open a list grouped by status, then an item', (tester) async {
    final anime = (await tester.runAsync(() => store.addList('Anime')))!; // real file IO needs the real clock
    store.items.addAll([
      Item(title: 'Frieren', kind: Kind.show, listId: anime.id, total: 28, seasons: [28])..setProgress(3),
      Item(title: 'Dune', kind: Kind.book, listId: anime.id, url: 'https://openlibrary.org/x'),
      Item(title: 'Loose link', kind: Kind.link),
    ]);
    await pumpApp(tester);
    expect(find.text('Anime'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('Inbox'), findsOneWidget); // the loose link

    await tester.tap(find.text('Anime'));
    await tester.pumpAndSettle();
    expect(find.text('WATCHING'), findsOneWidget);
    expect(find.text('PLAN TO READ'), findsOneWidget);
    expect(find.text('S1 · E3'), findsOneWidget);

    await tester.tap(find.text('Frieren'));
    await tester.pumpAndSettle();
    expect(find.text('Season 1 · Episode 3'), findsOneWidget);
    await tester.tap(find.text('Next Episode'));
    await tester.pumpAndSettle();
    expect(find.text('Season 1 · Episode 4'), findsOneWidget);
    await tester.tap(find.text('Watched')); // status pill
    await tester.pumpAndSettle();
    expect(store.items.first.status, Status.finished);
  });

  testWidgets('+ menu offers the four ways to add', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.bySemanticsLabel('Add'));
    await tester.pumpAndSettle();
    for (final t in ['Create a List', 'Find a Show or Book', 'Import', 'Write a Thought']) {
      expect(find.text(t), findsWidgets);
    }
    await tester.tap(find.bySemanticsLabel('Close').last);
    await tester.pumpAndSettle();
  });

  testWidgets('assistant answers from the library without a model', (tester) async {
    store.items.add(Item(title: 'Ramen place in Shibuya', kind: Kind.place));
    await pumpApp(tester);
    await tester.tap(find.bySemanticsLabel('Ask'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'where was that ramen?');
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('• Ramen place in Shibuya'), findsOneWidget);
  });

  testWidgets('stats page counts everything', (tester) async {
    store.items.addAll([Item(title: 'a', kind: Kind.book), Item(title: 'b', kind: Kind.show)]);
    await pumpApp(tester);
    await tester.tap(find.bySemanticsLabel('Stats'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
    expect(find.text('things in your library'), findsOneWidget);
  });

  testWidgets('settings: appearance switches to dark; models listed', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Get'), findsNWidgets(modelOptions.length));
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
  });
}
