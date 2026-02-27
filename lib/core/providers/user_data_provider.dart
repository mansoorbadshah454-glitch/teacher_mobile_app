import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rxdart/rxdart.dart';

// Provides the current teacher's document data by merging global_users + schools/{id}/teachers/{uid} in real-time
final teacherDataProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(null);

  // First, we need the global_user doc to get the schoolId. We listen to that too just in case.
  return FirebaseFirestore.instance
      .collection('global_users')
      .doc(user.uid)
      .snapshots()
      .switchMap((globalSnapshot) {
    if (!globalSnapshot.exists) {
      print('UserDataProvider: global_users document not found!');
      return Stream.value(null);
    }

    final globalData = globalSnapshot.data()!;
    final schoolId = globalData['schoolId'];

    if (schoolId == null) {
      print('UserDataProvider: No schoolId found in global_users!');
      return Stream.value(globalData); // Return what we have
    }

    // Now listen to the specific teacher profile in the school
    return FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('teachers')
        .doc(user.uid)
        .snapshots()
        .map((teacherSnapshot) {
      if (teacherSnapshot.exists) {
        // Merge global settings with specific teacher profile
        return {
          ...globalData,
          ...teacherSnapshot.data()!,
          'schoolId': schoolId,
        };
      }
      return globalData; // Fallback
    });
  }).handleError((e, st) {
    print('Error fetching teacher data stream: $e');
    print(st);
  });
});

// Provides the school data based on the teacher's schoolId
final schoolDataProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (teacherData == null || !teacherData.containsKey('schoolId')) {
    return Stream.value(null);
  }

  final schoolId = teacherData['schoolId'];

  // Combine School Document and Settings Document streams to merge the logo & name
  final schoolDocStream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .snapshots();

  final settingsDocStream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('settings')
      .doc('profile')
      .snapshots();

  return Rx.combineLatest2(schoolDocStream, settingsDocStream,
      (schoolSnap, settingsSnap) {
    if (schoolSnap.exists) {
      final schoolData = schoolSnap.data()!;

      if (settingsSnap.exists) {
        final settingsData = settingsSnap.data()!;
        if (settingsData.containsKey('profileImage')) {
          schoolData['logo'] = settingsData['profileImage'];
        }
        if (settingsData.containsKey('schoolName')) {
          schoolData['name'] = settingsData['schoolName'];
        }
      }
      return schoolData;
    }
    return null;
  }).handleError((e) {
    print('Error fetching school data stream: $e');
  });
});
