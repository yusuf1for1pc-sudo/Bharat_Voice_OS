enum AppScreen {
  onboarding,
  home,
  listening,
  processing,
  resultAgent,
  resultAnswer,
  confirmation,
  history,
  agentMode,
}

enum RingState {
  idle,
  active, // blob
  listening,
  processing,
}

class TaskResult {
  final String mode; // 'agent', 'answer', 'confirm'
  final String title;
  final String? answer;
  final List<TaskDetail>? details;
  final String? audioBase64;
  final String? detectedLanguage;
  final String? confirmQuestion;

  TaskResult({
    required this.mode,
    required this.title,
    this.answer,
    this.details,
    this.audioBase64,
    this.detectedLanguage,
    this.confirmQuestion,
  });

  factory TaskResult.fromJson(Map<String, dynamic> json) {
    return TaskResult(
      mode: json['mode'] as String,
      title: json['title'] as String? ?? '',
      answer: json['answer'] as String?,
      details: (json['details'] as List<dynamic>?)
          ?.map((d) => TaskDetail.fromJson(d as Map<String, dynamic>))
          .toList(),
      audioBase64: json['audio_base64'] as String?,
      detectedLanguage: json['detected_language'] as String?,
      confirmQuestion: json['confirm_question'] as String?,
    );
  }
}

class TaskDetail {
  final String icon;
  final String text;

  TaskDetail({required this.icon, required this.text});

  factory TaskDetail.fromJson(Map<String, dynamic> json) {
    return TaskDetail(
      icon: json['icon'] as String? ?? '•',
      text: json['text'] as String? ?? '',
    );
  }
}

class HistoryItem {
  final String icon;
  final String title;
  final String subtitle;
  final String time;

  HistoryItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
  });
}
