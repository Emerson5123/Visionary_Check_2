import 'package:flutter/material.dart';
import 'tts_service.dart';

/// Gestiona el sistema de accesibilidad tipo VoiceOver:
/// - 1 toque  → enfoca el elemento y lo anuncia por voz
/// - 2 toques → activa el elemento enfocado
class AccessibilityService extends ChangeNotifier {
  static final AccessibilityService _instance = AccessibilityService._internal();
  factory AccessibilityService() => _instance;
  AccessibilityService._internal();

  final TTSService _tts = TTSService();

  String? _focusedElementId;
  String? get focusedElementId => _focusedElementId;

  VoidCallback? _focusedAction;
  String _focusedDescription = '';

  Future<void> focusElement({
    required String id,
    required String description,
    required VoidCallback action,
  }) async {
    _focusedElementId   = id;
    _focusedAction      = action;
    _focusedDescription = description;
    notifyListeners();
    await _tts.stop();
    await _tts.speak(description);
  }

  Future<void> activateFocused() async {
    if (_focusedElementId == null || _focusedAction == null) {
      await _tts.speak('Ningún elemento seleccionado. Toca un elemento primero.');
      return;
    }
    await _tts.stop();
    await _tts.speak('Activando $_focusedDescription');
    await Future.delayed(const Duration(milliseconds: 300));
    _focusedAction!();
  }

  void clearFocus() {
    _focusedElementId   = null;
    _focusedAction      = null;
    _focusedDescription = '';
    notifyListeners();
  }

  Future<void> announce(String message) async {
    await _tts.stop();
    await _tts.speak(message);
  }
}