import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/question.dart';
import '../../../models/test_category.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/async_value_widget.dart';
import '../../../widgets/home_back_button.dart';
import '../../../widgets/refresh_icon_button.dart';
import 'question_form_sheet.dart';

/// Deck slide 07 — "Upload 3,000+ questions by Excel/CSV, add, edit,
/// delete, search, filter and export by subject or difficulty."
///
/// Every question shown/added/edited here belongs to the signed-in
/// admin's own category (Aptitude/Technical/Communication) — enforced
/// server-side by RLS (see supabase/policies.sql), and surfaced here as
/// a banner so it's clear at a glance which bank is being edited.
class QuestionBankScreen extends ConsumerWidget {
  const QuestionBankScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questionsAsync = ref.watch(questionsProvider);
    final subjectsAsync = ref.watch(subjectsProvider);
    final filter = ref.watch(questionFilterProvider);
    final adminAsync = ref.watch(currentAdminProvider);
    final categoryLabel = adminAsync.valueOrNull?.category.label;

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryLabel == null ? 'Question Bank' : '$categoryLabel Question Bank'),
        leading: const HomeBackButton(homeRoute: '/admin'),
        actions: [
          RefreshIconButton(onRefresh: () async {
            ref.invalidate(questionsProvider);
            ref.invalidate(subjectsProvider);
            await ref.read(questionsProvider.future);
          }),
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Bulk import',
            onPressed: () => context.push('/admin/question-bank/upload'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showQuestionFormSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add question'),
        backgroundColor: AppColors.admin,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search questions...', isDense: true),
              onSubmitted: (v) => ref.read(questionFilterProvider.notifier).state =
                  QuestionFilter(subject: filter.subject, difficulty: filter.difficulty, search: v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                subjectsAsync.when(
                  data: (subjects) => Row(
                    children: [
                      _FilterChip(
                        label: 'All subjects',
                        selected: filter.subject == null,
                        onTap: () => ref.read(questionFilterProvider.notifier).state =
                            QuestionFilter(difficulty: filter.difficulty, search: filter.search),
                      ),
                      ...subjects.map((s) => _FilterChip(
                            label: s,
                            selected: filter.subject == s,
                            onTap: () => ref.read(questionFilterProvider.notifier).state =
                                QuestionFilter(subject: s, difficulty: filter.difficulty, search: filter.search),
                          )),
                    ],
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (e, st) => const SizedBox.shrink(),
                ),
                const SizedBox(width: 12),
                ...QuestionDifficulty.values.map((d) => _FilterChip(
                      label: d.name,
                      selected: filter.difficulty == d,
                      onTap: () => ref.read(questionFilterProvider.notifier).state = QuestionFilter(
                        subject: filter.subject,
                        search: filter.search,
                        difficulty: filter.difficulty == d ? null : d,
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncValueWidget<List<Question>>(
              value: questionsAsync,
              data: (questions) {
                if (questions.isEmpty) {
                  return const EmptyState(icon: Icons.menu_book_outlined, title: 'No questions match these filters');
                }
                return RefreshIndicator(
                  color: AppColors.admin,
                  onRefresh: () async {
                    ref.invalidate(questionsProvider);
                    ref.invalidate(subjectsProvider);
                    await ref.read(questionsProvider.future);
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                    itemCount: questions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _QuestionTile(question: questions[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap(), selectedColor: AppColors.adminLight),
    );
  }
}

class _QuestionTile extends ConsumerWidget {
  final Question question;
  const _QuestionTile({required this.question});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.adminLight, borderRadius: BorderRadius.circular(20)),
                child: Text(question.subject, style: const TextStyle(fontSize: 11, color: AppColors.admin, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Text(question.difficulty.name, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  final service = ref.read(adminServiceProvider);
                  try {
                    if (value == 'edit') {
                      showQuestionFormSheet(context, ref, existing: question);
                    } else if (value == 'delete') {
                      await service.deleteQuestion(question.id);
                      ref.invalidate(questionsProvider);
                    } else if (value == 'toggle') {
                      await service.setQuestionActive(question.id, !question.isActive);
                      ref.invalidate(questionsProvider);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'toggle', child: Text(question.isActive ? 'Deactivate' : 'Activate')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(question.questionText, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
