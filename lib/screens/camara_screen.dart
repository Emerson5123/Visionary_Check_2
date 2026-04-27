  import 'package:flutter/material.dart';
  import 'package:camera/camera.dart';
  import 'package:uuid/uuid.dart';
  import '../widgets/accessible_widget.dart';
  import '../widgets/custom_app_bar.dart';
  import '../services/bill_detection_service.dart';
  import '../services/tts_service.dart';
  import '../services/accessibility_service.dart';
  import '../services/bill_repository.dart';
  import '../services/permission_service.dart';
  import '../models/bill_record.dart';
  import 'result_screen.dart';



  class CameraScreen extends StatefulWidget {
    const CameraScreen({Key? key}) : super(key: key);

    @override
    State<CameraScreen> createState() => _CameraScreenState();
  }

  class _CameraScreenState extends State<CameraScreen> {
    late CameraController _cameraController;
    final BillDetectionService _detectionService = BillDetectionService();
    final TTSService           _tts              = TTSService();
    final AccessibilityService _accessibility    = AccessibilityService();
    final BillRepository       _billRepository   = BillRepository();
    final PermissionService    _permissionService = PermissionService();

    bool    _isInitialized     = false;
    bool    _isProcessing      = false;
    bool    _isCameraReady     = false;
    String? _initializationError;

    // Estado del permiso
    _PermissionState _permissionState = _PermissionState.checking;

    @override
    void initState() {
      super.initState();
      _accessibility.clearFocus();
      _checkAndRequestPermission();
    }

    // ── Manejo de permisos ───────────────────────────────────────────────────

    Future<void> _checkAndRequestPermission() async {
      setState(() => _permissionState = _PermissionState.checking);

      final result = await _permissionService.checkAndRequestCamera();

      switch (result) {
        case PermissionResult.granted:
          setState(() => _permissionState = _PermissionState.granted);
          _initializeCamera();
          break;

        case PermissionResult.denied:
          setState(() => _permissionState = _PermissionState.denied);
          await _tts.speak(
            'Se necesita permiso de cámara para verificar billetes. '
                'Por favor otorga el permiso e intenta de nuevo.',
          );
          break;

        case PermissionResult.permanentlyDenied:
          setState(() => _permissionState = _PermissionState.permanentlyDenied);
          await _tts.speak(
            'El permiso de cámara fue denegado permanentemente. '
                'Ve a Configuración del teléfono, busca esta aplicación '
                'y activa el permiso de cámara manualmente.',
          );
          break;

        case PermissionResult.restricted:
          setState(() => _permissionState = _PermissionState.denied);
          await _tts.speak(
            'El acceso a la cámara está restringido en este dispositivo. '
                'Contacta al administrador del dispositivo.',
          );
          break;
      }
    }

    // ── Inicialización de cámara ─────────────────────────────────────────────

    Future<void> _initializeCamera() async {
      try {
        final cameras = await availableCameras();
        if (cameras.isEmpty) {
          setState(() => _initializationError = 'No se encontró cámara en el dispositivo');
          await _tts.speak('No se encontró cámara en el dispositivo');
          return;
        }

        _cameraController = CameraController(
          cameras.first,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );

        await _cameraController.initialize();

        if (mounted) {
          setState(() {
            _isInitialized = true;
            _isCameraReady = true;
          });
          await _tts.speak(
            'Cámara lista. '
                'Coloca el billete frente a la cámara, bien iluminado y centrado. '
                'Toca el botón de captura una vez para escucharlo, '
                'dos veces para capturar.',
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
            _initializationError = 'Error al inicializar cámara: $e';
          });
        }
        await _tts.speak('Error al inicializar la cámara. Intenta de nuevo.');
      }
    }

    // ── Captura y análisis ───────────────────────────────────────────────────

    Future<void> _captureAndAnalyze() async {
      if (_isProcessing || !_isInitialized || !_isCameraReady) {
        await _tts.speak('Por favor espera, la cámara se está preparando.');
        return;
      }

      try {
        setState(() => _isProcessing = true);
        await _tts.speak('Capturando imagen del billete...');
        await Future.delayed(const Duration(milliseconds: 500));

        final XFile capturedImage = await _cameraController.takePicture();

        await _tts.speak('Analizando billete con inteligencia artificial avanzada...');

        final analysis = await _detectionService.analyzeBill(capturedImage.path);

        await _saveBillToDatabase(imagePath: capturedImage.path, analysis: analysis);
        await _provideFeedback(analysis);

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ResultScreen(
                imagePath: capturedImage.path,
                isAuthentic: analysis.isAuthentic && analysis.hasBilletFeatures,
                confidence: analysis.confidencePercentage,
                denomination: analysis.denomination,
                currency: analysis.currency,
                details: analysis.details,
                detectedFeatures: analysis.detectedFeatures,
                suspiciousIndicators: analysis.suspiciousIndicators,
              ),
            ),
          ).then((_) {
            if (mounted) {
              setState(() {
                _isProcessing = false;
                _isCameraReady = true;
              });
            }
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isProcessing = false);
        await _tts.speak('Error al procesar la imagen. Intenta de nuevo.');
      }
    }

    Future<void> _saveBillToDatabase({
      required String imagePath,
      required BillAnalysis analysis,
    }) async {
      try {
        final billRecord = BillRecord(
          id: const Uuid().v4(),
          date: DateTime.now(),
          imagePath: imagePath,
          isAuthentic: analysis.isAuthentic && analysis.hasBilletFeatures,
          confidence: analysis.confidencePercentage,
          denomination: analysis.denomination,
          currency: analysis.currency,
        );
        await _billRepository.insertBill(billRecord);
      } catch (e) {
        print('❌ Error guardando en BD: $e');
      }
    }

    /// Método único para proporcionar feedback al usuario
    Future<void> _provideFeedback(BillAnalysis analysis) async {
      final currencyLabel = analysis.currency == 'USD'
          ? 'dólar estadounidense'
          : analysis.currency == 'ECU'
          ? 'billete ecuatoriano'
          : 'billete';

      final featuresText = analysis.detectedFeatures.isEmpty
          ? ''
          : ' Se detectaron ${analysis.detectedFeatures.length} características positivas.';

      final suspiciousText = analysis.suspiciousIndicators.isEmpty
          ? ''
          : ' ${analysis.suspiciousIndicators.length} indicadores sospechosos.';

      if (!analysis.hasBilletFeatures) {
        await _tts.speak(
          'No se detectó un billete. '
              'Asegúrate de que esté bien iluminado y enfocado. Intenta de nuevo.',
        );
      } else if (analysis.isAuthentic) {
        await _tts.speak(
          '¡Billete auténtico! '
              'Es un $currencyLabel de ${analysis.denomination}. '
              'Confianza ${analysis.confidencePercentage}.$featuresText',
        );
      } else {
        await _tts.speak(
          'Advertencia: este $currencyLabel de ${analysis.denomination} '
              'podría ser sospechoso. '
              'Confianza ${analysis.confidencePercentage}.$suspiciousText '
              'Verifica manualmente.',
        );
      }
    }

    // ── Widgets de UI ────────────────────────────────────────────────────────

    Widget _buildInstructionOverlay() {
      return Positioned(
        top: 20, left: 20, right: 20,
        child: AccessibleWidget(
          description:
          'Instrucciones: Coloca el billete en el centro, bien iluminado, '
              'sin sombras ni reflejos, y presiona el botón para capturar.',
          onActivate: () => _tts.speak(
            'Instrucciones: Coloca el billete en el centro, bien iluminado, '
                'sin sombras ni reflejos, y presiona el botón para capturar.',
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber, width: 2),
            ),
            child: Column(
              children: [
                const Icon(Icons.info, color: Colors.amber, size: 22),
                const SizedBox(height: 6),
                Text(
                  '• Billete en el centro\n'
                      '• Buena iluminación\n'
                      '• Sin sombras ni reflejos\n'
                      '• 1 toque = escuchar  |  2 toques = activar',
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget _buildFocusGuide() {
      return Positioned(
        top: MediaQuery.of(context).size.height * 0.25,
        left: 30, right: 30,
        height: MediaQuery.of(context).size.height * 0.38,
        child: AccessibleWidget(
          description: 'Marco de enfoque. Coloca el billete dentro de este rectángulo.',
          onActivate: () => _tts.speak(
            'Coloca el billete dentro del rectángulo ámbar en pantalla.',
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.amber, width: 3),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.withOpacity(0.3),
                  blurRadius: 15, spreadRadius: 3,
                ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.attach_money, color: Colors.amber, size: 56),
                  const SizedBox(height: 12),
                  Text(
                    'Billete aquí',
                    style: TextStyle(
                      color: Colors.amber.withOpacity(0.9),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget _buildCaptureButton() {
      return Positioned(
        bottom: 30, left: 20, right: 20,
        child: Column(
          children: [
            AccessibleWidget(
              description: _isProcessing
                  ? 'Analizando billete, por favor espera.'
                  : 'Botón capturar billete. Doble toque para tomar la foto y analizar.',
              onActivate: _isProcessing ? null : _captureAndAnalyze,
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isProcessing ? Colors.grey : Colors.amber,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.5),
                      blurRadius: 15, spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: _isProcessing ? Colors.white54 : Colors.black,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isProcessing)
              Column(
                children: [
                  const SizedBox(
                    width: 36, height: 36,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                      strokeWidth: 4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Analizando con IA avanzada...',
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14),
                  ),
                ],
              )
            else
              Text(
                '1 toque = escuchar  •  2 toques = capturar',
                style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
              ),
          ],
        ),
      );
    }

    // ── Pantallas de estado ──────────────────────────────────────────────────

    Widget _buildCheckingPermission() {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
            ),
            const SizedBox(height: 20),
            Text(
              'Verificando permisos...',
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16),
            ),
          ],
        ),
      );
    }

    Widget _buildPermissionDenied() {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_photography, color: Colors.amber, size: 72),
              const SizedBox(height: 24),
              const Text(
                'Permiso de Cámara Requerido',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Esta aplicación necesita acceso a la cámara '
                    'para fotografiar y verificar billetes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15),
              ),
              const SizedBox(height: 32),
              AccessibleButton(
                description:
                'Botón conceder permiso de cámara. '
                    'Doble toque para abrir la solicitud de permiso.',
                label: 'Conceder Permiso',
                onActivate: _checkAndRequestPermission,
                backgroundColor: Colors.amber,
                textColor: Colors.black,
                icon: Icons.camera_alt,
                height: 60,
              ),
            ],
          ),
        ),
      );
    }

    Widget _buildPermissionPermanentlyDenied() {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, color: Colors.red, size: 72),
              const SizedBox(height: 24),
              const Text(
                'Permiso Denegado',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'El permiso de cámara fue denegado permanentemente. '
                    'Ve a Configuración del teléfono y actívalo manualmente '
                    'para esta aplicación.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15),
              ),
              const SizedBox(height: 32),
              AccessibleButton(
                description:
                'Botón abrir configuración del teléfono. '
                    'Doble toque para ir a los ajustes y activar el permiso.',
                label: 'Abrir Configuración',
                onActivate: () async {
                  await _tts.speak(
                    'Abriendo configuración del teléfono. '
                        'Busca esta aplicación y activa el permiso de cámara.',
                  );
                  await _permissionService.openSettings();
                },
                backgroundColor: Colors.amber,
                textColor: Colors.black,
                icon: Icons.settings,
                height: 60,
              ),
              const SizedBox(height: 16),
              AccessibleButton(
                description: 'Botón reintentar permiso de cámara.',
                label: 'Reintentar',
                onActivate: _checkAndRequestPermission,
                backgroundColor: Colors.blueAccent,
                textColor: Colors.white,
                icon: Icons.refresh,
                height: 56,
              ),
            ],
          ),
        ),
      );
    }

    Widget _buildLoadingCamera() {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
            ),
            const SizedBox(height: 20),
            Text(
              'Inicializando cámara...',
              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16),
            ),
          ],
        ),
      );
    }

    Widget _buildCameraError() {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 60),
              const SizedBox(height: 20),
              const Text(
                'Error de Cámara',
                style: TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _initializationError ?? 'Error desconocido',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.8)),
              ),
              const SizedBox(height: 24),
              AccessibleButton(
                description: 'Botón reintentar inicializar la cámara',
                label: 'Reintentar',
                onActivate: () {
                  setState(() {
                    _isInitialized = false;
                    _initializationError = null;
                  });
                  _initializeCamera();
                },
                backgroundColor: Colors.amber,
                textColor: Colors.black,
              ),
            ],
          ),
        ),
      );
    }

    // ── Build principal ──────────────────────────────────────────────────────

    @override
    Widget build(BuildContext context) {
      return WillPopScope(
        onWillPop: () async {
          if (_isProcessing) {
            final shouldPop = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('¿Salir?'),
                content: const Text('Hay una captura en progreso. ¿Deseas salir?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('No'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Sí'),
                  ),
                ],
              ),
            );
            return shouldPop ?? false;
          }
          return true;
        },
        child: Scaffold(
          appBar: CustomAppBar(
            title: 'Capturar Billete',
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
            child: _buildBody(),
          ),
        ),
      );
    }

    Widget _buildBody() {
      // 1. Verificando permiso
      if (_permissionState == _PermissionState.checking) {
        return _buildCheckingPermission();
      }

      // 2. Permiso denegado
      if (_permissionState == _PermissionState.denied) {
        return _buildPermissionDenied();
      }

      // 3. Permiso denegado permanentemente
      if (_permissionState == _PermissionState.permanentlyDenied) {
        return _buildPermissionPermanentlyDenied();
      }

      // 4. Permiso concedido — mostrar cámara
      if (!_isInitialized) return _buildLoadingCamera();
      if (_initializationError != null) return _buildCameraError();

      return Stack(
        children: [
          Center(child: CameraPreview(_cameraController)),
          _buildInstructionOverlay(),
          _buildFocusGuide(),
          _buildCaptureButton(),
        ],
      );
    }

    @override
    void dispose() {
      try {
        if (_isInitialized && _initializationError == null) {
          _cameraController.dispose();
        }
        _detectionService.dispose();
      } catch (_) {}
      super.dispose();
    }
  }

  /// Estados internos del permiso de cámara
  enum _PermissionState {
    checking,
    granted,
    denied,
    permanentlyDenied,
  }