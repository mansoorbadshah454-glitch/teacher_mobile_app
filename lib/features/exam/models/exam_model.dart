import 'package:cloud_firestore/cloud_firestore.dart';

class ExamModel {
  final String id;
  final String title;
  final String session;
  final String status; // 'active', 'completed', 'upcoming'
  final DateTime? startDate;
  final DateTime? endDate;
  final int defaultTotalMarks;
  final int passingMarks;

  ExamModel({
    required this.id,
    required this.title,
    required this.session,
    this.status = 'active',
    this.startDate,
    this.endDate,
    this.defaultTotalMarks = 100,
    this.passingMarks = 33,
  });

  factory ExamModel.fromFirestore(String id, Map<String, dynamic> data) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return ExamModel(
      id: id,
      title: (data['title'] ?? data['name'] ?? 'Term Exam').toString(),
      session: (data['session'] ?? '').toString(),
      status: (data['status'] ?? 'active').toString(),
      startDate: parseDate(data['startDate']),
      endDate: parseDate(data['endDate']),
      defaultTotalMarks: (data['defaultTotalMarks'] as num?)?.toInt() ??
          (data['totalMarks'] as num?)?.toInt() ??
          100,
      passingMarks: (data['passingMarks'] as num?)?.toInt() ?? 33,
    );
  }
}

class ExamClassSubject {
  final String classId;
  final String className;
  final List<String> subjects;
  final int studentCount;

  ExamClassSubject({
    required this.classId,
    required this.className,
    required this.subjects,
    this.studentCount = 0,
  });

  ExamClassSubject copyWith({
    String? classId,
    String? className,
    List<String>? subjects,
    int? studentCount,
  }) {
    return ExamClassSubject(
      classId: classId ?? this.classId,
      className: className ?? this.className,
      subjects: subjects ?? this.subjects,
      studentCount: studentCount ?? this.studentCount,
    );
  }
}

class StudentMarksEntry {
  final String studentId;
  final String studentName;
  final String rollNumber;
  final String photoUrl;
  double? obtainedMarks;
  bool isAbsent;
  String remarks;

  StudentMarksEntry({
    required this.studentId,
    required this.studentName,
    required this.rollNumber,
    required this.photoUrl,
    this.obtainedMarks,
    this.isAbsent = false,
    this.remarks = '',
  });

  String getGrade(double total) {
    if (isAbsent) return 'ABS';
    if (obtainedMarks == null) return '-';
    if (total <= 0) return '-';
    final pct = (obtainedMarks! / total) * 100;
    if (pct >= 80) return 'A+';
    if (pct >= 70) return 'A';
    if (pct >= 60) return 'B';
    if (pct >= 50) return 'C';
    if (pct >= 40) return 'D';
    if (pct >= 33) return 'E';
    return 'F';
  }

  double? getPercentage(double total) {
    if (isAbsent || obtainedMarks == null || total <= 0) return null;
    return (obtainedMarks! / total) * 100;
  }
}
