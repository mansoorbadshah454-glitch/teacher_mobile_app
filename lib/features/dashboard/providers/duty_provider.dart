import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';

/// Helper to check if a timestamp is from yesterday or earlier
bool _isNewDay(Timestamp? lastUpdate) {
  if (lastUpdate == null) return false;
  
  final lastDate = lastUpdate.toDate();
  final now = DateTime.now();
  
  final lastDay = DateTime(lastDate.year, lastDate.month, lastDate.day);
  final currentDay = DateTime(now.year, now.month, now.day);
  
  return currentDay.isAfter(lastDay);
}

/// A class representing the current duty state
class DutyState {
  final bool isOnDuty;
  final bool isLoading;

  DutyState({required this.isOnDuty, this.isLoading = false});
}

/// Notifier to manage Duty state and write updates to Firestore
class DutyStatusNotifier extends AutoDisposeStreamNotifier<bool> {
  @override
  Stream<bool> build() {
    return _dutyStream();
  }

  Stream<bool> _dutyStream() async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      yield false;
      return;
    }

    // Await global user data to get schoolId
    final teacherData = await ref.watch(teacherDataProvider.future);
    if (teacherData == null || !teacherData.containsKey('schoolId')) {
      yield false;
      return;
    }

    final schoolId = teacherData['schoolId'] as String;

    yield* FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('teachers')
        .doc(user.uid)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return false;
      }

      final data = snapshot.data()!;
      final bool dutyStatus = data['isOnDuty'] ?? false;
      final Timestamp? lastUpdate = data['lastDutyUpdate'] as Timestamp?;

      if (_isNewDay(lastUpdate) || !dutyStatus) {
        return false;
      }

      return true;
    }).handleError((e) {
      print('DutyStatusNotifier stream error suppressed: $e');
      return false; // Return false or drop the event if it's transient
    });
  }

  Future<void> toggleDuty(bool newValue) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final teacherData = await ref.read(teacherDataProvider.future);
    if (teacherData == null || !teacherData.containsKey('schoolId')) return;

    final schoolId = teacherData['schoolId'] as String;

    try {
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .doc(user.uid)
          .set({
        'isOnDuty': newValue,
        'lastDutyUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('DutyStatusNotifier Error toggling duty: $e');
    }
  }
}

final dutyStatusProvider = AutoDisposeStreamNotifierProvider<DutyStatusNotifier, bool>(() {
  return DutyStatusNotifier();
});
