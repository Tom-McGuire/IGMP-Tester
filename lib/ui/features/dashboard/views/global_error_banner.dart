import 'package:material_ui/material_ui.dart';
import '../../../theme/app_theme.dart';

class GlobalErrorBanner extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onDismiss;
  final bool isWarning;

  const GlobalErrorBanner({
    super.key,
    required this.errorMessage,
    required this.onDismiss,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = AppTheme.isDark;
    final Color bgColor;
    final Color accentColor;
    final Color textColor;
    final Color borderColor;

    if (isWarning) {
      bgColor = isDark ? const Color(0xFF4B3711) : const Color(0xFFFFFBEB);
      accentColor = isDark ? const Color(0xFFFFC14D) : const Color(0xFFD97706);
      textColor = isDark ? const Color(0xFFFFECC2) : const Color(0xFF92400E);
      borderColor = isDark
          ? const Color(0xFFFFC14D).withValues(alpha: 0.35)
          : const Color(0xFFD97706).withValues(alpha: 0.45);
    } else {
      bgColor = isDark ? const Color(0xFF5A1D1D) : const Color(0xFFFEF2F2);
      accentColor = isDark ? const Color(0xFFFF8B8B) : const Color(0xFFDC2626);
      textColor = isDark ? const Color(0xFFFFD2D2) : const Color(0xFF991B1B);
      borderColor = isDark
          ? const Color(0xFFFF8B8B).withValues(alpha: 0.35)
          : const Color(0xFFDC2626).withValues(alpha: 0.45);
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: borderColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.error_outline,
            color: accentColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: accentColor, size: 16),
            onPressed: onDismiss,
            tooltip: 'Dismiss',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
