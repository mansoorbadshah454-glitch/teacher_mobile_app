import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';
import 'package:teacher_mobile_app/core/services/sync_queue_service.dart';

// 1. Fetch assigned class for the logged-in teacher with Hive Caching
final classSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');
final statsFilterProvider = StateProvider.autoDispose<String>((ref) => 'all'); // 'all', 'present', 'absent'

final assignedClassProvider = StreamProvider<Map<String, dynamic>?>((ref) async* {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;
  final authUser = ref.watch(currentUserProvider);

  final String teacherUid = teacherData?['uid'] ?? authUser?.uid ?? '';
  final cacheKey = 'assigned_class_$teacherUid';

  // 1. Yield cached data immediately if available
  final cachedData = LocalDbService.getCache(cacheKey);
  if (cachedData != null && cachedData is Map) {
    yield Map<String, dynamic>.from(cachedData);
  }

  if (teacherData == null || !teacherData.containsKey('schoolId') || teacherUid.isEmpty) {
    if (cachedData == null) yield null;
    return;
  }

  final schoolId = teacherData['schoolId'] as String;

  final classesStream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('classes')
      .where('teacherId', isEqualTo: teacherUid)
      .snapshots();

  await for (final classesQuery in classesStream) {
    if (classesQuery.docs.isNotEmpty) {
      final data = classesQuery.docs.first.data();
      data['id'] = classesQuery.docs.first.id;
      await LocalDbService.saveCache(cacheKey, data);
      yield data;
    } else {
      if (cachedData == null) yield null;
    }
  }
});

// 2. Fetch students for the assigned class with Hive Caching
final classStudentsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final assignedClassAsync = ref.watch(assignedClassProvider);

  final teacherData = teacherDataAsync.value;
  final assignedClass = assignedClassAsync.value;

  if (assignedClass == null) {
      yield [];
      return;
  }

  final classId = assignedClass['id'] as String;
  final cacheKey = 'students_$classId';

  // 1. Yield cached data immediately
  final cachedData = LocalDbService.getCache(cacheKey);
  if (cachedData != null && cachedData is List) {
    yield List<Map<String, dynamic>>.from(cachedData.map((e) => Map<String, dynamic>.from(e)));
  }

  final schoolId = teacherData?['schoolId'] as String?;
  if (schoolId == null) {
    return;
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

// Provider to check if today's attendance has already been recorded
final isAttendanceMarkedTodayProvider = Provider.autoDispose<bool>((ref) {
  final assignedClass = ref.watch(assignedClassProvider).value;
  final students = ref.watch(classStudentsProvider).value ?? [];
  final today = DateTime.now().toIso8601String().split('T')[0];

  if (assignedClass != null) {
    final cachedMarked = LocalDbService.getCache('attendance_marked_${assignedClass['id']}_$today');
    if (cachedMarked == true) return true;
  }

  if (students.isNotEmpty) {
    return students.any((s) => s['lastAttendanceDate'] == today);
  }
  return false;
});

// 3. Attendance State Manager (stores local 'present'/'absent' Map)
class AttendanceNotifier extends StateNotifier<AsyncValue<Map<String, String>>> {
  final Ref ref;

  AttendanceNotifier(this.ref) : super(const AsyncValue.loading()) {
    _initializeAttendance();
  }

  Future<void> _initializeAttendance() async {
    try {
      final List<Map<String, dynamic>> students = ref.read(classStudentsProvider).value ?? 
          await ref.read(classStudentsProvider.future).catchError((_) => <Map<String, dynamic>>[]);
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

  /// Saves full class attendance offline-first. Returns true if synced immediately, false if queued offline.
  Future<bool> saveAttendance() async {
    final user = ref.read(currentUserProvider);
    if (user == null || state is! AsyncData) {
      throw Exception("User not authenticated or attendance data not ready.");
    }

    final teacherData = ref.read(teacherDataProvider).value ?? 
        (LocalDbService.getCache('teacher_profile_${user.uid}') as Map<String, dynamic>?);
    final assignedClass = ref.read(assignedClassProvider).value ?? 
        (LocalDbService.getCache('assigned_class_${user.uid}') as Map<String, dynamic>?);

    if (teacherData == null || assignedClass == null) {
      throw Exception("Teacher profile or assigned class not found.");
    }

    final classId = assignedClass['id'] as String;
    final students = ref.read(classStudentsProvider).value ?? 
        (LocalDbService.getCache('students_$classId') as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];

    if (students.isEmpty) {
      throw Exception("No students found to mark attendance.");
    }

    final attendanceMap = state.value!;
    final schoolId = teacherData['schoolId'] as String;
    final teacherId = user.uid;
    final teacherName = teacherData['name'] as String? ?? 'Teacher';
    final className = assignedClass['name'] as String? ?? 'Class';
    final today = DateTime.now().toIso8601String().split('T')[0];

    // 1. Immediately update Local Hive Cache for instant UI feedback
    final updatedStudents = students.map((s) {
      final sMap = Map<String, dynamic>.from(s);
      final sId = sMap['id'] as String;
      final status = attendanceMap[sId] ?? 'absent';
      sMap['status'] = status;
      sMap['lastAttendanceDate'] = today;
      final historyRaw = sMap['attendanceHistory'];
      Map<String, dynamic> history = {};
      if (historyRaw is Map) {
        historyRaw.forEach((k, v) => history[k.toString()] = v);
      }
      history[today] = status;
      sMap['attendanceHistory'] = history;
      return sMap;
    }).toList();

    await LocalDbService.saveCache('students_$classId', updatedStudents);
    await LocalDbService.saveCache('attendance_marked_${classId}_$today', true);

    final payload = {
      'schoolId': schoolId,
      'classId': classId,
      'className': className,
      'teacherId': teacherId,
      'teacherName': teacherName,
      'date': today,
      'attendanceMap': attendanceMap,
      'students': updatedStudents,
    };

    // 2. Check internet connectivity
    final bool online = await SyncQueueService.isOnline();
    if (online) {
      try {
        final batch = FirebaseFirestore.instance.batch();

        // Attendance document with deterministic ID to prevent duplicates
        final historyRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('attendance')
            .doc('${classId}_$today');

        final records = attendanceMap.entries.map((entry) {
          final sId = entry.key;
          final status = entry.value;
          final sName = updatedStudents.firstWhere(
            (s) => s['id'] == sId,
            orElse: () => <String, dynamic>{'name': 'Unknown'},
          )['name'];
          return {
            'id': sId,
            'name': sName,
            'status': status,
          };
        }).toList();

        batch.set(historyRef, {
          'teacherId': teacherId,
          'teacherName': teacherName,
          'classId': classId,
          'className': className,
          'date': today,
          'timestamp': FieldValue.serverTimestamp(),
          'records': records,
          'totalPresent': records.where((r) => r['status'] == 'present').length,
          'totalAbsent': records.where((r) => r['status'] == 'absent').length,
        }, SetOptions(merge: true));

        for (var student in updatedStudents) {
          final sId = student['id'] as String;
          final status = attendanceMap[sId] ?? 'absent';

          final studentRef = FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('classes')
              .doc(classId)
              .collection('students')
              .doc(sId);

          batch.update(studentRef, {
            'status': status,
            'lastAttendanceDate': today,
            'attendanceHistory.$today': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();

        // Dispatch parent notifications asynchronously without blocking UI
        for (var student in updatedStudents) {
          final sId = student['id'] as String;
          final sName = student['name'] as String? ?? 'Student';
          final status = attendanceMap[sId] ?? 'absent';

          String? parentId;
          if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
            parentId = student['parentDetails']['parentId']?.toString();
          }

          if (parentId != null && parentId.isNotEmpty) {
            try {
              FirebaseFirestore.instance
                  .collection('schools')
                  .doc(schoolId)
                  .collection('notifications')
                  .add({
                'parentId': parentId,
                'studentId': sId,
                'studentName': sName,
                'title': 'Attendance Update',
                'type': 'attendance',
                'status': status,
                'className': className,
                'date': today,
                'message': status == 'leave_granted'
                    ? '$sName is on leave today, $today.'
                    : '$sName is marked $status in School today, $today.',
                'read': false,
                'createdAt': FieldValue.serverTimestamp(),
              });
            } catch (_) {}
          }
        }

        ref.invalidate(classStudentsProvider);
        return true; // Synced directly
      } catch (e) {
        // Fallback: enqueue offline task if network write threw an error
        await SyncQueueService.enqueue(
          type: 'attendance_confirm',
          payload: payload,
        );
        ref.invalidate(classStudentsProvider);
        return false; // Queued offline
      }
    } else {
      // Offline: Enqueue to background persistent sync queue
      await SyncQueueService.enqueue(
        type: 'attendance_confirm',
        payload: payload,
      );
      ref.invalidate(classStudentsProvider);
      return false; // Queued offline
    }
  }

  /// Surgical update for a single late student. Returns true if synced, false if queued offline.
  Future<bool> updateLateStudent({
    required String studentId,
    required String newStatus,
  }) async {
    setStatus(studentId, newStatus);

    final user = ref.read(currentUserProvider);
    if (user == null) return false;

    final teacherData = ref.read(teacherDataProvider).value ?? 
        (LocalDbService.getCache('teacher_profile_${user.uid}') as Map<String, dynamic>?);
    final assignedClass = ref.read(assignedClassProvider).value ?? 
        (LocalDbService.getCache('assigned_class_${user.uid}') as Map<String, dynamic>?);

    if (teacherData == null || assignedClass == null) return false;

    final classId = assignedClass['id'] as String;
    final schoolId = teacherData['schoolId'] as String;
    final today = DateTime.now().toIso8601String().split('T')[0];

    final students = ref.read(classStudentsProvider).value ?? 
        (LocalDbService.getCache('students_$classId') as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];

    final student = students.firstWhere(
      (s) => s['id'] == studentId,
      orElse: () => <String, dynamic>{'name': 'Student'},
    );

    // Update local cache
    final updatedStudents = students.map((s) {
      final sMap = Map<String, dynamic>.from(s);
      if (sMap['id'] == studentId) {
        sMap['status'] = newStatus;
        sMap['lastAttendanceDate'] = today;
        final historyRaw = sMap['attendanceHistory'];
        Map<String, dynamic> history = {};
        if (historyRaw is Map) {
          historyRaw.forEach((k, v) => history[k.toString()] = v);
        }
        history[today] = newStatus;
        sMap['attendanceHistory'] = history;
      }
      return sMap;
    }).toList();

    await LocalDbService.saveCache('students_$classId', updatedStudents);

    String? parentId;
    if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
      parentId = student['parentDetails']['parentId']?.toString();
    }

    final payload = {
      'schoolId': schoolId,
      'classId': classId,
      'studentId': studentId,
      'studentName': student['name'] ?? 'Student',
      'newStatus': newStatus,
      'date': today,
      'parentId': parentId,
    };

    final bool online = await SyncQueueService.isOnline();
    if (online) {
      try {
        final batch = FirebaseFirestore.instance.batch();

        final studentRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId)
            .collection('students')
            .doc(studentId);

        batch.update(studentRef, {
          'status': newStatus,
          'lastAttendanceDate': today,
          'attendanceHistory.$today': newStatus,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // Update attendance history document for today
        final historyRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('attendance')
            .doc('${classId}_$today');

        final historySnap = await historyRef.get();
        if (historySnap.exists && historySnap.data() != null) {
          final records = List<Map<String, dynamic>>.from(
            (historySnap.data()!['records'] as List? ?? []).map((r) => Map<String, dynamic>.from(r)),
          );
          bool found = false;
          for (var r in records) {
            if (r['id'] == studentId) {
              r['status'] = newStatus;
              found = true;
              break;
            }
          }
          if (!found) {
            records.add({'id': studentId, 'name': student['name'] ?? 'Student', 'status': newStatus});
          }

          batch.update(historyRef, {
            'records': records,
            'totalPresent': records.where((r) => r['status'] == 'present').length,
            'totalAbsent': records.where((r) => r['status'] == 'absent').length,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();

        // Notify only this late student's parent
        if (parentId != null && parentId.isNotEmpty) {
          try {
            FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('notifications')
                .add({
              'parentId': parentId,
              'studentId': studentId,
              'studentName': student['name'] ?? 'Student',
              'title': 'Attendance Update (Late Arrival)',
              'type': 'attendance',
              'status': newStatus,
              'date': today,
              'message': '${student['name'] ?? 'Student'} arrived late and status was updated to $newStatus on $today.',
              'read': false,
              'createdAt': FieldValue.serverTimestamp(),
            });
          } catch (_) {}
        }

        ref.invalidate(classStudentsProvider);
        return true;
      } catch (e) {
        await SyncQueueService.enqueue(
          type: 'attendance_late_update',
          payload: payload,
        );
        ref.invalidate(classStudentsProvider);
        return false;
      }
    } else {
      await SyncQueueService.enqueue(
        type: 'attendance_late_update',
        payload: payload,
      );
      ref.invalidate(classStudentsProvider);
      return false;
    }
  }
}

final attendanceProvider = StateNotifierProvider<AttendanceNotifier, AsyncValue<Map<String, String>>>((ref) {
  return AttendanceNotifier(ref);
});
