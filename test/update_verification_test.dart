import 'package:flutter_test/flutter_test.dart';
import 'package:snap_craft/services/update_installer_macos.dart';
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
        MacUpdateInstaller.parseTeamIdentifier(
          'Identifier=a.b\nTeamIdentifier=ABCDE12345\n',
        ),
        'ABCDE12345',
      );
    });

    test('treats ad-hoc "not set" and missing as no team', () {
      expect(
        MacUpdateInstaller.parseTeamIdentifier('TeamIdentifier=not set\n'),
        isNull,
      );
      expect(
        MacUpdateInstaller.parseTeamIdentifier('Signature=adhoc\n'),
        isNull,
      );
    });
  });

  group('validateTeamIdentifiers', () {
    test('allows update when both are ad-hoc (no team)', () {
      expect(
        () => MacUpdateInstaller.validateTeamIdentifiers(
          current: null,
          next: null,
        ),
        returnsNormally,
      );
    });

    test('allows update when current is ad-hoc and next is signed', () {
      expect(
        () => MacUpdateInstaller.validateTeamIdentifiers(
          current: null,
          next: 'ABCDE12345',
        ),
        returnsNormally,
      );
    });

    test('allows update when current is signed and next is ad-hoc release', () {
      expect(
        () => MacUpdateInstaller.validateTeamIdentifiers(
          current: 'ABCDE12345',
          next: null,
        ),
        returnsNormally,
      );
    });

    test('allows update when both teams match', () {
      expect(
        () => MacUpdateInstaller.validateTeamIdentifiers(
          current: 'ABCDE12345',
          next: 'ABCDE12345',
        ),
        returnsNormally,
      );
    });

    test('rejects update when teams differ', () {
      expect(
        () => MacUpdateInstaller.validateTeamIdentifiers(
          current: 'ABCDE12345',
          next: 'XYZ9876543',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
