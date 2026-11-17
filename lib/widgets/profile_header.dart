import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

/// Shared hero header for the three Profile screens (student/faculty/
/// admin) — previously each one just centered a flat CircleAvatar on the
/// plain scaffold background, which is why the whole page read as bare.
/// This mirrors the gradient-banner language already used on the Home
/// and Today's QR screens (rounded bottom corners, soft blob decoration,
/// role-colored gradient) so Profile finally looks like it belongs to
/// the same app instead of a leftover placeholder screen.
class ProfileHeader extends StatelessWidget {
  final String role;
  final String name;
  final String? subtitle;

  const ProfileHeader({super.key, required this.role, required this.name, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.gradientForRole(role);
    final trimmedName = name.trim();
    // A "?" reads as an error state ("something's wrong/unknown") rather
    // than "no name on file yet" — this account (e.g. an admin seeded
    // directly in Supabase without ever filling in full_name) genuinely
    // has no name, which is a normal, expected case, not a bug. A plain
    // person icon communicates that without looking broken.
    final initial = trimmedName.isNotEmpty ? trimmedName[0].toUpperCase() : null;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 22, 20, 28),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        ),
        child: Stack(
          children: [
            Positioned(top: -50, right: -40, child: _blob(140, 0.09)),
            Positioned(bottom: -34, left: -26, child: _blob(100, 0.07)),
            Column(
              children: [
                Container(
                  width: 78,
                  height: 78,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 5))],
                  ),
                  child: initial != null
                      ? Text(initial, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: colors.first))
                      : Icon(Icons.person_rounded, size: 38, color: colors.first),
                ),
                const SizedBox(height: 14),
                // Skip the name line entirely rather than rendering an
                // empty, oddly-tall blank Text — for a no-name account the
                // subtitle pill (email/register no./ID) below is the only
                // identity worth showing.
                if (trimmedName.isNotEmpty)
                  Text(trimmedName, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
                    child: Text(subtitle!, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(double size, double opacity) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(opacity)));
}
