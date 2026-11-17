import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/daily_test.dart';
import '../../../models/test_category.dart';
import '../../../widgets/test_qr_card.dart';

/// Lets an admin view/download/share the QR for one daily test — reached
/// either immediately after generating a test (see
/// DailyTestConfigScreen._generate) or "any time" afterwards by tapping a
/// test in the "Recent tests" list, so an admin isn't limited to sharing
/// the QR only in the moment right after generating it.
///
/// Uses the same [TestQrCard] the faculty "Today's QR" screen shows, so
/// the download/share behavior is identical for both roles — see that
/// widget's doc comment.
class AdminTestQrScreen extends StatelessWidget {
  final DailyTest test;
  const AdminTestQrScreen({super.key, required this.test});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${test.category.label} QR'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: TestQrCard(test: test),
      ),
    );
  }
}
