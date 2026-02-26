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
          .where('toId', isEqualTo: teacherId) // Only messages for this teacher
          .orderBy('timestamp', descending: true)
          .snapshots()
          .map((snapshot) {
             return snapshot.docs.map((doc) {
                 final data = doc.data();
                 data['id'] = doc.id; // Include auto-generated ID for deletion
                 return data;
             }).toList();
          });
    },
    loading: () => Stream.value(const <Map<String, dynamic>>[]),
    error: (_, __) => Stream.value(const <Map<String, dynamic>>[]),
  );
});
