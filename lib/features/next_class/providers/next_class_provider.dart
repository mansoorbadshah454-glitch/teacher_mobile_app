import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';

enum NextClassViewMode { classes, subjects, students, test }

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
    );
  }
}

class NextClassNotifier extends StateNotifier<NextClassState> {
  final Ref ref;
  final String? schoolId;

  NextClassNotifier(this.ref, this.schoolId) : super(NextClassState()) {
    if (schoolId != null) {
      _fetchClasses();
    }
  }

  void _fetchClasses() {
    if (schoolId == null) return;
    
    state = state.copyWith(isLoading: true);
    
    FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .snapshots()
        .listen((snapshot) {
      final classesData = snapshot.docs.map((doc) {
        final data = doc.data();
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
    );
    _fetchStudents();
  }

  void _fetchStudents() {
    if (schoolId == null || state.selectedClass == null) return;

    final classId = state.selectedClass!['id'];

    state = state.copyWith(isLoading: true);

    FirebaseFirestore.instance
        .collection('schools')
        .doc(schoolId)
        .collection('classes')
        .doc(classId)
        .collection('students')
        .snapshots()
        .listen((snapshot) {
      final studentsData = snapshot.docs.map((doc) {
        final data = doc.data();
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
    if (state.viewMode == NextClassViewMode.test) {
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

  void setSearchTerm(String term) {
    state = state.copyWith(searchTerm: term);
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
      orElse: () => null,
    );

    if (subjectScore != null) {
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
        final student = state.students.firstWhere((s) => s['id'] == studentId, orElse: () => {});
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

final nextClassProvider = StateNotifierProvider<NextClassNotifier, NextClassState>((ref) {
  final teacherDataAsync = ref.watch(teacherDataProvider);
  final String? schoolId = teacherDataAsync.value?['schoolId'];
  return NextClassNotifier(ref, schoolId);
});
