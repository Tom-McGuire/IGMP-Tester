import 'package:material_ui/material_ui.dart';

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
    final bgColor = isWarning
        ? const Color(0xFF4B3711)
        : const Color(0xFF5A1D1D);
    final accentColor = isWarning
        ? const Color(0xFFFFC14D)
        : const Color(0xFFFF8B8B);
    final textColor = isWarning
        ? const Color(0xFFFFECC2)
        : const Color(0xFFFFD2D2);

    return Container(
      width: double.infinity,
      color: bgColor,
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
