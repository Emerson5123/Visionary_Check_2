import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/accessible_widget.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onSettingsPressed;
  final VoidCallback? onHistoryPressed;
  final VoidCallback? onDeletePressed;
  final VoidCallback? onBackPressed;
  final bool showBackButton;

  const CustomAppBar({
    Key? key,
    required this.title,
    this.onSettingsPressed,
    this.onHistoryPressed,
    this.onDeletePressed,
    this.onBackPressed,
    this.showBackButton = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.primary,
      elevation: 0,
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppTheme.textOnPrimary,
          letterSpacing: 0.3,
        ),
      ),
      leading: showBackButton
          ? AccessibleWidget(
        description: 'Botón volver atrás',
        onActivate: onBackPressed ?? () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back_ios_new,
            color: AppTheme.textOnPrimary, size: 22),
      )
          : Padding(
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.primaryDark,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.currency_exchange,
              color: AppTheme.textOnPrimary, size: 20),
        ),
      ),
      automaticallyImplyLeading: false,
      actions: [
        if (onDeletePressed != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: AccessibleWidget(
              description: 'Botón limpiar historial',
              onActivate: onDeletePressed,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_sweep,
                    color: AppTheme.textOnPrimary, size: 22),
              ),
            ),
          ),
        if (onHistoryPressed != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: AccessibleWidget(
              description: 'Botón historial de verificaciones',
              onActivate: onHistoryPressed,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.history,
                    color: AppTheme.textOnPrimary, size: 22),
              ),
            ),
          ),
        if (onSettingsPressed != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: AccessibleWidget(
              description: 'Botón configuración',
              onActivate: onSettingsPressed,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.settings,
                    color: AppTheme.textOnPrimary, size: 22),
              ),
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}