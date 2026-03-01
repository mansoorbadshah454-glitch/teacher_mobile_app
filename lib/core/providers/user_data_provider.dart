import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Provides the current teacher's document data by merging global_users + schools/{id}/teachers/{uid} in real-time
final teacherDataProvider = StreamProvider<Map<String, dynamic>?>((ref) async* {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
      yield null;
      return;
  }

  try {
      // Fetch global data once
      final globalDoc = await FirebaseFirestore.instance.collection('global_users').doc(user.uid).get();
      if (!globalDoc.exists) {
          yield null;
          return;
      }

      final globalData = globalDoc.data()!;
      final schoolId = globalData['schoolId'];

      if (schoolId == null) {
          yield globalData;
          return;
      }

      // Stream the local school teacher profile
      yield* FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .doc(user.uid)
          .snapshots()
          .map((teacherSnapshot) {
        if (teacherSnapshot.exists) {
          return {
            ...globalData,
            ...teacherSnapshot.data()!,
            'schoolId': schoolId,
          };
        }
        return globalData;
      }).handleError((e) {
          print('teacherDataProvider stream error suppressed: $e');
      });
  } catch (e, st) {
      print('Error in teacherDataProvider stream setup: $e');
      print(st);
  }
});

// Provides the school data based on the teacher's schoolId
final schoolDataProvider = StreamProvider<Map<String, dynamic>?>((ref) async* {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (teacherData == null || !teacherData.containsKey('schoolId')) {
    yield null;
    return;
  }

  final schoolId = teacherData['schoolId'];

  try {
    // School base data stream
    final schoolDocStream = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .snapshots()
        .handleError((e) {
             print('schoolDataProvider stream sync error suppressed: $e');
        });

    // Iterate over the school snapshot stream
    await for (final schoolSnap in schoolDocStream) {
        if (!schoolSnap.exists) {
           yield null;
           continue;
        }

        final schoolData = schoolSnap.data()!;

        // Attempt a concurrent fetch for settings snapshot (or just an await if settings rarely change)
        // Usually, school settings don't change frequently during a session, but to keep it safe:
        try {
            final settingsSnap = await FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('settings')
                .doc('profile')
                .get();

            if (settingsSnap.exists) {
                final settingsData = settingsSnap.data()!;
                if (settingsData.containsKey('profileImage')) {
                  schoolData['logo'] = settingsData['profileImage'];
                }
                if (settingsData.containsKey('schoolName')) {
                  schoolData['name'] = settingsData['schoolName'];
                }
            }
        } catch (_) {} // Ignore settings errors

        yield schoolData;
    }
  } catch (e, st) {
    print('Error fetching school data stream: $e');
    print(st);
  }
});
