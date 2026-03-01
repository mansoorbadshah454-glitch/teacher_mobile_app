import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/attendance/providers/attendance_provider.dart';

// Provides metrics score data
class ClassMetrics {
  final int classScore;
  final int subjectScore;
  final int homeworkScore;

  ClassMetrics({
    this.classScore = 0,
    this.subjectScore = 0,
    this.homeworkScore = 0,
  });
}

// 1. Provider to calculate the class metrics based on assigned students and subjects
final classMetricsProvider = Provider<AsyncValue<ClassMetrics>>((ref) {
  final assignedClassAsync = ref.watch(assignedClassProvider);
  final studentsAsync = ref.watch(classStudentsProvider);

  if (assignedClassAsync.isLoading || studentsAsync.isLoading) {
    return const AsyncValue.loading();
  }

  if (assignedClassAsync.hasError) {
    return AsyncValue.error(assignedClassAsync.error!, assignedClassAsync.stackTrace!);
  }

  if (studentsAsync.hasError) {
    return AsyncValue.error(studentsAsync.error!, studentsAsync.stackTrace!);
  }

  final assignedClass = assignedClassAsync.value;
  final students = studentsAsync.value;

  if (assignedClass == null || students == null || students.isEmpty) {
    return AsyncValue.data(ClassMetrics());
  }

  final currentSubjects = List<String>.from(assignedClass['subjects'] ?? []);

  if (currentSubjects.isEmpty) {
    return AsyncValue.data(ClassMetrics());
  }

  int totalSubjectScoresSum = 0;
  int totalHomeworkScoresSum = 0;

  for (var s in students) {
    // Subject Scores
    final subScoresRaw = List<dynamic>.from(s['academicScores'] ?? []);
    final subScores = subScoresRaw
        .where((i) => currentSubjects.contains(i['subject']))
        .map((i) => int.tryParse(i['score'].toString()) ?? 0)
        .toList();

    for (var score in subScores) {
      totalSubjectScoresSum += score;
    }

    // Homework Scores
    final hwScoresRaw = List<dynamic>.from(s['homeworkScores'] ?? []);
    final hwScores = hwScoresRaw
        .where((i) => currentSubjects.contains(i['subject']))
        .map((i) => int.tryParse(i['score'].toString()) ?? 0)
        .toList();

    for (var score in hwScores) {
      totalHomeworkScoresSum += score;
    }
  }

  final totalExpectedScoresNumber = students.length * currentSubjects.length;

  final avgSubject = totalExpectedScoresNumber > 0 ? (totalSubjectScoresSum / totalExpectedScoresNumber) : 0.0;
  final avgHomework = totalExpectedScoresNumber > 0 ? (totalHomeworkScoresSum / totalExpectedScoresNumber) : 0.0;

  final totalCombinedScoresSum = totalSubjectScoresSum + totalHomeworkScoresSum;
  final totalCombinedExpectedNumber = totalExpectedScoresNumber * 2;
  
  final classScore = totalCombinedExpectedNumber > 0 ? (totalCombinedScoresSum / totalCombinedExpectedNumber) : 0.0;

  return AsyncValue.data(ClassMetrics(
    classScore: classScore.round(),
    subjectScore: avgSubject.round(),
    homeworkScore: avgHomework.round(),
  ));
});

// 2. Fetch Today's Attendance for Absent Count
final todaysAbsentCountProvider = StreamProvider<int>((ref) {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final assignedClassAsync = ref.watch(assignedClassProvider);

  if (teacherDataAsync.value == null || assignedClassAsync.value == null) {
    return Stream.value(0);
  }

  final String schoolId = teacherDataAsync.value!['schoolId'];
  final String classId = assignedClassAsync.value!['id'];
  
  // Format YYYY-MM-DD
  final today = DateTime.now().toIso8601String().split('T')[0];

  return FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('attendance')
      .where('classId', isEqualTo: classId)
      .where('date', isEqualTo: today)
      .snapshots()
      .map((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final docs = snapshot.docs.toList();
          docs.sort((a, b) {
            final tA = a.data()['timestamp'] as Timestamp?;
            final tB = b.data()['timestamp'] as Timestamp?;
            if (tA == null && tB == null) return 0;
            if (tA == null) return 1;
            if (tB == null) return -1;
            return tB.compareTo(tA); // Descending order
          });

          final data = docs.first.data();
          final records = List<dynamic>.from(data['records'] ?? []);
          return records.where((r) => r['status'] == 'absent').length;
        }
        return 0;
      });
});

// State provider for searching students in My Class View
final myClassSearchQueryProvider = StateProvider<String>((ref) => '');
