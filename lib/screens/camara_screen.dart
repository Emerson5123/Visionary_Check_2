import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../widgets/accessible_widget.dart';
import '../widgets/custom_app_bar.dart';
import '../services/bill_detection_service.dart';
import '../services/tts_service.dart';
import '../services/accessibility_service.dart';
import '../services/bill_repository.dart';
import '../services/permission_service.dart';
import '../services/authenticity_detector_v2.dart';
import '../services/hologram_detector.dart';
import '../services/watermark_detector.dart';
import '../services/serial_number_validator.dart';
import '../models/bill_record.dart';
import 'result_screen.dart';

// ─── Intervalo entre frames de análisis (ms) ─────────────────────────────────
const int _kScanIntervalMs = 3000;

// ─── Frames estables requeridos para confirmar detección ─────────────────────
const int _kStableFrames = 2;

class CameraScreen extends StatefulWidget {
  const CameraScreen({Key? key}) : super(key: key);
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {

  // ── Servicios ─────────────────────────────────────────────────────────────
  late CameraController      _cameraController;
  final BillDetectionService _detectionService  = BillDetectionService();
  final TTSService           _tts               = TTSService();
  final AccessibilityService _accessibility     = AccessibilityService();
  final BillRepository       _billRepository    = BillRepository();
  final PermissionService    _permissionService = PermissionService();
  final HologramDetector     _hologramDetector  = HologramDetector();
  final WatermarkDetector    _watermarkDetector = WatermarkDetector();
  final SerialNumberValidator _serialValidator  = SerialNumberValidator();
  final TextRecognizer       _textRecognizer    =
  TextRecognizer(script: TextRecognitionScript.latin);

  // ── Estado cámara / permisos ──────────────────────────────────────────────
  bool      _isInitialized = false;
  bool      _isProcessing  = false;
  bool      _isCameraReady = false;
  String?   _initError;
  _PermState _permState    = _PermState.checking;

  // ── Estado escáner ────────────────────────────────────────────────────────
  Timer?     _scanTimer;
  bool       _scanEnabled  = true;
  int        _stableCount  = 0;
  _ScanPhase _phase        = _ScanPhase.searching;

  // ── Datos en vivo ─────────────────────────────────────────────────────────
  BillAnalysis?           _liveResult;
  List<_LiveFeature>      _liveFeatures = [];
  _BillLiveData?          _liveData;

  // ── Animaciones ───────────────────────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late AnimationController _slideCtrl;
  late Animation<double>   _pulseAnim;
  late Animation<Offset>   _slideAnim;

  // ─────────────────────────────────────────────────────────────────────────
  Color get _frameColor {
    switch (_phase) {
      case _ScanPhase.detected:  return const Color(0xFF4CAF50);
      case _ScanPhase.analyzing: return const Color(0xFF2196F3);
      case _ScanPhase.scanning:  return const Color(0xFFFFCA28);
      default:                   return const Color(0xFFFFB300);
    }
  }

  // ── initState ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _accessibility.clearFocus();

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
            CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));

    _checkAndRequestPermission();
  }

  // ─────────────────────── PERMISOS ────────────────────────────────────────
  Future<void> _checkAndRequestPermission() async {
    setState(() => _permState = _PermState.checking);
    final result = await _permissionService.checkAndRequestCamera();
    switch (result) {
      case PermissionResult.granted:
        setState(() => _permState = _PermState.granted);
        _initializeCamera();
        break;
      case PermissionResult.denied:
        setState(() => _permState = _PermState.denied);
        await _tts.speak('Se necesita permiso de cámara para escanear billetes.');
        break;
      case PermissionResult.permanentlyDenied:
        setState(() => _permState = _PermState.permanentlyDenied);
        await _tts.speak('Permiso denegado. Ve a Configuración y actívalo.');
        break;
      default:
        setState(() => _permState = _PermState.denied);
    }
  }

  // ─────────────────────── CÁMARA ──────────────────────────────────────────
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _initError = 'No se encontró cámara en el dispositivo');
        return;
      }
      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController.initialize();
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _isCameraReady = true;
      });
      await _tts.speak(
          'Escáner automático activado. Coloca el billete frente a la cámara '
              'bien iluminado y centrado.');
      _startScan();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _initError = 'Error al inicializar cámara: $e';
        });
      }
    }
  }

  // ─────────────────────── ESCANEO CONTINUO ────────────────────────────────
  void _startScan() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(
        const Duration(milliseconds: _kScanIntervalMs), (_) => _scanCycle());
  }

  void _stopScan() {
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  Future<void> _scanCycle() async {
    if (_isProcessing || !_isCameraReady || !_scanEnabled) return;
    if (!_cameraController.value.isInitialized) return;

    setState(() {
      _isProcessing = true;
      _phase = _ScanPhase.scanning;
    });

    try {
      final XFile frame = await _cameraController.takePicture();
      final String imagePath = frame.path;

      // ── Leer imagen ──────────────────────────────────────────────
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        setState(() => _phase = _ScanPhase.searching);
        return;
      }

      // ── OCR paralelo ─────────────────────────────────────────────
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await _textRecognizer.processImage(inputImage);
      final ocrText = recognized.text.toUpperCase();

      // ── Análisis en paralelo ─────────────────────────────────────
      final results = await Future.wait([
        AuthenticityDetectorV2.detectPhotocopy(image),
        _hologramDetector.detectHologramFeatures(image),
        _watermarkDetector.detectWatermarks(image),
        _serialValidator.validateSerialNumber(imagePath, ocrText, 'USD'),
      ]);

      final auth     = results[0] as AuthenticityScore;
      final hologram = results[1] as HologramDetectionResult;
      final watermark = results[2] as WatermarkDetectionResult;
      final serial   = results[3] as SerialValidationResult;

      // ── Análisis completo (denominación + autenticidad global) ───
      final analysis = await _detectionService.analyzeBill(imagePath);
      if (!mounted) return;

      // ── Actualizar panel en vivo ─────────────────────────────────
      final liveData = _BillLiveData(
        denomination: analysis.denomination,
        currency: analysis.currency,
        serialNumber: serial.serialNumber,
        serialValid: serial.isValid,
        serialIssues: serial.issues,
        serialConfidence: serial.confidence,
        hasHologram: hologram.hasHologram,
        hologramScore: hologram.score,
        hologramIndicators: hologram.indicators,
        hasWatermark: watermark.hasWatermark,
        watermarkScore: watermark.score,
        watermarkIndicators: watermark.indicators,
        noiseLevel: auth.noiseLevel,
        edgeSharpness: auth.edgeSharpness,
        inkScore: auth.inkScore,
        microtextureScore: auth.microtextureScore,
        isPhotocopy: auth.isLikelyPhotocopy,
        overallConfidence: analysis.confidence,
        isAuthentic: analysis.isAuthentic,
        hasBillFeatures: analysis.hasBilletFeatures,
      );

      _buildLiveFeatures(liveData);

      if (analysis.hasBilletFeatures) {
        _stableCount++;
        setState(() {
          _liveResult = analysis;
          _liveData   = liveData;
          _phase      = _ScanPhase.detected;
        });
        _slideCtrl.forward();

        if (_stableCount >= _kStableFrames) {
          _stopScan();
          setState(() {
            _isCameraReady = false;
            _phase = _ScanPhase.analyzing;
          });
          await _tts.speak('Billete confirmado. Analizando con inteligencia artificial…');
          await _saveToDB(imagePath, analysis);
          await _provideFeedback(analysis, serial.serialNumber);

          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResultScreen(
                imagePath: imagePath,
                isAuthentic: analysis.isAuthentic && analysis.hasBilletFeatures,
                confidence: analysis.confidencePercentage,
                denomination: analysis.denomination,
                currency: analysis.currency,
                details: analysis.details,
                detectedFeatures: analysis.detectedFeatures,
                suspiciousIndicators: analysis.suspiciousIndicators,
              ),
            ),
          );

          if (!mounted) return;
          setState(() {
            _isProcessing  = false;
            _isCameraReady = true;
            _stableCount   = 0;
            _liveResult    = null;
            _liveData      = null;
            _liveFeatures  = [];
            _phase         = _ScanPhase.searching;
            _scanEnabled   = true;
          });
          _slideCtrl.reverse();
          _startScan();
          await _tts.speak('Escáner reiniciado. Puedes colocar otro billete.');
          return;
        }
      } else {
        if (_stableCount > 0) _stableCount = 0;
        setState(() {
          _phase      = _ScanPhase.searching;
          _liveResult = null;
          _liveData   = null;
        });
        if (_liveFeatures.isNotEmpty) {
          setState(() => _liveFeatures = []);
          _slideCtrl.reverse();
        }
      }
    } catch (e) {
      debugPrint('❌ Error en scanCycle: $e');
      setState(() => _phase = _ScanPhase.searching);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ─── Construir características en vivo ───────────────────────────────────
  void _buildLiveFeatures(_BillLiveData d) {
    final features = <_LiveFeature>[
      // 1. Denominación
      _LiveFeature(
        category: 'Identificación',
        label: 'Denominación',
        value: d.denomination == 'No detectada' || d.denomination == 'Unknown'
            ? 'No detectada'
            : '\$${d.denomination} ${d.currency}',
        score: d.denomination == 'No detectada' ? 0.0 : d.overallConfidence,
        ok: d.denomination != 'No detectada' && d.denomination != 'Unknown',
        icon: Icons.attach_money,
        detail: 'Confianza: ${(d.overallConfidence * 100).toStringAsFixed(0)}%',
      ),

      // 2. Número de serie
      _LiveFeature(
        category: 'Identificación',
        label: 'Número de serie',
        value: d.serialNumber ?? 'No detectado',
        score: d.serialConfidence,
        ok: d.serialValid,
        icon: Icons.tag,
        detail: d.serialNumber == null
            ? 'OCR no encontró serial'
            : d.serialValid
            ? 'Formato válido ✓'
            : d.serialIssues.isNotEmpty
            ? d.serialIssues.first
            : 'Formato inválido',
      ),

      // 3. Holograma
      _LiveFeature(
        category: 'Seguridad',
        label: 'Holograma',
        value: d.hasHologram ? 'Detectado' : 'No detectado',
        score: d.hologramScore,
        ok: d.hasHologram,
        icon: Icons.lens_blur,
        detail: d.hologramIndicators.isNotEmpty
            ? d.hologramIndicators.first
            : 'Puntuación: ${(d.hologramScore * 100).toStringAsFixed(0)}%',
      ),

      // 4. Marca de agua
      _LiveFeature(
        category: 'Seguridad',
        label: 'Marca de agua',
        value: d.hasWatermark ? 'Detectada' : 'No detectada',
        score: d.watermarkScore,
        ok: d.hasWatermark,
        icon: Icons.water_drop_outlined,
        detail: d.watermarkIndicators.isNotEmpty
            ? d.watermarkIndicators.first
            : 'Puntuación: ${(d.watermarkScore * 100).toStringAsFixed(0)}%',
      ),

      // 5. Tinta
      _LiveFeature(
        category: 'Impresión',
        label: 'Calidad de tinta',
        value: d.inkScore > 0.6 ? 'Auténtica' : 'Anomalía detectada',
        score: d.inkScore,
        ok: d.inkScore > 0.6,
        icon: Icons.format_color_fill,
        detail: 'Score: ${(d.inkScore * 100).toStringAsFixed(0)}%',
      ),

      // 6. Microtextura
      _LiveFeature(
        category: 'Impresión',
        label: 'Microtextura',
        value: d.microtextureScore > 0.5 ? 'Presente' : 'Ausente',
        score: d.microtextureScore,
        ok: d.microtextureScore > 0.5,
        icon: Icons.texture,
        detail: 'Score: ${(d.microtextureScore * 100).toStringAsFixed(0)}%',
      ),

      // 7. Ruido / fotocopia
      _LiveFeature(
        category: 'Impresión',
        label: 'Detección fotocopia',
        value: d.isPhotocopy ? '⚠ Posible fotocopia' : 'Sin anomalías',
        score: d.isPhotocopy ? 0.15 : 0.9,
        ok: !d.isPhotocopy,
        icon: Icons.print_disabled,
        detail: 'Ruido: ${(d.noiseLevel * 100).toStringAsFixed(0)}%  '
            'Bordes: ${(d.edgeSharpness * 100).toStringAsFixed(0)}%',
      ),
    ];

    if (mounted) {
      setState(() => _liveFeatures = features);
      if (_slideCtrl.value == 0) _slideCtrl.forward();
    }
  }

  // ─────────────────────── HELPERS ─────────────────────────────────────────
  Future<void> _saveToDB(String path, BillAnalysis a) async {
    try {
      await _billRepository.insertBill(BillRecord(
        id: const Uuid().v4(),
        date: DateTime.now(),
        imagePath: path,
        isAuthentic: a.isAuthentic && a.hasBilletFeatures,
        confidence: a.confidencePercentage,
        denomination: a.denomination,
        currency: a.currency,
      ));
    } catch (e) {
      debugPrint('❌ Error BD: $e');
    }
  }

  Future<void> _provideFeedback(BillAnalysis a, String? serial) async {
    final cur = a.currency == 'USD' ? 'dólar' : 'billete ecuatoriano';
    if (!a.hasBilletFeatures) {
      await _tts.speak('No se detectó un billete válido.');
    } else if (a.isAuthentic) {
      final serialMsg = serial != null ? ' Número de serie: $serial.' : '';
      await _tts.speak('¡Billete auténtico! Es un $cur de ${a.denomination}. '
          'Confianza ${a.confidencePercentage}.$serialMsg');
    } else {
      await _tts.speak('Advertencia: $cur de ${a.denomination} podría ser sospechoso. '
          'Confianza ${a.confidencePercentage}. Verifica manualmente.');
    }
  }

  void _toggleScan() {
    setState(() => _scanEnabled = !_scanEnabled);
    if (_scanEnabled) {
      _startScan();
      _tts.speak('Escáner reanudado.');
    } else {
      _stopScan();
      _tts.speak('Escáner pausado.');
    }
  }

  // ─────────────────────── BUILD ────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isProcessing) {
          final go = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('¿Salir?'),
              content: const Text('Hay un análisis en progreso.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('No')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Sí')),
              ],
            ),
          );
          return go ?? false;
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: CustomAppBar(
          title: 'Escáner de Billetes',
          showBackButton: true,
          onBackPressed: () => Navigator.pop(context),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_permState == _PermState.checking) return _buildLoader('Verificando permisos…');
    if (_permState == _PermState.denied) return _buildPermDenied();
    if (_permState == _PermState.permanentlyDenied) return _buildPermPermanent();
    if (!_isInitialized) return _buildLoader('Iniciando escáner…');
    if (_initError != null) return _buildCamError();

    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(_cameraController)),
        Positioned.fill(child: Container(color: Colors.black.withOpacity(0.15))),
        _buildScanFrame(),
        _buildTopBadge(),
        _buildFeaturesPanel(),
        _buildBottomBar(),
      ],
    );
  }

  // ── Marco de escaneo ──────────────────────────────────────────────────────
  Widget _buildScanFrame() {
    final size   = MediaQuery.of(context).size;
    final frameH = size.height * 0.36;
    final frameT = size.height * 0.13;

    return Positioned(
      top: frameT, left: 24, right: 24, height: frameH,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (_, child) => Transform.scale(
          scale: _phase == _ScanPhase.searching ? _pulseAnim.value : 1.0,
          child: child,
        ),
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _frameColor, width: 2.5),
                boxShadow: [
                  BoxShadow(
                      color: _frameColor.withOpacity(0.28),
                      blurRadius: 22,
                      spreadRadius: 3),
                ],
              ),
            ),
            ..._corners(),
            if (_phase == _ScanPhase.scanning || _phase == _ScanPhase.searching)
              _ScanLine(color: _frameColor),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Icon(_phaseIcon,
                        key: ValueKey(_phase), color: _frameColor, size: 44),
                  ),
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _phaseLabel,
                      key: ValueKey(_phaseLabel),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _frameColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
                      ),
                    ),
                  ),
                  if (_stableCount > 0 && _stableCount < _kStableFrames)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        'Confirmando… $_stableCount/$_kStableFrames',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _corners() {
    final c = _frameColor;
    return [
      _Corner(top: true,  left: true,  color: c),
      _Corner(top: true,  left: false, color: c),
      _Corner(top: false, left: true,  color: c),
      _Corner(top: false, left: false, color: c),
    ];
  }

  IconData get _phaseIcon {
    switch (_phase) {
      case _ScanPhase.detected:  return Icons.check_circle_outline;
      case _ScanPhase.analyzing: return Icons.analytics_outlined;
      case _ScanPhase.scanning:  return Icons.radar;
      default:                   return Icons.document_scanner_outlined;
    }
  }

  String get _phaseLabel {
    switch (_phase) {
      case _ScanPhase.detected:  return '¡Billete detectado!';
      case _ScanPhase.analyzing: return 'Analizando con IA…';
      case _ScanPhase.scanning:  return 'Escaneando…';
      default: return _scanEnabled ? 'Buscando billete…' : '⏸  Pausado';
    }
  }

  // ── Badge superior ─────────────────────────────────────────────────────────
  Widget _buildTopBadge() {
    return Positioned(
      top: 10, left: 16, right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.amber.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.sensors, color: Colors.amber, size: 15),
            const SizedBox(width: 8),
            Text(
              'Escaneo automático activo',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
            ),
            if (_isProcessing) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 10, height: 10,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(Colors.amber)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Panel de características ───────────────────────────────────────────────
  Widget _buildFeaturesPanel() {
    final size = MediaQuery.of(context).size;
    final top  = size.height * 0.51;

    return Positioned(
      top: top, left: 10, right: 10, bottom: 96,
      child: SlideTransition(
        position: _slideAnim,
        child: AnimatedOpacity(
          opacity: _liveFeatures.isEmpty ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.82),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                // ── Header ───────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Colors.amber, size: 16),
                      const SizedBox(width: 6),
                      const Text(
                        'ANÁLISIS DE SEGURIDAD EN VIVO',
                        style: TextStyle(
                          color: Colors.amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const Spacer(),
                      if (_liveResult != null)
                        _AuthBadge(
                          authentic: _liveResult!.isAuthentic,
                          confidence: _liveResult!.confidencePercentage,
                        ),
                    ],
                  ),
                ),

                // ── Lista scrollable ──────────────────────────────
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    children: [
                      if (_liveFeatures.isNotEmpty) ...[
                        _CategorySection(
                          label: 'IDENTIFICACIÓN',
                          features: _liveFeatures
                              .where((f) => f.category == 'Identificación')
                              .toList(),
                        ),
                        const SizedBox(height: 6),
                        _CategorySection(
                          label: 'ELEMENTOS DE SEGURIDAD',
                          features: _liveFeatures
                              .where((f) => f.category == 'Seguridad')
                              .toList(),
                        ),
                        const SizedBox(height: 6),
                        _CategorySection(
                          label: 'CALIDAD DE IMPRESIÓN',
                          features: _liveFeatures
                              .where((f) => f.category == 'Impresión')
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Barra inferior ─────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    return Positioned(
      bottom: 20, left: 0, right: 0,
      child: Column(
        children: [
          AccessibleWidget(
            description: _scanEnabled
                ? 'Pausar escáner. Doble toque para pausar.'
                : 'Reanudar escáner. Doble toque para reanudar.',
            onActivate: _toggleScan,
            child: Container(
              width: 62, height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _scanEnabled ? Colors.amber : Colors.white.withOpacity(0.18),
                border: Border.all(
                    color: _scanEnabled ? Colors.amber : Colors.white38, width: 2),
                boxShadow: [
                  if (_scanEnabled)
                    BoxShadow(
                        color: Colors.amber.withOpacity(0.45),
                        blurRadius: 18, spreadRadius: 2),
                ],
              ),
              child: Icon(
                _scanEnabled ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: _scanEnabled ? Colors.black : Colors.white,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _scanEnabled
                ? '1 toque = escuchar  •  2 toques = pausar'
                : 'Escáner pausado',
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
          ),
        ],
      ),
    );
  }

  // ── Estados de carga / error ───────────────────────────────────────────────
  Widget _buildLoader(String msg) => Container(
    color: Colors.deepPurple.shade900,
    child: Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Colors.amber)),
        const SizedBox(height: 20),
        Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 15)),
      ]),
    ),
  );

  Widget _buildPermDenied() => _PermScreen(
    icon: Icons.no_photography,
    title: 'Permiso de Cámara Requerido',
    body: 'Esta app necesita acceso a la cámara para escanear billetes.',
    buttonLabel: 'Conceder Permiso',
    buttonIcon: Icons.camera_alt,
    onButton: _checkAndRequestPermission,
  );

  Widget _buildPermPermanent() => _PermScreen(
    icon: Icons.block,
    iconColor: Colors.red,
    title: 'Permiso Denegado',
    body: 'Ve a Configuración del teléfono y activa el permiso de cámara.',
    buttonLabel: 'Abrir Configuración',
    buttonIcon: Icons.settings,
    onButton: () async {
      await _tts.speak('Abriendo configuración.');
      await _permissionService.openSettings();
    },
    secondLabel: 'Reintentar',
    onSecond: _checkAndRequestPermission,
  );

  Widget _buildCamError() => Container(
    color: Colors.deepPurple.shade900,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 56),
          const SizedBox(height: 16),
          const Text('Error de Cámara',
              style: TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(_initError ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 24),
          AccessibleButton(
            description: 'Reintentar cámara',
            label: 'Reintentar',
            onActivate: () {
              setState(() {
                _isInitialized = false;
                _initError = null;
              });
              _initializeCamera();
            },
            backgroundColor: Colors.amber,
            textColor: Colors.black,
          ),
        ]),
      ),
    ),
  );

  @override
  void dispose() {
    _stopScan();
    _pulseCtrl.dispose();
    _slideCtrl.dispose();
    _textRecognizer.close();
    try {
      if (_isInitialized && _initError == null) _cameraController.dispose();
      _detectionService.dispose();
    } catch (_) {}
    super.dispose();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  MODELO DE DATOS EN VIVO
// ═════════════════════════════════════════════════════════════════════════════
class _BillLiveData {
  final String  denomination;
  final String  currency;
  final String? serialNumber;
  final bool    serialValid;
  final List<String> serialIssues;
  final double  serialConfidence;
  final bool    hasHologram;
  final double  hologramScore;
  final List<String> hologramIndicators;
  final bool    hasWatermark;
  final double  watermarkScore;
  final List<String> watermarkIndicators;
  final double  noiseLevel;
  final double  edgeSharpness;
  final double  inkScore;
  final double  microtextureScore;
  final bool    isPhotocopy;
  final double  overallConfidence;
  final bool    isAuthentic;
  final bool    hasBillFeatures;

  const _BillLiveData({
    required this.denomination,
    required this.currency,
    required this.serialNumber,
    required this.serialValid,
    required this.serialIssues,
    required this.serialConfidence,
    required this.hasHologram,
    required this.hologramScore,
    required this.hologramIndicators,
    required this.hasWatermark,
    required this.watermarkScore,
    required this.watermarkIndicators,
    required this.noiseLevel,
    required this.edgeSharpness,
    required this.inkScore,
    required this.microtextureScore,
    required this.isPhotocopy,
    required this.overallConfidence,
    required this.isAuthentic,
    required this.hasBillFeatures,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
//  MODELO DE CARACTERÍSTICA EN VIVO
// ═════════════════════════════════════════════════════════════════════════════
class _LiveFeature {
  final String   category;
  final String   label;
  final String   value;
  final double   score;   // 0..1
  final bool     ok;
  final IconData icon;
  final String   detail;

  const _LiveFeature({
    required this.category,
    required this.label,
    required this.value,
    required this.score,
    required this.ok,
    required this.icon,
    required this.detail,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
//  WIDGETS UI
// ═════════════════════════════════════════════════════════════════════════════

// ── Sección de categoría ──────────────────────────────────────────────────────
class _CategorySection extends StatelessWidget {
  final String label;
  final List<_LiveFeature> features;
  const _CategorySection({required this.label, required this.features});

  @override
  Widget build(BuildContext context) {
    if (features.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...features.map((f) => _FeatureTile(feature: f)),
      ],
    );
  }
}

// ── Tile de característica ────────────────────────────────────────────────────
class _FeatureTile extends StatelessWidget {
  final _LiveFeature feature;
  const _FeatureTile({required this.feature});

  @override
  Widget build(BuildContext context) {
    final color = feature.ok ? Colors.greenAccent : Colors.redAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // Icono
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(feature.icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          // Contenido
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      feature.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      feature.ok ? Icons.check_circle : Icons.cancel,
                      color: color, size: 13,
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // Valor destacado
                Text(
                  feature.value,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                // Barra de score
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: feature.score.clamp(0.0, 1.0),
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(color),
                    minHeight: 3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  feature.detail,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.45), fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Badge auténtico / sospechoso ──────────────────────────────────────────────
class _AuthBadge extends StatelessWidget {
  final bool authentic;
  final String confidence;
  const _AuthBadge({required this.authentic, required this.confidence});

  @override
  Widget build(BuildContext context) {
    final color = authentic ? Colors.greenAccent : Colors.redAccent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          authentic ? Icons.verified : Icons.warning_amber_rounded,
          color: color, size: 12,
        ),
        const SizedBox(width: 4),
        Text(
          '${authentic ? "Auténtico" : "Sospechoso"} · $confidence',
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }
}

// ── Línea de barrido animada ──────────────────────────────────────────────────
class _ScanLine extends StatefulWidget {
  final Color color;
  const _ScanLine({required this.color});
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1700))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Positioned(
        top: _anim.value * (MediaQuery.of(context).size.height * 0.30),
        left: 0, right: 0,
        child: Container(
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.transparent,
              widget.color.withOpacity(0.9),
              Colors.transparent,
            ]),
            borderRadius: BorderRadius.circular(1),
            boxShadow: [
              BoxShadow(color: widget.color.withOpacity(0.5), blurRadius: 6),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Esquinas del marco ────────────────────────────────────────────────────────
class _Corner extends StatelessWidget {
  final bool top, left;
  final Color color;
  const _Corner({required this.top, required this.left, required this.color});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top:    top  ? 0 : null,
      bottom: top  ? null : 0,
      left:   left ? 0 : null,
      right:  left ? null : 0,
      child: SizedBox(
        width: 24, height: 24,
        child: CustomPaint(
          painter: _CornerPainter(color: color, top: top, left: left),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final bool  top, left;
  const _CornerPainter({required this.color, required this.top, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    if (top && left) {
      path.moveTo(0, size.height); path.lineTo(0, 0); path.lineTo(size.width, 0);
    } else if (top) {
      path.moveTo(0, 0); path.lineTo(size.width, 0); path.lineTo(size.width, size.height);
    } else if (left) {
      path.moveTo(0, 0); path.lineTo(0, size.height); path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height); path.lineTo(size.width, size.height); path.lineTo(size.width, 0);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_CornerPainter o) => o.color != color;
}

// ── Pantalla de permiso genérica ──────────────────────────────────────────────
class _PermScreen extends StatelessWidget {
  final IconData     icon;
  final Color        iconColor;
  final String       title, body, buttonLabel;
  final IconData     buttonIcon;
  final VoidCallback onButton;
  final String?      secondLabel;
  final VoidCallback? onSecond;

  const _PermScreen({
    required this.icon,
    this.iconColor = Colors.amber,
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.buttonIcon,
    required this.onButton,
    this.secondLabel,
    this.onSecond,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.deepPurple.shade900,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: iconColor, size: 68),
            const SizedBox(height: 20),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 14)),
            const SizedBox(height: 28),
            AccessibleButton(
              description: buttonLabel,
              label: buttonLabel,
              onActivate: onButton,
              backgroundColor: Colors.amber,
              textColor: Colors.black,
              icon: buttonIcon,
              height: 56,
            ),
            if (secondLabel != null && onSecond != null) ...[
              const SizedBox(height: 14),
              AccessibleButton(
                description: secondLabel!,
                label: secondLabel!,
                onActivate: onSecond!,
                backgroundColor: Colors.blueAccent,
                textColor: Colors.white,
                icon: Icons.refresh,
                height: 52,
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

// ─── Enums ────────────────────────────────────────────────────────────────────
enum _PermState  { checking, granted, denied, permanentlyDenied }
enum _ScanPhase  { searching, scanning, detected, analyzing }