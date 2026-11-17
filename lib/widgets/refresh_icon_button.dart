import 'package:flutter/material.dart';

/// A manual "refresh now" affordance alongside pull-to-refresh.
/// Pull-to-refresh alone is easy to miss — nothing on screen hints it's
/// there, it doesn't work well on short/non-scrollable content, and
/// several screens in this app (dashboards with a custom gradient header
/// instead of a scrolling list, for instance) don't have a comfortable
/// pull gesture at all. This gives every data screen an explicit tap
/// target that does the exact same invalidate-and-await refetch, with
/// its own small spinner so tapping it multiple times in a row is a
/// no-op instead of stacking up redundant requests.
class RefreshIconButton extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Color? color;
  const RefreshIconButton({super.key, required this.onRefresh, this.color});

  @override
  State<RefreshIconButton> createState() => _RefreshIconButtonState();
}

class _RefreshIconButtonState extends State<RefreshIconButton> {
  bool _loading = false;

  Future<void> _run() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Refresh',
      onPressed: _loading ? null : _run,
      icon: _loading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: widget.color),
            )
          : Icon(Icons.refresh_rounded, color: widget.color),
    );
  }
}
