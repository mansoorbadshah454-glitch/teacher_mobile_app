import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';

// Provides real-time chat messages between the current teacher and a specific admin
final chatMessagesProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, adminId) {
  final userAsync = ref.watch(teacherDataProvider);
  final authUser = ref.watch(currentUserProvider);

  if (authUser == null) {
    return Stream.value(const []);
  }

  return userAsync.when(
    data: (userData) {
      if (userData == null || userData['schoolId'] == null) {
        return Stream.value(const []);
      }

      final schoolId = userData['schoolId'];
      final teacherId = authUser.uid;
      final db = FirebaseFirestore.instance;

      // Fetch messages where:
      // (fromId == teacherId AND toId == adminId) OR (fromId == adminId AND toId == teacherId)
      
      // Since Firestore doesn't support OR queries across different fields easily without composite indexes or multiple queries,
      // and given the existing message schema (toId, fromId), we will fetch all messages for this teacher and filter locally 
      // OR use two streams and merge them.
      
      // Let's use two queries and merge for efficiency on the wire, but for now, 
      // following the existing schema where 'messages' is a flat collection under 'school/messages'.
      
      // We'll combine them by listening to both
      // However, to keep it simple and reactive, let's fetch messages for the teacher and filter.
      // The current 'inboxProvider' already fetches messages for the teacher ('toId' == teacherId).
      // We also need messages FROM the teacher ('fromId' == teacherId).

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
              final fromId = msg['fromId'] ?? msg['from'];
              final toId = msg['toId'] ?? msg['to'];

              // Filter to specific conversation with adminId
              // Compatibility: If participants is missing (old message), it won't show up here,
              // but we only fix new messages for scalability.
              final isFromSelected = (fromId == adminId || fromId == 'principal' || fromId == 'admin');
              final isToSelected = (toId == adminId || toId == 'principal' || toId == 'admin');

              return isFromSelected || isToSelected;
            })
            .toList();

        // Sort in-memory to avoid composite index requirement
        messages.sort((a, b) {
          final aTime = (a['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          final bTime = (b['timestamp'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          return bTime.compareTo(aTime); // Descending
        });

        return messages;
      });
    },
    loading: () => Stream.value(const []),
    error: (e, __) => Stream.value(const []),
  );
});
