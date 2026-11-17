import 'test_category.dart';

enum QuestionDifficulty { easy, medium, hard }

QuestionDifficulty difficultyFromString(String value) {
  return QuestionDifficulty.values.firstWhere(
    (d) => d.name == value,
    orElse: () => QuestionDifficulty.medium,
  );
}

class Question {
  final String id;
  /// Broad partition (Aptitude/Technical/Communication) — which admin's
  /// bank this question belongs to. Distinct from [subject]/[topic],
  /// which stay free-text sub-topics *within* this category.
  final TestCategory category;
  final String subject;
  final String? topic;
  final String questionText;
  final String optionA;
  final String optionB;
  final String optionC;
  final String optionD;
  final String correctOption; // A/B/C/D — hidden from students at answer-time
  final QuestionDifficulty difficulty;
  final bool isActive;

  const Question({
    required this.id,
    required this.category,
    required this.subject,
    required this.questionText,
    required this.optionA,
    required this.optionB,
    required this.optionC,
    required this.optionD,
    required this.correctOption,
    this.topic,
    this.difficulty = QuestionDifficulty.medium,
    this.isActive = true,
  });

  Map<String, String> get options => {
        'A': optionA,
        'B': optionB,
        'C': optionC,
        'D': optionD,
      };

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] as String,
      category: TestCategoryX.fromString(json['category'] as String? ?? 'aptitude'),
      subject: json['subject'] as String,
      topic: json['topic'] as String?,
      questionText: json['question_text'] as String,
      optionA: json['option_a'] as String,
      optionB: json['option_b'] as String,
      optionC: json['option_c'] as String,
      optionD: json['option_d'] as String,
      correctOption: json['correct_option'] as String,
      difficulty: difficultyFromString(json['difficulty'] as String? ?? 'medium'),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'category': category.value,
        'subject': subject,
        'topic': topic,
        'question_text': questionText,
        'option_a': optionA,
        'option_b': optionB,
        'option_c': optionC,
        'option_d': optionD,
        'correct_option': correctOption,
        'difficulty': difficulty.name,
        'is_active': isActive,
      };
}
