import 'package:aptiqr/widgets/qr_scanner_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets(
        'Unsupported scanner on $platform cancels without a plugin call',
        (tester) async {
      String? result = 'not completed';
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showQrScanner(context);
              },
              child: const Text('Scan'),
            ),
          );
        }),
      ));
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      expect(find.text('Scan on a mobile device'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }
}
