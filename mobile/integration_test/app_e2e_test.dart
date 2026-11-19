import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uback/core/testing/test_keys.dart';
import 'package:uback/main.dart';

Future<void> _waitForCompleted(WidgetTester tester, {Duration timeout = const Duration(seconds: 90)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 500));
    final stateFinder = find.byKey(AppTestKeys.statusState);
    if (stateFinder.evaluate().isNotEmpty) {
      final text = tester.widget<Text>(stateFinder).data ?? '';
      if (text == 'Completed' || text == 'Finished with Errors' || text == 'Cancelled') {
        await tester.pumpAndSettle();
        return;
      }
    }
  }
  fail('Timed out waiting for backup to finish.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Full E2E: SMB config, oldest-first limited Copy, idempotent Copy, and Crop cleanup',
      (tester) async {
    await tester.pumpWidget(const UBackApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify app logo + version label exist, and zero media file previews are rendered
    expect(find.byKey(AppTestKeys.appLogo), findsOneWidget);
    expect(find.byKey(AppTestKeys.appVersion), findsOneWidget);
    final fileImages = find.byWidgetPredicate((w) => w is Image && w.image is FileImage);
    expect(fileImages, findsNothing);

    // 1. Open Settings -> confirm compile-time defaults loaded -> Test Connection against real SMB2 server
    await tester.tap(find.byKey(AppTestKeys.openSettings));
    await tester.pumpAndSettle();

    final hostField = tester.widget<TextField>(find.byKey(AppTestKeys.settingsHost));
    expect(hostField.controller?.text, '10.0.2.2');

    await tester.ensureVisible(find.byKey(AppTestKeys.settingsTestConnection));
    await tester.tap(find.byKey(AppTestKeys.settingsTestConnection));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.byKey(AppTestKeys.connectionStatusBanner), findsOneWidget);
    expect(find.textContaining('Connected to smb://10.0.2.2'), findsOneWidget);

    await tester.tap(find.byKey(AppTestKeys.settingsSave));
    await tester.pumpAndSettle();

    // 2. Copy Mode + Limit: Oldest 2 files -> transfers 2 oldest (1 Camera + 1 Screenshot)
    await tester.tap(find.byKey(AppTestKeys.modeCopy));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppTestKeys.limitFiles));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AppTestKeys.limitValueInput), '2');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await _waitForCompleted(tester);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '2');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTransferred)).data, '2');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');

    // 3. Copy Mode + All files -> skips 2 already SHA-256 verified files, transfers remaining 2
    await tester.ensureVisible(find.byKey(AppTestKeys.limitAll));
    await tester.tap(find.byKey(AppTestKeys.limitAll));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await _waitForCompleted(tester);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '4');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '2');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTransferred)).data, '2');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');

    // 4. Crop Mode + All files -> verifies all 4 on SMB and deletes them locally (WhatsApp untouched)
    await tester.ensureVisible(find.byKey(AppTestKeys.modeCrop));
    await tester.tap(find.byKey(AppTestKeys.modeCrop));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await _waitForCompleted(tester);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '4');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '4');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');
  });
}
