import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';
import 'package:teacher_mobile_app/core/services/sync_queue_service.dart';
import 'package:uuid/uuid.dart';

enum NextClassViewMode { classes, subjects, students, scheduleTest, test, activeTestScore, homework }

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

class HomeworkDraft {
  final String chapter;
  final String topic;
  final String description;
  final DateTime? dueDate;

  HomeworkDraft({
    this.chapter = '',
    this.topic = '',
    this.description = '',
    this.dueDate,
  });

  HomeworkDraft copyWith({
    String? chapter,
    String? topic,
    String? description,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) {
    return HomeworkDraft(
      chapter: chapter ?? this.chapter,
      topic: topic ?? this.topic,
      description: description ?? this.description,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
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

  // Set of studentIds marked as absent for the active test
  final Set<String> absentTestStudents;

  // Schedule Test Drafts per subject
  final Map<String, ScheduleTestDraft> scheduleDrafts;

  // Homework Drafts per subject
  final Map<String, HomeworkDraft> homeworkDrafts;

  // Getters for UI backward compatibility
  DateTime? get scheduleDate => selectedSubject != null ? scheduleDrafts[selectedSubject!]?.date : null;
  TimeOfDay? get scheduleTime => selectedSubject != null ? scheduleDrafts[selectedSubject!]?.time : null;
  String get scheduleParagraphs => selectedSubject != null ? (scheduleDrafts[selectedSubject!]?.paragraphs ?? '') : '';
  String get testType => selectedSubject != null ? (scheduleDrafts[selectedSubject!]?.type ?? 'Written') : 'Written';
  int get maxMarks => selectedSubject != null ? (scheduleDrafts[selectedSubject!]?.maxMarks ?? 10) : 10;
  String get testChapter => selectedSubject != null ? (scheduleDrafts[selectedSubject!]?.chapter ?? '') : '';

  // Homework getters
  String get homeworkChapter => selectedSubject != null ? (homeworkDrafts[selectedSubject!]?.chapter ?? '') : '';
  String get homeworkTopic => selectedSubject != null ? (homeworkDrafts[selectedSubject!]?.topic ?? '') : '';
  String get homeworkDescription => selectedSubject != null ? (homeworkDrafts[selectedSubject!]?.description ?? '') : '';
  DateTime? get homeworkDueDate => selectedSubject != null ? homeworkDrafts[selectedSubject!]?.dueDate : null;

  final Map<String, dynamic>? activeScheduledTest;
    final List<Map<String, dynamic>> testReportsList;
  final int testReportsPageIndex;
  final bool isFetchingTest;

  final Map<String, dynamic>? activeHomework;
  final List<Map<String, dynamic>> homeworkList;
  final bool isFetchingHomework;

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
    this.absentTestStudents = const {},
    this.scheduleDrafts = const {},
    this.homeworkDrafts = const {},
    this.activeScheduledTest,
    this.testReportsList = const [],
    this.testReportsPageIndex = 0,
    this.isFetchingTest = false,
    this.activeHomework,
    this.homeworkList = const [],
    this.isFetchingHomework = false,
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
    Set<String>? absentTestStudents,
    Map<String, ScheduleTestDraft>? scheduleDrafts,
    Map<String, HomeworkDraft>? homeworkDrafts,
    Map<String, dynamic>? activeScheduledTest,
    List<Map<String, dynamic>>? testReportsList,
    int? testReportsPageIndex,
    bool? isFetchingTest,
    Map<String, dynamic>? activeHomework,
    List<Map<String, dynamic>>? homeworkList,
    bool? isFetchingHomework,
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
      absentTestStudents: absentTestStudents ?? this.absentTestStudents,
      scheduleDrafts: scheduleDrafts ?? this.scheduleDrafts,
      homeworkDrafts: homeworkDrafts ?? this.homeworkDrafts,
      activeScheduledTest: activeScheduledTest ?? this.activeScheduledTest,
      testReportsList: testReportsList ?? this.testReportsList,
      testReportsPageIndex: testReportsPageIndex ?? this.testReportsPageIndex,
      isFetchingTest: isFetchingTest ?? this.isFetchingTest,
      activeHomework: activeHomework ?? this.activeHomework,
      homeworkList: homeworkList ?? this.homeworkList,
      isFetchingHomework: isFetchingHomework ?? this.isFetchingHomework,
    );
  }
}

class NextClassNotifier extends StateNotifier<NextClassState> {
  final Ref ref;
  final String? schoolId;

  StreamSubscription<QuerySnapshot>? _classesSubscription;
  StreamSubscription<QuerySnapshot>? _studentsSubscription;
  StreamSubscription<QuerySnapshot>? _scheduledTestSubscription;
  StreamSubscription<QuerySnapshot>? _homeworkSubscription;

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
    _homeworkSubscription?.cancel();
    super.dispose();
  }

  void _fetchClasses() {
    if (schoolId == null) return;
    
    // 1. Instant offline retrieval from LocalDbService
    final cachedClasses = LocalDbService.getCache('classes_$schoolId');
    if (cachedClasses is List && cachedClasses.isNotEmpty) {
      final list = cachedClasses.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      state = state.copyWith(classes: list, isLoading: false);
    } else {
      state = state.copyWith(isLoading: true);
    }
    
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

      // Cache classes locally
      LocalDbService.saveCache('classes_$schoolId', classesData);

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
    final classId = state.selectedClass?['id'];
    
    // Check local caches for instant offline UI
    List<Map<String, dynamic>> cachedStudents = [];
    Map<String, dynamic> cachedActiveTest = {};
    List<Map<String, dynamic>> cachedHwList = [];
    Map<String, dynamic> cachedActiveHw = {};

    if (schoolId != null && classId != null) {
      final studentsRaw = LocalDbService.getCache('students_${schoolId}_$classId');
      if (studentsRaw is List) {
        cachedStudents = studentsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      final testRaw = LocalDbService.getCache('scheduled_test_${schoolId}_${classId}_$subject');
      if (testRaw is Map) {
        cachedActiveTest = Map<String, dynamic>.from(testRaw);
      }

      final hwRaw = LocalDbService.getCache('homework_${schoolId}_${classId}_$subject');
      if (hwRaw is Map) {
        if (hwRaw['list'] is List) {
          cachedHwList = (hwRaw['list'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
        if (hwRaw['active'] is Map) {
          cachedActiveHw = Map<String, dynamic>.from(hwRaw['active'] as Map);
        }
      }

      // Merge pending SyncQueue items for instant offline display
      final pendingHw = SyncQueueService.getPendingHomeworkFor(
        schoolId: schoolId!,
        classId: classId,
        subject: subject,
      );
      for (var ph in pendingHw) {
        final existingIdx = cachedHwList.indexWhere((h) => h['id'] == ph['id']);
        if (existingIdx >= 0) {
          cachedHwList[existingIdx] = ph;
        } else {
          cachedHwList.insert(0, ph);
        }
        if (ph['status'] == 'active' || cachedActiveHw.isEmpty) {
          cachedActiveHw = ph;
        }
      }

      final pendingTest = SyncQueueService.getPendingScheduledTestFor(
        schoolId: schoolId!,
        classId: classId,
        subject: subject,
      );
      if (pendingTest != null && pendingTest.isNotEmpty) {
        cachedActiveTest = pendingTest;
      }
    }

    state = state.copyWith(
      selectedSubject: subject,
      viewMode: NextClassViewMode.students,
      scoreUpdates: {},
      testScores: {},
      students: cachedStudents.isNotEmpty ? cachedStudents : state.students,
      activeScheduledTest: cachedActiveTest,
      activeHomework: cachedActiveHw,
      homeworkList: cachedHwList,
    );

    _fetchStudents();
    _fetchScheduledTest();
    _fetchHomework();
    SyncQueueService.processQueue();
  }

  void _fetchHomework() {
    if (schoolId == null || state.selectedClass == null || state.selectedSubject == null) return;
    final classId = state.selectedClass!['id'];
    final subject = state.selectedSubject!;

    if (state.homeworkList.isEmpty) {
      state = state.copyWith(isFetchingHomework: true);
    }

    SyncQueueService.processQueue();

    _homeworkSubscription?.cancel();
    _homeworkSubscription = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('homework')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        final docs = snapshot.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          data['isPendingSync'] = false;
          return data;
        }).where((data) => data['subject'] == subject).toList();

        // Merge pending offline queue items so they are never erased by snapshot
        final pendingHw = SyncQueueService.getPendingHomeworkFor(
          schoolId: schoolId!,
          classId: classId,
          subject: subject,
        );
        for (var ph in pendingHw) {
          final idx = docs.indexWhere((h) => h['id'] == ph['id']);
          if (idx >= 0) {
            // Already synced to Firestore -> Clean from queue
            SyncQueueService.removePendingHomework(ph['id'].toString());
          } else {
            docs.insert(0, ph);
          }
        }

        // Sort descending by createdAt / updatedAt / assignedDate
        docs.sort((a, b) {
          final aTime = a['createdAt'] ?? a['updatedAt'];
          final bTime = b['createdAt'] ?? b['updatedAt'];
          if (aTime is Timestamp && bTime is Timestamp) {
            return bTime.compareTo(aTime);
          }
          final aDate = (a['assignedDate'] ?? '').toString();
          final bDate = (b['assignedDate'] ?? '').toString();
          return bDate.compareTo(aDate);
        });

        Map<String, dynamic>? active;
        final activeMatches = docs.where((h) => h['status'] == 'active').toList();
        if (activeMatches.isNotEmpty) {
          active = activeMatches.first;
        } else if (docs.isNotEmpty) {
          active = docs.first;
        }

        // Cache homework locally
        LocalDbService.saveCache('homework_${schoolId}_${classId}_$subject', {
          'list': docs,
          'active': active ?? {},
        });

        state = state.copyWith(
          homeworkList: docs,
          activeHomework: active ?? {},
          isFetchingHomework: false,
        );
      }
    }, onError: (e) {
      if (mounted) state = state.copyWith(isFetchingHomework: false);
    });
  }

  void _fetchScheduledTest() {
    if (schoolId == null || state.selectedClass == null || state.selectedSubject == null) return;
    final classId = state.selectedClass!['id'];
    final subject = state.selectedSubject!;

    // 1. Instant offline cache restore
    final cachedActive = LocalDbService.getCache('scheduled_test_${schoolId}_${classId}_$subject');
    final cachedReports = LocalDbService.getCache('test_reports_${schoolId}_${classId}_$subject');
    if (cachedActive is Map || cachedReports is List) {
      state = state.copyWith(
        activeScheduledTest: cachedActive is Map ? Map<String, dynamic>.from(cachedActive) : null,
        testReportsList: cachedReports is List ? cachedReports.map((e) => Map<String, dynamic>.from(e as Map)).toList() : null,
      );
    }

    if (state.activeScheduledTest == null || state.activeScheduledTest!.isEmpty) {
      state = state.copyWith(isFetchingTest: true);
    }

    SyncQueueService.processQueue();

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
        final allDocs = snapshot.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          return data;
        }).where((doc) => doc['subject'] == subject).toList();

        // 1. Scheduled / Active test matches
        final validScheduled = allDocs.where((doc) => doc['status'] == 'scheduled').toList();
        validScheduled.sort((a, b) {
          final aTime = a['createdAt'];
          final bTime = b['createdAt'];
          if (aTime is Timestamp && bTime is Timestamp) return bTime.compareTo(aTime);
          return 0;
        });

        // 2. Completed tests (History & Reports)
        final completedDocs = allDocs.where((doc) => doc['status'] == 'completed').toList();
        completedDocs.sort((a, b) {
          final aTime = a['completedAt'] ?? a['createdAt'];
          final bTime = b['completedAt'] ?? b['createdAt'];
          if (aTime is Timestamp && bTime is Timestamp) return bTime.compareTo(aTime);
          final aDate = (a['dateStr'] ?? '').toString();
          final bDate = (b['dateStr'] ?? '').toString();
          return bDate.compareTo(aDate);
        });

        final pendingTest = SyncQueueService.getPendingScheduledTestFor(
          schoolId: schoolId!,
          classId: classId,
          subject: subject,
        );

        Map<String, dynamic>? active;
        if (validScheduled.isNotEmpty) {
          active = validScheduled.first;
          active['isPendingSync'] = false;
          if (pendingTest != null && pendingTest['id'] == active['id']) {
            SyncQueueService.removePendingScheduledTest(active['id'].toString());
          }
        } else if (pendingTest != null && pendingTest.isNotEmpty) {
          active = pendingTest;
        }

        LocalDbService.saveCache('scheduled_test_${schoolId}_${classId}_$subject', active ?? <String, dynamic>{});
        LocalDbService.saveCache('test_reports_${schoolId}_${classId}_$subject', completedDocs);

        state = state.copyWith(
          activeScheduledTest: active ?? {},
          testReportsList: completedDocs,
          isFetchingTest: false,
        );
      }
    }, onError: (e) {
      if (mounted) state = state.copyWith(isFetchingTest: false);
    });
  }

  void _fetchStudents() {
    if (schoolId == null || state.selectedClass == null) return;

    final classId = state.selectedClass!['id'];

    if (state.students.isEmpty) {
      state = state.copyWith(isLoading: true);
    }

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

      LocalDbService.saveCache('students_${schoolId}_$classId', studentsData);

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
    } else if (state.viewMode == NextClassViewMode.scheduleTest || state.viewMode == NextClassViewMode.homework) {
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

  void goToScheduleTestForm() {
    state = state.copyWith(viewMode: NextClassViewMode.test);
  }

  void goToScheduleTestMode() {
    state = state.copyWith(viewMode: NextClassViewMode.scheduleTest, testReportsPageIndex: 0);
  }

  void setTestReportsPage(int page) {
    state = state.copyWith(testReportsPageIndex: page);
  }

  void goToHomeworkMode() {
    state = state.copyWith(viewMode: NextClassViewMode.homework);
  }

  void goToActiveTestScoreMode() {
    Map<String, int> restoredScores = Map<String, int>.from(state.testScores);
    Set<String> restoredAbsent = Set<String>.from(state.absentTestStudents);

    // If memory is empty, load draft from LocalDbService
    if (restoredScores.isEmpty && restoredAbsent.isEmpty && schoolId != null && state.activeScheduledTest != null) {
      final testId = state.activeScheduledTest!['id'];
      if (testId != null) {
        final draftKey = 'test_draft_${schoolId}_$testId';
        final cached = LocalDbService.getCache(draftKey);
        if (cached is Map) {
          if (cached['scores'] is Map) {
            final Map rawScores = cached['scores'] as Map;
            for (var entry in rawScores.entries) {
              final parsedVal = int.tryParse(entry.value.toString());
              if (parsedVal != null) {
                restoredScores[entry.key.toString()] = parsedVal;
              }
            }
          }
          if (cached['absent'] is List) {
            final List rawAbsent = cached['absent'] as List;
            for (var sId in rawAbsent) {
              restoredAbsent.add(sId.toString());
            }
          }
        }
      }
    }

    state = state.copyWith(
      viewMode: NextClassViewMode.activeTestScore,
      testScores: restoredScores,
      absentTestStudents: restoredAbsent,
    );
  }

  void setSearchTerm(String term) {
    state = state.copyWith(searchTerm: term);
  }

  // --- Homework Draft & Actions ---
  HomeworkDraft get _currentHomeworkDraft => state.selectedSubject != null
      ? (state.homeworkDrafts[state.selectedSubject!] ?? HomeworkDraft())
      : HomeworkDraft();

  void _updateHomeworkDraft(HomeworkDraft newDraft) {
    if (state.selectedSubject == null) return;
    final newDrafts = Map<String, HomeworkDraft>.from(state.homeworkDrafts);
    newDrafts[state.selectedSubject!] = newDraft;
    state = state.copyWith(homeworkDrafts: newDrafts);
  }

  void setHomeworkChapter(String chapter) {
    _updateHomeworkDraft(_currentHomeworkDraft.copyWith(chapter: chapter));
  }

  void setHomeworkTopic(String topic) {
    _updateHomeworkDraft(_currentHomeworkDraft.copyWith(topic: topic));
  }

  void setHomeworkDescription(String description) {
    _updateHomeworkDraft(_currentHomeworkDraft.copyWith(description: description));
  }

  void setHomeworkDueDate(DateTime dueDate) {
    _updateHomeworkDraft(_currentHomeworkDraft.copyWith(dueDate: dueDate));
  }

  void populateDraftFromExisting(Map<String, dynamic> hw) {
    DateTime? due;
    if (hw['dueDateTime'] is Timestamp) {
      due = (hw['dueDateTime'] as Timestamp).toDate();
    } else if (hw['dueDateTime'] is DateTime) {
      due = hw['dueDateTime'] as DateTime;
    } else if (hw['dueDateTime'] is String) {
      due = DateTime.tryParse(hw['dueDateTime']);
    } else if (hw['dueDate'] != null) {
      try {
        due = DateTime.parse(hw['dueDate'].toString());
      } catch (_) {}
    }

    _updateHomeworkDraft(HomeworkDraft(
      chapter: hw['chapter'] ?? '',
      topic: hw['topic'] ?? '',
      description: hw['description'] ?? '',
      dueDate: due,
    ));
  }

  Future<bool> saveHomework({String? editHomeworkId}) async {
    if (state.isSaving) return false;
    if (schoolId == null || state.selectedClass == null || state.selectedSubject == null) return false;

    final topic = state.homeworkTopic.trim();
    final chapter = state.homeworkChapter.trim();
    final description = state.homeworkDescription.trim();
    final dueDate = state.homeworkDueDate ?? DateTime.now().add(const Duration(days: 1));

    if (topic.isEmpty && chapter.isEmpty) return false;

    state = state.copyWith(isSaving: true);

    try {
      final classId = state.selectedClass!['id'] as String;
      final className = state.selectedClass?['name'] ?? '';
      final teacherData = ref.read(teacherDataProvider).value;
      final teacherName = teacherData?['name'] ?? 'Teacher';
      final teacherId = teacherData?['id'] ?? teacherData?['uid'] ?? '';

      final dueDateStr = "${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}";
      final assignedDateStr = "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";

      final homeworkId = (editHomeworkId != null && editHomeworkId.isNotEmpty) 
          ? editHomeworkId 
          : const Uuid().v4();

      final hwData = <String, dynamic>{
        'id': homeworkId,
        'className': className,
        'subject': state.selectedSubject,
        'chapter': chapter,
        'topic': topic,
        'description': description,
        'assignedDate': assignedDateStr,
        'dueDate': dueDateStr,
        'dueDateTime': dueDate.toIso8601String(),
        'teacherName': teacherName,
        'teacherId': teacherId,
        'status': 'active',
      };

      // Clear draft for this subject
      final newDrafts = Map<String, HomeworkDraft>.from(state.homeworkDrafts);
      newDrafts.remove(state.selectedSubject);

      // Optimistic state update in homeworkList
      final currentList = List<Map<String, dynamic>>.from(state.homeworkList);
      final existingIndex = currentList.indexWhere((h) => h['id'] == homeworkId);
      if (existingIndex >= 0) {
        currentList[existingIndex] = hwData;
      } else {
        currentList.insert(0, hwData);
      }

      // Save to local cache
      final homeworkCacheKey = 'homework_${schoolId}_${classId}_${state.selectedSubject}';
      await LocalDbService.saveCache(homeworkCacheKey, {
        'list': currentList,
        'active': hwData,
      });

      // Optimistic state update
      state = state.copyWith(
        isSaving: false,
        activeHomework: hwData,
        homeworkList: currentList,
        homeworkDrafts: newDrafts,
      );

      final bool online = await SyncQueueService.isOnline();
      if (online) {
        try {
          final hwColl = FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('classes')
              .doc(classId)
              .collection('homework');

          final firestoreData = Map<String, dynamic>.from(hwData);
          firestoreData['dueDateTime'] = Timestamp.fromDate(dueDate);
          firestoreData['updatedAt'] = FieldValue.serverTimestamp();
          if (editHomeworkId == null || editHomeworkId.isEmpty) {
            firestoreData['createdAt'] = FieldValue.serverTimestamp();
          }

          await hwColl.doc(homeworkId).set(firestoreData, SetOptions(merge: true));
          return true; // Synced immediately
        } catch (e) {
          debugPrint("Online save homework failed, fallback to SyncQueue: $e");
        }
      }

      // Offline or network fallback
      await SyncQueueService.enqueue(
        type: 'homework_save',
        payload: {
          'schoolId': schoolId,
          'classId': classId,
          'homeworkId': homeworkId,
          'homeworkData': hwData,
        },
      );
      return false; // Queued offline
    } catch (e) {
      debugPrint("Error saving homework: $e");
      state = state.copyWith(isSaving: false);
      rethrow;
    }
  }

  Future<void> deleteHomework(String homeworkId) async {
    if (schoolId == null || state.selectedClass == null || state.selectedSubject == null) return;
    final classId = state.selectedClass!['id'] as String;

    // Remove from pending queue if present
    await SyncQueueService.removePendingHomework(homeworkId);

    // Optimistic UI update
    final updatedList = state.homeworkList.where((h) => h['id'] != homeworkId).toList();
    final newActive = state.activeHomework?['id'] == homeworkId
        ? (updatedList.isNotEmpty ? updatedList.first : null)
        : state.activeHomework;

    state = state.copyWith(
      homeworkList: updatedList,
      activeHomework: newActive ?? {},
    );

    // Save to local cache
    final homeworkCacheKey = 'homework_${schoolId}_${classId}_${state.selectedSubject}';
    await LocalDbService.saveCache(homeworkCacheKey, {
      'list': updatedList,
      'active': newActive ?? {},
    });

    final bool online = await SyncQueueService.isOnline();
    if (online) {
      try {
        await FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId)
            .collection('homework')
            .doc(homeworkId)
            .delete();
        return;
      } catch (e) {
        debugPrint("Online delete homework failed, fallback to SyncQueue: $e");
      }
    }

    await SyncQueueService.enqueue(
      type: 'homework_delete',
      payload: {
        'schoolId': schoolId,
        'classId': classId,
        'homeworkId': homeworkId,
      },
    );
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

  Future<bool> saveScheduledTest() async {
    if (state.isSaving) return false;
    if (schoolId == null || state.selectedClass == null || state.selectedSubject == null) return false;
    if (state.scheduleDate == null || state.scheduleTime == null) return false;
    
    state = state.copyWith(isSaving: true);

    try {
      final classId = state.selectedClass!['id'] as String;
      final className = state.selectedClass?['name'] ?? '';
      
      final scheduleDateTime = DateTime(
        state.scheduleDate!.year,
        state.scheduleDate!.month,
        state.scheduleDate!.day,
        state.scheduleTime!.hour,
        state.scheduleTime!.minute,
      );
      final isoDate = scheduleDateTime.toIso8601String();
      
      final dateStr = "${state.scheduleDate!.year}-${state.scheduleDate!.month.toString().padLeft(2, '0')}-${state.scheduleDate!.day.toString().padLeft(2, '0')}";
      final timeStr = "${state.scheduleTime!.hour.toString().padLeft(2, '0')}:${state.scheduleTime!.minute.toString().padLeft(2, '0')}";
      
      final testMessage = 'A ${state.testType} test has been scheduled for ${state.selectedSubject}.\nChapter: ${state.testChapter}\nTopic: ${state.scheduleParagraphs}\nDate: $dateStr at $timeStr\nMax Marks: ${state.maxMarks}';

      final testId = const Uuid().v4();

      final testData = {
        'id': testId,
        'subject': state.selectedSubject,
        'chapter': state.testChapter,
        'paragraphs': state.scheduleParagraphs,
        'dateStr': dateStr,
        'timeStr': timeStr,
        'isoDate': isoDate,
        'maxMarks': state.maxMarks,
        'testType': state.testType,
        'status': 'scheduled',
      };

      final newDrafts = Map<String, ScheduleTestDraft>.from(state.scheduleDrafts);
      newDrafts.remove(state.selectedSubject);

      // Save to local cache
      final scheduledTestCacheKey = 'scheduled_test_${schoolId}_${classId}_${state.selectedSubject}';
      await LocalDbService.saveCache(scheduledTestCacheKey, testData);

      // FAST OPTIMISTIC UI UPDATE
      state = state.copyWith(
        isSaving: false,
        activeScheduledTest: testData,
        scheduleDrafts: newDrafts,
      );

      final bool online = await SyncQueueService.isOnline();
      if (online) {
        try {
          final testRef = FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('classes')
              .doc(classId)
              .collection('scheduled_tests')
              .doc(testId);

          final firestoreTestData = Map<String, dynamic>.from(testData);
          firestoreTestData['createdAt'] = FieldValue.serverTimestamp();

          await testRef.set(firestoreTestData, SetOptions(merge: true));

          // Dispatch parent notifications
          final processedParents = <String>{};
          var batch = FirebaseFirestore.instance.batch();
          int batchCount = 0;

          for (var student in state.students) {
            String? parentId;
            if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
              parentId = student['parentDetails']['parentId']?.toString();
            }
            if (parentId != null && parentId.isNotEmpty && !processedParents.contains(parentId)) {
              processedParents.add(parentId);
              final alertRef = FirebaseFirestore.instance
                  .collection('schools')
                  .doc(schoolId)
                  .collection('notifications')
                  .doc();
              batch.set(alertRef, {
                'parentId': parentId,
                'studentId': student['id'] ?? '',
                'studentName': student['name'] ?? 'Student',
                'title': 'Test Scheduled: ${state.selectedSubject}',
                'message': testMessage,
                'type': 'academic',
                'read': false,
                'className': className,
                'createdAt': FieldValue.serverTimestamp(),
              });
              batchCount++;
              if (batchCount >= 400) {
                await batch.commit();
                batch = FirebaseFirestore.instance.batch();
                batchCount = 0;
              }
            }
          }
          if (batchCount > 0) {
            await batch.commit();
          }
          return true; // Synced immediately
        } catch (e) {
          debugPrint("Online save scheduled test failed, fallback to SyncQueue: $e");
        }
      }

      // Offline or network fallback -> Add to SyncQueue
      await SyncQueueService.enqueue(
        type: 'test_schedule',
        payload: {
          'schoolId': schoolId,
          'classId': classId,
          'className': className,
          'testId': testId,
          'testData': testData,
          'students': state.students,
          'testMessage': testMessage,
        },
      );
      return false; // Queued offline
    } catch (e) {
      debugPrint("Error processing scheduled test locally: $e");
      state = state.copyWith(isSaving: false);
      rethrow;
    }
  }

  Future<void> cancelScheduledTest() async {
    if (state.isSaving) return;
    if (schoolId == null || state.selectedClass == null || state.activeScheduledTest == null || state.activeScheduledTest!.isEmpty) return;
    
    _clearTestDraftLocally();
    final classId = state.selectedClass!['id'] as String;
    final className = state.selectedClass?['name'] ?? '';
    final testId = state.activeScheduledTest!['id'] as String;
    final testType = state.activeScheduledTest!['testType'] ?? 'Written';
    final subject = state.selectedSubject ?? '';

    // Remove from pending queue if present
    await SyncQueueService.removePendingScheduledTest(testId);

    // OPTIMISTIC UI UPDATE: Instantly route to form
    state = state.copyWith(isSaving: false, activeScheduledTest: {}, viewMode: NextClassViewMode.scheduleTest);

    // Update local cache
    final scheduledTestCacheKey = 'scheduled_test_${schoolId}_${classId}_$subject';
    await LocalDbService.saveCache(scheduledTestCacheKey, <String, dynamic>{});

    final testMessage = 'The $testType test for $subject has been cancelled and will be scheduled in the future.';

    final bool online = await SyncQueueService.isOnline();
    if (online) {
      try {
        final testRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId)
            .collection('scheduled_tests')
            .doc(testId);
            
        await testRef.delete();

        // Dispatch cancellation alerts
        final processedParents = <String>{};
        var batch = FirebaseFirestore.instance.batch();
        int batchCount = 0;

        for (var student in state.students) {
          String? parentId;
          if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
            parentId = student['parentDetails']['parentId']?.toString();
          }
          if (parentId != null && parentId.isNotEmpty && !processedParents.contains(parentId)) {
            processedParents.add(parentId);
            final alertRef = FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('notifications')
                .doc();
            batch.set(alertRef, {
              'parentId': parentId,
              'studentId': student['id'] ?? '',
              'studentName': student['name'] ?? 'Student',
              'title': 'Test Cancelled: $subject',
              'message': testMessage,
              'type': 'academic',
              'read': false,
              'className': className,
              'createdAt': FieldValue.serverTimestamp(),
            });
            batchCount++;
            if (batchCount >= 400) {
              await batch.commit();
              batch = FirebaseFirestore.instance.batch();
              batchCount = 0;
            }
          }
        }
        if (batchCount > 0) {
          await batch.commit();
        }
        return;
      } catch (e) {
        debugPrint("Online cancel test failed, fallback to SyncQueue: $e");
      }
    }

    // Offline or fallback to SyncQueue
    await SyncQueueService.enqueue(
      type: 'test_cancel',
      payload: {
        'schoolId': schoolId,
        'classId': classId,
        'className': className,
        'testId': testId,
        'subject': subject,
        'students': state.students,
        'cancelMessage': testMessage,
      },
    );
  }

  Future<void> completeScheduledTest() async {
    if (state.isSaving) return;
    if (schoolId == null || state.selectedClass == null || state.activeScheduledTest == null || state.activeScheduledTest!.isEmpty) return;
    
    _clearTestDraftLocally();
    final classId = state.selectedClass!['id'] as String;
    final testId = state.activeScheduledTest!['id'] as String;
    final subject = state.selectedSubject ?? '';

    // OPTIMISTIC UI UPDATE: Instantly route to form
    state = state.copyWith(isSaving: false, activeScheduledTest: {}, viewMode: NextClassViewMode.scheduleTest);

    // Update local cache
    final scheduledTestCacheKey = 'scheduled_test_${schoolId}_${classId}_$subject';
    await LocalDbService.saveCache(scheduledTestCacheKey, <String, dynamic>{});

    final bool online = await SyncQueueService.isOnline();
    if (online) {
      try {
        final testRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId)
            .collection('scheduled_tests')
            .doc(testId);
            
        await testRef.update({'status': 'completed'});
        return;
      } catch (e) {
        debugPrint("Online complete test failed, fallback to SyncQueue: $e");
      }
    }

    await SyncQueueService.enqueue(
      type: 'test_complete',
      payload: {
        'schoolId': schoolId,
        'classId': classId,
        'testId': testId,
      },
    );
  }

  Future<void> saveActiveTestScores(String message) async {
    if (state.isSaving) return;
    if (schoolId == null || state.selectedClass == null || state.activeScheduledTest == null || state.activeScheduledTest!.isEmpty) return;
    
    _clearTestDraftLocally();
    final classId = state.selectedClass!['id'] as String;
    final className = state.selectedClass?['name'] ?? '';
    final testId = state.activeScheduledTest!['id'] as String;
    final subject = state.selectedSubject ?? '';
    final testType = state.activeScheduledTest!['testType'] ?? 'Written';
    final maxMarks = state.activeScheduledTest!['maxMarks'] ?? 10;
    final dateStr = state.activeScheduledTest!['dateStr'] ?? '';
    final testScoresCopy = Map<String, int>.from(state.testScores);
    final absentStudentsCopy = Set<String>.from(state.absentTestStudents);

    final testMessage = message.isNotEmpty ? message : 'The scores for the $testType test in $subject have been published.';

    state = state.copyWith(
      isSaving: false,
      viewMode: NextClassViewMode.scheduleTest,
      testScores: {},
      absentTestStudents: {},
    );

    final bool online = await SyncQueueService.isOnline();
    if (online) {
      try {
        final batch = FirebaseFirestore.instance.batch();
        final processedParents = <String>{};

        for (var student in state.students) {
          final studentId = student['id']?.toString() ?? '';
          if (studentId.isEmpty) continue;
          final bool isAbsent = absentStudentsCopy.contains(studentId);

          String? parentId;
          if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
            parentId = student['parentDetails']['parentId']?.toString();
          }

          if (parentId != null && parentId.isNotEmpty && !processedParents.contains(parentId)) {
            processedParents.add(parentId);
            final alertRef = FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('notifications')
                .doc();

            final sName = student['name'] ?? 'Student';
            final notifTitle = isAbsent ? 'Test Absence: $subject' : 'Test Results: $subject';
            final notifMsg = isAbsent
                ? '$sName was marked ABSENT for the $testType test in $subject on $dateStr.'
                : testMessage;

            batch.set(alertRef, {
              'parentId': parentId,
              'studentId': studentId,
              'studentName': sName,
              'title': notifTitle,
              'message': notifMsg,
              'type': 'academic',
              'read': false,
              'className': className,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }

          // Save score if it was entered or student is absent
          if (testScoresCopy.containsKey(studentId) || isAbsent) {
            final score = isAbsent ? null : testScoresCopy[studentId];
            final studentRef = FirebaseFirestore.instance
                .collection('schools')
                .doc(schoolId)
                .collection('classes')
                .doc(classId)
                .collection('students')
                .doc(studentId);

            final scoreRef = studentRef.collection('testScores').doc(testId);
            batch.set(scoreRef, {
              'subject': subject,
              'testType': testType,
              'score': score,
              'isAbsent': isAbsent,
              'maxMarks': maxMarks,
              'date': dateStr,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }

        // Also mark test document as completed with full scores snapshot
        final testDocRef = FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .collection('classes')
            .doc(classId)
            .collection('scheduled_tests')
            .doc(testId);

        batch.update(testDocRef, {
          'status': 'completed',
          'scores': testScoresCopy,
          'absentStudents': absentStudentsCopy.toList(),
          'completedAt': FieldValue.serverTimestamp(),
          'presentCount': testScoresCopy.length,
          'absentCount': absentStudentsCopy.length,
        });

        await batch.commit();
        return;
      } catch (e) {
        debugPrint("Online test scores save failed, fallback to SyncQueue: $e");
      }
    }

    // Offline or fallback
    await SyncQueueService.enqueue(
      type: 'test_scores_save',
      payload: {
        'schoolId': schoolId,
        'classId': classId,
        'className': className,
        'testId': testId,
        'subject': subject,
        'testType': testType,
        'maxMarks': maxMarks,
        'dateStr': dateStr,
        'testMessage': testMessage,
        'testScores': testScoresCopy,
        'scores': testScoresCopy,
        'absentStudents': absentStudentsCopy.toList(),
        'students': state.students,
      },
    );
  }

  Future<bool> updateCompletedTestScores({
    required String testId,
    required Map<String, int> updatedScores,
    required Set<String> updatedAbsent,
    bool notifyParents = false,
  }) async {
    if (schoolId == null || state.selectedClass == null) return false;
    final classId = state.selectedClass!['id'] as String;
    final className = state.selectedClass?['name'] ?? '';
    final subject = state.selectedSubject ?? '';

    final testIdx = state.testReportsList.indexWhere((t) => t['id'] == testId);
    final testData = testIdx >= 0 ? state.testReportsList[testIdx] : null;
    final testType = testData?['testType'] ?? 'Written';
    final maxMarks = testData?['maxMarks'] ?? 10;
    final dateStr = testData?['dateStr'] ?? '';

    final testRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('scheduled_tests')
        .doc(testId);

    try {
      final batch = FirebaseFirestore.instance.batch();

      batch.update(testRef, {
        'scores': updatedScores,
        'absentStudents': updatedAbsent.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'presentCount': updatedScores.length,
        'absentCount': updatedAbsent.length,
      });

      for (var student in state.students) {
        final studentId = student['id']?.toString() ?? '';
        if (studentId.isEmpty) continue;
        final bool isAbsent = updatedAbsent.contains(studentId);
        final bool hasScore = updatedScores.containsKey(studentId);

        if (hasScore || isAbsent) {
          final studentRef = FirebaseFirestore.instance
              .collection('schools')
              .doc(schoolId)
              .collection('classes')
              .doc(classId)
              .collection('students')
              .doc(studentId);

          final scoreRef = studentRef.collection('testScores').doc(testId);
          batch.set(scoreRef, {
            'subject': subject,
            'testType': testType,
            'score': isAbsent ? null : updatedScores[studentId],
            'isAbsent': isAbsent,
            'maxMarks': maxMarks,
            'date': dateStr,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          if (notifyParents) {
            String? parentId;
            if (student['parentDetails'] != null && student['parentDetails']['parentId'] != null) {
              parentId = student['parentDetails']['parentId']?.toString();
            }
            if (parentId != null && parentId.isNotEmpty) {
              final alertRef = FirebaseFirestore.instance
                  .collection('schools')
                  .doc(schoolId)
                  .collection('notifications')
                  .doc();
              final sName = student['name'] ?? 'Student';
              final notifTitle = isAbsent ? 'Updated Test Absence: $subject' : 'Updated Test Results: $subject';
              final notifMsg = isAbsent
                  ? '$sName was marked ABSENT for the updated $testType test in $subject.'
                  : 'Updated test scores for $sName in $subject have been published.';
              batch.set(alertRef, {
                'parentId': parentId,
                'studentId': studentId,
                'studentName': sName,
                'title': notifTitle,
                'message': notifMsg,
                'type': 'academic',
                'read': false,
                'className': className,
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
          }
        }
      }

      await batch.commit();

      if (testIdx >= 0) {
        final updatedList = List<Map<String, dynamic>>.from(state.testReportsList);
        updatedList[testIdx] = {
          ...updatedList[testIdx],
          'scores': updatedScores,
          'absentStudents': updatedAbsent.toList(),
          'presentCount': updatedScores.length,
          'absentCount': updatedAbsent.length,
        };
        state = state.copyWith(testReportsList: updatedList);
        LocalDbService.saveCache('test_reports_${schoolId}_${classId}_$subject', updatedList);
      }
      return true;
    } catch (e) {
      debugPrint("Error updating test report: $e");
      return false;
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
    
    if (schoolId == null || state.selectedClass == null || state.selectedSubject == null) return;

    final classId = state.selectedClass!['id'] as String;
    final subject = state.selectedSubject!;
    final scoreUpdatesCopy = Map<String, Map<String, int>>.from(state.scoreUpdates);

    state = state.copyWith(isSaving: false, scoreUpdates: {});

    final bool online = await SyncQueueService.isOnline();
    if (online) {
      try {
        final batch = FirebaseFirestore.instance.batch();

        for (var entry in scoreUpdatesCopy.entries) {
          final studentId = entry.key;
          final updates = entry.value;

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

          if (updates.containsKey('academic')) {
            final idx = newAcademicScores.indexWhere((s) => s['subject'] == subject);
            if (idx >= 0) {
              newAcademicScores[idx] = { ...newAcademicScores[idx], 'score': updates['academic'] };
            } else {
              newAcademicScores.add({ 'subject': subject, 'score': updates['academic'] });
            }
          }

          if (updates.containsKey('homework')) {
            final idx = newHomeworkScores.indexWhere((s) => s['subject'] == subject);
            if (idx >= 0) {
              newHomeworkScores[idx] = { ...newHomeworkScores[idx], 'score': updates['homework'] };
            } else {
              newHomeworkScores.add({ 'subject': subject, 'score': updates['homework'] });
            }
          }

          batch.update(studentRef, {
            'academicScores': newAcademicScores,
            'homeworkScores': newHomeworkScores,
          });
        }

        await batch.commit();
        return;
      } catch (e) {
        debugPrint("Online save scores failed, fallback to SyncQueue: $e");
      }
    }

    // Offline or fallback to SyncQueue
    await SyncQueueService.enqueue(
      type: 'daily_scores_save',
      payload: {
        'schoolId': schoolId,
        'classId': classId,
        'subject': subject,
        'scoreUpdates': scoreUpdatesCopy,
        'students': state.students,
      },
    );
  }

  // --- Test Mode Logic ---
  void updateTestScore(String studentId, int value) {
    final newTestScores = Map<String, int>.from(state.testScores);
    newTestScores[studentId] = value;
    final newAbsent = Set<String>.from(state.absentTestStudents);
    newAbsent.remove(studentId);
    state = state.copyWith(testScores: newTestScores, absentTestStudents: newAbsent);
    _saveTestDraftLocally(newTestScores, newAbsent);
  }

  void toggleTestAbsent(String studentId) {
    final newAbsent = Set<String>.from(state.absentTestStudents);
    final newScores = Map<String, int>.from(state.testScores);
    if (newAbsent.contains(studentId)) {
      newAbsent.remove(studentId);
    } else {
      newAbsent.add(studentId);
      newScores.remove(studentId);
    }
    state = state.copyWith(absentTestStudents: newAbsent, testScores: newScores);
    _saveTestDraftLocally(newScores, newAbsent);
  }

  void resetTestScores() {
    _clearTestDraftLocally();
    state = state.copyWith(testScores: {}, absentTestStudents: {});
  }

  void _saveTestDraftLocally(Map<String, int> scores, Set<String> absent) {
    if (schoolId == null || state.activeScheduledTest == null) return;
    final testId = state.activeScheduledTest!['id'];
    if (testId == null) return;
    final draftKey = 'test_draft_${schoolId}_$testId';
    LocalDbService.saveCache(draftKey, {
      'scores': scores,
      'absent': absent.toList(),
    });
  }

  void _clearTestDraftLocally() {
    if (schoolId == null || state.activeScheduledTest == null) return;
    final testId = state.activeScheduledTest!['id'];
    if (testId == null) return;
    final draftKey = 'test_draft_${schoolId}_$testId';
    LocalDbService.removeCache(draftKey);
  }

  int getTestDraftRecordedCount() {
    int count = state.testScores.length + state.absentTestStudents.length;
    if (count > 0) return count;
    if (schoolId == null || state.activeScheduledTest == null) return 0;
    final testId = state.activeScheduledTest!['id'];
    if (testId == null) return 0;
    final draftKey = 'test_draft_${schoolId}_$testId';
    final cached = LocalDbService.getCache(draftKey);
    if (cached is Map) {
      final scores = (cached['scores'] as Map?)?.length ?? 0;
      final absent = (cached['absent'] as List?)?.length ?? 0;
      return scores + absent;
    }
    return 0;
  }

}

final nextClassProvider = StateNotifierProvider.autoDispose<NextClassNotifier, NextClassState>((ref) {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final String? schoolId = teacherDataAsync.value?['schoolId'];
  return NextClassNotifier(ref, schoolId);
});
