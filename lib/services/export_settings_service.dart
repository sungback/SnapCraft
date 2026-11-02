import 'package:shared_preferences/shared_preferences.dart';

class ExportSettingsService {
  ExportSettingsService({this._preferences});

  static const _directoryKey = 'png_save_directory';

  SharedPreferences? _preferences;
  String? _directory;

  String? get directory => _directory;

  Future<SharedPreferences> _getPreferences() async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<void> load() async {
    final preferences = await _getPreferences();
    _directory = _normalize(preferences.getString(_directoryKey));
  }

  Future<void> setDirectory(String? directory) async {
    final next = _normalize(directory);
    final preferences = await _getPreferences();
    final saved = next == null
        ? await preferences.remove(_directoryKey)
        : await preferences.setString(_directoryKey, next);
    if (!saved) {
      throw StateError('PNG 저장 폴더 설정을 저장하지 못했습니다.');
    }
    _directory = next;
  }

  String? _normalize(String? directory) =>
      directory == null || directory.trim().isEmpty ? null : directory;
}
