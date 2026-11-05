import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';
import 'package:teacher_mobile_app/core/services/sync_queue_service.dart';

class ParentPersonalChatParams {
  final String schoolId;
  final String parentId;
  final String studentId;

  const ParentPersonalChatParams({
    required this.schoolId,
    required this.parentId,
    required this.studentId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ParentPersonalChatParams &&
          runtimeType == other.runtimeType &&
          schoolId == other.schoolId &&
          parentId == other.parentId &&
          studentId == other.studentId;

  @override
  int get hashCode => schoolId.hashCode ^ parentId.hashCode ^ studentId.hashCode;
}

DateTime? _parseTimestamp(dynamic val) {
  if (val == null) return null;
  if (val is Timestamp) return val.toDate();
  if (val is DateTime) return val;
  if (val is String) return DateTime.tryParse(val);
  return null;
}

/// Refresh trigger to force instant local echo on offline/online message dispatch
final parentChatRefreshTriggerProvider = StateProvider.autoDispose<int>((ref) => 0);

/// Stream provider for 1-on-1 personal messages between teacher and a specific parent for a student.
/// Implements:
/// 1. Instant offline retrieval from LocalDbService (1 page / 40 messages max)
/// 2. 14-day window in-memory filter and Firestore auto-purge
/// 3. Zero Composite Index Requirement (uses direct equality filters supported out-of-the-box)
/// 4. Merging with offline-queued pending items from SyncQueueService
/// 5. Instant local echo on offline/online message submission
final parentPersonalChatMessagesProvider =
    StreamProvider.family.autoDispose<List<Map<String, dynamic>>, ParentPersonalChatParams>((ref, params) async* {
  ref.watch(parentChatRefreshTriggerProvider);
  final cacheKey = 'chat_${params.schoolId}_${params.parentId}_${params.studentId}';
  final fourteenDaysAgo = DateTime.now().subtract(const Duration(days: 14));

  // Helper to fetch and merge pending items with a messages list
  List<Map<String, dynamic>> mergeWithPending(List<Map<String, dynamic>> messages) {
    final pending = SyncQueueService.getPendingMessagesFor(
      schoolId: params.schoolId,
      parentId: params.parentId,
      studentId: params.studentId,
    );

    if (pending.isEmpty) return messages;

    final combined = <Map<String, dynamic>>[...pending, ...messages];
    combined.sort((a, b) {
      final tA = _parseTimestamp(a['timestamp']);
      final tB = _parseTimestamp(b['timestamp']);
      if (tA == null && tB == null) return 0;
      if (tA == null) return 1;
      if (tB == null) return -1;
      return tB.compareTo(tA); // Descending (newest first)
    });
    return combined;
  }

  // 1. Immediately yield cached messages (capped to 40 items / 1 page)
  final cached = LocalDbService.getCache(cacheKey);
  if (cached is List) {
    final filteredCache = cached
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) {
          final time = _parseTimestamp(m['timestamp']);
          return time == null || time.isAfter(fourteenDaysAgo);
        })
        .toList();
    final pageCapped = filteredCache.length > 40 ? filteredCache.sublist(0, 40) : filteredCache;
    yield mergeWithPending(pageCapped);
  } else {
    // Even if cache is empty, check for pending items
    final pendingOnly = mergeWithPending([]);
    if (pendingOnly.isNotEmpty) {
      yield pendingOnly;
    }
  }

  if (params.schoolId.isEmpty || params.parentId.isEmpty || params.studentId.isEmpty) {
    yield [];
    return;
  }

  // 2. Stream from Firestore with simple equality filters (No composite index required!)
  Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  try {
    stream = FirebaseFirestore.instance
        .collection('schools')
        .doc(params.schoolId)
        .collection('messages')
        .where('parentId', isEqualTo: params.parentId)
        .where('studentId', isEqualTo: params.studentId)
        .snapshots();
  } catch (e) {
    debugPrint('⚠️ [PersonalChat] Stream initialization fallback: $e');
    return;
  }

  await for (final snapshot in stream) {
    final serverMessages = <Map<String, dynamic>>[];
    final docsToDelete = <DocumentReference>[];

    for (final doc in snapshot.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      data['read'] = data['read'] ?? false;

      final timestamp = _parseTimestamp(data['timestamp']);
      if (timestamp != null && timestamp.isBefore(fourteenDaysAgo)) {
        // Auto-purge: document is older than 14 days, mark for Firestore deletion!
        docsToDelete.add(doc.reference);
      } else {
        serverMessages.add(data);
      }
    }

    // In-memory sort by timestamp descending (newest first)
    serverMessages.sort((a, b) {
      final tA = _parseTimestamp(a['timestamp']);
      final tB = _parseTimestamp(b['timestamp']);
      if (tA == null && tB == null) return 0;
      if (tA == null) return 1;
      if (tB == null) return -1;
      return tB.compareTo(tA);
    });

    // Auto-delete documents older than 14 days from Firestore to save DB storage cost
    if (docsToDelete.isNotEmpty) {
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final ref in docsToDelete) {
          batch.delete(ref);
        }
        batch.commit().catchError((e) {
          debugPrint('⚠️ [PersonalChat] Purge error: $e');
        });
        debugPrint('🧹 [ChatPurge] Automatically deleted ${docsToDelete.length} messages older than 14 days.');
      } catch (_) {}
    }

    // Limit cache to 1 page (40 recent messages) to keep device memory fast & lean
    final pageCapped = serverMessages.length > 40 ? serverMessages.sublist(0, 40) : serverMessages;
    await LocalDbService.saveCache(cacheKey, pageCapped);

    yield mergeWithPending(pageCapped);
  }
});
