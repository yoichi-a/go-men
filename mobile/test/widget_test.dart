import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';

void main() {
  testWidgets('Go-men app renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const GoMenApp());
    await tester.pumpAndSettle();

    expect(find.text('Go-men'), findsOneWidget);
  });
}
