import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/backup/backup_planner.dart';
import 'package:uback/core/backup/media_exporter.dart';

BackupItem _item(String id, DateTime date, int sizeBytes, {String source = 'camera'}) {
  return BackupItem(
    id: id,
    fileName: '$id.jpg',
    localPath: '/sdcard/$id.jpg',
    sourceFolder: source,
    sizeBytes: sizeBytes,
    createdAt: date,
    mimeType: 'image/jpeg',
  );
}

void main() {
  final items = [
    _item('newest', DateTime(2025, 6, 1), 300),
    _item('oldest', DateTime(2023, 1, 1), 100),
    _item('middle_ss', DateTime(2024, 3, 1), 200, source: 'screenshots'),
    _item('second', DateTime(2023, 8, 1), 150),
  ];

  test('sorts strictly oldest-first', () {
    final planned = BackupPlanner.plan(items);
    expect(planned.map((e) => e.id).toList(), ['oldest', 'second', 'middle_ss', 'newest']);
  });

  test('applies maxFiles limit on oldest items', () {
    final planned = BackupPlanner.plan(items, limit: const BackupLimit(maxFiles: 2));
    expect(planned.map((e) => e.id).toList(), ['oldest', 'second']);
  });

  test('applies maxBytes limit on oldest items', () {
    // oldest (100) + second (150) = 250 <= 300; adding middle_ss (200) -> 450 > 300
    final planned = BackupPlanner.plan(items, limit: const BackupLimit(maxBytes: 300));
    expect(planned.map((e) => e.id).toList(), ['oldest', 'second']);
  });

  test('never deadlocks when oldest single file exceeds maxBytes', () {
    final planned = BackupPlanner.plan(items, limit: const BackupLimit(maxBytes: 50));
    expect(planned.map((e) => e.id).toList(), ['oldest']);
  });
}
