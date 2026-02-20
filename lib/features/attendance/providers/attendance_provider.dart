import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';

// 1. Fetch assigned class for the logged-in teacher
final classSearchQueryProvider = StateProvider<String>((ref) => '');
final statsFilterProvider = StateProvider<String>((ref) => 'all'); // 'all', 'present', 'absent'

final assignedClassProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final teacherData = await ref.watch(teacherDataProvider.future);
  if (teacherData == null || !teacherData.containsKey('schoolId') || !teacherData.containsKey('name')) {
    return null;
  }

  final schoolId = teacherData['schoolId'] as String;
  final teacherName = teacherData['name'] as String;

  try {
    final classesQuery = await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .where('teacher', isEqualTo: teacherName)
        .get();

    if (classesQuery.docs.isNotEmpty) {
      final data = classesQuery.docs.first.data();
      data['id'] = classesQuery.docs.first.id;
      return data;
    }
    return null;
  } catch (e) {
    print('Error fetching assigned class: $e');
    return null;
  }
});

// 2. Fetch students for the assigned class
final classStudentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final teacherData = await ref.watch(teacherDataProvider.future);
  final assignedClass = await ref.watch(assignedClassProvider.future);

  if (teacherData == null || assignedClass == null) return [];

  final schoolId = teacherData['schoolId'] as String;
  final classId = assignedClass['id'] as String;

  try {
    final studentsQuery = await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('students')
        .orderBy('rollNo')
        .get();

    return studentsQuery.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  } catch (e) {
    print('Error fetching students: $e');
    return [];
  }
});

// 3. Attendance State Manager (stores local 'present'/'absent' Map)
class AttendanceNotifier extends StateNotifier<AsyncValue<Map<String, String>>> {
  final Ref ref;

  AttendanceNotifier(this.ref) : super(const AsyncValue.loading()) {
    _initializeAttendance();
  }

  Future<void> _initializeAttendance() async {
    try {
      final students = await ref.read(classStudentsProvider.future);
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      final Map<String, String> initialAttendance = {};
      
      for (var s in students) {
        if (s['lastAttendanceDate'] == today) {
           initialAttendance[s['id']] = s['status'] ?? 'absent';
        }
      }
      
      state = AsyncValue.data(initialAttendance);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void toggleStatus(String studentId) {
    if (state is AsyncData) {
      final currentMap = Map<String, String>.from(state.value!);
      final currentStatus = currentMap[studentId] ?? 'absent';
      currentMap[studentId] = currentStatus == 'present' ? 'absent' : 'present';
      state = AsyncValue.data(currentMap);
    }
  }

  void refreshFromSaved(String today) async {
      try {
           final students = await ref.read(classStudentsProvider.future);
           final Map<String, String> currentMap = Map<String, String>.from(state.value ?? {});
           for (var s in students) {
               if(currentMap.containsKey(s['id'])) continue;
               if (s['lastAttendanceDate'] == today) {
                   currentMap[s['id']] = s['status'] ?? 'absent';
               }
           }
           state = AsyncValue.data(currentMap);
      } catch (e) {}
  }

  Future<void> saveAttendance() async {
    final teacherData = await ref.read(teacherDataProvider.future);
    final assignedClass = await ref.read(assignedClassProvider.future);
    final students = await ref.read(classStudentsProvider.future);
    final user = FirebaseAuth.instance.currentUser;

    if (teacherData == null || assignedClass == null || user == null || state is! AsyncData) return;

    final attendanceMap = state.value!;
    final schoolId = teacherData['schoolId'] as String;
    final teacherId = user.uid; // Always use exact user id
    final teacherName = teacherData['name'] as String;
    final classId = assignedClass['id'] as String;
    final className = assignedClass['name'] as String;
    final today = DateTime.now().toIso8601String().split('T')[0];

    try {
      final batch = FirebaseFirestore.instance.batch();

      // 1. History Record
      final historyRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('attendance')
          .doc(); // Auto ID

      batch.set(historyRef, {
        'teacherId': teacherId,
        'teacherName': teacherName,
        'classId': classId,
        'className': className,
        'date': today,
        'timestamp': FieldValue.serverTimestamp(),
        'records': attendanceMap.entries.map((entry) {
          final sId = entry.key;
          final status = entry.value;
          final sName = students.firstWhere((s) => s['id'] == sId, orElse: () => {'name': 'Unknown'})['name'];
          return {
            'id': sId,
            'name': sName,
            'status': status,
          };
        }).toList(),
      });

      // 2. Loop through students to update sub-collection and prepare parent notifications
      for (var student in students) {
        final studentId = student['id'] as String;
        final status = attendanceMap[studentId] ?? 'absent';

        // Update Student
        final studentRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId)
            .collection('students')
            .doc(studentId);
            
        batch.update(studentRef, {
          'status': status,
          'lastAttendanceDate': today,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // Local State update for "lastAttendanceDate: today" to emulate the React app
      // Refetch students or update manually in state if needed, but since it's firestore we might just re-fetch
      ref.invalidate(classStudentsProvider);

      // 3. Parent Notifications (done after commit to avoid batch limits and perform queries)
      for (var student in students) {
        final studentId = student['id'] as String;
        final studentName = student['name'] as String;
        final status = attendanceMap[studentId] ?? 'absent';

        try {
          final parentsQuery = await FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('parents')
              .where('children', arrayContains: studentId)
              .get();

          for (var parentDoc in parentsQuery.docs) {
             await FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('notifications')
                .add({
                  'parentId': parentDoc.id,
                  'studentId': studentId,
                  'studentName': studentName,
                  'type': 'attendance',
                  'status': status,
                  'className': className,
                  'date': today,
                  'message': '$studentName was marked $status in $className today.',
                  'read': false,
                  'createdAt': FieldValue.serverTimestamp(),
                });
          }
        } catch (e) {
           print('Error creating parent notification for $studentName: $e');
        }
      }

    } catch (e) {
      print('Error saving attendance: $e');
      throw e;
    }
  }
}

final attendanceProvider = StateNotifierProvider<AttendanceNotifier, AsyncValue<Map<String, String>>>((ref) {
  return AttendanceNotifier(ref);
});
