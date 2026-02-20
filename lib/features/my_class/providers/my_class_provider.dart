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
  final studentCount = students.length;

  double totalSubjectScore = 0;
  double totalHomeworkScore = 0;
  double totalAttendance = 0;

  for (var s in students) {
    // Subject Score Avg
    final subScoresRaw = List<dynamic>.from(s['academicScores'] ?? []);
    final subScores = subScoresRaw
        .where((i) => currentSubjects.contains(i['subject']))
        .map((i) => int.tryParse(i['score'].toString()) ?? 0)
        .toList();

    double subAvg = 0;
    if (subScores.isNotEmpty) {
      subAvg = subScores.reduce((a, b) => a + b) / subScores.length;
    }
    totalSubjectScore += subAvg;

    // Homework Score Avg
    final hwScoresRaw = List<dynamic>.from(s['homeworkScores'] ?? []);
    final hwScores = hwScoresRaw
        .where((i) => currentSubjects.contains(i['subject']))
        .map((i) => int.tryParse(i['score'].toString()) ?? 0)
        .toList();

    double hwAvg = 0;
    if (hwScores.isNotEmpty) {
      hwAvg = hwScores.reduce((a, b) => a + b) / hwScores.length;
    }
    totalHomeworkScore += hwAvg;

    // Attendance
    totalAttendance += (int.tryParse(s['attendance'].toString()) ?? 85);
  }

  final avgSubject = studentCount > 0 ? (totalSubjectScore / studentCount) : 0;
  final avgHomework = studentCount > 0 ? (totalHomeworkScore / studentCount) : 0;
  final avgAttendance = studentCount > 0 ? (totalAttendance / studentCount) : 0;

  final classScore = (avgSubject + avgHomework + avgAttendance) / 3;

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
      .orderBy('timestamp', descending: true)
      .limit(1)
      .snapshots()
      .map((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final data = snapshot.docs.first.data();
          final records = List<dynamic>.from(data['records'] ?? []);
          return records.where((r) => r['status'] == 'absent').length;
        }
        return 0;
      });
});

// State provider for searching students in My Class View
final myClassSearchQueryProvider = StateProvider<String>((ref) => '');
