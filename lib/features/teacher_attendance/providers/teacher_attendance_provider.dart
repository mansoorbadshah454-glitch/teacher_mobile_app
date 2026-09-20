import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';
import 'package:teacher_mobile_app/core/services/sync_queue_service.dart';

class TeacherAttendanceState {
  final bool isLoading;
  final String? error;
  final String? successMessage;

  TeacherAttendanceState({
    this.isLoading = false,
    this.error,
    this.successMessage,
  });

  TeacherAttendanceState copyWith({
    bool? isLoading,
    String? error,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return TeacherAttendanceState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }
}

class TeacherAttendanceNotifier extends StateNotifier<TeacherAttendanceState> {
  final Ref ref;

  TeacherAttendanceNotifier(this.ref) : super(TeacherAttendanceState());

  void clearMessages() {
    state = state.copyWith(clearError: true, clearSuccess: true);
  }

  Future<void> scanBarcode(String scannedCode) async {
    if (state.isLoading) return;
    
    state = state.copyWith(isLoading: true, clearError: true, clearSuccess: true);

    try {
      final user = ref.read(currentUserProvider);
      final teacherDataAsync = ref.read(teacherDataProvider);
      final teacherData = teacherDataAsync.value;

      if (user == null || teacherData == null || !teacherData.containsKey('schoolId')) {
        throw Exception("User data or School ID not found.");
      }

      final String schoolId = teacherData['schoolId'];
      final String uid = user.uid;

      final bool online = await SyncQueueService.isOnline();

      // 1. Fetch current Check-in Code (from Firestore or local Hive cache if offline)
      Map<String, dynamic>? settingsData;
      if (online) {
        try {
          final settingsDoc = await FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('settings')
              .doc('profile')
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(const Duration(seconds: 3));

          if (settingsDoc.exists && settingsDoc.data() != null) {
            settingsData = settingsDoc.data();
            await LocalDbService.saveCache('school_settings_$schoolId', settingsData);
          }
        } catch (_) {}
      }

      if (settingsData == null) {
        final cached = LocalDbService.getCache('school_settings_$schoolId');
        if (cached is Map) {
          settingsData = Map<String, dynamic>.from(cached);
        }
      }

      final currentCode = settingsData?['currentCheckinCode'] as String?;
      final cleanScanned = scannedCode.trim();
      final cleanSchoolId = schoolId.trim().toLowerCase();

      bool isValid = false;

      // 1. Exact match with active check-in code
      if (currentCode != null && currentCode.trim().isNotEmpty && cleanScanned == currentCode.trim()) {
        isValid = true;
      }
      // 2. Official school QR code format: checkin_<schoolId>_<timestamp> or checkin_<schoolId>
      else if (cleanScanned.toLowerCase().startsWith('checkin_$cleanSchoolId')) {
        isValid = true;
      }
      // 3. Direct school ID match
      else if (cleanScanned.toLowerCase() == cleanSchoolId) {
        isValid = true;
      }
      // 4. Scanned code contains schoolId and checkin keyword
      else if (cleanScanned.toLowerCase().contains('checkin') && cleanScanned.toLowerCase().contains(cleanSchoolId)) {
        isValid = true;
      }

      if (!isValid) {
        throw Exception("Invalid or expired QR code. Please try again.");
      }

      // 2. Code is valid! Capture EXACT device timestamp at the moment of scanning
      final nowTime = DateTime.now();
      final String todayStr = DateFormat('yyyy-MM-dd').format(nowTime);
      final String exactTimeStr = DateFormat('hh:mm a').format(nowTime);
      final cacheKey = 'teacher_today_attendance_${uid}_$todayStr';

      // 3. Determine if already checked in today
      bool alreadyCheckedIn = false;
      final localLog = LocalDbService.getCache(cacheKey);
      if (localLog is Map && localLog['checkIn'] != null) {
        alreadyCheckedIn = true;
      } else if (online) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('teachers')
              .doc(uid)
              .collection('attendance_logs')
              .doc(todayStr)
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(const Duration(seconds: 3));
          if (doc.exists && doc.data()?['checkIn'] != null) {
            alreadyCheckedIn = true;
          }
        } catch (_) {}
      }

      if (!alreadyCheckedIn) {
        // ------------------ CHECK-IN ------------------
        final exactTimestamp = Timestamp.fromDate(nowTime);

        // Update local cache immediately
        await LocalDbService.saveCache(cacheKey, {
          'date': todayStr,
          'checkIn': nowTime.toIso8601String(),
          'status': 'Present',
        });

        if (online) {
          try {
            final attendanceRef = FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('teachers')
                .doc(uid)
                .collection('attendance_logs')
                .doc(todayStr);

            await attendanceRef.set({
              'date': todayStr,
              'checkIn': exactTimestamp,
              'status': 'Present',
            }, SetOptions(merge: true));

            await FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('teachers')
                .doc(uid)
                .set({
              'lastAttendanceDate': todayStr,
            }, SetOptions(merge: true));

            state = state.copyWith(
              isLoading: false,
              successMessage: "Checked In at $exactTimeStr! (Status: Present)",
            );
          } catch (e) {
            // Network failure fallback
            await SyncQueueService.enqueue(
              type: 'teacher_checkin',
              payload: {
                'schoolId': schoolId,
                'teacherId': uid,
                'date': todayStr,
                'checkInTime': nowTime.toIso8601String(),
                'status': 'Present',
              },
            );

            state = state.copyWith(
              isLoading: false,
              successMessage: "⚡ Checked In at $exactTimeStr! (Saved offline, will auto-sync)",
            );
          }
        } else {
          // Offline queue
          await SyncQueueService.enqueue(
            type: 'teacher_checkin',
            payload: {
              'schoolId': schoolId,
              'teacherId': uid,
              'date': todayStr,
              'checkInTime': nowTime.toIso8601String(),
              'status': 'Present',
            },
          );

          state = state.copyWith(
            isLoading: false,
            successMessage: "⚡ Checked In at $exactTimeStr! (Saved offline, will auto-sync)",
          );
        }
        ref.invalidate(todayTeacherAttendanceProvider);
      } else {
        // ------------------ CHECK-OUT ------------------
        final String teacherEndTime = settingsData?['teacherEndTime'] as String? ?? '14:00';
        final parts = teacherEndTime.split(':');
        final endHour = int.tryParse(parts[0]) ?? 14;
        final endMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        final endDateTime = DateTime(nowTime.year, nowTime.month, nowTime.day, endHour, endMinute);

        String checkoutStatus = "Present";
        if (nowTime.isBefore(endDateTime)) {
          checkoutStatus = "Half Day";
        }

        // Update local cache
        final existing = (localLog is Map) ? Map<String, dynamic>.from(localLog) : <String, dynamic>{};
        existing['checkOut'] = nowTime.toIso8601String();
        existing['status'] = checkoutStatus;
        await LocalDbService.saveCache(cacheKey, existing);

        if (online) {
          try {
            final attendanceRef = FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('teachers')
                .doc(uid)
                .collection('attendance_logs')
                .doc(todayStr);

            await attendanceRef.update({
              'checkOut': Timestamp.fromDate(nowTime),
              'status': checkoutStatus,
            });

            state = state.copyWith(
              isLoading: false,
              successMessage: "Checked Out at $exactTimeStr! (Status: $checkoutStatus)",
            );
          } catch (e) {
            await SyncQueueService.enqueue(
              type: 'teacher_checkout',
              payload: {
                'schoolId': schoolId,
                'teacherId': uid,
                'date': todayStr,
                'checkOutTime': nowTime.toIso8601String(),
                'status': checkoutStatus,
              },
            );

            state = state.copyWith(
              isLoading: false,
              successMessage: "⚡ Checked Out at $exactTimeStr! (Saved offline, will auto-sync)",
            );
          }
        } else {
          await SyncQueueService.enqueue(
            type: 'teacher_checkout',
            payload: {
              'schoolId': schoolId,
              'teacherId': uid,
              'date': todayStr,
              'checkOutTime': nowTime.toIso8601String(),
              'status': checkoutStatus,
            },
          );

          state = state.copyWith(
            isLoading: false,
            successMessage: "⚡ Checked Out at $exactTimeStr! (Saved offline, will auto-sync)",
          );
        }
        ref.invalidate(todayTeacherAttendanceProvider);
      }

    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString().replaceAll("Exception: ", ""));
    }
  }
}

final teacherAttendanceProvider = StateNotifierProvider<TeacherAttendanceNotifier, TeacherAttendanceState>((ref) {
  return TeacherAttendanceNotifier(ref);
});

final schoolSettingsProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (user == null || teacherData == null || !teacherData.containsKey('schoolId')) {
    yield {};
    return;
  }

  final String schoolId = teacherData['schoolId'];
  final cacheKey = 'school_settings_$schoolId';

  // 1. Immediately yield cached settings offline
  final cached = LocalDbService.getCache(cacheKey);
  if (cached != null && cached is Map) {
    yield Map<String, dynamic>.from(cached);
  }

  final stream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('settings')
      .doc('profile')
      .snapshots();

  await for (final snapshot in stream) {
    if (snapshot.exists && snapshot.data() != null) {
      final data = snapshot.data() as Map<String, dynamic>;
      await LocalDbService.saveCache(cacheKey, data);
      yield data;
    }
  }
});

final attendanceMonthProvider = StateProvider<int>((ref) => DateTime.now().month);
final attendanceYearProvider = StateProvider<int>((ref) => DateTime.now().year);

// Provider to stream attendance history for a specific month for the Calendar Grid
final monthlyTeacherAttendanceProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  final month = ref.watch(attendanceMonthProvider);
  final year = ref.watch(attendanceYearProvider);

  if (user == null || teacherData == null || !teacherData.containsKey('schoolId')) {
    yield {};
    return;
  }

  final String schoolId = teacherData['schoolId'];
  final String uid = user.uid;

  final startDate = '$year-${month.toString().padLeft(2, '0')}-01';
  final endDate = '$year-${month.toString().padLeft(2, '0')}-31';

  yield* FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('teachers')
      .doc(uid)
      .collection('attendance_logs')
      .where('date', isGreaterThanOrEqualTo: startDate)
      .where('date', isLessThanOrEqualTo: endDate)
      .snapshots()
      .map((snapshot) {
    final Map<String, dynamic> dataMap = {};
    for (var doc in snapshot.docs) {
      dataMap[doc.id] = doc.data();
    }
    return dataMap;
  });
});

// Provider to stream today's attendance log for the Duty Status Screen
final todayTeacherAttendanceProvider = StreamProvider<Map<String, dynamic>?>((ref) async* {
  final user = ref.watch(currentUserProvider);
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (user == null) {
    yield null;
    return;
  }

  final String uid = user.uid;
  final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final cacheKey = 'teacher_today_attendance_${uid}_$todayStr';

  // 1. Yield local check-in log immediately if available
  final cachedLog = LocalDbService.getCache(cacheKey);
  if (cachedLog != null && cachedLog is Map) {
    yield Map<String, dynamic>.from(cachedLog);
  }

  if (teacherData == null || !teacherData.containsKey('schoolId')) {
    if (cachedLog == null) yield null;
    return;
  }

  final String schoolId = teacherData['schoolId'];

  final stream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('teachers')
      .doc(uid)
      .collection('attendance_logs')
      .doc(todayStr)
      .snapshots();

  await for (final snapshot in stream) {
    if (snapshot.exists && snapshot.data() != null) {
      final data = snapshot.data()!;
      await LocalDbService.saveCache(cacheKey, data);
      yield data;
    } else {
      if (cachedLog == null) yield null;
    }
  }
});
