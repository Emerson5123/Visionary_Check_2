import 'package:flutter/material.dart';
import 'dart:io';
import '../widgets/accessible_widget.dart';
import '../widgets/custom_app_bar.dart';
import '../services/tts_service.dart';
import '../services/accessibility_service.dart';
import '../theme/app_theme.dart';

class ResultScreen extends StatefulWidget {
  final String imagePath;
  final bool isAuthentic;
  final String confidence;  // ← Mantiene String como está
  final String denomination;
  final String currency;
  final String details;
  final List<String> detectedFeatures;      // ← AGREGADO
  final List<String> suspiciousIndicators;  // ← AGREGADO

  const ResultScreen({
    Key? key,
    required this.imagePath,
    required this.isAuthentic,
    required this.confidence,
    required this.denomination,
    this.currency = 'UNKNOWN',
    this.details = '',
    this.detectedFeatures = const [],        // ← AGREGADO
    this.suspiciousIndicators = const [],    // ← AGREGADO
  }) : super(key: key);

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final TTSService _tts = TTSService();
  final AccessibilityService _accessibility = AccessibilityService();

  @override
  void initState() {
    super.initState();
    // clearFocus() dispara notifyListeners() → no llamar durante build.
    // WidgetsBinding.addPostFrameCallback garantiza que el árbol ya fue
    // construido antes de emitir la notificación.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _accessibility.clearFocus();
    });
    _announceResult();
  }

  void _announceResult() async {
    await Future.delayed(const Duration(milliseconds: 400));
    final label = widget.currency == 'USD'
        ? 'dólar estadounidense'
        : widget.currency == 'ECU'
        ? 'billete ecuatoriano'
        : 'billete';

    final featuresText = widget.detectedFeatures.isEmpty
        ? ''
        : ' Detectadas ${widget.detectedFeatures.length} características positivas.';

    final suspiciousText = widget.suspiciousIndicators.isEmpty
        ? ''
        : ' ${widget.suspiciousIndicators.length} indicadores sospechosos.';

    await _tts.speak(
      'Resultado: ${widget.isAuthentic ? "AUTÉNTICO" : "SOSPECHOSO"}. '
          'Es un $label de ${widget.denomination}. '
          'Confianza ${widget.confidence}.$featuresText$suspiciousText',
    );
  }

  String get _currencyLabel => widget.currency == 'USD' ? 'USD'
      : widget.currency == 'ECU' ? 'Ecuador' : 'Desconocida';

  @override
  Widget build(BuildContext context) {
    final isAuth = widget.isAuthentic;
    final statusColor = isAuth ? AppTheme.success : AppTheme.error;
    final statusGradient = isAuth ? AppTheme.successGradient : AppTheme.errorGradient;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: CustomAppBar(
          title: 'Resultado',
          showBackButton: true,
          onBackPressed: () => Navigator.pop(context)
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          // Banner resultado
          AccessibleWidget(
            description: isAuth ? 'Billete AUTÉNTICO' : 'Billete SOSPECHOSO',
            onActivate: () => _tts.speak(isAuth
                ? 'El billete fue verificado como auténtico.'
                : 'El billete fue marcado como sospechoso.'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  gradient: statusGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: statusColor.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6)
                    )
                  ]
              ),
              child: Row(children: [
                Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle
                    ),
                    child: Icon(
                        isAuth ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 34
                    )
                ),
                const SizedBox(width: 16),
                Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          isAuth ? '¡AUTÉNTICO!' : '¡SOSPECHOSO!',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold
                          )
                      ),
                      Text(
                          'Confianza ${widget.confidence}',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14
                          )
                      ),
                    ]
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // Imagen
          AccessibleWidget(
            description: 'Imagen del billete capturado.',
            onActivate: () => _tts.speak('Imagen del billete.'),
            child: Container(
                width: double.infinity,
                height: 180,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.divider, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.primary.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4)
                      )
                    ]
                ),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.cover
                    )
                )
            ),
          ),
          const SizedBox(height: 20),

          // Detalles
          AccessibleWidget(
            description: 'Detalles: ${widget.denomination}, $_currencyLabel, ${widget.confidence}',
            onActivate: () => _tts.speak(
                'Denominación ${widget.denomination}. Moneda $_currencyLabel. '
                    '${widget.detectedFeatures.isNotEmpty ? "${widget.detectedFeatures.length} características detectadas. " : ""}'
                    '${widget.suspiciousIndicators.isNotEmpty ? "${widget.suspiciousIndicators.length} indicadores sospechosos." : ""}'
            ),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.divider),
                  boxShadow: [
                    BoxShadow(
                        color: AppTheme.primary.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4)
                    )
                  ]
              ),
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    _row(Icons.monetization_on_outlined, 'Denominación', widget.denomination, AppTheme.primary),
                    _div(),
                    _row(Icons.flag_outlined, 'Moneda', _currencyLabel, AppTheme.primary),
                    _div(),
                    _row(Icons.analytics_outlined, 'Confianza', widget.confidence, AppTheme.primary),
                    _div(),
                    _row(
                        isAuth ? Icons.verified_outlined : Icons.report_problem_outlined,
                        'Estado',
                        isAuth ? 'Auténtico' : 'Sospechoso',
                        isAuth ? AppTheme.success : AppTheme.error
                    ),

                    // ← NUEVO: Características detectadas
                    if (widget.detectedFeatures.isNotEmpty) ...[
                      _div(),
                      _featuresSection('✅ Características Detectadas', widget.detectedFeatures),
                    ],

                    // ← NUEVO: Indicadores sospechosos
                    if (widget.suspiciousIndicators.isNotEmpty) ...[
                      _div(),
                      _featuresSection('⚠️ Indicadores Sospechosos', widget.suspiciousIndicators),
                    ],

                    if (widget.details.isNotEmpty) ...[
                      _div(),
                      Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppTheme.surfaceAlt,
                              borderRadius: BorderRadius.circular(10)
                          ),
                          child: Text(
                              widget.details,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12.5
                              )
                          )
                      ),
                    ],
                  ])
              ),
            ),
          ),
          const SizedBox(height: 24),

          AccessibleButton(
              description: 'Verificar otro billete.',
              label: 'Verificar Otro',
              onActivate: () => Navigator.pop(context),
              backgroundColor: AppTheme.primary,
              textColor: AppTheme.textOnPrimary,
              icon: Icons.refresh,
              height: 54
          ),
          const SizedBox(height: 12),
          AccessibleButton(
              description: 'Volver al inicio.',
              label: 'Volver al Inicio',
              onActivate: () => Navigator.popUntil(context, (r) => r.isFirst),
              backgroundColor: AppTheme.surface,
              textColor: AppTheme.textSecondary,
              icon: Icons.home_outlined,
              height: 54
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  // ← NUEVO: Widget para mostrar listas de características
  Widget _featuresSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        ...items.take(4).map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Icon(Icons.circle, size: 8, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        )),
        if (items.length > 4)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+${items.length - 4} más...',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary.withOpacity(0.7),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(IconData icon, String label, String value, Color color) =>
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const Spacer(),
            Text(
                value,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600
                )
            ),
          ])
      );

  Widget _div() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Divider(color: AppTheme.divider, height: 1, thickness: 1)
  );
}