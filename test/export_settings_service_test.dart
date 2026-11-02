import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snap_craft/services/export_settings_service.dart';

class _FailingPreferences implements SharedPreferences {
  _FailingPreferences(this.value);

  final String value;

  @override
  String? getString(String key) => value;

  @override
  Future<bool> setString(String key, String value) async => false;

  @override
  Future<bool> remove(String key) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('folder changes persist and restore in a new instance', () async {
    final settings = ExportSettingsService();
    await settings.load();
    expect(settings.directory, isNull);

    const directory = '/폴더 이름/캡쳐 ';
    await settings.setDirectory(directory);
    expect(settings.directory, directory);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('png_save_directory'), directory);

    final restored = ExportSettingsService();
    await restored.load();
    expect(restored.directory, directory);

    await restored.setDirectory('/다른 폴더');
    final changed = ExportSettingsService();
    await changed.load();
    expect(changed.directory, '/다른 폴더');

    await changed.setDirectory(null);
    expect(changed.directory, isNull);
    expect(preferences.containsKey('png_save_directory'), isFalse);
    final cleared = ExportSettingsService();
    await cleared.load();
    expect(cleared.directory, isNull);
  });

  test('blank folders load as unset and clear the stored preference', () async {
    SharedPreferences.setMockInitialValues({'png_save_directory': '  '});
    final settings = ExportSettingsService();
    await settings.load();
    expect(settings.directory, isNull);
    await settings.setDirectory('/캡쳐');
    await settings.setDirectory(' \t ');
    expect(settings.directory, isNull);
    expect(
      (await SharedPreferences.getInstance()).containsKey('png_save_directory'),
      isFalse,
    );
  });

  test('failed changes and clearing preserve the current folder', () async {
    final settings = ExportSettingsService(
      preferences: _FailingPreferences('/기존 폴더'),
    );
    await settings.load();

    await expectLater(settings.setDirectory('/새 폴더'), throwsStateError);
    expect(settings.directory, '/기존 폴더');
    await expectLater(settings.setDirectory(null), throwsStateError);
    expect(settings.directory, '/기존 폴더');
  });
}
