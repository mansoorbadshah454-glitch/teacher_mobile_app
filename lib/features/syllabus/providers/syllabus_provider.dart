import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';
import 'package:teacher_mobile_app/features/timetable/providers/timetable_provider.dart';

// Represents a unique Syllabus Assignment for a teacher
class SyllabusAssignment {
  final String className;
  final String subject;

  SyllabusAssignment({required this.className, required this.subject});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyllabusAssignment &&
          runtimeType == other.runtimeType &&
          className == other.className &&
          subject == other.subject;

  @override
  int get hashCode => className.hashCode ^ subject.hashCode;
}

// 1. Extracts unique {class, subject} pairs from the Timetable
final mySyllabusesProvider = Provider<AsyncValue<List<SyllabusAssignment>>>((ref) {
  final timetableAsync = ref.watch(timetableProvider);

  return timetableAsync.when(
    data: (slots) {
      final assignments = <SyllabusAssignment>{};
      
      for (var slot in slots) {
        if (!slot.isFree && !slot.isBreak && slot.className.isNotEmpty && slot.subject.isNotEmpty) {
          assignments.add(SyllabusAssignment(
            className: slot.className,
            subject: slot.subject,
          ));
        }
      }

      final sortedList = assignments.toList()
        ..sort((a, b) {
          int classCompare = a.className.compareTo(b.className);
          if (classCompare != 0) return classCompare;
          return a.subject.compareTo(b.subject);
        });

      return AsyncValue.data(sortedList);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

// Helper for safe timestamp comparison
int _compareTimes(dynamic a, dynamic b) {
  int aMs = 0;
  int bMs = 0;
  if (a is Timestamp) aMs = a.millisecondsSinceEpoch;
  else if (a is DateTime) aMs = a.millisecondsSinceEpoch;
  else if (a is String) aMs = DateTime.tryParse(a)?.millisecondsSinceEpoch ?? 0;

  if (b is Timestamp) bMs = b.millisecondsSinceEpoch;
  else if (b is DateTime) bMs = b.millisecondsSinceEpoch;
  else if (b is String) bMs = DateTime.tryParse(b)?.millisecondsSinceEpoch ?? 0;

  return aMs.compareTo(bMs);
}

// 3. Fetch Syllabus Chapters for a specific Class and Subject (REAL-TIME STREAM WITH OFFLINE CACHE)
final syllabusChaptersProvider = StreamProvider.family<List<Map<String, dynamic>>, SyllabusAssignment>((ref, assignment) async* {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (teacherData == null || !teacherData.containsKey('schoolId')) {
    yield [];
    return;
  }

  final schoolId = teacherData['schoolId'] as String;
  final cacheKey = 'syllabus_chapters_${schoolId}_${assignment.className}_${assignment.subject}';

  // 1. Immediately yield cached chapters offline
  final cached = LocalDbService.getCache(cacheKey);
  if (cached is List) {
    try {
      final list = cached.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      yield list;
    } catch (_) {}
  }

  String classId = '';
  try {
    final classSnapshot = await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .where('name', isEqualTo: assignment.className)
        .limit(1)
        .get(const GetOptions(source: Source.serverAndCache))
        .timeout(const Duration(seconds: 3));

    if (classSnapshot.docs.isNotEmpty) {
      classId = classSnapshot.docs.first.id;
    } else {
      final allClasses = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 3));

      final cleanAssignName = assignment.className.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      for (var cDoc in allClasses.docs) {
        final cName = (cDoc.data()['name'] ?? '').toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        if (cName == cleanAssignName || cDoc.id.toLowerCase() == cleanAssignName) {
          classId = cDoc.id;
          break;
        }
      }
    }
  } catch (e) {
    debugPrint('Error finding class for syllabus: $e');
  }

  if (classId.isEmpty) {
    if (cached == null) yield [];
    return;
  }

  final chaptersStream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('classes')
      .doc(classId)
      .collection('syllabus')
      .doc(assignment.subject)
      .collection('chapters')
      .snapshots()
      .handleError((e) {
        debugPrint('Syllabus chapters stream error suppressed: $e');
      });

  await for (final snapshot in chaptersStream) {
    final docs = snapshot.docs.map((doc) {
      return {'id': doc.id, ...doc.data()};
    }).toList();

    // Sort locally by createdAt if available safely
    docs.sort((a, b) => _compareTimes(a['createdAt'], b['createdAt']));

    await LocalDbService.saveCache(cacheKey, docs);
    yield docs;
  }
});

// 4. Update Chapter Status
class SyllabusService {
  final Ref ref;
  SyllabusService(this.ref);

  Future<void> toggleChapterStatus(SyllabusAssignment assignment, String chapterId, String currentStatus) async {
    final teacherData = ref.read(teacherDataProvider).value;
    if (teacherData == null || !teacherData.containsKey('schoolId')) return;

    final schoolId = teacherData['schoolId'] as String;
    String classId = '';

    try {
      final classSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .where('name', isEqualTo: assignment.className)
          .limit(1)
          .get();

      if (classSnapshot.docs.isNotEmpty) {
        classId = classSnapshot.docs.first.id;
      } else {
        final allClasses = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .get();

        final cleanAssignName = assignment.className.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        for (var cDoc in allClasses.docs) {
          final cName = (cDoc.data()['name'] ?? '').toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
          if (cName == cleanAssignName || cDoc.id.toLowerCase() == cleanAssignName) {
            classId = cDoc.id;
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('Error finding class for toggleChapterStatus: $e');
    }

    if (classId.isEmpty) return;

    String newStatus;
    if (currentStatus == 'Pending') {
      newStatus = 'In Progress';
    } else if (currentStatus == 'In Progress') {
      newStatus = 'Completed';
    } else {
      newStatus = 'Pending';
    }

    await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('syllabus')
        .doc(assignment.subject)
        .collection('chapters')
        .doc(chapterId)
        .update({'status': newStatus});
  }
}

final syllabusServiceProvider = Provider((ref) => SyllabusService(ref));
