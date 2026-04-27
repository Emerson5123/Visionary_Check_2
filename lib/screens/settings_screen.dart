import 'package:flutter/material.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/accessible_widget.dart';
import '../services/tts_service.dart';
import '../services/accessibility_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TTSService _tts = TTSService();
  final AccessibilityService _accessibility = AccessibilityService();

  String _selectedLanguage = 'es-ES';
  double _volume           = 1.0;
  double _speechRate       = 0.5;
  bool   _enableVoice      = true;

  @override
  void initState() {
    super.initState();
    _enableVoice = _tts.voiceEnabled;
    _accessibility.clearFocus();
    _announceScreen();
  }

  void _announceScreen() async {
    await Future.delayed(const Duration(milliseconds: 400));
    await _tts.speak(
      'Pantalla de configuración. '
          'Toca un elemento para escucharlo, doble toque para activarlo.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Configuración',
        showBackButton: true,
        onBackPressed: () => Navigator.pop(context),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepPurple.shade900, Colors.deepPurple.shade500],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [

            _sectionTitle('Configuración de Voz'),
            const SizedBox(height: 14),

            AccessibleWidget(
              description: _enableVoice
                  ? 'Interruptor: Voz activada. Doble toque para desactivar.'
                  : 'Interruptor: Voz desactivada. Doble toque para activar.',
              onActivate: () async {
                final newValue = !_enableVoice;
                setState(() => _enableVoice = newValue);
                await _tts.setVoiceEnabled(newValue);
                if (newValue) await _tts.speak('Voz activada');
              },
              child: Card(
                color: Colors.white.withOpacity(0.1),
                child: SwitchListTile(
                  title: const Text('Retroalimentación de Voz', style: TextStyle(color: Colors.white)),
                  value: _enableVoice,
                  onChanged: null,
                  activeColor: Colors.amber,
                ),
              ),
            ),
            const SizedBox(height: 12),

            AccessibleWidget(
              description: 'Control de volumen. Valor actual: ${(_volume * 100).toInt()} por ciento. Doble toque para escuchar.',
              onActivate: () => _tts.speak('Volumen al ${(_volume * 100).toInt()} por ciento.'),
              child: Card(
                color: Colors.white.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Volumen: ${(_volume * 100).toInt()}%',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      Slider(
                        value: _volume,
                        onChanged: (v) => setState(() => _volume = v),
                        onChangeEnd: (v) => _tts.speak('Volumen al ${(v * 100).toInt()} por ciento'),
                        min: 0.0, max: 1.0,
                        activeColor: Colors.amber,
                        inactiveColor: Colors.white.withOpacity(0.3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            AccessibleWidget(
              description: 'Control de velocidad de habla. Valor actual: ${(_speechRate * 100).toInt()} por ciento. Doble toque para escuchar.',
              onActivate: () => _tts.speak('Velocidad al ${(_speechRate * 100).toInt()} por ciento.'),
              child: Card(
                color: Colors.white.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Velocidad: ${(_speechRate * 100).toInt()}%',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      Slider(
                        value: _speechRate,
                        onChanged: (v) => setState(() => _speechRate = v),
                        onChangeEnd: (v) {
                          _tts.setSpeechRate(v);
                          _tts.speak('Velocidad ajustada');
                        },
                        min: 0.1, max: 1.0,
                        activeColor: Colors.amber,
                        inactiveColor: Colors.white.withOpacity(0.3),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
            _sectionTitle('Idioma de Voz'),
            const SizedBox(height: 14),

            AccessibleButton(
              description: 'Idioma Español. ${_selectedLanguage == 'es-ES' ? 'Actualmente seleccionado.' : 'Doble toque para seleccionar.'}',
              label: _selectedLanguage == 'es-ES' ? 'Español ✓' : 'Español',
              onActivate: () {
                setState(() => _selectedLanguage = 'es-ES');
                _tts.setLanguage('es-ES');
                _tts.speak('Idioma cambiado a español');
              },
              backgroundColor: _selectedLanguage == 'es-ES' ? Colors.amber : Colors.white.withOpacity(0.15),
              textColor: _selectedLanguage == 'es-ES' ? Colors.black : Colors.white,
              height: 56,
            ),
            const SizedBox(height: 10),

            AccessibleButton(
              description: 'Idioma Inglés. ${_selectedLanguage == 'en-US' ? 'Actualmente seleccionado.' : 'Doble toque para seleccionar.'}',
              label: _selectedLanguage == 'en-US' ? 'English ✓' : 'English',
              onActivate: () {
                setState(() => _selectedLanguage = 'en-US');
                _tts.setLanguage('en-US');
                _tts.speak('Language changed to English');
              },
              backgroundColor: _selectedLanguage == 'en-US' ? Colors.amber : Colors.white.withOpacity(0.15),
              textColor: _selectedLanguage == 'en-US' ? Colors.black : Colors.white,
              height: 56,
            ),

            const SizedBox(height: 24),
            _sectionTitle('Prueba de Voz'),
            const SizedBox(height: 14),

            AccessibleButton(
              description: 'Botón probar voz. Doble toque para escuchar un mensaje de prueba.',
              label: 'Probar Voz',
              onActivate: () => _tts.speak(
                'Esta es una prueba de voz. El volumen y velocidad están correctamente configurados.',
              ),
              backgroundColor: Colors.teal,
              textColor: Colors.white,
              icon: Icons.volume_up,
              height: 56,
            ),

            const SizedBox(height: 24),
            _sectionTitle('Acerca de la Aplicación'),
            const SizedBox(height: 14),

            AccessibleWidget(
              description: 'Información: Versión 1.0.0. Desarrollado por Nathalia. Año 2026.',
              onActivate: () => _tts.speak('Versión 1.0.0. Desarrollado por Nathalia. Año 2026.'),
              child: Card(
                color: Colors.white.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _infoRow('Versión', '1.0.0'),
                      const SizedBox(height: 10),
                      _infoRow('Desarrollador', 'Nathalia'),
                      const SizedBox(height: 10),
                      _infoRow('Año', '2026'),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return AccessibleWidget(
      description: 'Sección: $title',
      onActivate: () => _tts.speak(title),
      child: Text(title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}