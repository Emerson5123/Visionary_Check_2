# 👁️ Visionary Cash Check

> Aplicación móvil para verificación de autenticidad de billetes diseñada para personas con discapacidad visual.

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white" />
  <img src="https://img.shields.io/badge/TFLite-MobileNet_v1-FF6F00?logo=tensorflow&logoColor=white" />
  <img src="https://img.shields.io/badge/ML_Kit-OCR%20%2B%20Labels-4285F4?logo=google&logoColor=white" />
  <img src="https://img.shields.io/badge/Plataformas-Android%20%7C%20iOS-green" />
</p>

---

## 📖 Descripción

**Visionary Cash Check** es una aplicación accesible que permite a personas con discapacidad visual verificar si un billete es auténtico o falsificado. Usando la cámara del teléfono o imágenes de la galería, la app analiza el billete mediante inteligencia artificial y comunica el resultado completamente por voz.

Actualmente soporta billetes en **dólares estadounidenses (USD)** y **billetes ecuatorianos (ECU)**.

---

## ✨ Características principales

- 📷 **Captura con cámara** o selección desde galería
- 🧠 **Pipeline de IA de 4 pasos** para análisis de autenticidad
- 🔊 **Text-to-Speech (TTS)** — toda la interfaz es narrada por voz
- 👆 **Interacción accesible** — un toque escucha, doble toque activa
- 💾 **Historial local** de verificaciones con SQLite
- ⚙️ **Configuración de voz** — idioma, volumen y velocidad
- 🌍 Multi-plataforma: Android, iOS, Web, Linux, macOS, Windows

---

## 🧠 Pipeline de análisis

Cuando se analiza un billete, la app ejecuta 4 pasos en secuencia:

```
📷 Imagen de entrada
       │
       ▼
 ┌─────────────────────────────────┐
 │  PASO 0 – Mejora de imagen      │  Recorte, deskew, denoising,
 │  ImageEnhancerService           │  corrección de brillo/contraste
 └──────────────┬──────────────────┘
                │
                ▼
 ┌─────────────────────────────────┐
 │  PASO 1 – Detección de bordes   │  Algoritmo Sobel v3
 │  EdgeDetectionService           │
 └──────────────┬──────────────────┘
                │
                ▼
 ┌─────────────────────────────────┐
 │  PASO 2 – Identificación        │  Detección de moneda por color
 │  de moneda                      │  USD / ECU
 └──────────────┬──────────────────┘
                │
                ▼
 ┌─────────────────────────────────┐
 │  PASO 3 – Denominación          │  EnhancedDenominationDetector
 │  + Autenticidad                 │  AuthenticityDetectorV2
 └──────────────┬──────────────────┘
                │
                ▼
        ✅ Resultado + TTS
```

### Detectores de autenticidad

| # | Detector | Qué analiza |
|---|---|---|
| 1 | Características de seguridad | Microimpresión, franjas, gradientes |
| 2 | Análisis de textura | Patrones LBP, entropía, periodicidad |
| 3 | Validación de perspectiva | Detección de bordes del billete |
| 4 | Histograma avanzado | Canales RGB y HSV |
| 5 | OCR + Seguridad | Texto, número serial, marca de agua, holograma |

---

## 📱 Pantallas

| Pantalla | Descripción |
|---|---|
| 🏠 **Home** | Acceso rápido a cámara, galería e historial |
| 📷 **Cámara** | Captura en tiempo real con guía de encuadre |
| ✅ **Resultado** | Veredicto (auténtico/sospechoso), denominación y confianza |
| 📋 **Historial** | Registro de verificaciones anteriores guardado localmente |
| ⚙️ **Configuración** | Ajustes de voz: idioma, velocidad y volumen |

---

## 💵 Billetes soportados

| Moneda | Denominaciones |
|---|---|
| 🇺🇸 USD | $1 · $2 · $5 · $10 · $20 |
| 🇪🇨 ECU | Billetes ecuatorianos |

---

## 🛠️ Tecnologías

| Tecnología | Uso |
|---|---|
| **Flutter / Dart** | Framework principal |
| **TFLite (MobileNet v1)** | Modelo de clasificación local |
| **Google ML Kit** | OCR + etiquetado de imágenes |
| **flutter_tts** | Text-to-Speech accesible |
| **SQLite (sqflite)** | Historial local de verificaciones |
| **image** | Procesamiento y mejora de imágenes |
| **camera / image_picker** | Captura y selección de fotos |
| **permission_handler** | Gestión de permisos de cámara y galería |

---

## 🚀 Instalación y ejecución

### Requisitos previos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) `^3.x`
- Dart `^3.11.4`
- Android Studio / Xcode (para emuladores)
- Dispositivo físico recomendado (para accesibilidad y cámara)

### Pasos

```bash
# 1. Clonar el repositorio
git clone https://github.com/Emerson5123/Visionary_Check_2.git
cd Visionary_Check_2

# 2. Instalar dependencias
flutter pub get

# 3. Verificar configuración
flutter doctor

# 4. Ejecutar en dispositivo o emulador
flutter run
```

> **Nota:** Los modelos TFLite y datasets de imágenes están incluidos en `assets/`. No se requiere descarga adicional.

---

## 📁 Estructura del proyecto

```
lib/
├── main.dart                    # Punto de entrada
├── models/
│   └── bill_record.dart         # Modelo de registro de verificación
├── screens/
│   ├── home_screen.dart         # Pantalla principal
│   ├── camara_screen.dart       # Cámara en tiempo real
│   ├── result_screen.dart       # Resultado del análisis
│   ├── history_screen.dart      # Historial de verificaciones
│   └── settings_screen.dart     # Configuración de voz
├── services/
│   ├── bill_detection_service.dart      # Orquestador del pipeline
│   ├── authenticity_detector_v2.dart    # Detector de autenticidad
│   ├── enhanced_denomination_detector.dart
│   ├── edge_detection_service.dart
│   ├── image_enhancer_service.dart
│   ├── ocr_optimizer_service.dart
│   ├── hologram_detector.dart
│   ├── watermark_detector.dart
│   ├── serial_number_validator.dart
│   ├── tts_service.dart                 # Text-to-Speech
│   ├── accessibility_service.dart
│   ├── database_service.dart
│   └── ...
├── theme/
│   └── app_theme.dart           # Tema visual de la app
└── widgets/
    ├── accessible_widget.dart   # Widgets con soporte TTS
    └── custom_app_bar.dart

assets/
├── models/
│   └── mobilenet_v1_1.0_224.tflite
└── datasets/
    └── billetes/
        └── usa_currency/        # Imágenes de referencia por denominación
```

---

## ♿ Accesibilidad

La accesibilidad es el núcleo de esta app:

- **Voz en cada interacción** — botones, resultados y navegación se anuncian automáticamente.
- **Sistema de toque doble** — `1 toque` = escuchar descripción, `2 toques` = activar acción.
- **Mensaje de bienvenida** en voz al iniciar la app.
- **Configuración de TTS** — idioma (es-ES, en-US y más), volumen y velocidad de habla.
- Compatible con lectores de pantalla del sistema operativo.

---

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor:

1. Haz un fork del repositorio
2. Crea una rama para tu feature: `git checkout -b feature/nueva-funcionalidad`
3. Realiza tus cambios y haz commit: `git commit -m "feat: descripción"`
4. Sube tu rama: `git push origin feature/nueva-funcionalidad`
5. Abre un Pull Request

---

## 📄 Licencia

Este proyecto está bajo la licencia MIT. Consulta el archivo `LICENSE` para más detalles.

---

<p align="center">
  Hecho con ❤️ para la comunidad con discapacidad visual
</p>
