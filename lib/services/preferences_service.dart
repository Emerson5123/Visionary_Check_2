import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;
  PreferencesService._internal();

  static const String _keyVoiceEnabled = 'voice_enabled';
  static const String _keyVolume       = 'voice_volume';
  static const String _keySpeechRate   = 'speech_rate';
  static const String _keyLanguage     = 'voice_language';

  // ── Guardar ──────────────────────────────────────────────────────────────
  Future<void> saveVoiceEnabled(bool value)  async => (await SharedPreferences.getInstance()).setBool(_keyVoiceEnabled, value);
  Future<void> saveVolume(double value)      async => (await SharedPreferences.getInstance()).setDouble(_keyVolume, value);
  Future<void> saveSpeechRate(double value)  async => (await SharedPreferences.getInstance()).setDouble(_keySpeechRate, value);
  Future<void> saveLanguage(String value)    async => (await SharedPreferences.getInstance()).setString(_keyLanguage, value);

  // ── Cargar todas a la vez ────────────────────────────────────────────────
  Future<AppPreferences> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    return AppPreferences(
      voiceEnabled: prefs.getBool(_keyVoiceEnabled)   ?? true,
      volume:       prefs.getDouble(_keyVolume)        ?? 1.0,
      speechRate:   prefs.getDouble(_keySpeechRate)    ?? 0.5,
      language:     prefs.getString(_keyLanguage)      ?? 'es-ES',
    );
  }

  // ── Resetear ─────────────────────────────────────────────────────────────
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyVoiceEnabled);
    await prefs.remove(_keyVolume);
    await prefs.remove(_keySpeechRate);
    await prefs.remove(_keyLanguage);
  }
}

class AppPreferences {
  final bool   voiceEnabled;
  final double volume;
  final double speechRate;
  final String language;

  const AppPreferences({
    required this.voiceEnabled,
    required this.volume,
    required this.speechRate,
    required this.language,
  });
}