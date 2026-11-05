import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';
import 'package:teacher_mobile_app/core/services/sync_queue_service.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/features/timetable/providers/timetable_provider.dart';
import 'package:teacher_mobile_app/features/exam/models/exam_model.dart';

// 1. Fetch all assigned classes & subjects for the logged-in teacher (OFFLINE RESILIENT LIVE STREAM)
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

  final cacheKey = 'teacher_exam_classes_${schoolId}_$teacherUid';

  // 1. Instantly yield cached classes if offline or on initial open
  final cached = LocalDbService.getCache(cacheKey);
  if (cached is List) {
    try {
      final cachedList = cached.map((e) => ExamClassSubject(
        classId: (e['classId'] ?? '').toString(),
        className: (e['className'] ?? '').toString(),
        subjects: List<String>.from(e['subjects'] ?? ['General']),
        studentCount: (e['studentCount'] as num?)?.toInt() ?? 0,
      )).toList();
      yield cachedList;
    } catch (_) {}
  }

  // 2. Stream the classes collection so any updates reflect in real-time
  try {
    final classesStream = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .snapshots()
        .handleError((e) {
          debugPrint('Classes stream error suppressed: $e');
        });

    await for (final snapshot in classesStream) {
      final Map<String, Set<String>> classSubjectMap = {};

      // A. Read directly from permanent weeklyMaster timetable document
      try {
        final timetableDoc = await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('timetables')
            .doc('weeklyMaster')
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 4));

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

      // B. Fallback to timetable slots if weeklyMaster was empty
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

        if (classId.isEmpty) {
          final cleanTarget = className.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
          for (final d in snapshot.docs) {
            final cleanD = (d.data()['name'] ?? '').toString().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
            if (cleanD == cleanTarget) {
              classId = d.id;
              studentCount = (d.data()['studentCount'] as num?)?.toInt() ??
                  (d.data()['totalStudents'] as num?)?.toInt() ??
                  0;
              break;
            }
          }
        }

        // If root document doesn't store a static counter, fetch real count
        if (classId.isNotEmpty && studentCount == 0) {
          try {
            final countSnap = await FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('classes')
                .doc(classId)
                .collection('students')
                .count()
                .get()
                .timeout(const Duration(seconds: 3));
            studentCount = countSnap.count ?? 0;
          } catch (_) {
            try {
              final stSnap = await FirebaseFirestore.instance
                  .collection('schools')
                  .doc(schoolId)
                  .collection('classes')
                  .doc(classId)
                  .collection('students')
                  .get(const GetOptions(source: Source.cache));
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

      // Save to local cache
      final cacheData = result.map((e) => {
        'classId': e.classId,
        'className': e.className,
        'subjects': e.subjects,
        'studentCount': e.studentCount,
      }).toList();
      await LocalDbService.saveCache(cacheKey, cacheData);

      yield result;
    }
  } catch (e) {
    debugPrint('teacherExamClassesProvider stream setup error: $e');
  }
});

// 2. Fetch Active Exams list for the School (OFFLINE RESILIENT)
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

  final cacheKey = 'school_exams_$schoolId';
  final cached = LocalDbService.getCache(cacheKey);
  if (cached is List && cached.isNotEmpty) {
    try {
      final cachedExams = cached.map((e) => ExamModel(
        id: (e['id'] ?? '').toString(),
        title: (e['title'] ?? '').toString(),
        session: (e['session'] ?? '').toString(),
        status: (e['status'] ?? 'active').toString(),
        isLocked: (e['isLocked'] == true) || (e['status'] == 'completed') || (e['status'] == 'archived'),
        defaultTotalMarks: (e['defaultTotalMarks'] as num?)?.toInt() ?? 100,
        passingMarks: (e['passingMarks'] as num?)?.toInt() ?? 33,
      )).toList();
      yield cachedExams;
    } catch (_) {}
  }

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
      final list = snapshot.docs.map((doc) {
        return ExamModel.fromFirestore(doc.id, doc.data());
      }).toList();
      // Cache exams
      LocalDbService.saveCache(cacheKey, list.map((e) => {
        'id': e.id,
        'title': e.title,
        'session': e.session,
        'status': e.status,
        'isLocked': e.isLocked,
        'defaultTotalMarks': e.defaultTotalMarks,
        'passingMarks': e.passingMarks,
      }).toList());
      return list;
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

// 4. Fetch Students and Existing Marks for a Class + Exam + Subject (OFFLINE RESILIENT LIVE STREAM)
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

  // 1. Resolve Class ID by using passed query.classId or exact matching
  String targetClassId = query.classId.trim();

  // If query.classId is empty, fallback to exact class name lookup (NEVER use partial .contains())
  if (targetClassId.isEmpty) {
    try {
      final classesSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 3));

      final cleanQueryName = query.className.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

      for (final cDoc in classesSnap.docs) {
        final cData = cDoc.data();
        final cName = (cData['name'] ?? '').toString().trim();
        final cleanCName = cName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
        final cleanDocId = cDoc.id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

        // STRICT EXACT MATCH ONLY - prevents Class 10/1A from hijacking Class 1
        if (cleanCName == cleanQueryName || cleanDocId == cleanQueryName) {
          targetClassId = cDoc.id;
          break;
        }
      }
    } catch (e) {
      debugPrint('Error resolving target class ID: $e');
    }
  }

  final marksDocId = '${query.examId}_${query.subject}'.replaceAll('/', '_').replaceAll(' ', '_');
  final marksCacheKey = 'exam_marks_${schoolId}_${targetClassId}_$marksDocId';
  final studentsCacheKey = 'students_${schoolId}_$targetClassId';

  // Check pending offline queue for any unsynced marks
  final pendingMarks = SyncQueueService.getPendingMarksFor(
    schoolId: schoolId,
    classId: targetClassId,
    examId: query.examId,
    subject: query.subject,
  );

  // 1. Immediately yield from local cache if available (Offline-First)
  final cachedStudents = LocalDbService.getCache(studentsCacheKey);
  final cachedMarks = LocalDbService.getCache(marksCacheKey);

  if (cachedStudents is List && cachedStudents.isNotEmpty) {
    Map<String, dynamic> marksMap = {};
    int totalMarks = 100;
    int passingMarks = 33;
    bool isAlreadySubmitted = false;

    if (pendingMarks != null && pendingMarks['marksData'] != null) {
      marksMap = Map<String, dynamic>.from(pendingMarks['marksData']);
      totalMarks = (pendingMarks['totalMarks'] as num?)?.toInt() ?? 100;
      passingMarks = (pendingMarks['passingMarks'] as num?)?.toInt() ?? 33;
      isAlreadySubmitted = true;
    } else if (cachedMarks is Map) {
      marksMap = Map<String, dynamic>.from(cachedMarks['marks'] ?? {});
      totalMarks = (cachedMarks['totalMarks'] as num?)?.toInt() ?? 100;
      passingMarks = (cachedMarks['passingMarks'] as num?)?.toInt() ?? 33;
      isAlreadySubmitted = cachedMarks['isAlreadySubmitted'] ?? (marksMap.isNotEmpty);
    }

    final List<StudentMarksEntry> entries = [];
    for (var sRaw in cachedStudents) {
      if (sRaw is! Map) continue;
      final studentId = (sRaw['id'] ?? sRaw['studentId'] ?? '').toString();
      final studentName = (sRaw['name'] ?? sRaw['fullName'] ?? 'Student').toString();
      final rollNo = (sRaw['rollNo'] ?? sRaw['rollNumber'] ?? '').toString();
      final photoUrl = (sRaw['photoUrl'] ?? sRaw['image'] ?? '').toString();

      final mark = marksMap[studentId] as Map<String, dynamic>?;
      double? obtained;
      bool isAbsent = false;
      String remarks = '';

      if (mark != null) {
        if (mark['isAbsent'] == true) {
          isAbsent = true;
        } else if (mark['obtainedMarks'] != null) {
          obtained = (mark['obtainedMarks'] as num).toDouble();
        }
        remarks = (mark['remarks'] ?? '').toString();
      }

      entries.add(StudentMarksEntry(
        studentId: studentId,
        studentName: studentName,
        rollNumber: rollNo,
        photoUrl: photoUrl,
        obtainedMarks: obtained,
        isAbsent: isAbsent,
        remarks: remarks,
      ));
    }

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
      'isOfflineCache': true,
    };
  }

  // 2. Stream the students subcollection live
  try {
    final studentsStream = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(targetClassId)
        .collection('students')
        .snapshots()
        .handleError((e) {
          debugPrint('Students stream error suppressed: $e');
        });

    await for (final snapshot in studentsStream) {
      // Also fetch existing marks
      Map<String, dynamic> marksMap = {};
      int totalMarks = 100;
      int passingMarks = 33;
      bool isAlreadySubmitted = false;

      // Overlay pending queue if any
      final currentPending = SyncQueueService.getPendingMarksFor(
        schoolId: schoolId,
        classId: targetClassId,
        examId: query.examId,
        subject: query.subject,
      );

      if (currentPending != null && currentPending['marksData'] != null) {
        marksMap = Map<String, dynamic>.from(currentPending['marksData']);
        totalMarks = (currentPending['totalMarks'] as num?)?.toInt() ?? 100;
        passingMarks = (currentPending['passingMarks'] as num?)?.toInt() ?? 33;
        isAlreadySubmitted = true;
      } else {
        try {
          final marksDocSnapshot = await FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('classes')
              .doc(targetClassId)
              .collection('exam_marks')
              .doc(marksDocId)
              .get(const GetOptions(source: Source.serverAndCache))
              .timeout(const Duration(seconds: 3));

          if (marksDocSnapshot.exists && marksDocSnapshot.data() != null) {
            final existingMarksData = marksDocSnapshot.data()!;
            marksMap = (existingMarksData['marks'] as Map<String, dynamic>?) ?? {};
            totalMarks = (existingMarksData['totalMarks'] as num?)?.toInt() ?? 100;
            passingMarks = (existingMarksData['passingMarks'] as num?)?.toInt() ?? 33;
            isAlreadySubmitted = true;
          }
        } catch (_) {}
      }

      final List<StudentMarksEntry> entries = [];
      final List<Map<String, dynamic>> studentsForCache = [];

      for (final doc in snapshot.docs) {
        final sData = doc.data();
        final studentId = doc.id;
        final firstName = (sData['firstName'] ?? '').toString().trim();
        final lastName = (sData['lastName'] ?? '').toString().trim();
        final combinedName = firstName.isNotEmpty ? '$firstName $lastName'.trim() : '';
        final studentName = (sData['name'] ?? sData['fullName'] ?? combinedName).toString().trim();
        final rollNo = (sData['rollNo'] ?? sData['rollNumber'] ?? '').toString().trim();
        final photoUrl = (sData['photoUrl'] ?? sData['avatar'] ?? sData['profilePic'] ?? sData['image'] ?? '').toString();

        studentsForCache.add({
          'id': studentId,
          'name': studentName.isNotEmpty ? studentName : 'Student',
          'rollNo': rollNo,
          'photoUrl': photoUrl,
        });

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

      // Save to local DB cache
      await LocalDbService.saveCache(studentsCacheKey, studentsForCache);
      await LocalDbService.saveCache(marksCacheKey, {
        'marks': marksMap,
        'totalMarks': totalMarks,
        'passingMarks': passingMarks,
        'isAlreadySubmitted': isAlreadySubmitted,
      });

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
        'isOfflineCache': false,
      };
    }
  } catch (e) {
    debugPrint('examMarksSheetProvider stream error: $e');
  }
});

// 5. StateNotifier for Saving Marks (WITH COMPLETE OFFLINE & AUTO-SYNC QUEUE)
class MarksSaveState {
  final bool isLoading;
  final bool isSuccess;
  final bool isOffline;
  final String? message;
  final String? error;

  MarksSaveState({
    this.isLoading = false,
    this.isSuccess = false,
    this.isOffline = false,
    this.message,
    this.error,
  });
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

    // 1. Immediately update Local Hive Cache so UI displays latest marks offline instantly
    final marksCacheKey = 'exam_marks_${schoolId}_${classId}_$marksDocId';
    await LocalDbService.saveCache(marksCacheKey, {
      'marks': marksData,
      'totalMarks': totalMarks,
      'passingMarks': passingMarks,
      'isAlreadySubmitted': true,
    });

    final bool online = await SyncQueueService.isOnline();

    if (online) {
      try {
        final batch = FirebaseFirestore.instance.batch();

        // Save to Class Exam Marks Collection
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

        // Also merge into each student's exam_results subcollection
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

        await batch.commit().timeout(const Duration(seconds: 6));
        state = MarksSaveState(
          isSuccess: true,
          isOffline: false,
          message: "Marks for $subject saved to cloud successfully!",
        );
        return true;
      } catch (e) {
        debugPrint('Online marks commit failed, queuing offline: $e');
        // Network timeout/failure fallback to Sync Queue
        await SyncQueueService.enqueue(
          type: 'exam_marks_save',
          payload: {
            'schoolId': schoolId,
            'classId': classId,
            'className': className,
            'examId': examId,
            'examTitle': examTitle,
            'subject': subject,
            'teacherId': teacherId,
            'teacherName': teacherName,
            'totalMarks': totalMarks,
            'passingMarks': passingMarks,
            'marksData': marksData,
          },
        );

        state = MarksSaveState(
          isSuccess: true,
          isOffline: true,
          message: "⚡ Marks saved offline! Will auto-sync when online.",
        );
        return true;
      }
    } else {
      // Direct offline queue
      await SyncQueueService.enqueue(
        type: 'exam_marks_save',
        payload: {
          'schoolId': schoolId,
          'classId': classId,
          'className': className,
          'examId': examId,
          'examTitle': examTitle,
          'subject': subject,
          'teacherId': teacherId,
          'teacherName': teacherName,
          'totalMarks': totalMarks,
          'passingMarks': passingMarks,
          'marksData': marksData,
        },
      );

      state = MarksSaveState(
        isSuccess: true,
        isOffline: true,
        message: "⚡ Marks saved offline! Will auto-sync when online.",
      );
      return true;
    }
  }

  void reset() {
    state = MarksSaveState();
  }
}

final marksSaveProvider =
    StateNotifierProvider<MarksSaveNotifier, MarksSaveState>((ref) => MarksSaveNotifier());
