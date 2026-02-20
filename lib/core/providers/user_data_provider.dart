import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Provides the current teacher's document data by merging global_users + schools/{id}/teachers/{uid}
final teacherDataProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  try {
    print('UserDataProvider: Fetching global_users document for ${user.uid}');
    // 1. Fetch from global_users
    final globalDoc = await FirebaseFirestore.instance
        .collection('global_users')
        .doc(user.uid)
        .get();
        
    if (!globalDoc.exists) {
        print('UserDataProvider: global_users document not found!');
        return null;
    }

    final globalData = globalDoc.data()!;
    final schoolId = globalData['schoolId'];
    
    if (schoolId == null) {
        print('UserDataProvider: No schoolId found in global_users!');
        return globalData; // Return what we have just in case
    }

    print('UserDataProvider: Fetching teacher profile from schools/$schoolId/teachers/${user.uid}');
    // 2. Fetch specific teacher profile
    final teacherDoc = await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('teachers')
        .doc(user.uid)
        .get();

    if (teacherDoc.exists) {
        // Merge global settings with specific teacher profile
        return {
            ...globalData,
            ...teacherDoc.data()!,
            'schoolId': schoolId,
        };
    }
    
    return globalData;
  } catch (e, st) {
    print('Error fetching teacher data: $e');
    print(st);
    return null;
  }
});

// Provides the school data based on the teacher's schoolId
final schoolDataProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final teacherData = await ref.watch(teacherDataProvider.future);
  if (teacherData == null || !teacherData.containsKey('schoolId')) return null;

  final schoolId = teacherData['schoolId'];
  try {
    print('UserDataProvider: Fetching school document for $schoolId');
    // Fetch School Root document
    final doc = await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .get();
        
    if (doc.exists) {
      final schoolData = doc.data()!;
      // Let's also check for a settings subcollection if needed based on the web app behaviour
      // Often settings/profile holds the logo
      try {
          final settingsDoc = await FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('settings')
              .doc('profile')
              .get();
          if (settingsDoc.exists) {
              final settingsData = settingsDoc.data()!;
              if (settingsData.containsKey('profileImage')) {
                  schoolData['logo'] = settingsData['profileImage'];
              }
              if (settingsData.containsKey('schoolName')) {
                  schoolData['name'] = settingsData['schoolName'];
              }
          }
      } catch (e) {
          print('UserDataProvider: Could not fetch settings/profile for school: $e');
      }
      return schoolData;
    }
    return null;
  } catch (e) {
    print('Error fetching school data: $e');
    return null;
  }
});
