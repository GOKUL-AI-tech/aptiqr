import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

class ProfileInfoItem {
  final IconData icon;
  final String label;
  final String value;
  const ProfileInfoItem({required this.icon, required this.label, required this.value});
}

/// Replaces the old bare "label ... value" text rows (no card, no icons,
/// no visual separation from the plain background) with a single bordered,
/// softly-shadowed card — icon chips give each field a visual anchor and
/// dividers separate rows, instead of relying on vertical spacing alone.
class ProfileInfoCard extends StatelessWidget {
  final String role;
  final List<ProfileInfoItem> items;
  const ProfileInfoCard({super.key, required this.role, required this.items});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.forRole(role);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _row(items[i], accent),
            if (i != items.length - 1) const Divider(height: 1, indent: 58, color: AppColors.border),
          ],
        ],
      ),
    );
  }

  Widget _row(ProfileInfoItem item, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
            child: Icon(item.icon, size: 17, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(item.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              item.value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
