import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';

// Provides a real-time list of messages intended for the current teacher
final inboxProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final userAsync = ref.watch(teacherDataProvider);
  final authUser = ref.watch(currentUserProvider);

  if (authUser == null) {
      return Stream.value(const <Map<String, dynamic>>[]);
  }

  // Need schoolId and teacherId to fetch messages
  return userAsync.when(
    data: (userData) {
      if (userData == null || userData['schoolId'] == null) {
        return Stream.value(const <Map<String, dynamic>>[]);
      }
      
      final schoolId = userData['schoolId'];
      final teacherId = authUser.uid;

      final db = FirebaseFirestore.instance;
      
      return db
          .collection('schools')
          .doc(schoolId)
          .collection('messages')
          .where('participants', arrayContains: teacherId)
          .snapshots()
          .map((snapshot) {
            final messages = snapshot.docs
                .map((doc) {
                  final data = doc.data();
                  data['id'] = doc.id;
                  return data;
                })
                .where((msg) {
                  // Filter for messages actually intended to be received by me
                  return msg['toId'] == teacherId || msg['to'] == teacherId || msg['to'] == 'all';
                })
                .toList();

            // Sort in-memory to avoid composite index requirement
            messages.sort((a, b) {
              final aTime = (a['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
              final bTime = (b['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
              return bTime.compareTo(aTime); // Descending (Newest first)
            });

            return messages;
          }).handleError((e) {
             print('InboxProvider: Eager sync error suppressed: $e');
          });
    },
    loading: () => Stream.value(const <Map<String, dynamic>>[]),
    error: (e, __) {
      print('InboxProvider Error State: $e');
      return Stream.value(const <Map<String, dynamic>>[]);
    },
  );
});
