import 'package:flutter/material.dart';
import '../services/ai_service.dart';

/// Empty / error state when the AI backend is unreachable (common in demo auth).
class AiBackendRequiredView extends StatelessWidget {
  final VoidCallback? onRetry;
  final String? detail;

  const AiBackendRequiredView({super.key, this.onRetry, this.detail});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off_rounded, color: Colors.white.withAlpha(70), size: 52),
          const SizedBox(height: 16),
          const Text('AI requires backend',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 17,
                fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(detail ?? AiService.backendRequiredMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withAlpha(150),
                fontSize: 13, height: 1.5)),
          if (onRetry != null) ...[
            const SizedBox(height: 22),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, color: Color(0xFF4F8AFF)),
              label: const Text('Try again',
                style: TextStyle(color: Color(0xFF4F8AFF),
                    fontWeight: FontWeight.w600)),
            ),
          ],
        ]),
      ),
    );
  }
}
