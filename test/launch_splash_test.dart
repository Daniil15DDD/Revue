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
    expect(find.byKey(const ValueKey('launch-splash')), findsOneWidget); // splash on screen
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('launch-splash')), findsOneWidget); // still animating
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('launch-splash')), findsNothing);
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
    expect(find.byKey(const ValueKey('launch-splash')), findsNothing);
  });

  testWidgets('reduce motion is a short cross-fade', (t) async {
    await t.pumpWidget(app(calm: true));
    await t.pump(); // the clock starts after the first frame
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    expect(find.byKey(const ValueKey('launch-splash')), findsNothing);
  });
}
