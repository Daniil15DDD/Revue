import 'dart:io';

import 'package:flutter/cupertino.dart';
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
    await tester.pumpWidget(RevueApp(store: store, llm: GemmaLlm(), listenForShares: false));
    await tester.pumpAndSettle();
  }

  testWidgets('empty library explains how to save things', (tester) async {
    await pumpApp(tester);
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.textContaining('Share → Revue'), findsOneWidget);
  });

  testWidgets('cards show, lists filter, item page opens', (tester) async {
    final watch = store.lists.first;
    store.items.addAll([
      Item(
          title: 'Cosmos documentary',
          url: 'https://youtu.be/cosmos',
          kind: Kind.video,
          source: 'YouTube · PBS',
          listId: watch.id,
          rating: 4),
      Item(title: 'Best tacos in town', kind: Kind.place),
    ]);
    await pumpApp(tester);
    expect(find.text('Cosmos documentary'), findsOneWidget);
    expect(find.text('Best tacos in town'), findsOneWidget);

    await tester.tap(find.text('${watch.emoji} ${watch.name}'));
    await tester.pumpAndSettle();
    expect(find.text('Best tacos in town'), findsNothing);

    await tester.tap(find.text('Cosmos documentary'));
    await tester.pumpAndSettle();
    expect(find.text('Watch'), findsOneWidget);
    expect(find.text('YOUR REVIEW'), findsOneWidget);
  });

  testWidgets('assistant answers from the library without a model', (tester) async {
    store.items.add(Item(title: 'Ramen place in Shibuya', kind: Kind.place));
    await pumpApp(tester);
    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    expect(find.text('Get model'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'where was that ramen?');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.textContaining('• Ramen place in Shibuya'), findsOneWidget);
  });

  testWidgets('iPhone gets native Cupertino UI', variant: TargetPlatformVariant.only(TargetPlatform.iOS), (tester) async {
    store.items.add(Item(title: 'Cosmos documentary', url: 'https://youtu.be/c', kind: Kind.video));
    await pumpApp(tester);
    expect(find.byType(CupertinoTabBar), findsOneWidget);
    expect(find.byType(CupertinoSliverNavigationBar), findsOneWidget);
    expect(find.byType(CupertinoSearchTextField), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.text('Cosmos documentary'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoListSection), findsWidgets);
    expect(find.byType(CupertinoSwitch), findsOneWidget);
    expect(find.text('Watched'), findsOneWidget);
  });

  testWidgets('appearance setting switches the app to dark', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    expect(store.appearance, 'dark');
  });

  testWidgets('settings lists downloadable on-device models', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Download'), findsNWidgets(modelOptions.length));
  });
}
