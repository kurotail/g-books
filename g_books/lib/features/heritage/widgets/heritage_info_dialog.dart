import 'package:flutter/material.dart';
import '../../../data/models/heritage_model.dart';

class HeritageInfoDialog extends StatelessWidget {
  final HeritageModel heritage;
  const HeritageInfoDialog({super.key, required this.heritage});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1200),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFF4A3800)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                heritage.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFF4A3800)),
              const SizedBox(height: 16),
              Text(
                heritage.description.isNotEmpty
                    ? heritage.description
                    : '簡介尚未開放，敬請期待。',
                style: const TextStyle(
                  color: Color(0xFFCCB88A),
                  fontSize: 15,
                  height: 2.0,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    '關 閉',
                    style: TextStyle(
                      color: Color(0xFFD4A843),
                      letterSpacing: 5,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
