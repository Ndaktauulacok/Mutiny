import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mutiny/ui/glass.dart';

void main() {
  Future<NavigatorState> pumpTwoPages(WidgetTester tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: const ColoredBox(color: Colors.black, child: Center(child: Text('first'))),
    ));
    key.currentState!.push(FadeRoute(const ColoredBox(color: Colors.black, child: Center(child: Text('second')))));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    return key.currentState!;
  }

  testWidgets('swiping from the left edge goes back', (tester) async {
    await pumpTwoPages(tester);
    await tester.dragFrom(const Offset(5, 300), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
    expect(find.text('first'), findsOneWidget);
  });

  testWidgets('a short swipe snaps back and stays', (tester) async {
    final nav = await pumpTwoPages(tester);
    final g = await tester.startGesture(const Offset(5, 300));
    await g.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await g.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 400));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    expect(nav.userGestureInProgress, isFalse);
  });

  testWidgets('dragging in the middle of the page does not go back', (tester) async {
    await pumpTwoPages(tester);
    await tester.dragFrom(const Offset(300, 300), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
  });
}
