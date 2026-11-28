import 'package:shared_preferences/shared_preferences.dart';

class ExportSettingsService {
  ExportSettingsService({this._preferences});

  static const _directoryKey = 'png_save_directory';
  static const _autoSaveKey = 'png_auto_save_on_capture';

  SharedPreferences? _preferences;
  String? _directory;
  bool _autoSave = false;

  String? get directory => _directory;
  bool get autoSave => _autoSave;

  Future<SharedPreferences> _getPreferences() async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<void> load() async {
    final preferences = await _getPreferences();
    _directory = _normalize(preferences.getString(_directoryKey));
    _autoSave = _directory != null && (preferences.getBool(_autoSaveKey) ?? false);
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
    if (next == null && _autoSave) {
      await preferences.setBool(_autoSaveKey, false);
      _autoSave = false;
    }
  }

  Future<void> setAutoSave(bool enabled) async {
    if (enabled && _directory == null) {
      throw StateError('자동 저장을 켜려면 먼저 저장 폴더를 지정하세요.');
    }
    final preferences = await _getPreferences();
    final saved = await preferences.setBool(_autoSaveKey, enabled);
    if (!saved) {
      throw StateError('자동 저장 설정을 저장하지 못했습니다.');
    }
    _autoSave = enabled;
  }

  String? _normalize(String? directory) =>
      directory == null || directory.trim().isEmpty ? null : directory;
}
