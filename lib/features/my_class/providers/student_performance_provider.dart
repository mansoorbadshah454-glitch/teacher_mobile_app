import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/attendance/providers/attendance_provider.dart';

class StudentPerformanceData {
  final Map<String, int> academicScores;
  final Map<String, int> homeworkScores;
  final Map<String, int> wellness;
  final int attendance;

  StudentPerformanceData({
    required this.academicScores,
    required this.homeworkScores,
    required this.wellness,
    required this.attendance,
  });

  StudentPerformanceData copyWith({
    Map<String, int>? academicScores,
    Map<String, int>? homeworkScores,
    Map<String, int>? wellness,
    int? attendance,
  }) {
    return StudentPerformanceData(
      academicScores: academicScores ?? this.academicScores,
      homeworkScores: homeworkScores ?? this.homeworkScores,
      wellness: wellness ?? this.wellness,
      attendance: attendance ?? this.attendance,
    );
  }
}

class StudentPerformanceNotifier extends StateNotifier<AsyncValue<StudentPerformanceData?>> {
  final Ref ref;
  final String studentId;

  StudentPerformanceNotifier(this.ref, this.studentId) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    final studentsData = ref.read(classStudentsProvider).value;
    final assignedClass = ref.read(assignedClassProvider).value;

    if (studentsData == null || assignedClass == null) {
      state = const AsyncValue.data(null);
      return;
    }

    final student = studentsData.firstWhere((s) => s['id'] == studentId, orElse: () => {});
    if (student.isEmpty) {
      state = const AsyncValue.data(null);
      return;
    }

    final currentSubjects = List<String>.from(assignedClass['subjects'] ?? []);

    Map<String, int> acScores = {};
    for (String subj in currentSubjects) {
      final existing = (student['academicScores'] as List<dynamic>?)
          ?.firstWhere((s) => s['subject'] == subj, orElse: () => {'score': 0});
      acScores[subj] = int.tryParse(existing?['score'].toString() ?? '0') ?? 0;
    }

    Map<String, int> hwScores = {};
    for (String subj in currentSubjects) {
      final existing = (student['homeworkScores'] as List<dynamic>?)
          ?.firstWhere((s) => s['subject'] == subj, orElse: () => {'score': 0});
      hwScores[subj] = int.tryParse(existing?['score'].toString() ?? '0') ?? 0;
    }

    Map<String, int> wlScores = {
      'behavior': int.tryParse(student['wellness']?['behavior']?.toString() ?? '80') ?? 80,
      'health': int.tryParse(student['wellness']?['health']?.toString() ?? '80') ?? 80,
      'hygiene': int.tryParse(student['wellness']?['hygiene']?.toString() ?? '80') ?? 80,
    };

    int att = 85;
    if (student['attendance'] != null) {
        if(student['attendance'] is num) {
             att = (student['attendance'] as num).toInt();
        } else if (student['attendance'] is Map && student['attendance']['percentage'] != null) {
             att = int.tryParse(student['attendance']['percentage'].toString()) ?? 85;
        } else {
             att = int.tryParse(student['attendance'].toString()) ?? 85;
        }
    }

    state = AsyncValue.data(StudentPerformanceData(
      academicScores: acScores,
      homeworkScores: hwScores,
      wellness: wlScores,
      attendance: att,
    ));
  }

  void updateAcademicScore(String subject, int score) {
    if (state.value == null) return;
    final newScores = Map<String, int>.from(state.value!.academicScores);
    newScores[subject] = score;
    state = AsyncValue.data(state.value!.copyWith(academicScores: newScores));
  }

  void updateHomeworkScore(String subject, int score) {
    if (state.value == null) return;
    final newScores = Map<String, int>.from(state.value!.homeworkScores);
    newScores[subject] = score;
    state = AsyncValue.data(state.value!.copyWith(homeworkScores: newScores));
  }

  void updateWellness(String key, int score) {
    if (state.value == null) return;
    final newScores = Map<String, int>.from(state.value!.wellness);
    newScores[key] = score;
    state = AsyncValue.data(state.value!.copyWith(wellness: newScores));
  }

  void updateAttendance(int score) {
    if (state.value == null) return;
    state = AsyncValue.data(state.value!.copyWith(attendance: score));
  }

  Future<void> save() async {
    final data = state.value;
    final teacherData = ref.read(teacherDataProvider).value;
    final assignedClass = ref.read(assignedClassProvider).value;
    final studentsData = ref.read(classStudentsProvider).value;
    
    if (data == null || teacherData == null || assignedClass == null || studentsData == null) {
      throw Exception("Missing required data for saving.");
    }

    final String schoolId = teacherData['schoolId'];
    final String classId = assignedClass['id'];
    final student = studentsData.firstWhere((s) => s['id'] == studentId);

    final academicScoresList = data.academicScores.entries.map((e) => {'subject': e.key, 'score': e.value}).toList();
    final homeworkScoresList = data.homeworkScores.entries.map((e) => {'subject': e.key, 'score': e.value}).toList();

    final studentRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('students')
        .doc(studentId);

    await studentRef.update({
      'academicScores': academicScoresList,
      'homeworkScores': homeworkScoresList,
      'wellness': data.wellness,
      'attendance': data.attendance,
    });

    // Handle Notifications
    try {
        final highScores = [
            ...data.academicScores.entries.where((e) => e.value >= 80).map((e) => e.key),
            ...data.homeworkScores.entries.where((e) => e.value >= 80).map((e) => e.key),
        ].toSet().toList(); // Make unique

         final lowScores = [
            ...data.academicScores.entries.where((e) => e.value < 50).map((e) => e.key),
            ...data.homeworkScores.entries.where((e) => e.value < 50).map((e) => e.key),
        ].toSet().toList(); // Make unique

        String title = "Performance Update";
        String message = "";
        String type = "info";

        if (highScores.isNotEmpty && lowScores.isEmpty) {
            title = "🌟 Excellent Progress!";
            message = "Great news! ${student['name']} is excelling in ${highScores.join(', ')}. Keep up the fantastic work!";
            type = "celebration";
        } else if (lowScores.isNotEmpty && highScores.isEmpty) {
            title = "🌱 Growth Opportunity";
            message = "We noticed ${student['name']} is finding ${lowScores.join(', ')} a bit challenging. Let's work together to support their improvement.";
            type = "alert";
        } else if (highScores.isNotEmpty && lowScores.isNotEmpty) {
            title = "📊 Performance Update";
            message = "${student['name']} is doing great in ${highScores.join(', ')}, but could use some extra support in ${lowScores.join(', ')}.";
            type = "info";
        } else {
            title = "📝 Just Updated";
            message = "A new performance report is available for ${student['name']}. Please check the app for the latest details.";
        }

        final parentsQuery = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('parents')
            .where('children', arrayContains: studentId)
            .limit(1)
            .get();

        if (parentsQuery.docs.isNotEmpty) {
            final parentId = parentsQuery.docs.first.id;
            await FirebaseFirestore.instance
                 .collection('schools')
                 .doc(schoolId)
                 .collection('notifications')
                 .add({
                     'parentId': parentId,
                     'studentId': studentId,
                     'studentName': student['name'],
                     'title': title,
                     'message': message,
                     'type': type,
                     'read': false,
                     'createdAt': FieldValue.serverTimestamp(),
                 });
            print("Notification sent to parent: $parentId");
        } else {
             print("No parent account found for this student. $studentId");
        }

    } catch(e) {
        print("Failed to send notification: $e");
    }
  }
}

final studentPerformanceProvider = StateNotifierProvider.family<StudentPerformanceNotifier, AsyncValue<StudentPerformanceData?>, String>((ref, studentId) {
  return StudentPerformanceNotifier(ref, studentId);
});
