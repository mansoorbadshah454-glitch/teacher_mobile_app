import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
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


// 3. Stream Syllabus Chapters for a specific Class and Subject
final syllabusChaptersProvider = StreamProvider.family<List<Map<String, dynamic>>, SyllabusAssignment>((ref, assignment) async* {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (teacherData == null || !teacherData.containsKey('schoolId')) {
    yield [];
    return;
  }

  final schoolId = teacherData['schoolId'] as String;
  final classSnapshot = await FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('classes')
      .where('name', isEqualTo: assignment.className)
      .limit(1)
      .get();

  if (classSnapshot.docs.isEmpty) {
    yield [];
    return;
  }

  final classId = classSnapshot.docs.first.id;

  yield* FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('classes')
      .doc(classId)
      .collection('syllabus')
      .doc(assignment.subject)
      .collection('chapters')
      .snapshots()
      .map((snapshot) {
    final docs = snapshot.docs.map((doc) {
      return {'id': doc.id, ...doc.data()};
    }).toList();
    
    // Sort locally by createdAt if available
    docs.sort((a, b) {
      final aTime = a['createdAt'] as Timestamp?;
      final bTime = b['createdAt'] as Timestamp?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1; // nulls at the end
      if (bTime == null) return -1;
      return aTime.compareTo(bTime);
    });
    
    return docs;
  });
});

// 4. Update Chapter Status
class SyllabusService {
  final Ref ref;
  SyllabusService(this.ref);

  Future<void> toggleChapterStatus(SyllabusAssignment assignment, String chapterId, String currentStatus) async {
    final teacherData = ref.read(teacherDataProvider).value;
    if (teacherData == null || !teacherData.containsKey('schoolId')) return;

    final schoolId = teacherData['schoolId'] as String;
    final classSnapshot = await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .where('name', isEqualTo: assignment.className)
        .limit(1)
        .get();

    if (classSnapshot.docs.isEmpty) return;
    
    final classId = classSnapshot.docs.first.id;

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
