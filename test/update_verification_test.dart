import 'package:flutter_test/flutter_test.dart';
import 'package:snap_craft/services/update_service.dart';

void main() {
  const hashA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const hashB =
      'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

  group('parseChecksum', () {
    const sums =
        '$hashA  SnapCraft-macOS.zip\n$hashB *SnapCraft-Windows-x64.zip\n';

    test('finds a text-mode and a binary-mode entry', () {
      expect(UpdateService.parseChecksum(sums, 'SnapCraft-macOS.zip'), hashA);
      expect(
        UpdateService.parseChecksum(sums, 'SnapCraft-Windows-x64.zip'),
        hashB.toLowerCase(),
      );
    });

    test('returns null for a missing file or a malformed hash', () {
      expect(UpdateService.parseChecksum(sums, 'other.zip'), isNull);
      expect(
        UpdateService.parseChecksum(
          'abc123  SnapCraft-macOS.zip',
          'SnapCraft-macOS.zip',
        ),
        isNull,
      );
    });

    test('does not match a file name that only ends the same way', () {
      expect(
        UpdateService.parseChecksum(
          '$hashA  x-SnapCraft-macOS.zip',
          'SnapCraft-macOS.zip',
        ),
        isNull,
      );
    });
  });

  group('parseTeamIdentifier', () {
    test('reads the team id', () {
      expect(
        UpdateService.parseTeamIdentifier(
          'Identifier=a.b\nTeamIdentifier=ABCDE12345\n',
        ),
        'ABCDE12345',
      );
    });

    test('treats ad-hoc "not set" and missing as no team', () {
      expect(
        UpdateService.parseTeamIdentifier('TeamIdentifier=not set\n'),
        isNull,
      );
      expect(UpdateService.parseTeamIdentifier('Signature=adhoc\n'), isNull);
    });
  });
}
