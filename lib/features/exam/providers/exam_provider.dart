import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/features/timetable/providers/timetable_provider.dart';
import 'package:teacher_mobile_app/features/exam/models/exam_model.dart';

// 1. Fetch all assigned classes & subjects for the logged-in teacher (LIVE STREAM)
final teacherExamClassesProvider = StreamProvider<List<ExamClassSubject>>((ref) async* {
  final user = ref.watch(currentUserProvider);
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;
  final timetableAsync = ref.watch(timetableProvider);
  final slots = timetableAsync.value ?? [];

  if (user == null || teacherData == null || !teacherData.containsKey('schoolId')) {
    yield [];
    return;
  }

  final String schoolId = (teacherData['schoolId'] ?? '').toString();
  final String teacherUid = user.uid;
  if (schoolId.isEmpty) {
    yield [];
    return;
  }

  // Stream the classes collection so any updates reflect in real-time
  final classesStream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('classes')
      .snapshots();

  await for (final snapshot in classesStream) {
    final Map<String, Set<String>> classSubjectMap = {};

    // 1. Read directly from permanent weeklyMaster timetable document (The Master Schedule)
    try {
      final timetableDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('timetables')
          .doc('weeklyMaster')
          .get();

      if (timetableDoc.exists && timetableDoc.data() != null) {
        final tData = timetableDoc.data()!;
        final List<dynamic> rows = tData['rows'] ?? [];

        for (var r in rows) {
          if (r == null || r is! Map) continue;
          final rTeacherId = (r['teacherId'] ?? '').toString();

          if (rTeacherId == teacherUid || rTeacherId == teacherData['id']) {
            final List<dynamic> cells = r['cells'] ?? [];
            for (var c in cells) {
              if (c == null || c is! Map) continue;
              final cClass = (c['class'] ?? '').toString().trim();
              final cSubj = (c['subject'] ?? '').toString().trim();

              if (cClass.isNotEmpty && cClass != 'FREE' && cClass != 'BREAK' && cSubj.isNotEmpty) {
                classSubjectMap.putIfAbsent(cClass, () => <String>{}).add(cSubj);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Timetable master fetch error: $e');
    }

    // 2. Fallback to timetable slots if weeklyMaster was empty
    if (classSubjectMap.isEmpty) {
      for (final slot in slots) {
        if (!slot.isFree && !slot.isBreak && slot.className.trim().isNotEmpty) {
          final cName = slot.className.trim();
          final subj = slot.subject.trim();
          if (subj.isNotEmpty) {
            classSubjectMap.putIfAbsent(cName, () => <String>{}).add(subj);
          }
        }
      }
    }

    // Build the result
    final List<ExamClassSubject> result = [];

    for (final entry in classSubjectMap.entries) {
      final className = entry.key;
      final subjectsList = entry.value.toList()..sort();

      String classId = '';
      int studentCount = 0;

      for (final d in snapshot.docs) {
        final dName = (d.data()['name'] ?? '').toString().trim().toLowerCase();
        if (dName == className.toLowerCase()) {
          classId = d.id;
          studentCount = (d.data()['studentCount'] as num?)?.toInt() ??
              (d.data()['totalStudents'] as num?)?.toInt() ??
              0;
          break;
        }
      }

      if (classId.isEmpty && snapshot.docs.isNotEmpty) {
        classId = snapshot.docs.first.id;
        studentCount = (snapshot.docs.first.data()['studentCount'] as num?)?.toInt() ??
            (snapshot.docs.first.data()['totalStudents'] as num?)?.toInt() ??
            0;
      }

      // If root document doesn't store a static counter, fetch real count from subcollection
      if (classId.isNotEmpty && studentCount == 0) {
        try {
          final countSnap = await FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('classes')
              .doc(classId)
              .collection('students')
              .count()
              .get();
          studentCount = countSnap.count ?? 0;
        } catch (_) {
          try {
            final stSnap = await FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('classes')
                .doc(classId)
                .collection('students')
                .get();
            studentCount = stSnap.docs.length;
          } catch (_) {}
        }
      }

      if (classId.isNotEmpty) {
        result.add(ExamClassSubject(
          classId: classId,
          className: className,
          subjects: subjectsList.isNotEmpty ? subjectsList : ['General'],
          studentCount: studentCount,
        ));
      }
    }

    result.sort((a, b) => a.className.compareTo(b.className));
    yield result;
  }
});

// 2. Fetch Active Exams list for the School (with fallback presets)
final schoolExamsProvider = StreamProvider<List<ExamModel>>((ref) async* {
  // Yield default presets immediately so UI never hangs
  yield _getDefaultExams();

  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (teacherData == null || !teacherData.containsKey('schoolId')) {
    return;
  }

  final String schoolId = (teacherData['schoolId'] ?? '').toString();
  if (schoolId.isEmpty) return;

  try {
    final stream = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('exams')
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return _getDefaultExams();
      }
      return snapshot.docs.map((doc) {
        return ExamModel.fromFirestore(doc.id, doc.data());
      }).toList();
    }).handleError((e) {
      debugPrint('Exams stream error (falling back to defaults): $e');
      return _getDefaultExams();
    });

    yield* stream;
  } catch (e) {
    debugPrint('Error setting up exams stream: $e');
    yield _getDefaultExams();
  }
});

List<ExamModel> _getDefaultExams() {
  return [
    ExamModel(
      id: 'first_term_2026',
      title: 'First Term Examination 2026',
      session: '2025-2026',
      status: 'active',
      defaultTotalMarks: 100,
      passingMarks: 33,
    ),
    ExamModel(
      id: 'mid_term_2026',
      title: 'Mid Term Examination 2026',
      session: '2025-2026',
      status: 'active',
      defaultTotalMarks: 50,
      passingMarks: 17,
    ),
    ExamModel(
      id: 'monthly_test',
      title: 'Monthly Class Test',
      session: '2025-2026',
      status: 'active',
      defaultTotalMarks: 25,
      passingMarks: 10,
    ),
    ExamModel(
      id: 'final_term_2026',
      title: 'Annual / Final Examination 2026',
      session: '2025-2026',
      status: 'upcoming',
      defaultTotalMarks: 100,
      passingMarks: 33,
    ),
  ];
}

// 3. Class & Subject parameter bundle for marks query
class ExamSubjectQuery {
  final String classId;
  final String className;
  final String examId;
  final String subject;

  ExamSubjectQuery({
    required this.classId,
    required this.className,
    required this.examId,
    required this.subject,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExamSubjectQuery &&
          runtimeType == other.runtimeType &&
          classId == other.classId &&
          className == other.className &&
          examId == other.examId &&
          subject == other.subject;

  @override
  int get hashCode => classId.hashCode ^ className.hashCode ^ examId.hashCode ^ subject.hashCode;
}

// 4. Fetch Students and Existing Marks for a Class + Exam + Subject (LIVE STREAM)
final examMarksSheetProvider =
    StreamProvider.family<Map<String, dynamic>, ExamSubjectQuery>((ref, query) async* {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final teacherData = teacherDataAsync.value;

  if (teacherData == null || !teacherData.containsKey('schoolId')) {
    yield {'students': <StudentMarksEntry>[], 'totalMarks': 100, 'passingMarks': 33};
    return;
  }

  final String schoolId = (teacherData['schoolId'] ?? '').toString();
  if (schoolId.isEmpty) {
    yield {'students': <StudentMarksEntry>[], 'totalMarks': 100, 'passingMarks': 33};
    return;
  }

  // 1. Resolve Class ID by finding matching class document in schools/{schoolId}/classes
  String targetClassId = query.classId;

  try {
    final classesSnap = await FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .get();

    final cleanQueryName = query.className.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

    for (final cDoc in classesSnap.docs) {
      final cData = cDoc.data();
      final cName = (cData['name'] ?? '').toString().trim();
      final cleanCName = cName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      final cleanDocId = cDoc.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

      if (cleanCName == cleanQueryName || cleanDocId == cleanQueryName || cleanCName.contains(cleanQueryName) || cleanQueryName.contains(cleanCName)) {
        targetClassId = cDoc.id;
        break;
      }
    }
  } catch (e) {
    debugPrint('Error resolving target class ID: $e');
  }

  final marksDocId = '${query.examId}_${query.subject}'.replaceAll('/', '_').replaceAll(' ', '_');

  // 2. Stream the students subcollection live
  final studentsStream = FirebaseFirestore.instance
      .collection('schools')
      .doc(schoolId)
      .collection('classes')
      .doc(targetClassId)
      .collection('students')
      .snapshots();

  await for (final snapshot in studentsStream) {
    // Also fetch existing marks
    Map<String, dynamic> marksMap = {};
    int totalMarks = 100;
    int passingMarks = 33;
    bool isAlreadySubmitted = false;

    try {
      final marksDocSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .doc(targetClassId)
          .collection('exam_marks')
          .doc(marksDocId)
          .get();

      if (marksDocSnapshot.exists && marksDocSnapshot.data() != null) {
        final existingMarksData = marksDocSnapshot.data()!;
        marksMap = (existingMarksData['marks'] as Map<String, dynamic>?) ?? {};
        totalMarks = (existingMarksData['totalMarks'] as num?)?.toInt() ?? 100;
        passingMarks = (existingMarksData['passingMarks'] as num?)?.toInt() ?? 33;
        isAlreadySubmitted = true;
      }
    } catch (_) {}

    final List<StudentMarksEntry> entries = [];

    for (final doc in snapshot.docs) {
      final sData = doc.data();
      final studentId = doc.id;
      final firstName = (sData['firstName'] ?? '').toString().trim();
      final lastName = (sData['lastName'] ?? '').toString().trim();
      final combinedName = firstName.isNotEmpty ? '$firstName $lastName'.trim() : '';
      final studentName = (sData['name'] ?? sData['fullName'] ?? combinedName).toString().trim();
      final rollNo = (sData['rollNo'] ?? sData['rollNumber'] ?? '').toString().trim();
      final photoUrl = (sData['photoUrl'] ?? sData['avatar'] ?? sData['profilePic'] ?? sData['image'] ?? '').toString();

      final existingStudentMark = marksMap[studentId] as Map<String, dynamic>?;

      double? obtained;
      bool isAbsent = false;
      String remarks = '';

      if (existingStudentMark != null) {
        if (existingStudentMark['isAbsent'] == true) {
          isAbsent = true;
        } else if (existingStudentMark['obtainedMarks'] != null) {
          obtained = (existingStudentMark['obtainedMarks'] as num).toDouble();
        }
        remarks = (existingStudentMark['remarks'] ?? '').toString();
      }

      entries.add(StudentMarksEntry(
        studentId: studentId,
        studentName: studentName.isNotEmpty ? studentName : 'Student',
        rollNumber: rollNo,
        photoUrl: photoUrl,
        obtainedMarks: obtained,
        isAbsent: isAbsent,
        remarks: remarks,
      ));
    }

    // Sort by roll number if numerical, otherwise by name
    entries.sort((a, b) {
      final rollA = int.tryParse(a.rollNumber);
      final rollB = int.tryParse(b.rollNumber);
      if (rollA != null && rollB != null) {
        return rollA.compareTo(rollB);
      }
      return a.studentName.compareTo(b.studentName);
    });

    yield {
      'students': entries,
      'totalMarks': totalMarks,
      'passingMarks': passingMarks,
      'resolvedClassId': targetClassId,
      'isAlreadySubmitted': isAlreadySubmitted,
    };
  }
});

// 5. StateNotifier for Saving Marks
class MarksSaveState {
  final bool isLoading;
  final bool isSuccess;
  final String? error;

  MarksSaveState({this.isLoading = false, this.isSuccess = false, this.error});
}

class MarksSaveNotifier extends StateNotifier<MarksSaveState> {
  MarksSaveNotifier() : super(MarksSaveState());

  Future<bool> saveMarks({
    required String schoolId,
    required String classId,
    required String className,
    required String examId,
    required String examTitle,
    required String subject,
    required String teacherId,
    required String teacherName,
    required int totalMarks,
    required int passingMarks,
    required List<StudentMarksEntry> entries,
  }) async {
    state = MarksSaveState(isLoading: true);

    try {
      final marksDocId = '${examId}_$subject'.replaceAll('/', '_').replaceAll(' ', '_');
      final Map<String, dynamic> marksData = {};

      for (final entry in entries) {
        marksData[entry.studentId] = {
          'studentId': entry.studentId,
          'studentName': entry.studentName,
          'rollNumber': entry.rollNumber,
          'obtainedMarks': entry.isAbsent ? null : entry.obtainedMarks,
          'isAbsent': entry.isAbsent,
          'remarks': entry.remarks,
          'grade': entry.getGrade(totalMarks.toDouble()),
          'percentage': entry.getPercentage(totalMarks.toDouble()),
        };
      }

      final batch = FirebaseFirestore.instance.batch();

      // 1. Save to Class Exam Marks Collection
      final classMarksRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .doc(classId)
          .collection('exam_marks')
          .doc(marksDocId);

      batch.set(
        classMarksRef,
        {
          'examId': examId,
          'examTitle': examTitle,
          'classId': classId,
          'className': className,
          'subject': subject,
          'teacherId': teacherId,
          'teacherName': teacherName,
          'totalMarks': totalMarks,
          'passingMarks': passingMarks,
          'updatedAt': FieldValue.serverTimestamp(),
          'marks': marksData,
        },
        SetOptions(merge: true),
      );

      // 2. Also merge into each student's exam_results subcollection
      for (final entry in entries) {
        final studentResultRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId)
            .collection('students')
            .doc(entry.studentId)
            .collection('exam_results')
            .doc(examId);

        batch.set(
          studentResultRef,
          {
            'examId': examId,
            'examTitle': examTitle,
            'updatedAt': FieldValue.serverTimestamp(),
            'subjects': {
              subject: {
                'subject': subject,
                'totalMarks': totalMarks,
                'obtainedMarks': entry.isAbsent ? null : entry.obtainedMarks,
                'isAbsent': entry.isAbsent,
                'grade': entry.getGrade(totalMarks.toDouble()),
                'remarks': entry.remarks,
              }
            }
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();
      state = MarksSaveState(isSuccess: true);
      return true;
    } catch (e) {
      debugPrint('Error saving marks: $e');
      state = MarksSaveState(error: e.toString());
      return false;
    }
  }

  void reset() {
    state = MarksSaveState();
  }
}

final marksSaveProvider =
    StateNotifierProvider<MarksSaveNotifier, MarksSaveState>((ref) => MarksSaveNotifier());
