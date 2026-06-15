import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class StepIndicator extends StatelessWidget {
  final List<String> steps;
  final int currentStep;

  const StepIndicator({
    super.key,
    required this.steps,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < steps.length; i++) ...[
            _StepItem(
              label: steps[i],
              isActive: i == currentStep,
              isDone: i < currentStep,
            ),
            if (i < steps.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '▼',
                  style: TextStyle(color: AppColors.stepInactive, fontSize: 10),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isDone;

  const _StepItem({
    required this.label,
    required this.isActive,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: (isActive || isDone) ? AppColors.stepActive : AppColors.stepInactive,
      fontSize: 13,
      fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
    );

    if (isActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.stepActive, width: 1.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: style),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Text(label, style: style),
    );
  }
}
