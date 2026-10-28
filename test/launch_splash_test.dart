import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revue/launch_splash.dart';

Widget app({bool calm = false}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: calm),
        child: LaunchSplash(child: child!),
      ),
      home: const Scaffold(body: Text('home')),
    );

void main() {
  testWidgets('plays, then leaves only the app', (t) async {
    await t.pumpWidget(app());
    expect(find.byType(Image), findsNWidgets(2)); // letter + ribbon on screen
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(Image), findsNWidgets(2)); // still animating
    await t.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a tap skips to the reveal', (t) async {
    await t.pumpWidget(app());
    await t.pump(const Duration(milliseconds: 100));
    final g = await t.startGesture(const Offset(200, 300));
    await g.up();
    await t.pump(); // the restarted animation starts its clock on this frame
    await t.pump(const Duration(milliseconds: 700)); // vs ~1250 ms without the tap
    await t.pump();
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('reduce motion is a short cross-fade', (t) async {
    await t.pumpWidget(app(calm: true));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    expect(find.byType(Image), findsNothing);
  });
}
