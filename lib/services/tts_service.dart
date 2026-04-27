import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  static final TTSService _instance = TTSService._internal();
  final FlutterTts _flutterTts = FlutterTts();

  bool _voiceEnabled = true;
  bool get voiceEnabled => _voiceEnabled;

  factory TTSService() => _instance;
  TTSService._internal() { _initTTS(); }

  void _initTTS() async {
    await _flutterTts.setLanguage("es-ES");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    if (!_voiceEnabled) return;  // ← NUEVO: respeta el toggle
    try {
      await _flutterTts.speak(text);
    } catch (e) {
      print('⚠️ Error TTS speak: $e');
    }
  }

  Future<void> stop() async {
    try { await _flutterTts.stop(); } catch (e) { print('⚠️ Error TTS stop: $e'); }
  }

  Future<void> setVoiceEnabled(bool enabled) async {
    _voiceEnabled = enabled;
    if (!enabled) await stop();  // ← Para el audio si se desactiva
    print('🔊 Voz ${enabled ? 'activada' : 'desactivada'}');
  }

  Future<void> setLanguage(String l)    async { try { await _flutterTts.setLanguage(l);    } catch (_) {} }
  Future<void> setSpeechRate(double r)  async { try { await _flutterTts.setSpeechRate(r);  } catch (_) {} }
  Future<void> setVolume(double v)      async { try { await _flutterTts.setVolume(v);      } catch (_) {} }
}