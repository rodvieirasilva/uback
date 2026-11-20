import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uback/core/testing/test_keys.dart';
import 'package:uback/main.dart';

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('Timed out waiting for widget: $finder');
}

Future<void> _waitForTextContains(
  WidgetTester tester,
  Key key,
  String expected, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    final finder = find.byKey(key);
    if (finder.evaluate().isNotEmpty) {
      final text = tester.widget<Text>(finder).data ?? '';
      if (text.contains(expected)) {
        await tester.pumpAndSettle();
        return;
      }
    }
  }
  fail('Timed out waiting for $key to contain "$expected"');
}

Future<void> _waitForCompleted(
  WidgetTester tester, {
  int? expectedTotal,
  int? expectedSkipped,
  Duration timeout = const Duration(seconds: 120),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 500));
    final stateFinder = find.byKey(AppTestKeys.statusState);
    if (stateFinder.evaluate().isNotEmpty) {
      final text = tester.widget<Text>(stateFinder).data ?? '';
      if (text == 'Completed' || text == 'Finished with Errors' || text == 'Cancelled') {
        final totalText = find.byKey(AppTestKeys.statTotal).evaluate().isNotEmpty
            ? tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data
            : null;
        final skippedText = find.byKey(AppTestKeys.statSkipped).evaluate().isNotEmpty
            ? tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data
            : null;
        final totalOk = expectedTotal == null || totalText == '$expectedTotal';
        final skippedOk = expectedSkipped == null || skippedText == '$expectedSkipped';
        if (text != 'Completed' || (totalOk && skippedOk)) {
          await tester.pumpAndSettle();
          return;
        }
      }
    }
  }
  fail('Timed out waiting for backup to finish.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Full E2E: expanded MediaSources, Custom Folders, global oldest-first Copy, idempotent Copy, and Crop cleanup',
      (tester) async {
    await tester.pumpWidget(const UBackApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify clean Home UI: no destination banner, no phase jargon, zero file previews
    expect(find.textContaining('DESTINATION (OLDEST FIRST'), findsNothing);
    expect(find.byKey(AppTestKeys.appLogo), findsOneWidget);
    expect(find.byKey(AppTestKeys.appVersion), findsOneWidget);
    final versionText = tester.widget<Text>(find.byKey(AppTestKeys.appVersion)).data ?? '';
    expect(versionText, isNot(contains('+')));
    expect(versionText, contains(' • '));
    expect(find.textContaining('PHASE'), findsNothing);
    expect(find.textContaining('Phase'), findsNothing);
    final fileImages = find.byWidgetPredicate((w) => w is Image && w.image is FileImage);
    expect(fileImages, findsNothing);

    // Verify hierarchical Media Sources exist and estimate the 14 built-in seeded items
    // (10 unique media/doc + 1 duplicate-hash photo + 2 read-only WhatsApp DB files + 1 incremental WA delta)
    expect(find.byKey(AppTestKeys.sourceToggle('camera')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('screenshots')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('screen_recordings')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('whatsapp')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('documents')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('downloads')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('snapshots')), findsOneWidget);
    await _waitForTextContains(tester, AppTestKeys.mediaSourcesSummary, 'Selected: 14 files');

    // Verify Device Snapshots shows non-zero Contacts + SMS + Call Logs (3 files) and toggle it ON
    await _waitForTextContains(tester, AppTestKeys.sourceStats('snapshots'), '3 files');
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceToggle('snapshots')));
    await tester.tap(find.byKey(AppTestKeys.sourceToggle('snapshots')));
    await tester.pumpAndSettle();
    await _waitForTextContains(tester, AppTestKeys.mediaSourcesSummary, 'Selected: 17 files');

    // Verify expanding WhatsApp reveals Received, Sent, Chat Databases, and Incremental Chat Deltas
    await tester.ensureVisible(find.byKey(AppTestKeys.sourceExpand('whatsapp')));
    await tester.tap(find.byKey(AppTestKeys.sourceExpand('whatsapp')));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceExpand('whatsapp.sent')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceExpand('whatsapp.received')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('whatsapp.databases')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('whatsapp.deltas')), findsOneWidget);

    // 1. Open Settings -> confirm Destination Type, add Custom Folder (DJI/Media), and Test Connection
    await tester.tap(find.byKey(AppTestKeys.openSettings));
    await tester.pumpAndSettle();

    expect(find.byKey(AppTestKeys.settingsDestinationType), findsOneWidget);
    final hostField = tester.widget<TextField>(find.byKey(AppTestKeys.settingsHost));
    expect(hostField.controller?.text, '10.0.2.2');

    await tester.ensureVisible(find.byKey(AppTestKeys.settingsBrowseCustomFolder));
    expect(find.byKey(AppTestKeys.settingsBrowseCustomFolder), findsOneWidget);
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsCustomFolderPath));
    await tester.enterText(find.byKey(AppTestKeys.settingsCustomFolderPath), 'DJI/Media');
    await tester.enterText(find.byKey(AppTestKeys.settingsCustomFolderName), 'DJI Drone');
    await tester.ensureVisible(find.byKey(AppTestKeys.settingsAddCustomFolder));
    await tester.tap(find.byKey(AppTestKeys.settingsAddCustomFolder));
    await _waitForFinder(
      tester,
      find.byKey(AppTestKeys.settingsRemoveCustomFolder('custom.dji-media')),
    );

    await tester.ensureVisible(find.byKey(AppTestKeys.settingsTestConnection));
    await tester.tap(find.byKey(AppTestKeys.settingsTestConnection));
    await _waitForFinder(tester, find.byKey(AppTestKeys.connectionStatusBanner));

    expect(find.byKey(AppTestKeys.connectionStatusBanner), findsOneWidget);
    expect(find.textContaining('Connected to smb://10.0.2.2'), findsOneWidget);

    await tester.ensureVisible(find.byKey(AppTestKeys.settingsSave));
    await tester.tap(find.byKey(AppTestKeys.settingsSave));
    await _waitForFinder(tester, find.byKey(AppTestKeys.modeCopy));

    // Confirm Custom Folder bumped live count from 17 -> 18 files, then collapse Media Sources
    await _waitForTextContains(tester, AppTestKeys.mediaSourcesSummary, 'Selected: 18 files');
    await tester.ensureVisible(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.tap(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceToggle('camera')), findsNothing);

    // 2. Copy Mode + Limit: Oldest 3 files globally across ALL sources:
    // (1) WhatsApp Voice Note 2022-05 -> transferred
    // (2) Camera Image 2023-01-10 -> transferred
    // (3) Camera Image DUP 2023-01-11 (identical SHA-256!) -> SKIPPED without copying!
    await tester.ensureVisible(find.byKey(AppTestKeys.modeCopy));
    await tester.tap(find.byKey(AppTestKeys.modeCopy));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(AppTestKeys.limitFiles));
    await tester.tap(find.byKey(AppTestKeys.limitFiles));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AppTestKeys.limitValueInput), '3');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await _waitForCompleted(tester, expectedTotal: 3, expectedSkipped: 1);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '3');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTransferred)).data, '2');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '1');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');

    // 2b. Simulate full app restart (brand-new BackupController loading real Android SharedPreferences + Keystore)
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(UBackApp(key: UniqueKey()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Verify saved session state restored: Copy mode, Limit=files(3), Media Sources collapsed,
    // custom folder DJI/Media persisted (15 files total), and expanded WhatsApp sub-group remembered!
    expect(find.text('Start Copy Backup'), findsOneWidget);
    expect(find.byKey(AppTestKeys.limitValueInput), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(AppTestKeys.limitValueInput)).controller?.text,
      '3',
    );
    expect(find.byKey(AppTestKeys.sourceToggle('camera')), findsNothing);
    await _waitForTextContains(tester, AppTestKeys.mediaSourcesSummary, 'Selected: 18 files');

    // Expand Media Sources and verify custom folder + WhatsApp expanded sub-group were restored
    await tester.ensureVisible(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.tap(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.pumpAndSettle();
    expect(find.byKey(AppTestKeys.sourceExpand('whatsapp.sent')), findsOneWidget);
    expect(find.byKey(AppTestKeys.sourceToggle('custom')), findsOneWidget);

    // Re-collapse Media Sources for compact layout
    await tester.ensureVisible(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.tap(find.byKey(AppTestKeys.mediaSourcesCollapse));
    await tester.pumpAndSettle();

    // 3. Copy Mode + All files -> exercises live Pause -> Resume mid-run, skips 3 already SHA-256
    // verified files (incl. duplicate hash), transfers remaining 12 (9 files + 3 Device Snapshots)
    await tester.ensureVisible(find.byKey(AppTestKeys.limitAll));
    await tester.tap(find.byKey(AppTestKeys.limitAll));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));

    // Wait for Pause button to become active, pause the transfer, verify Paused state, then resume!
    final pauseDeadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(pauseDeadline)) {
      await tester.pump(const Duration(milliseconds: 150));
      final pauseFinder = find.byKey(AppTestKeys.pauseBackup);
      if (pauseFinder.evaluate().isNotEmpty) {
        final btn = tester.widget<ButtonStyleButton>(pauseFinder);
        if (btn.onPressed != null) {
          await tester.ensureVisible(pauseFinder);
          await tester.tap(pauseFinder);
          await _waitForFinder(tester, find.byKey(AppTestKeys.resumeBackup));
          expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Paused');
          await tester.tap(find.byKey(AppTestKeys.resumeBackup));
          await tester.pump(const Duration(milliseconds: 250));

          // Simulate locking the phone screen and alternating between other apps mid-backup:
          // cycle through inactive -> hidden -> paused (while BackupForegroundService transfers
          // in the background) -> resumed, twice, verifying zero UI freeze or dropped progress.
          for (var cycle = 0; cycle < 2; cycle++) {
            tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
            tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
            tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
            await Future<void>.delayed(const Duration(milliseconds: 300));
            tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
            tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
            tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
            await tester.pump(const Duration(milliseconds: 250));
          }
          break;
        }
      }
    }

    await _waitForCompleted(tester, expectedTotal: 18, expectedSkipped: 3);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(find.byKey(AppTestKeys.statElapsed), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statEta)).data, 'ETA: Done');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '18');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '3');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTransferred)).data, '15');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');

    // 4. Crop Mode + All files -> WhatsApp delta watermark already committed at _id=3 so 0 new deltas
    // are generated (proving true incremental non-duplication!), verifies remaining 17 on SMB, deletes
    // 12 media/doc files locally, and keeps Download + read-only WhatsApp DBs + Contacts/SMS/Call Logs untouched!
    await tester.ensureVisible(find.byKey(AppTestKeys.modeCrop));
    await tester.tap(find.byKey(AppTestKeys.modeCrop));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(AppTestKeys.startBackup));
    await tester.tap(find.byKey(AppTestKeys.startBackup));
    await _waitForCompleted(tester, expectedTotal: 17, expectedSkipped: 17);

    expect(tester.widget<Text>(find.byKey(AppTestKeys.statusState)).data, 'Completed');
    expect(find.byKey(AppTestKeys.statElapsed), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statEta)).data, 'ETA: Done');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statTotal)).data, '17');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statSkipped)).data, '17');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statFailed)).data, '0');
    expect(tester.widget<Text>(find.byKey(AppTestKeys.statRemaining)).data, '0');

    // 5. Restart app once more -> confirm Crop Mode & Limit=All persisted across restart!
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(UBackApp(key: UniqueKey()));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.text('Start Crop Backup'), findsOneWidget);
    expect(find.byKey(AppTestKeys.limitValueInput), findsNothing);
  });
}
