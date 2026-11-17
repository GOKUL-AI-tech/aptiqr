import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

class LoadingButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback? onPressed;
  final Color? color;

  const LoadingButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: color == null
          ? null
          : ButtonStyle(
              backgroundColor: MaterialStateProperty.resolveWith(
                (states) => states.contains(MaterialState.disabled) ? AppColors.surfaceAlt : color,
              ),
              foregroundColor: MaterialStateProperty.resolveWith(
                (states) => states.contains(MaterialState.disabled) ? AppColors.textSecondary : Colors.white,
              ),
              shadowColor: MaterialStatePropertyAll(color!.withOpacity(0.35)),
            ),
      child: loading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Text(label),
    );
  }
}
