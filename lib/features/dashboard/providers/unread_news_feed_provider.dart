import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';

final _teacherLastReadProvider = StreamProvider<Timestamp?>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return Stream.value(null);
  }

  final teacherDataAsync = ref.watch(teacherDataProvider);

  return teacherDataAsync.when(
    data: (teacherData) {
      if (teacherData == null || !teacherData.containsKey('schoolId')) {
        return Stream.value(null);
      }

      final schoolId = teacherData['schoolId'] as String;

      // Stream the teacher's profile to listen for changes to lastReadNewsFeed
      return FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('teachers')
          .doc(user.uid)
          .snapshots()
          .map((teacherSnapshot) {
        if (teacherSnapshot.exists && teacherSnapshot.data() != null) {
          final data = teacherSnapshot.data()!;
          if (data.containsKey('lastReadNewsFeed')) {
            return data['lastReadNewsFeed'] as Timestamp?;
          }
        }
        return null;
      });
    },
    loading: () => Stream.value(null),
    error: (_, __) => Stream.value(null),
  );
});

/// Provider to calculate the number of unread news feed posts.
final unreadNewsFeedProvider = StreamProvider<int>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return Stream.value(0);
  }

  // Watch the teacher data to get the school ID
  final teacherDataAsync = ref.watch(teacherDataProvider);
  // Watch the teacher's last read timestamp
  final lastReadAsync = ref.watch(_teacherLastReadProvider);

  return teacherDataAsync.when(
    data: (teacherData) {
      if (teacherData == null || !teacherData.containsKey('schoolId')) {
        return Stream.value(0);
      }

      final schoolId = teacherData['schoolId'] as String;

      return lastReadAsync.when(
        data: (lastReadTimestamp) {
          // Now query posts that are newer than the last read timestamp
          Query postsQuery = FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('posts')
              .orderBy('timestamp', descending: true);

          if (lastReadTimestamp != null) {
            postsQuery = postsQuery.where('timestamp', isGreaterThan: lastReadTimestamp);
          } else {
            // If the user has never read the feed, limit to recent posts to avoid huge numbers
            // For example, posts from the last 7 days
            final sevenDaysAgo = Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 7)));
            postsQuery = postsQuery.where('timestamp', isGreaterThan: sevenDaysAgo);
          }

          return postsQuery.snapshots().map((snapshot) {
            return snapshot.docs.length;
          });
        },
        loading: () => Stream.value(0),
        error: (_, __) => Stream.value(0),
      );
    },
    loading: () => Stream.value(0),
    error: (_, __) => Stream.value(0),
  );
});
