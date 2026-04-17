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
  bool _academicModified = false;
  bool _wellnessModified = false;

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

    final data = StudentPerformanceData(
      academicScores: acScores,
      homeworkScores: hwScores,
      wellness: wlScores,
      attendance: att,
    );
    state = AsyncValue.data(data);
  }

  void updateAcademicScore(String subject, int score) {
    if (state.value == null) return;
    _academicModified = true;
    final newScores = Map<String, int>.from(state.value!.academicScores);
    newScores[subject] = score;
    state = AsyncValue.data(state.value!.copyWith(academicScores: newScores));
  }

  void updateHomeworkScore(String subject, int score) {
    if (state.value == null) return;
    _academicModified = true;
    final newScores = Map<String, int>.from(state.value!.homeworkScores);
    newScores[subject] = score;
    state = AsyncValue.data(state.value!.copyWith(homeworkScores: newScores));
  }

  void updateWellness(String key, int score) {
    if (state.value == null) return;
    _wellnessModified = true;
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

    final updateData = {
      'academicScores': academicScoresList,
      'homeworkScores': homeworkScoresList,
      'wellness': data.wellness,
      'attendance': data.attendance,
      'classId': classId,
      'className': assignedClass['name'] ?? 'Unknown',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await studentRef.update(updateData);

    // Handle Notifications
    try {
        final bool academicChanged = _academicModified;
        final bool wellnessChanged = _wellnessModified;

        String? parentId;
        if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
            parentId = student['parentDetails']['parentId'];
        }

        if (parentId != null) {
            if (academicChanged) {
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
                print("Academic Notification sent to parent: $parentId");
            }

            if (wellnessChanged) {
                // Wellness Notification
                final healthScore = data.wellness['health'] ?? 80;
                final behaviorScore = data.wellness['behavior'] ?? 80;
                final hygieneScore = data.wellness['hygiene'] ?? 80;
                final Map<String, int> wScores = {
                   'behavior': behaviorScore,
                   'health': healthScore,
                   'hygiene': hygieneScore,
                };

                final highW = wScores.entries.where((e) => e.value >= 80).map((e) => e.key).toList();
                final lowW = wScores.entries.where((e) => e.value < 60).map((e) => e.key).toList();
                final avgW = wScores.entries.where((e) => e.value >= 60 && e.value < 80).map((e) => e.key).toList();

                String wTitle = "";
                String wMessage = "";
                String wType = "personality"; 
                
                if (highW.length == 3) {
                    wTitle = "🌟 Exceptional Habits!";
                    wMessage = "${student['name']} is setting a wonderful example in class with outstanding behavior, health, and personal hygiene. Keep up the excellent work!";
                    wType = "personality";
                } else if (lowW.length > 1 && highW.isEmpty) {
                    wTitle = "🚨 Action Required: Well-being";
                    wMessage = "We've noticed a few concerns regarding ${student['name']}'s ${lowW.join(' and ')}. Let's work together to provide the right support for their well-being.";
                    wType = lowW.first;
                } else if (highW.isNotEmpty && (lowW.isNotEmpty || avgW.isNotEmpty)) {
                    wTitle = "🌱 Steady Personal Growth";
                    wMessage = "${student['name']} is doing wonderfully in ${highW.join(' and ')}! To help them shine even more, guided daily routines at home can really boost their ${[...lowW, ...avgW].join(' and ')}.";
                    wType = lowW.isNotEmpty ? lowW.first : avgW.first;
                } else if (lowW.length == 1) {
                    wTitle = "🤝 Let's Support ${student['name']}";
                    wMessage = "${student['name']} is doing well overall, but we've noticed they might need a bit more guidance regarding their ${lowW.first}. Let's work together to help them improve here.";
                    wType = lowW.first;
                } else {
                    wTitle = "😊 Great Habits & Well-being!";
                    wMessage = "${student['name']} is maintaining steady habits. Continuing to encourage good daily routines will help them excel further in behavior and personal care.";
                    wType = avgW.isNotEmpty ? avgW.first : "personality";
                }

                await FirebaseFirestore.instance
                     .collection('schools')
                     .doc(schoolId)
                     .collection('notifications')
                     .add({
                         'parentId': parentId,
                         'studentId': studentId,
                         'studentName': student['name'],
                         'title': wTitle,
                         'message': wMessage,
                         'type': wType,
                         'read': false,
                         'createdAt': FieldValue.serverTimestamp(),
                     });
                print("Wellness Notification sent to parent: $parentId");
            }
        }
            
        // Reset flags so we don't spam if they hit save multiple times
        _academicModified = false;
        _wellnessModified = false;

    } catch(e) {
        print("Failed to send notification: $e");
    }
  }

}

final studentPerformanceProvider = StateNotifierProvider.family<StudentPerformanceNotifier, AsyncValue<StudentPerformanceData?>, String>((ref, studentId) {
  return StudentPerformanceNotifier(ref, studentId);
});
