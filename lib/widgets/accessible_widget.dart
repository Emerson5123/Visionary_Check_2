import 'package:flutter/material.dart';
import '../services/accessibility_service.dart';
import '../theme/app_theme.dart';

/// 1 toque  → enfoca y anuncia por TTS
/// 2 toques → ejecuta [onActivate]
/// Foco visible con borde teal (colores BilletesMx)
class AccessibleWidget extends StatefulWidget {
  final String description;
  final VoidCallback? onActivate;
  final Widget child;
  final String? elementId;
  final bool enabled;

  const AccessibleWidget({
    Key? key,
    required this.description,
    required this.child,
    this.onActivate,
    this.elementId,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<AccessibleWidget> createState() => _AccessibleWidgetState();
}

class _AccessibleWidgetState extends State<AccessibleWidget> {
  final AccessibilityService _accessibility = AccessibilityService();
  bool _isFocused = false;

  String get _id => widget.elementId ?? widget.description;

  @override
  void initState() {
    super.initState();
    _accessibility.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _accessibility.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    final focused = _accessibility.focusedElementId == _id;
    if (focused != _isFocused) setState(() => _isFocused = focused);
  }

  void _handleTap() {
    if (!widget.enabled) {
      _accessibility.announce('${widget.description}, desactivado.');
      return;
    }
    _accessibility.focusElement(
      id: _id, description: widget.description,
      action: widget.onActivate ?? () {},
    );
  }

  void _handleDoubleTap() {
    if (!widget.enabled) return;
    if (_accessibility.focusedElementId == _id) {
      _accessibility.activateFocused();
    } else {
      _accessibility.focusElement(
        id: _id, description: widget.description,
        action: widget.onActivate ?? () {},
      ).then((_) => _accessibility.activateFocused());
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      onDoubleTap: _handleDoubleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: _isFocused
            ? BoxDecoration(
          border: Border.all(color: AppTheme.warning, width: 2.5),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.warning.withOpacity(0.35),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        )
            : null,
        child: widget.child,
      ),
    );
  }
}

/// Botón accesible con estilo BilletesMx
class AccessibleButton extends StatelessWidget {
  final String description;
  final String label;
  final VoidCallback? onActivate;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final double height;
  final bool enabled;

  const AccessibleButton({
    Key? key,
    required this.description,
    required this.label,
    this.onActivate,
    this.backgroundColor,
    this.textColor,
    this.icon,
    this.height = 56,
    this.enabled = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? AppTheme.primary;
    final fgColor = textColor ?? AppTheme.textOnPrimary;

    return AccessibleWidget(
      description: description,
      onActivate: onActivate,
      enabled: enabled,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            backgroundColor: enabled ? bgColor : AppTheme.divider,
            disabledBackgroundColor: enabled ? bgColor : AppTheme.divider,
            elevation: enabled ? 2 : 0,
            shadowColor: bgColor.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: fgColor, size: 22),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fgColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}