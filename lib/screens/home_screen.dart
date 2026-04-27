import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/accessible_widget.dart';
import '../widgets/custom_app_bar.dart';
import '../services/accessibility_service.dart';
import '../services/tts_service.dart';
import '../services/permission_service.dart';
import '../services/bill_detection_service.dart';
import '../services/bill_repository.dart';
import '../models/bill_record.dart';
import '../theme/app_theme.dart';
import 'package:uuid/uuid.dart';
import 'result_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'camara_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TTSService           _tts               = TTSService();
  final AccessibilityService _accessibility     = AccessibilityService();
  final PermissionService    _permissionService = PermissionService();
  final BillDetectionService _detectionService  = BillDetectionService();
  final BillRepository       _billRepository    = BillRepository();
  final ImagePicker          _imagePicker       = ImagePicker();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _accessibility.clearFocus();
    _welcomeAnnouncement();
  }

  void _welcomeAnnouncement() async {
    await Future.delayed(const Duration(milliseconds: 500));
    await _tts.speak(
      'Bienvenido a Visionary Cash Check. '
          'Toca un elemento una vez para escuchar qué es. '
          'Toca dos veces para activarlo.',
    );
  }

  void _openCamera() {
    if (_isProcessing) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => const CameraScreen()));
  }

  Future<void> _openGallery() async {
    if (_isProcessing) return;
    final permResult = await _permissionService.checkAndRequestPhotos();
    if (permResult == PermissionResult.permanentlyDenied) {
      await _tts.speak('Permiso de galería denegado. Ve a Configuración del teléfono.');
      await _permissionService.openSettings();
      return;
    }
    if (permResult != PermissionResult.granted) {
      await _tts.speak('Se necesita permiso para acceder a la galería.');
      return;
    }
    try {
      await _tts.speak('Abriendo galería de fotos...');
      final XFile? image = await _imagePicker.pickImage(
          source: ImageSource.gallery, imageQuality: 95);
      if (image == null) { await _tts.speak('No se seleccionó ninguna imagen.'); return; }

      setState(() => _isProcessing = true);
      await _tts.speak('Analizando billete...');
      final analysis = await _detectionService.analyzeBill(image.path);

      await _billRepository.insertBill(BillRecord(
        id: const Uuid().v4(), date: DateTime.now(), imagePath: image.path,
        isAuthentic: analysis.isAuthentic && analysis.hasBilletFeatures,
        confidence: analysis.confidencePercentage,
        denomination: analysis.denomination, currency: analysis.currency,
      ));
      await _provideFeedback(analysis);
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ResultScreen(
          imagePath: image.path,
          isAuthentic: analysis.isAuthentic && analysis.hasBilletFeatures,
          confidence: analysis.confidencePercentage,
          denomination: analysis.denomination,
          currency: analysis.currency, details: analysis.details,
        )));
      }
    } catch (e) {
      await _tts.speak('Error al procesar la imagen.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _provideFeedback(BillAnalysis analysis) async {
    final label = analysis.currency == 'USD' ? 'dólar estadounidense'
        : analysis.currency == 'ECU' ? 'billete ecuatoriano' : 'billete';
    if (!analysis.hasBilletFeatures) {
      await _tts.speak('No se detectó un billete. Asegúrate de usar una foto clara.');
    } else if (analysis.isAuthentic) {
      await _tts.speak('¡Billete auténtico! Es un $label de ${analysis.denomination}. '
          'Confianza ${analysis.confidencePercentage}.');
    } else {
      await _tts.speak('Advertencia: este $label podría ser sospechoso. Verifica manualmente.');
    }
  }

  void _openHistory() => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
  void _openSettings() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: CustomAppBar(
        title: 'Visionary Cash Check',
        onHistoryPressed: _openHistory,
        onSettingsPressed: _openSettings,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [

                // ── Hero card ──────────────────────────────────────────────
                AccessibleWidget(
                  description: 'Ícono principal. Esta aplicación verifica billetes auténticos.',
                  onActivate: () => _tts.speak(
                      'Visionary Cash Check verifica la autenticidad de billetes. '
                          'Usa Capturar Foto o Galería para comenzar.'),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withOpacity(0.35),
                          blurRadius: 20, offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Ícono billete estilo BilletesMx
                        Container(
                          width: 90, height: 90,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryDark,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(Icons.crop_landscape,
                                  color: AppTheme.textOnPrimary, size: 52),
                              Positioned(
                                child: Container(
                                  width: 22, height: 22,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: AppTheme.textOnPrimary, width: 2),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Verificar Billete',
                          style: TextStyle(
                            color: AppTheme.textOnPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Captura o selecciona una foto\npara verificar su autenticidad',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textOnPrimary.withOpacity(0.85),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Instrucción accesibilidad ─────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '1 toque = escuchar  •  2 toques = activar',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Botón Capturar Foto ────────────────────────────────────
                AccessibleButton(
                  description: 'Botón Capturar Foto. Abre la cámara para escanear un billete.',
                  label: 'Capturar Foto',
                  onActivate: _openCamera,
                  backgroundColor: AppTheme.primary,
                  textColor: AppTheme.textOnPrimary,
                  icon: Icons.camera_alt,
                  height: 58,
                  enabled: !_isProcessing,
                ),

                const SizedBox(height: 14),

                // ── Botón Galería ──────────────────────────────────────────
                AccessibleButton(
                  description: 'Botón Seleccionar de Galería. Elige una foto existente para verificar.',
                  label: 'Seleccionar de Galería',
                  onActivate: _openGallery,
                  backgroundColor: AppTheme.surface,
                  textColor: AppTheme.primary,
                  icon: Icons.photo_library_outlined,
                  height: 54,
                  enabled: !_isProcessing,
                ),

                const SizedBox(height: 14),

                // ── Botón Historial ────────────────────────────────────────
                AccessibleButton(
                  description: 'Botón Ver Historial. Muestra las verificaciones anteriores.',
                  label: 'Ver Historial',
                  onActivate: _openHistory,
                  backgroundColor: AppTheme.surface,
                  textColor: AppTheme.textSecondary,
                  icon: Icons.history,
                  height: 54,
                  enabled: !_isProcessing,
                ),

                // ── Cargando ───────────────────────────────────────────────
                if (_isProcessing) ...[
                  const SizedBox(height: 24),
                  Column(
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 12),
                      Text('Analizando imagen...',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                    ],
                  ),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}