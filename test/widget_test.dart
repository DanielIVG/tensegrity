import 'package:flutter_test/flutter_test.dart';

import 'package:tensegrity/main.dart';

void main() {
  testWidgets('Muestra la pantalla de la balanza', (WidgetTester tester) async {
    await tester.pumpWidget(const TensegrityApp());

    expect(find.text('Balanza de tensegridad'), findsOneWidget);
    expect(find.text('Conectar'), findsOneWidget);
    expect(find.text('Desconectado'), findsOneWidget);
  });
}
