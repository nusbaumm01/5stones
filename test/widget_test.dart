import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:five_stones/main.dart';

void main() {
  testWidgets('home screen offers both game modes', (tester) async {
    await tester.pumpWidget(const FiveStonesApp());
    expect(find.text('5Stones'), findsOneWidget);
    expect(find.text('Two players'), findsOneWidget);
    expect(find.text('Play the computer'), findsOneWidget);
  });

  testWidgets('choosing a mode opens the game screen', (tester) async {
    await tester.pumpWidget(const FiveStonesApp());
    await tester.tap(find.byKey(const Key('play-computer')));
    await tester.pumpAndSettle();
    expect(find.text('Versus computer'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
