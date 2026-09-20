import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:flutter/foundation.dart';

import 'package:teacher_mobile_app/core/services/local_db_service.dart';

// Provides the current teacher's document data by merging global_users + schools/{id}/teachers/{uid} in real-time
final teacherDataProvider = StreamProvider<Map<String, dynamic>?>((ref) async* {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
      yield null;
      return;
  }

  final cacheKey = 'teacher_profile_${user.uid}';

  // 1. Immediately yield cached profile if offline or opening cold
  final cachedProfile = LocalDbService.getCache(cacheKey);
  if (cachedProfile != null && cachedProfile is Map) {
    debugPrint('📦 [Hive] Loaded teacher profile for ${user.uid} from local cache.');
    yield Map<String, dynamic>.from(cachedProfile);
  }

  try {
      // Fetch global data (from cache if offline)
      DocumentSnapshot<Map<String, dynamic>> globalDoc;
      try {
        globalDoc = await FirebaseFirestore.instance.collection('global_users').doc(user.uid).get(
          const GetOptions(source: Source.serverAndCache),
        );
      } catch (_) {
        globalDoc = await FirebaseFirestore.instance.collection('global_users').doc(user.uid).get(
          const GetOptions(source: Source.cache),
        );
      }

      if (!globalDoc.exists || globalDoc.data() == null) {
          if (cachedProfile != null && cachedProfile is Map) {
            yield Map<String, dynamic>.from(cachedProfile);
          } else {
            yield null;
          }
          return;
      }

      final globalData = globalDoc.data()!;
      final schoolId = globalData['schoolId'] as String?;

      if (schoolId == null) {
          debugPrint('teacherDataProvider: User ${user.uid} has no schoolId in global_users');
          yield globalData;
          return;
      }

      debugPrint('teacherDataProvider: Fetching local profile from schools/$schoolId/teachers/${user.uid}');

      // Stream the local school teacher profile
      final stream = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .doc(user.uid)
          .snapshots();

      await for (final teacherSnapshot in stream) {
        Map<String, dynamic> combined;
        if (teacherSnapshot.exists && teacherSnapshot.data() != null) {
          combined = {
            ...globalData,
            ...teacherSnapshot.data()!,
            'schoolId': schoolId,
          };
        } else {
          combined = {
            ...globalData,
            'schoolId': schoolId,
          };
        }

        // Save fresh combined profile to local Hive cache
        await LocalDbService.saveCache(cacheKey, combined);
        yield combined;
      }
  } catch (e, st) {
      debugPrint('Error in teacherDataProvider stream setup: $e');
      debugPrint(st.toString());
      if (cachedProfile != null && cachedProfile is Map) {
        yield Map<String, dynamic>.from(cachedProfile);
      }
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
    // Determine local prefs instantly for fast visual caching
    final prefs = await SharedPreferences.getInstance();

    // School base data stream
    final schoolDocStream = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .snapshots()
        .handleError((e) {
             debugPrint('schoolDataProvider stream sync error suppressed: $e');
        });

    // Iterate over the school snapshot stream
    await for (final schoolSnap in schoolDocStream) {
        if (!schoolSnap.exists) {
           yield null;
           continue;
        }

        final schoolData = schoolSnap.data()!;

        // 1. Instantly inject the cached logo and name into the model before hitting the backend
        final cachedLogo = prefs.getString('cached_school_logo_$schoolId');
        final cachedName = prefs.getString('cached_school_name_$schoolId');
        
        if (cachedLogo != null && cachedLogo.isNotEmpty) {
           schoolData['logo'] = cachedLogo;
        }
        if (cachedName != null && cachedName.isNotEmpty) {
           schoolData['name'] = cachedName;
        }

        // 2. Yield immediately into the riverpod stream. This draws the Drawer and UI instantly!
        yield Map<String, dynamic>.from(schoolData);

        // 3. Perform the network call asynchronously and if it's different, update cache and yield again seamlessly.
        try {
            final settingsSnap = await FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('settings')
                .doc('profile')
                .get();

            if (settingsSnap.exists) {
                final settingsData = settingsSnap.data()!;
                bool changed = false;

                if (settingsData.containsKey('profileImage')) {
                  final freshLogo = settingsData['profileImage'];
                  if (freshLogo != null && freshLogo != schoolData['logo']) {
                      schoolData['logo'] = freshLogo;
                      await prefs.setString('cached_school_logo_$schoolId', freshLogo);
                      changed = true;
                  }
                }
                
                final freshName = settingsData['name'] ?? settingsData['schoolName'];
                if (freshName != null && freshName != schoolData['name']) {
                    schoolData['name'] = freshName;
                    await prefs.setString('cached_school_name_$schoolId', freshName);
                    changed = true;
                }

                if (changed) {
                    yield Map<String, dynamic>.from(schoolData);
                }
            }
        } catch (_) {} // Ignore settings errors
    }
  } catch (e, st) {
    debugPrint('Error fetching school data stream: $e');
    debugPrint(st.toString());
  }
});
