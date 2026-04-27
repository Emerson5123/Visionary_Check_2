import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/database_service.dart';
import 'services/preferences_service.dart';
import 'services/tts_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('🚀 Inicializando Visionary Check...');

  final dbService = DatabaseService();
  try {
    await dbService.database;
    print('✅ Base de datos inicializada');
  } catch (e) {
    print('❌ Error BD: $e');
  }

  try {
    final saved = await PreferencesService().loadAll();
    final tts   = TTSService();
    await tts.setVoiceEnabled(saved.voiceEnabled);
    await tts.setVolume(saved.volume);
    await tts.setSpeechRate(saved.speechRate);
    await tts.setLanguage(saved.language);
    print('✅ Preferencias cargadas');
  } catch (e) {
    print('❌ Error cargando preferencias: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visionary Cash Check',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const HomeScreen(),
    );
  }
}