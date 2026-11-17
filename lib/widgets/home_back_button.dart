import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Leading AppBar icon for bottom-nav tab screens that aren't the "home"
/// tab of their role's shell (Home for student, Today's QR for faculty,
/// Dashboard for admin). Those root tabs have no previous screen to pop
/// to — go_router doesn't add a back arrow there by default — so this
/// gives every other tab a consistent way back to that role's home tab
/// instead of leaving them without one.
class HomeBackButton extends StatelessWidget {
  final String homeRoute;
  const HomeBackButton({super.key, required this.homeRoute});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      tooltip: 'Home',
      onPressed: () => context.go(homeRoute),
    );
  }
}
