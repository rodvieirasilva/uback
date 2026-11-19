import 'package:flutter_test/flutter_test.dart';
import 'package:uback/core/utils/path_sanitizer.dart';

void main() {
  group('PathSanitizer.sanitizeDeviceName', () {
    test('matches spec examples', () {
      expect(PathSanitizer.sanitizeDeviceName("Alice's Phone"), 'alice');
      expect(PathSanitizer.sanitizeDeviceName("Rodrigo's phone"), 'rodrigo');
    });

    test('handles curly apostrophes, case variations, spaces and special chars', () {
      expect(PathSanitizer.sanitizeDeviceName('Rodrigo’s   PHONE!!'), 'rodrigo');
      expect(PathSanitizer.sanitizeDeviceName('Galaxy S23 FE'), 'galaxys23fe');
      expect(PathSanitizer.sanitizeDeviceName('   '), 'android');
      expect(PathSanitizer.sanitizeDeviceName('Phone'), 'android');
    });
  });

  group('PathSanitizer.sanitizeSourceFolder', () {
    test('normalizes camera, screenshots and future buckets', () {
      expect(PathSanitizer.sanitizeSourceFolder('Camera'), 'camera');
      expect(PathSanitizer.sanitizeSourceFolder('Screenshots'), 'screenshots');
      expect(PathSanitizer.sanitizeSourceFolder('WhatsApp Images'), 'whatsapp-images');
      expect(PathSanitizer.sanitizeSourceFolder(''), 'other');
    });
  });

  group('PathSanitizer.buildRelativeRemoteDir', () {
    test('builds {basePath}/{device}/{source}/{YYYY}/{MM}', () {
      final path = PathSanitizer.buildRelativeRemoteDir(
        basePath: 'local/phone',
        deviceFolder: "Rodrigo's Phone",
        sourceFolder: 'Camera',
        createdAt: DateTime(2025, 4, 12),
      );
      expect(path, 'local/phone/rodrigo/camera/2025/04');
    });

    test('handles screenshots, nested whatsapp/recordings subpaths, and slashes', () {
      final ssPath = PathSanitizer.buildRelativeRemoteDir(
        basePath: '/local/phone/',
        deviceFolder: "Alice's phone",
        sourceFolder: 'Screenshots',
        createdAt: DateTime(2023, 11, 5),
      );
      expect(ssPath, 'local/phone/alice/screenshots/2023/11');

      final waPath = PathSanitizer.buildRelativeRemoteDir(
        basePath: 'local/phone',
        deviceFolder: "Rodrigo's Phone",
        sourceFolder: 'whatsapp/sent/videos',
        createdAt: DateTime(2024, 2, 1),
      );
      expect(waPath, 'local/phone/rodrigo/whatsapp/sent/videos/2024/02');

      final recPath = PathSanitizer.buildRelativeRemoteDir(
        basePath: 'local/phone',
        deviceFolder: 'rodrigo',
        sourceFolder: 'recordings',
        createdAt: DateTime(2023, 4, 12),
      );
      expect(recPath, 'local/phone/rodrigo/recordings/2023/04');
    });
  });

  group('PathSanitizer.disambiguateFileName', () {
    test('inserts short hash before extension', () {
      expect(
        PathSanitizer.disambiguateFileName('IMG_0001.jpg', 'a1b2c3d4'),
        'IMG_0001_a1b2c3d4.jpg',
      );
      expect(
        PathSanitizer.disambiguateFileName('archive', 'a1b2c3d4'),
        'archive_a1b2c3d4',
      );
    });
  });

  group('PathSanitizer.formatBytes', () {
    test('formats human-readable byte sizes', () {
      expect(PathSanitizer.formatBytes(0), '0 B');
      expect(PathSanitizer.formatBytes(512), '512 B');
      expect(PathSanitizer.formatBytes(1536), '1.5 KB');
      expect(PathSanitizer.formatBytes(5 * 1024 * 1024), '5.0 MB');
    });
  });
}
