import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';

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

      // 1. Fetch current Check-in Code from School Settings
      final settingsDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('settings')
          .doc('profile')
          .get();

      if (!settingsDoc.exists) {
        throw Exception("School settings not found.");
      }

      final currentCode = settingsDoc.data()?['currentCheckinCode'] as String?;

      if (currentCode == null || currentCode.isEmpty) {
        throw Exception("No active check-in code found for this school.");
      }

      if (scannedCode != currentCode) {
        throw Exception("Invalid or expired QR code. Please try again.");
      }

      // 2. Code is valid. Proceed to Check-in / Check-out
      final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      final attendanceRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .doc(uid)
          .collection('attendance_logs')
          .doc(todayStr);

      final attendanceDoc = await attendanceRef.get();

      if (!attendanceDoc.exists) {
        // Check-in
        await attendanceRef.set({
          'date': todayStr,
          'checkIn': FieldValue.serverTimestamp(),
          'status': 'Present',
        });
        
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('teachers')
            .doc(uid)
            .set({
          'lastAttendanceDate': todayStr,
        }, SetOptions(merge: true));

        state = state.copyWith(isLoading: false, successMessage: "Successfully Checked In for today!");
      } else {
        // Check-out (updates existing document)
        final String teacherEndTime = settingsDoc.data()?['teacherEndTime'] as String? ?? '14:00';
        final nowTime = DateTime.now();
        
        final parts = teacherEndTime.split(':');
        final endHour = int.tryParse(parts[0]) ?? 14;
        final endMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
        
        final endDateTime = DateTime(nowTime.year, nowTime.month, nowTime.day, endHour, endMinute);
        
        // Check if checkout time is strictly before the end time
        String checkoutStatus = "Present";
        if (nowTime.isBefore(endDateTime)) {
          checkoutStatus = "Half Day";
        }

        await attendanceRef.update({
          'checkOut': FieldValue.serverTimestamp(),
          'status': checkoutStatus,
        });
        state = state.copyWith(isLoading: false, successMessage: "Successfully Checked Out for today!");
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
  yield* FirebaseFirestore.instance.collection('schools').doc(schoolId).collection('settings').doc('profile').snapshots().map((snapshot) {
    if (snapshot.exists) {
      if (snapshot.data() != null) {
        return snapshot.data() as Map<String, dynamic>;
      }
    }
    return {};
  });
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

  if (user == null || teacherData == null || !teacherData.containsKey('schoolId')) {
    yield null;
    return;
  }

  final String schoolId = teacherData['schoolId'];
  final String uid = user.uid;
  final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

  yield* FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('teachers')
      .doc(uid)
      .collection('attendance_logs')
      .doc(todayStr)
      .snapshots()
      .map((snapshot) {
    if (snapshot.exists) {
      return snapshot.data();
    }
    return null;
  });
});
