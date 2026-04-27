import 'package:permission_handler/permission_handler.dart';

/// Resultado de una solicitud de permiso
enum PermissionResult {
  granted,           // Concedido
  denied,            // Denegado (puede volver a pedirse)
  permanentlyDenied, // Denegado permanentemente (ir a ajustes)
  restricted,        // Restringido por el sistema (menores, MDM)
}

/// Servicio para manejar permisos de cámara y galería
class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  // ── Cámara ───────────────────────────────────────────────────────────────

  /// Verifica si el permiso de cámara ya está concedido
  Future<bool> isCameraGranted() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Solicita el permiso de cámara y devuelve el resultado
  Future<PermissionResult> requestCamera() async {
    final status = await Permission.camera.request();
    return _mapStatus(status);
  }

  /// Verifica y solicita cámara en un solo paso.
  /// Devuelve true si el permiso está disponible para usar.
  Future<PermissionResult> checkAndRequestCamera() async {
    final status = await Permission.camera.status;

    if (status.isGranted) return PermissionResult.granted;
    if (status.isPermanentlyDenied) return PermissionResult.permanentlyDenied;
    if (status.isRestricted) return PermissionResult.restricted;

    // Solicitar si está denegado o no determinado
    final result = await Permission.camera.request();
    return _mapStatus(result);
  }

  // ── Galería ──────────────────────────────────────────────────────────────

  /// Verifica y solicita acceso a fotos en un solo paso.
  Future<PermissionResult> checkAndRequestPhotos() async {
    // En Android 13+ se usa READ_MEDIA_IMAGES, en iOS photos
    final permission = Permission.photos;
    final status = await permission.status;

    if (status.isGranted || status.isLimited) return PermissionResult.granted;
    if (status.isPermanentlyDenied) return PermissionResult.permanentlyDenied;
    if (status.isRestricted) return PermissionResult.restricted;

    final result = await permission.request();
    return _mapStatus(result);
  }

  // ── Abrir ajustes del sistema ─────────────────────────────────────────────

  /// Abre la pantalla de ajustes de la app para que el usuario
  /// pueda conceder el permiso manualmente.
  Future<void> openSettings() async {
    await openAppSettings();
  }

  // ── Helper privado ───────────────────────────────────────────────────────

  PermissionResult _mapStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return PermissionResult.granted;
    if (status.isPermanentlyDenied)           return PermissionResult.permanentlyDenied;
    if (status.isRestricted)                  return PermissionResult.restricted;
    return PermissionResult.denied;
  }
}