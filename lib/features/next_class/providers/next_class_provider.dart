import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';

import 'package:flutter/material.dart';
import 'dart:async';

enum NextClassViewMode { classes, subjects, students, scheduleTest, test, activeTestScore }

class ScheduleTestDraft {
  final DateTime? date;
  final TimeOfDay? time;
  final String paragraphs;
  final String type;
  final int maxMarks;
  final String chapter;

  ScheduleTestDraft({
    this.date,
    this.time,
    this.paragraphs = '',
    this.type = 'Written',
    this.maxMarks = 10,
    this.chapter = '',
  });

  ScheduleTestDraft copyWith({
    DateTime? date,
    TimeOfDay? time,
    String? paragraphs,
    String? type,
    int? maxMarks,
    String? chapter,
    bool clearDate = false,
    bool clearTime = false,
  }) {
    return ScheduleTestDraft(
      date: clearDate ? null : (date ?? this.date),
      time: clearTime ? null : (time ?? this.time),
      paragraphs: paragraphs ?? this.paragraphs,
      type: type ?? this.type,
      maxMarks: maxMarks ?? this.maxMarks,
      chapter: chapter ?? this.chapter,
    );
  }
}

class NextClassState {
  final NextClassViewMode viewMode;
  final Map<String, dynamic>? selectedClass;
  final String? selectedSubject;
  final List<Map<String, dynamic>> classes;
  final List<Map<String, dynamic>> students;
  final bool isLoading;
  final bool isSaving;
  final String searchTerm;
  
  // Maps studentId to a map of { 'academic': score, 'homework': score }
  final Map<String, Map<String, int>> scoreUpdates;
  
  // Maps studentId to test score
  final Map<String, int> testScores;

  // Schedule Test Drafts per subject
  final Map<String, ScheduleTestDraft> scheduleDrafts;

  // Getters for UI backward compatibility
  DateTime? get scheduleDate => selectedSubject != null ? scheduleDrafts[selectedSubject!]?.date : null;
  TimeOfDay? get scheduleTime => selectedSubject != null ? scheduleDrafts[selectedSubject!]?.time : null;
  String get scheduleParagraphs => selectedSubject != null ? (scheduleDrafts[selectedSubject!]?.paragraphs ?? '') : '';
  String get testType => selectedSubject != null ? (scheduleDrafts[selectedSubject!]?.type ?? 'Written') : 'Written';
  int get maxMarks => selectedSubject != null ? (scheduleDrafts[selectedSubject!]?.maxMarks ?? 10) : 10;
  String get testChapter => selectedSubject != null ? (scheduleDrafts[selectedSubject!]?.chapter ?? '') : '';

  final Map<String, dynamic>? activeScheduledTest;
  final bool isFetchingTest;

  NextClassState({
    this.viewMode = NextClassViewMode.classes,
    this.selectedClass,
    this.selectedSubject,
    this.classes = const [],
    this.students = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.searchTerm = '',
    this.scoreUpdates = const {},
    this.testScores = const {},
    this.scheduleDrafts = const {},
    this.activeScheduledTest,
    this.isFetchingTest = false,
  });

  NextClassState copyWith({
    NextClassViewMode? viewMode,
    Map<String, dynamic>? selectedClass,
    String? selectedSubject,
    List<Map<String, dynamic>>? classes,
    List<Map<String, dynamic>>? students,
    bool? isLoading,
    bool? isSaving,
    String? searchTerm,
    Map<String, Map<String, int>>? scoreUpdates,
    Map<String, int>? testScores,
    Map<String, ScheduleTestDraft>? scheduleDrafts,
    Map<String, dynamic>? activeScheduledTest,
    bool? isFetchingTest,
  }) {
    return NextClassState(
      viewMode: viewMode ?? this.viewMode,
      selectedClass: selectedClass ?? this.selectedClass,
      selectedSubject: selectedSubject ?? this.selectedSubject,
      classes: classes ?? this.classes,
      students: students ?? this.students,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      searchTerm: searchTerm ?? this.searchTerm,
      scoreUpdates: scoreUpdates ?? this.scoreUpdates,
      testScores: testScores ?? this.testScores,
      scheduleDrafts: scheduleDrafts ?? this.scheduleDrafts,
      activeScheduledTest: activeScheduledTest ?? this.activeScheduledTest,
      isFetchingTest: isFetchingTest ?? this.isFetchingTest,
    );
  }
}

class NextClassNotifier extends StateNotifier<NextClassState> {
  final Ref ref;
  final String? schoolId;

  StreamSubscription<QuerySnapshot>? _classesSubscription;
  StreamSubscription<QuerySnapshot>? _studentsSubscription;
  StreamSubscription<QuerySnapshot>? _scheduledTestSubscription;

  NextClassNotifier(this.ref, this.schoolId) : super(NextClassState()) {
    if (schoolId != null) {
      _fetchClasses();
    }
  }

  @override
  void dispose() {
    _classesSubscription?.cancel();
    _studentsSubscription?.cancel();
    _scheduledTestSubscription?.cancel();
    super.dispose();
  }

  void _fetchClasses() {
    if (schoolId == null) return;
    
    state = state.copyWith(isLoading: true);
    
    _classesSubscription?.cancel();
    _classesSubscription = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .snapshots()
        .listen((snapshot) {
      final classesData = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();

      // Sort classes numerically/alphabetically
      int getClassOrder(String? name) {
        if (name == null) return 0;
        final lowerName = name.toLowerCase();
        if (lowerName.contains('nursery')) return -2;
        if (lowerName.contains('prep')) return -1;
        final match = RegExp(r'\d+').firstMatch(name);
        return match != null ? int.parse(match.group(0)!) : 0;
      }

      classesData.sort((a, b) => getClassOrder(a['name'] as String?) - getClassOrder(b['name'] as String?));

      if (mounted) {
        state = state.copyWith(classes: classesData, isLoading: false);
      }
    }, onError: (e) {
      if (mounted) {
        state = state.copyWith(isLoading: false);
      }
    });
  }

  void selectClass(Map<String, dynamic> cls) {
    state = state.copyWith(
      selectedClass: cls,
      viewMode: NextClassViewMode.subjects,
      selectedSubject: null,
      students: [],
      scoreUpdates: {},
      testScores: {},
    );
  }

  void selectSubject(String subject) {
    state = state.copyWith(
      selectedSubject: subject,
      viewMode: NextClassViewMode.students,
      scoreUpdates: {},
      testScores: {},
      activeScheduledTest: {},
    );
    _fetchStudents();
    _fetchScheduledTest();
  }

  void _fetchScheduledTest() {
    if (schoolId == null || state.selectedClass == null || state.selectedSubject == null) return;
    final classId = state.selectedClass!['id'];
    state = state.copyWith(isFetchingTest: true);

    _scheduledTestSubscription?.cancel();
    _scheduledTestSubscription = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('scheduled_tests')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        final validDocs = snapshot.docs.where((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          return data['subject'] == state.selectedSubject && data['status'] == 'scheduled';
        }).toList();

        if (validDocs.isNotEmpty) {
          // Sort by createdAt descending to always pick the newest test if duplicates exist
          validDocs.sort((a, b) {
            final aData = Map<String, dynamic>.from(a.data());
            final bData = Map<String, dynamic>.from(b.data());
            final aTime = aData['createdAt'];
            final bTime = bData['createdAt'];
            if (aTime == null || bTime == null) return 0;
            // Handle Timestamp
            if (aTime is Timestamp && bTime is Timestamp) {
              return bTime.compareTo(aTime);
            }
            return 0;
          });

          final data = Map<String, dynamic>.from(validDocs.first.data());
          data['id'] = validDocs.first.id;
          state = state.copyWith(activeScheduledTest: data, isFetchingTest: false);
        } else {
          state = state.copyWith(activeScheduledTest: {}, isFetchingTest: false);
        }
      }
    }, onError: (e) {
      if (mounted) state = state.copyWith(isFetchingTest: false);
    });
  }

  void _fetchStudents() {
    if (schoolId == null || state.selectedClass == null) return;

    final classId = state.selectedClass!['id'];

    state = state.copyWith(isLoading: true);

    _studentsSubscription?.cancel();
    _studentsSubscription = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('students')
        .snapshots()
        .listen((snapshot) {
      final studentsData = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        return data;
      }).toList();

      studentsData.sort((a, b) {
        final rollA = a['rollNo']?.toString() ?? '0';
        final rollB = b['rollNo']?.toString() ?? '0';
        return rollA.compareTo(rollB);
      });

      if (mounted) {
        state = state.copyWith(
          students: studentsData,
          isLoading: false,
          scoreUpdates: {}, // clear updates when data refreshes to prevent staleness
        );
      }
    }, onError: (e) {
      if (mounted) {
        state = state.copyWith(isLoading: false);
      }
    });
  }

  void goBack() {
    if (state.viewMode == NextClassViewMode.test || state.viewMode == NextClassViewMode.activeTestScore) {
      state = state.copyWith(viewMode: NextClassViewMode.scheduleTest);
    } else if (state.viewMode == NextClassViewMode.scheduleTest) {
      state = state.copyWith(viewMode: NextClassViewMode.students);
    } else if (state.viewMode == NextClassViewMode.students) {
      state = state.copyWith(
        viewMode: NextClassViewMode.subjects,
        selectedSubject: null,
        scoreUpdates: {},
      );
    } else if (state.viewMode == NextClassViewMode.subjects) {
      state = state.copyWith(
        viewMode: NextClassViewMode.classes,
        selectedClass: null,
      );
    }
  }

  void goToTestMode() {
    state = state.copyWith(viewMode: NextClassViewMode.test);
  }

  void goToScheduleTestMode() {
    state = state.copyWith(viewMode: NextClassViewMode.scheduleTest);
  }

  void goToActiveTestScoreMode() {
    state = state.copyWith(
      viewMode: NextClassViewMode.activeTestScore,
      testScores: {}, // Reset test scores when entering
    );
  }

  void setSearchTerm(String term) {
    state = state.copyWith(searchTerm: term);
  }

  ScheduleTestDraft get _currentDraft => state.selectedSubject != null 
      ? (state.scheduleDrafts[state.selectedSubject!] ?? ScheduleTestDraft())
      : ScheduleTestDraft();

  void _updateDraft(ScheduleTestDraft newDraft) {
    if (state.selectedSubject == null) return;
    final newDrafts = Map<String, ScheduleTestDraft>.from(state.scheduleDrafts);
    newDrafts[state.selectedSubject!] = newDraft;
    state = state.copyWith(scheduleDrafts: newDrafts);
  }

  void setTestChapter(String chapter) {
    _updateDraft(_currentDraft.copyWith(chapter: chapter));
  }

  void setScheduleDate(DateTime date) {
    _updateDraft(_currentDraft.copyWith(date: date));
  }

  void setScheduleTime(TimeOfDay time) {
    _updateDraft(_currentDraft.copyWith(time: time));
  }

  void setScheduleParagraphs(String paragraphs) {
    _updateDraft(_currentDraft.copyWith(paragraphs: paragraphs));
  }

  void setTestType(String type) {
    _updateDraft(_currentDraft.copyWith(type: type));
  }

  void setMaxMarks(int marks) {
    _updateDraft(_currentDraft.copyWith(maxMarks: marks));
  }

  Future<void> saveScheduledTest() async {
    if (state.isSaving) return;
    if (schoolId == null || state.selectedClass == null || state.selectedSubject == null) return;
    
    state = state.copyWith(isSaving: true);

    try {
      final classId = state.selectedClass!['id'];
      
      final scheduleDateTime = DateTime(
        state.scheduleDate!.year,
        state.scheduleDate!.month,
        state.scheduleDate!.day,
        state.scheduleTime!.hour,
        state.scheduleTime!.minute,
      );
      final isoDate = scheduleDateTime.toIso8601String();
      
      final dateStr = state.scheduleDate != null ? "${state.scheduleDate!.year}-${state.scheduleDate!.month.toString().padLeft(2, '0')}-${state.scheduleDate!.day.toString().padLeft(2, '0')}" : "TBD";
      final timeStr = state.scheduleTime != null ? "${state.scheduleTime!.hour.toString().padLeft(2, '0')}:${state.scheduleTime!.minute.toString().padLeft(2, '0')}" : "TBD";
      
      final testMessage = 'A ${state.testType} test has been scheduled for ${state.selectedSubject}.\nChapter: ${state.testChapter}\nTopic: ${state.scheduleParagraphs}\nDate: $dateStr at $timeStr\nMax Marks: ${state.maxMarks}';

      final testData = {
        'subject': state.selectedSubject,
        'chapter': state.testChapter,
        'paragraphs': state.scheduleParagraphs,
        'dateStr': dateStr,
        'timeStr': timeStr,
        'isoDate': isoDate,
        'maxMarks': state.maxMarks,
        'testType': state.testType,
        'status': 'scheduled',
        'createdAt': FieldValue.serverTimestamp(),
      };

      final testRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .doc(classId)
          .collection('scheduled_tests')
          .doc();

      final localTestState = Map<String, dynamic>.from(testData);
      localTestState['id'] = testRef.id;

      final newDrafts = Map<String, ScheduleTestDraft>.from(state.scheduleDrafts);
      newDrafts.remove(state.selectedSubject);

      // FAST OPTIMISTIC UI UPDATE
      state = state.copyWith(
        isSaving: false,
        activeScheduledTest: localTestState,
        scheduleDrafts: newDrafts,
      );

      // ASYNCHRONOUS BACKGROUND SAVE (TEST FIRST, THEN ALERTS)
      testRef.set(testData).then((_) {
        try {
          final batch = FirebaseFirestore.instance.batch();
          final processedParents = <String>{};
          for (var student in state.students) {
            String? parentId;
            if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
              parentId = student['parentDetails']['parentId'];
            }
            if (parentId != null && !processedParents.contains(parentId)) {
              processedParents.add(parentId);
              final alertRef = FirebaseFirestore.instance
                  .collection('schools')
                  .doc(schoolId)
                  .collection('notifications')
                  .doc();
              batch.set(alertRef, {
                'parentId': parentId,
                'studentId': student['id'],
                'studentName': student['name'] ?? 'Student',
                'title': 'Test Scheduled: ${state.selectedSubject}',
                'message': testMessage,
                'type': 'academic',
                'read': false,
                'className': state.selectedClass?['name'] ?? '',
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
          }
          batch.commit().catchError((e) => print("Error sending parent alerts: $e"));
        } catch (e) {
          print("Error preparing alerts batch: $e");
        }
      }).catchError((e) {
        print("Error saving scheduled test to Firebase: $e");
      });

    } catch (e) {
      print("Error processing scheduled test locally: $e");
      state = state.copyWith(isSaving: false);
    }
  }

  Future<void> cancelScheduledTest() async {
    if (state.isSaving) return;
    if (schoolId == null || state.selectedClass == null || state.activeScheduledTest == null || state.activeScheduledTest!.isEmpty) return;
    
    final classId = state.selectedClass!['id'];
    final testId = state.activeScheduledTest!['id'];
    final testType = state.activeScheduledTest!['testType'] ?? 'Written';

    // OPTIMISTIC UI UPDATE: Instantly route to form
    state = state.copyWith(isSaving: false, activeScheduledTest: {}, viewMode: NextClassViewMode.scheduleTest);

    try {
      final testMessage = 'The $testType test for ${state.selectedSubject} has been cancelled and will be scheduled in the future.';

      final testRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .doc(classId)
          .collection('scheduled_tests')
          .doc(testId);
          
      // Delete the test independently first
      await testRef.delete();

      // Run alerts in a separate background try-catch to prevent permission failures
      try {
        final batch = FirebaseFirestore.instance.batch();
        final processedParents = <String>{};
        for (var student in state.students) {
          String? parentId;
          if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
            parentId = student['parentDetails']['parentId'];
          }
          if (parentId != null && !processedParents.contains(parentId)) {
            processedParents.add(parentId);
            final alertRef = FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('notifications')
                .doc();
            batch.set(alertRef, {
              'parentId': parentId,
              'studentId': student['id'],
              'studentName': student['name'] ?? 'Student',
              'title': 'Test Cancelled: ${state.selectedSubject}',
              'message': testMessage,
              'type': 'academic',
              'read': false,
              'className': state.selectedClass?['name'] ?? '',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }
        batch.commit().catchError((e) => print("Error sending cancel alerts: $e"));
      } catch (e) {
        print("Error preparing cancel alerts: $e");
      }
      
    } catch (e) {
      print("Error cancelling scheduled test: $e");
    }
  }

  Future<void> completeScheduledTest() async {
    if (state.isSaving) return;
    if (schoolId == null || state.selectedClass == null || state.activeScheduledTest == null || state.activeScheduledTest!.isEmpty) return;
    
    final classId = state.selectedClass!['id'];
    final testId = state.activeScheduledTest!['id'];

    // OPTIMISTIC UI UPDATE: Instantly route to form
    state = state.copyWith(isSaving: false, activeScheduledTest: {}, viewMode: NextClassViewMode.scheduleTest);

    try {
      final testRef = FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .doc(classId)
          .collection('scheduled_tests')
          .doc(testId);
          
      await testRef.update({'status': 'completed'});
    } catch (e) {
      print("Error completing scheduled test: $e");
    }
  }

  Future<void> saveActiveTestScores(String message) async {
    if (state.isSaving) return;
    if (schoolId == null || state.selectedClass == null || state.activeScheduledTest == null || state.activeScheduledTest!.isEmpty) return;
    
    state = state.copyWith(isSaving: true);

    try {
      final classId = state.selectedClass!['id'];
      final testId = state.activeScheduledTest!['id'];
      final batch = FirebaseFirestore.instance.batch();

      final testMessage = message.isNotEmpty ? message : 'The scores for the ${state.activeScheduledTest!['testType']} test in ${state.selectedSubject} have been published.';

      final processedParents = <String>{};

      for (var student in state.students) {
        final studentId = student['id'];

        String? parentId;
        if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
          parentId = student['parentDetails']['parentId'];
        }

        if (parentId != null && !processedParents.contains(parentId)) {
          processedParents.add(parentId);
          final alertRef = FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('notifications')
              .doc();
          batch.set(alertRef, {
            'parentId': parentId,
            'studentId': studentId,
            'studentName': student['name'] ?? 'Student',
            'title': 'Test Results: ${state.selectedSubject}',
            'message': testMessage,
            'type': 'academic',
            'read': false,
            'className': state.selectedClass?['name'] ?? '',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        // Save score if it was entered
        if (state.testScores.containsKey(studentId)) {
          final score = state.testScores[studentId]!;
          final studentRef = FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('classes')
              .doc(classId)
              .collection('students')
              .doc(studentId);

          // Assuming we add it to a generic testHistory array or just write a subcollection
          // We'll write to a 'testScores' subcollection to be safe and structured
          final scoreRef = studentRef.collection('testScores').doc(testId);
          batch.set(scoreRef, {
            'subject': state.selectedSubject,
            'testType': state.activeScheduledTest!['testType'],
            'score': score,
            'maxMarks': state.activeScheduledTest!['maxMarks'],
            'date': state.activeScheduledTest!['dateStr'],
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      await batch.commit();

      state = state.copyWith(
        isSaving: false,
        viewMode: NextClassViewMode.scheduleTest,
        testScores: {},
      );
    } catch (e) {
      print("Error saving active test scores: $e");
      state = state.copyWith(isSaving: false);
    }
  }

  // --- Scoring Logic ---

  int getStudentScore(Map<String, dynamic> student, String type) {
    final studentId = student['id'] as String;
    
    // Check local updates first
    if (state.scoreUpdates[studentId] != null && state.scoreUpdates[studentId]![type] != null) {
      return state.scoreUpdates[studentId]![type]!;
    }

    // Fallback to database
    final scoresArrayRaw = type == 'academic' ? student['academicScores'] : student['homeworkScores'];
    final scoresArray = List<dynamic>.from(scoresArrayRaw ?? []);
    
    final subjectScore = scoresArray.firstWhere(
      (s) => s['subject'] == state.selectedSubject,
      orElse: () { return <String, dynamic>{}; },
    );

    if (subjectScore is Map && subjectScore.isNotEmpty) {
      return int.tryParse(subjectScore['score'].toString()) ?? 0;
    }
    return 0;
  }

  void updateScore(String studentId, String type, int value) {
    final newUpdates = Map<String, Map<String, int>>.from(state.scoreUpdates);
    
    if (!newUpdates.containsKey(studentId)) {
      newUpdates[studentId] = {};
    }
    
    newUpdates[studentId]![type] = value;
    
    state = state.copyWith(scoreUpdates: newUpdates);
  }

  Future<void> saveAllScores() async {
    if (state.isSaving) return;
    if (state.scoreUpdates.isEmpty) return;
    
    if (schoolId == null || state.selectedClass == null) return;

    final classId = state.selectedClass!['id'];

    state = state.copyWith(isSaving: true);

    try {
      final batch = FirebaseFirestore.instance.batch();

      for (var entry in state.scoreUpdates.entries) {
        final studentId = entry.key;
        final updates = entry.value;

        // Find student in current list
        final student = state.students.firstWhere((s) => s['id'] == studentId, orElse: () { return <String, dynamic>{}; });
        if (student.isEmpty) continue;

        final studentRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId)
            .collection('students')
            .doc(studentId);

        List<dynamic> newAcademicScores = List<dynamic>.from(student['academicScores'] ?? []);
        List<dynamic> newHomeworkScores = List<dynamic>.from(student['homeworkScores'] ?? []);

        // Update Academic
        if (updates.containsKey('academic')) {
          final idx = newAcademicScores.indexWhere((s) => s['subject'] == state.selectedSubject);
          if (idx >= 0) {
            newAcademicScores[idx] = { ...newAcademicScores[idx], 'score': updates['academic'] };
          } else {
            newAcademicScores.add({ 'subject': state.selectedSubject, 'score': updates['academic'] });
          }
        }

        // Update Homework
        if (updates.containsKey('homework')) {
          final idx = newHomeworkScores.indexWhere((s) => s['subject'] == state.selectedSubject);
          if (idx >= 0) {
            newHomeworkScores[idx] = { ...newHomeworkScores[idx], 'score': updates['homework'] };
          } else {
            newHomeworkScores.add({ 'subject': state.selectedSubject, 'score': updates['homework'] });
          }
        }

        batch.update(studentRef, {
          'academicScores': newAcademicScores,
          'homeworkScores': newHomeworkScores,
        });
      }

      await batch.commit();
      
      // Clear updates after successful save
      state = state.copyWith(isSaving: false, scoreUpdates: {});
      
    } catch (e) {
      print("Error saving scores: $e");
      state = state.copyWith(isSaving: false);
      rethrow;
    }
  }

  // --- Test Mode Logic ---
  void updateTestScore(String studentId, int value) {
    final newTestScores = Map<String, int>.from(state.testScores);
    newTestScores[studentId] = value;
    state = state.copyWith(testScores: newTestScores);
  }

  void resetTestScores() {
    state = state.copyWith(testScores: {});
  }

}

final nextClassProvider = StateNotifierProvider.autoDispose<NextClassNotifier, NextClassState>((ref) {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final String? schoolId = teacherDataAsync.value?['schoolId'];
  return NextClassNotifier(ref, schoolId);
});
