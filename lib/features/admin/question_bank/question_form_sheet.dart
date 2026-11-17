import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/question.dart';
import '../../../models/test_category.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/loading_button.dart';

Future<void> showQuestionFormSheet(BuildContext context, WidgetRef ref, {Question? existing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _QuestionFormSheet(existing: existing),
  );
}

class _QuestionFormSheet extends ConsumerStatefulWidget {
  final Question? existing;
  const _QuestionFormSheet({this.existing});

  @override
  ConsumerState<_QuestionFormSheet> createState() => _QuestionFormSheetState();
}

class _QuestionFormSheetState extends ConsumerState<_QuestionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _subject;
  late final TextEditingController _topic;
  late final TextEditingController _text;
  late final TextEditingController _a;
  late final TextEditingController _b;
  late final TextEditingController _c;
  late final TextEditingController _d;
  String _correct = 'A';
  QuestionDifficulty _difficulty = QuestionDifficulty.medium;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _subject = TextEditingController(text: e?.subject ?? '');
    _topic = TextEditingController(text: e?.topic ?? '');
    _text = TextEditingController(text: e?.questionText ?? '');
    _a = TextEditingController(text: e?.optionA ?? '');
    _b = TextEditingController(text: e?.optionB ?? '');
    _c = TextEditingController(text: e?.optionC ?? '');
    _d = TextEditingController(text: e?.optionD ?? '');
    _correct = e?.correctOption ?? 'A';
    _difficulty = e?.difficulty ?? QuestionDifficulty.medium;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    // Category is never user-chosen here — a new question always lands
    // in the signed-in admin's own category (matching the RLS policy
    // that would reject any other value), and an edit keeps whatever
    // category it already had (which, since this admin could only ever
    // have loaded it via questionsProvider in the first place, is
    // necessarily their own).
    final category = widget.existing?.category ??
        ref.read(currentAdminProvider).valueOrNull?.category ??
        TestCategory.aptitude;
    final q = Question(
      id: widget.existing?.id ?? '',
      category: category,
      subject: _subject.text.trim(),
      topic: _topic.text.trim(),
      questionText: _text.text.trim(),
      optionA: _a.text.trim(),
      optionB: _b.text.trim(),
      optionC: _c.text.trim(),
      optionD: _d.text.trim(),
      correctOption: _correct,
      difficulty: _difficulty,
    );
    try {
      final service = ref.read(adminServiceProvider);
      if (widget.existing == null) {
        await service.createQuestion(q);
      } else {
        await service.updateQuestion(widget.existing!.id, q);
      }
      ref.invalidate(questionsProvider);
      ref.invalidate(subjectsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // Previously uncaught — a failed insert/update (e.g. this admin's
      // category didn't match the RLS policy, or a network drop) left
      // the Save button stuck spinning forever with no error shown and
      // no way to tell the save actually failed.
      setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Form(
          key: _formKey,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Text(widget.existing == null ? 'Add question' : 'Edit question', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject'), validator: _req),
              const SizedBox(height: 12),
              TextFormField(controller: _topic, decoration: const InputDecoration(labelText: 'Topic (optional)')),
              const SizedBox(height: 12),
              TextFormField(controller: _text, decoration: const InputDecoration(labelText: 'Question'), maxLines: 3, validator: _req),
              const SizedBox(height: 12),
              TextFormField(controller: _a, decoration: const InputDecoration(labelText: 'Option A'), validator: _req),
              const SizedBox(height: 12),
              TextFormField(controller: _b, decoration: const InputDecoration(labelText: 'Option B'), validator: _req),
              const SizedBox(height: 12),
              TextFormField(controller: _c, decoration: const InputDecoration(labelText: 'Option C'), validator: _req),
              const SizedBox(height: 12),
              TextFormField(controller: _d, decoration: const InputDecoration(labelText: 'Option D'), validator: _req),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _correct,
                      decoration: const InputDecoration(labelText: 'Correct option'),
                      items: const ['A', 'B', 'C', 'D'].map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                      onChanged: (v) => setState(() => _correct = v ?? 'A'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<QuestionDifficulty>(
                      value: _difficulty,
                      decoration: const InputDecoration(labelText: 'Difficulty'),
                      items: QuestionDifficulty.values.map((d) => DropdownMenuItem(value: d, child: Text(d.name))).toList(),
                      onChanged: (v) => setState(() => _difficulty = v ?? QuestionDifficulty.medium),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 20),
              LoadingButton(label: 'Save', loading: _saving, onPressed: _save, color: AppColors.admin),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;
}
