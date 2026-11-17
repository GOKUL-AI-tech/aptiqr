import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// College-crest placeholder mark used on splash/role-select/login
/// screens. Swap the child Icon for `Image.asset('assets/images/crest.png')`
/// once the real crest artwork is dropped into assets/images/.
class AppLogo extends StatelessWidget {
  final double size;
  final Color? background;
  const AppLogo({super.key, this.size = 84, this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: AppColors.primaryOrange.withOpacity(0.22), blurRadius: 22, offset: const Offset(0, 10)),
          BoxShadow(color: AppColors.shadow, blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Icon(Icons.school_rounded, size: size * 0.5, color: AppColors.primaryOrange),
    );
  }
}
