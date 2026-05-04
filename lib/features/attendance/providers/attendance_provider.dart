import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';

// 1. Fetch assigned class for the logged-in teacher
final classSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');
final statsFilterProvider = StateProvider.autoDispose<String>((ref) => 'all'); // 'all', 'present', 'absent'

final assignedClassProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (teacherData == null || !teacherData.containsKey('schoolId') || !teacherData.containsKey('name')) {
    return Stream.value(null);
  }

  final schoolId = teacherData['schoolId'] as String;
  final authUser = ref.watch(currentUserProvider);
  final String teacherUid = teacherData['uid'] ?? authUser?.uid ?? '';

  if (teacherUid.isEmpty) {
    return Stream.value(null);
  }

  return FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('classes')
      .where('teacherId', isEqualTo: teacherUid)
      .snapshots()
      .map((classesQuery) {
    if (classesQuery.docs.isNotEmpty) {
      final data = classesQuery.docs.first.data();
      data['id'] = classesQuery.docs.first.id;
      return data;
    }
    return null;
  });
});

// 2. Fetch students for the assigned class with Hive Caching
final classStudentsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final assignedClassAsync = ref.watch(assignedClassProvider);

  final teacherData = teacherDataAsync.value;
  final assignedClass = assignedClassAsync.value;

  if (teacherData == null || assignedClass == null) {
      yield [];
      return;
  }

  final schoolId = teacherData['schoolId'] as String;
  final classId = assignedClass['id'] as String;
  final cacheKey = 'students_$classId';

  // 1. Yield cached data immediately
  final cachedData = LocalDbService.getCache(cacheKey);
  if (cachedData != null && cachedData is List) {
    print("📦 [Hive] Loaded ${cachedData.length} students from local cache.");
    yield List<Map<String, dynamic>>.from(cachedData.map((e) => Map<String, dynamic>.from(e)));
  }

  // 2. Listen to Firestore silently
  final studentsStream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('classes')
      .doc(classId)
      .collection('students')
      .orderBy('rollNo')
      .snapshots();

  await for (final snapshot in studentsStream) {
    final freshData = snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
    
    // Save fresh data to Hive
    await LocalDbService.saveCache(cacheKey, freshData);
    
    yield freshData;
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
      final todayStr = DateTime.now().toIso8601String().split('T')[0];
      
      final Map<String, String> initialAttendance = {};
      
      for (var s in students) {
        if (s['lastAttendanceDate'] == todayStr) {
           initialAttendance[s['id']] = s['status'] ?? 'absent';
        } else {
           final activeLeave = s['activeLeave'];
           if (activeLeave != null && activeLeave['status'] == 'granted') {
              final startStr = activeLeave['startDate'].toString().split('T')[0];
              final endStr = activeLeave['endDate'].toString().split('T')[0];
              if (todayStr.compareTo(startStr) >= 0 && todayStr.compareTo(endStr) <= 0) {
                  initialAttendance[s['id']] = 'leave_granted';
              }
           }
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

  void setStatus(String studentId, String status) {
    if (state is AsyncData) {
      final currentMap = Map<String, String>.from(state.value!);
      currentMap[studentId] = status;
      state = AsyncValue.data(currentMap);
    }
  }

  void refreshFromSaved(String today) async {
      try {
           final students = await ref.read(classStudentsProvider.future);
           final Map<String, String> currentMap = Map<String, String>.from(state.value ?? {});
           final todayStr = DateTime.now().toIso8601String().split('T')[0];

           for (var s in students) {
               if(currentMap.containsKey(s['id'])) continue;
               if (s['lastAttendanceDate'] == today) {
                   currentMap[s['id']] = s['status'] ?? 'absent';
               } else {
                   final activeLeave = s['activeLeave'];
                   if (activeLeave != null && activeLeave['status'] == 'granted') {
                      final startStr = activeLeave['startDate'].toString().split('T')[0];
                      final endStr = activeLeave['endDate'].toString().split('T')[0];
                      if (todayStr.compareTo(startStr) >= 0 && todayStr.compareTo(endStr) <= 0) {
                          currentMap[s['id']] = 'leave_granted';
                      }
                   }
               }
           }
           state = AsyncValue.data(currentMap);
      } catch (e) {}
  }

  Future<void> saveAttendance() async {
    final teacherData = await ref.read(teacherDataProvider.future);
    final assignedClass = await ref.read(assignedClassProvider.future);
    final students = await ref.read(classStudentsProvider.future);
    final user = ref.read(currentUserProvider);

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
          final sName = students.firstWhere((s) => s['id'] == sId, orElse: () { return <String, dynamic>{'name': 'Unknown'}; })['name'];
          return {
            'id': sId,
            'name': sName,
            'status': status,
          };
        }).toList(),
      });

      // 2. Loop through students to update both sub-collection and master record
      for (var student in students) {
        final studentId = student['id'] as String;
        final status = attendanceMap[studentId] ?? 'absent';

        // 2a. Update Class-specific student record
        final studentRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId)
            .collection('students')
            .doc(studentId);
            
        // Fetch existing history to append to it safely (avoids Dart's shallow merge overwrites)
        final existingHistoryRaw = student['attendanceHistory'];
        Map<String, dynamic> mergedHistory = {};
        if (existingHistoryRaw != null && existingHistoryRaw is Map) {
            existingHistoryRaw.forEach((key, value) {
                mergedHistory[key.toString()] = value;
            });
        }
        mergedHistory[today] = status;

        batch.update(studentRef, {
          'status': status,
          'lastAttendanceDate': today,
          'attendanceHistory': mergedHistory,
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
          String? parentId;
          if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
              parentId = student['parentDetails']['parentId'];
          }

          if (parentId != null) {
             await FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('notifications')
                .add({
                  'parentId': parentId,
                  'studentId': studentId,
                  'studentName': studentName,
                  'title': 'Attendance Update',
                  'type': 'attendance',
                  'status': status,
                  'className': className,
                  'date': today,
                  'message': status == 'leave_granted' 
                      ? '$studentName is on leave today, $today.' 
                      : '$studentName is marked $status in School today, $today.',
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
