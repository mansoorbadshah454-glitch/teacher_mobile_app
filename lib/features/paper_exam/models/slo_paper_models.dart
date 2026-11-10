import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single Student Learning Outcome (SLO)
class SloItem {
  final String sloCode;
  final String statement;

  const SloItem({
    required this.sloCode,
    required this.statement,
  });

  factory SloItem.fromJson(Map<String, dynamic> json) {
    return SloItem(
      sloCode: (json['slo_code'] ?? json['sloCode'] ?? '').toString(),
      statement: (json['statement'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'slo_code': sloCode,
      'statement': statement,
    };
  }

  SloItem copyWith({String? sloCode, String? statement}) {
    return SloItem(
      sloCode: sloCode ?? this.sloCode,
      statement: statement ?? this.statement,
    );
  }
}

/// Represents a question in the question bank
class SloQuestion {
  final String id;
  final String sloCode;
  final String type; // "MCQ" | "SHORT" | "LONG"
  final String cognitiveLevel; // "Knowledge" | "Understanding" | "Application"
  final String questionText;
  final List<String> options; // Empty for SHORT & LONG
  final String correctAnswer;
  final String rubric;

  const SloQuestion({
    required this.id,
    required this.sloCode,
    required this.type,
    required this.cognitiveLevel,
    required this.questionText,
    this.options = const [],
    required this.correctAnswer,
    required this.rubric,
  });

  factory SloQuestion.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['options'];
    List<String> parsedOptions = [];
    if (rawOptions is List) {
      parsedOptions = rawOptions.map((e) => e.toString()).toList();
    }

    return SloQuestion(
      id: (json['id'] ?? '').toString(),
      sloCode: (json['slo_code'] ?? json['sloCode'] ?? '').toString(),
      type: (json['type'] ?? 'SHORT').toString().toUpperCase(),
      cognitiveLevel: (json['cognitive_level'] ?? json['cognitiveLevel'] ?? 'Understanding').toString(),
      questionText: (json['question_text'] ?? json['questionText'] ?? '').toString(),
      options: parsedOptions,
      correctAnswer: (json['correct_answer'] ?? json['correctAnswer'] ?? '').toString(),
      rubric: (json['rubric'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slo_code': sloCode,
      'type': type,
      'cognitive_level': cognitiveLevel,
      'question_text': questionText,
      'options': options,
      'correct_answer': correctAnswer,
      'rubric': rubric,
    };
  }

  SloQuestion copyWith({
    String? id,
    String? sloCode,
    String? type,
    String? cognitiveLevel,
    String? questionText,
    List<String>? options,
    String? correctAnswer,
    String? rubric,
  }) {
    return SloQuestion(
      id: id ?? this.id,
      sloCode: sloCode ?? this.sloCode,
      type: type ?? this.type,
      cognitiveLevel: cognitiveLevel ?? this.cognitiveLevel,
      questionText: questionText ?? this.questionText,
      options: options ?? this.options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      rubric: rubric ?? this.rubric,
    );
  }
}

/// Represents the single-document bundled bank for a chapter
class ChapterBankDoc {
  final String docId;
  final String publisher;
  final String grade;
  final String subject;
  final int chapterNumber;
  final String chapterTitle;
  final bool isRtl;
  final List<SloItem> slos;
  final List<SloQuestion> questions;
  final dynamic updatedAt;

  const ChapterBankDoc({
    required this.docId,
    required this.publisher,
    required this.grade,
    required this.subject,
    required this.chapterNumber,
    required this.chapterTitle,
    this.isRtl = false,
    this.slos = const [],
    this.questions = const [],
    this.updatedAt,
  });

  /// Build docId following standard format: {publisher}_{grade}_{subject}_CH{chapterNumber}
  static String generateDocId({
    required String publisher,
    required String grade,
    required String subject,
    required int chapterNumber,
  }) {
    final pubClean = publisher.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    final subClean = subject.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    return '${pubClean}_${grade}_${subClean}_CH$chapterNumber';
  }

  factory ChapterBankDoc.fromJson(Map<String, dynamic> json) {
    final rawSlos = json['slos'];
    List<SloItem> parsedSlos = [];
    if (rawSlos is List) {
      parsedSlos = rawSlos
          .whereType<Map<String, dynamic>>()
          .map((e) => SloItem.fromJson(e))
          .toList();
    }

    final rawQuestions = json['questions'];
    List<SloQuestion> parsedQuestions = [];
    if (rawQuestions is List) {
      parsedQuestions = rawQuestions
          .whereType<Map<String, dynamic>>()
          .map((e) => SloQuestion.fromJson(e))
          .toList();
    }

    return ChapterBankDoc(
      docId: (json['doc_id'] ?? json['docId'] ?? '').toString(),
      publisher: (json['publisher'] ?? '').toString(),
      grade: (json['grade'] ?? '').toString(),
      subject: (json['subject'] ?? '').toString(),
      chapterNumber: (json['chapter_number'] ?? json['chapterNumber'] ?? 1) is int
          ? (json['chapter_number'] ?? json['chapterNumber'] ?? 1)
          : int.tryParse((json['chapter_number'] ?? json['chapterNumber'] ?? 1).toString()) ?? 1,
      chapterTitle: (json['chapter_title'] ?? json['chapterTitle'] ?? '').toString(),
      isRtl: json['is_rtl'] == true || json['isRtl'] == true,
      slos: parsedSlos,
      questions: parsedQuestions,
      updatedAt: json['updated_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'doc_id': docId,
      'publisher': publisher,
      'grade': grade,
      'subject': subject,
      'chapter_number': chapterNumber,
      'chapter_title': chapterTitle,
      'is_rtl': isRtl,
      'slos': slos.map((s) => s.toJson()).toList(),
      'questions': questions.map((q) => q.toJson()).toList(),
      'updated_at': updatedAt ?? FieldValue.serverTimestamp(),
    };
  }

  ChapterBankDoc copyWith({
    String? docId,
    String? publisher,
    String? grade,
    String? subject,
    int? chapterNumber,
    String? chapterTitle,
    bool? isRtl,
    List<SloItem>? slos,
    List<SloQuestion>? questions,
    dynamic updatedAt,
  }) {
    return ChapterBankDoc(
      docId: docId ?? this.docId,
      publisher: publisher ?? this.publisher,
      grade: grade ?? this.grade,
      subject: subject ?? this.subject,
      chapterNumber: chapterNumber ?? this.chapterNumber,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      isRtl: isRtl ?? this.isRtl,
      slos: slos ?? this.slos,
      questions: questions ?? this.questions,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Blueprint Configuration for Paper Generation
class PaperBlueprintConfig {
  final String schoolName;
  final String? campusOrAddress;
  final String? boardAffiliation;
  final String examTitle;
  final String timeAllowed;
  final int totalMarks;
  final int mcqCount;
  final int shortCount;
  final int longCount;
  final double knowledgeRatio; // Default 0.30
  final double understandingRatio; // Default 0.50
  final double applicationRatio; // Default 0.20

  const PaperBlueprintConfig({
    required this.schoolName,
    this.campusOrAddress,
    this.boardAffiliation,
    required this.examTitle,
    required this.timeAllowed,
    required this.totalMarks,
    this.mcqCount = 10,
    this.shortCount = 8,
    this.longCount = 3,
    this.knowledgeRatio = 0.30,
    this.understandingRatio = 0.50,
    this.applicationRatio = 0.20,
  });

  PaperBlueprintConfig copyWith({
    String? schoolName,
    String? campusOrAddress,
    String? boardAffiliation,
    String? examTitle,
    String? timeAllowed,
    int? totalMarks,
    int? mcqCount,
    int? shortCount,
    int? longCount,
    double? knowledgeRatio,
    double? understandingRatio,
    double? applicationRatio,
  }) {
    return PaperBlueprintConfig(
      schoolName: schoolName ?? this.schoolName,
      campusOrAddress: campusOrAddress ?? this.campusOrAddress,
      boardAffiliation: boardAffiliation ?? this.boardAffiliation,
      examTitle: examTitle ?? this.examTitle,
      timeAllowed: timeAllowed ?? this.timeAllowed,
      totalMarks: totalMarks ?? this.totalMarks,
      mcqCount: mcqCount ?? this.mcqCount,
      shortCount: shortCount ?? this.shortCount,
      longCount: longCount ?? this.longCount,
      knowledgeRatio: knowledgeRatio ?? this.knowledgeRatio,
      understandingRatio: understandingRatio ?? this.understandingRatio,
      applicationRatio: applicationRatio ?? this.applicationRatio,
    );
  }
}
