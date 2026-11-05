import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/core/services/sync_queue_service.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/features/exam/models/exam_model.dart';
import 'package:teacher_mobile_app/features/exam/providers/exam_provider.dart';

class MarksEntryScreen extends ConsumerStatefulWidget {
  final ExamClassSubject classItem;

  const MarksEntryScreen({super.key, required this.classItem});

  @override
  ConsumerState<MarksEntryScreen> createState() => _MarksEntryScreenState();
}

class _MarksEntryScreenState extends ConsumerState<MarksEntryScreen> {
  late String _selectedSubject;
  String? _selectedExamId;
  String _selectedExamTitle = '';
  int _totalMarks = 100;
  int _passingMarks = 33;
  String _searchQuery = '';

  // Local state for editing marks
  List<StudentMarksEntry> _entries = [];
  bool _isDataLoaded = false;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  bool _isModified = false;
  String? _resolvedClassId;

  @override
  void initState() {
    super.initState();
    _selectedSubject = widget.classItem.subjects.isNotEmpty ? widget.classItem.subjects.first : 'General';
    _totalMarks = 100;
    _passingMarks = 33;
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    for (var f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _initControllers() {
    for (var entry in _entries) {
      if (!_controllers.containsKey(entry.studentId)) {
        final initialText = entry.isAbsent
            ? ''
            : (entry.obtainedMarks != null ? (entry.obtainedMarks! % 1 == 0 ? entry.obtainedMarks!.toInt().toString() : entry.obtainedMarks.toString()) : '');
        _controllers[entry.studentId] = TextEditingController(text: initialText);
      }
      if (!_focusNodes.containsKey(entry.studentId)) {
        _focusNodes[entry.studentId] = FocusNode();
      }
    }
  }

  Future<void> _handleBackAttempt(dynamic teacherData, dynamic authUser) async {
    if (!_isModified) {
      if (mounted) context.pop();
      return;
    }

    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text("Unsaved Marks", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "You have entered or modified marks for $_selectedSubject in ${widget.classItem.className}. Would you like to save before leaving?",
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _isModified = false;
              Navigator.pop(ctx, true);
            },
            child: const Text("Discard", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx, false);
              await _performSave(teacherData, authUser);
              if (mounted) context.pop();
            },
            child: const Text("Save & Exit", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldLeave == true && mounted) {
      context.pop();
    }
  }

  Future<void> _performSave(dynamic teacherData, dynamic authUser) async {
    final schoolId = (teacherData?['schoolId'] ?? '').toString();
    final teacherUid = authUser?.uid ?? (teacherData?['id'] ?? '');
    final teacherName = (teacherData?['name'] ?? teacherData?['fullName'] ?? 'Teacher').toString();

    if (_selectedExamId == null || schoolId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select an exam first")),
      );
      return;
    }

    // Safety check: Ensure exam is not locked/completed by Principal
    final examsList = ref.read(schoolExamsProvider).value ?? [];
    final currentExam = examsList.firstWhere(
      (e) => e.id == _selectedExamId,
      orElse: () => ExamModel(id: '', title: '', session: ''),
    );
    if (currentExam.isCompletedOrLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🔒 This exam has been marked as COMPLETED by Principal. Marks cannot be modified."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Check for invalid marks
    final hasExceeding = _entries.any(
      (e) => !e.isAbsent && e.obtainedMarks != null && e.obtainedMarks! > _totalMarks,
    );

    if (hasExceeding) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Some marks exceed maximum total marks ($_totalMarks)!"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final targetClassId = (_resolvedClassId != null && _resolvedClassId!.isNotEmpty) ? _resolvedClassId! : widget.classItem.classId;

    final success = await ref.read(marksSaveProvider.notifier).saveMarks(
          schoolId: schoolId,
          classId: targetClassId,
          className: widget.classItem.className,
          examId: _selectedExamId!,
          examTitle: _selectedExamTitle,
          subject: _selectedSubject,
          teacherId: teacherUid,
          teacherName: teacherName,
          totalMarks: _totalMarks,
          passingMarks: _passingMarks,
          entries: _entries,
        );

    if (success) {
      _isModified = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;
    final examsAsync = ref.watch(schoolExamsProvider);
    final teacherData = ref.watch(teacherDataProvider).value;
    final authUser = ref.watch(currentUserProvider);
    final saveState = ref.watch(marksSaveProvider);

    // Listen to Save State for alerts
    ref.listen<MarksSaveState>(marksSaveProvider, (previous, next) {
      if (next.isSuccess && (previous == null || !previous.isSuccess)) {
        _isModified = false;
        final bool isOff = next.isOffline;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isOff ? Icons.cloud_off : Icons.check_circle,
                  color: Colors.white,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    next.message ?? (isOff
                        ? "⚡ Marks saved offline! Will auto-sync when online."
                        : "Marks for $_selectedSubject saved successfully!"),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: isOff ? const Color(0xFFD97706) : const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: isOff ? 4 : 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        ref.read(marksSaveProvider.notifier).reset();
        // Invalidate current sheet to reload updated values
        if (_selectedExamId != null) {
          ref.invalidate(
            examMarksSheetProvider(ExamSubjectQuery(
              classId: widget.classItem.classId,
              className: widget.classItem.className,
              examId: _selectedExamId!,
              subject: _selectedSubject,
            )),
          );
        }
      }

      if (next.error != null && (previous == null || previous.error != next.error)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving marks: ${next.error}"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    return PopScope(
      canPop: !_isModified,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackAttempt(teacherData, authUser);
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${widget.classItem.className} • Marks Entry",
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              Text(
                "Subject: $_selectedSubject",
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF4F46E5),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => _handleBackAttempt(teacherData, authUser),
          ),
          actions: [
            ValueListenableBuilder<int>(
              valueListenable: SyncQueueService.pendingCountNotifier,
              builder: (context, count, _) {
                if (count > 0) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: GestureDetector(
                        onTap: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Syncing $count offline items..."),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                          await SyncQueueService.checkAndSync();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade400,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sync, size: 12, color: Colors.black87),
                              const SizedBox(width: 3),
                              Text(
                                "$count",
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            IconButton(
              icon: const Icon(Icons.assignment_outlined, color: Colors.white),
              tooltip: "Exams Status Overview",
              onPressed: () {
                final exams = (examsAsync.value != null && examsAsync.value!.isNotEmpty)
                    ? examsAsync.value!
                    : _getFallbackExams();
                _showExamsStatusDialog(context, exams);
              },
            ),
          ],
        ),
      body: Builder(
        builder: (context) {
          final exams = (examsAsync.value != null && examsAsync.value!.isNotEmpty)
              ? examsAsync.value!
              : _getFallbackExams();

          final currentExam = exams.firstWhere(
            (e) => e.id == _selectedExamId,
            orElse: () => ExamModel(id: '', title: '', session: ''),
          );
          final bool isExamLocked = currentExam.isCompletedOrLocked;
          final currentVal = exams.any((e) => e.id == _selectedExamId) ? _selectedExamId : null;

          return Column(
            children: [
              // Top Control Panel: Exam Selector & (if selected) Subject Chips + Search & Total Marks Bar
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : const Color(0xFF1E293B),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Exam Dropdown Row
                    Row(
                      children: [
                        const Icon(Icons.assignment_outlined, size: 18, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 8),
                        const Text(
                          "Exam:",
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            decoration: BoxDecoration(
                              color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: currentVal,
                                hint: const Text(
                                  "-- Select Exam (Term / Test) --",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4F46E5)),
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                dropdownColor: isLight ? Colors.white : const Color(0xFF1E293B),
                                items: exams.map((exam) {
                                  final isLocked = exam.isCompletedOrLocked;
                                  return DropdownMenuItem<String>(
                                    value: exam.id,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            exam.title,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                        if (isLocked) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.red.withOpacity(0.3)),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.lock, size: 10, color: Colors.red),
                                                SizedBox(width: 3),
                                                Text(
                                                  "LOCKED",
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (newVal) {
                                  if (newVal != null && newVal != _selectedExamId) {
                                    final selected = exams.firstWhere((e) => e.id == newVal, orElse: () => exams.first);
                                    setState(() {
                                      _selectedExamId = newVal;
                                      _selectedExamTitle = selected.title;
                                      _totalMarks = selected.defaultTotalMarks;
                                      _passingMarks = selected.passingMarks;
                                      _isDataLoaded = false;
                                      _entries.clear();
                                      _controllers.clear();
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Show Subjects & Search bar ONLY after exam is selected
                    if (_selectedExamId != null) ...[
                      const SizedBox(height: 12),

                      // Subject Selector Chips (if teacher has > 1 subject)
                      if (widget.classItem.subjects.length > 1) ...[
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: widget.classItem.subjects.map((subj) {
                              final isSelected = subj == _selectedSubject;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(subj),
                                  selected: isSelected,
                                  selectedColor: const Color(0xFF4F46E5),
                                  backgroundColor: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                  onSelected: (selected) {
                                    if (selected && subj != _selectedSubject) {
                                      setState(() {
                                        _selectedSubject = subj;
                                        _isDataLoaded = false;
                                        _entries.clear();
                                        _controllers.clear();
                                      });
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Search and Read-Only Total Marks Bar
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextField(
                                onChanged: (val) => setState(() => _searchQuery = val),
                                textAlignVertical: TextAlignVertical.center,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: "Search student or roll no...",
                                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                                  prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                ),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4F46E5).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "Max: $_totalMarks | Pass: $_passingMarks",
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF4F46E5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Students Marks Sheet OR Empty State Placeholder
              Expanded(
                child: _selectedExamId == null
                    ? _buildNoExamSelectedPlaceholder(isDark, isLight)
                    : _buildStudentsSheet(isExamLocked),
              ),

              // Bottom Floating Action Button to Save Marks (Only when exam is selected)
              if (_selectedExamId != null)
                _buildSaveActionBar(teacherData, authUser, saveState, isExamLocked),
            ],
          );
        },
      ),
    ),
  );
}

  Widget _buildNoExamSelectedPlaceholder(bool isDark, bool isLight) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF4F46E5).withOpacity(0.15),
                    const Color(0xFF7C3AED).withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF4F46E5).withOpacity(0.25),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.assignment_turned_in_outlined,
                size: 40,
                color: Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "No Exam Selected",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Please select an examination (e.g. 1st Term, Mid Term, Annual Exam, or Monthly Test) from the dropdown above to view student marks.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, size: 15, color: Color(0xFF4F46E5)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      "Marks criteria & locked status are set by Principal",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : const Color(0xFF4F46E5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentsSheet(bool isExamLocked) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;

    final sheetAsync = ref.watch(
      examMarksSheetProvider(
        ExamSubjectQuery(
          classId: widget.classItem.classId,
          className: widget.classItem.className,
          examId: _selectedExamId!,
          subject: _selectedSubject,
        ),
      ),
    );

    return sheetAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFF4F46E5)),
      ),
      error: (e, st) => Center(
        child: Text("Error: $e", style: const TextStyle(color: Colors.red)),
      ),
      data: (data) {
        final List<StudentMarksEntry> serverEntries = List<StudentMarksEntry>.from(data['students'] ?? []);
        final resolvedId = (data['resolvedClassId'] ?? '').toString();
        if (resolvedId.isNotEmpty) {
          _resolvedClassId = resolvedId;
        }

        if (!_isDataLoaded || _entries.isEmpty) {
          if (serverEntries.isNotEmpty) {
            _entries = serverEntries;
            _totalMarks = data['totalMarks'] ?? _totalMarks;
            _passingMarks = data['passingMarks'] ?? _passingMarks;
            _initControllers();
            _isDataLoaded = true;
          }
        }

        final currentList = _entries.isNotEmpty ? _entries : serverEntries;

        final filteredEntries = currentList.where((s) {
          if (_searchQuery.trim().isEmpty) return true;
          final q = _searchQuery.toLowerCase();
          return s.studentName.toLowerCase().contains(q) || s.rollNumber.toLowerCase().contains(q);
        }).toList();

        if (filteredEntries.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline, size: 48, color: isDark ? Colors.white38 : Colors.grey),
                const SizedBox(height: 12),
                Text(
                  "No students found",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Prominent banner if exam is completed/locked by Principal
            if (isExamLocked)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock, color: Color(0xFFDC2626), size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "This exam has been marked as COMPLETED by Principal. Scores are permanently locked in view-only mode.",
                        style: TextStyle(
                          color: Color(0xFF991B1B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: filteredEntries.length,
                itemBuilder: (context, index) {
                  final entry = filteredEntries[index];
                  return _buildStudentMarkRow(entry, index, filteredEntries.length, isExamLocked);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStudentMarkRow(StudentMarksEntry entry, int index, int totalCount, bool isExamLocked) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;
    final controller = _controllers[entry.studentId];
    final focusNode = _focusNodes[entry.studentId];
    final grade = entry.getGrade(_totalMarks.toDouble());

    Color gradeBg = const Color(0xFFE2E8F0);
    Color gradeFg = const Color(0xFF475569);

    if (entry.isAbsent) {
      gradeBg = const Color(0xFFFEE2E2);
      gradeFg = const Color(0xFFEF4444);
    } else if (grade == 'A+' || grade == 'A') {
      gradeBg = const Color(0xFFD1FAE5);
      gradeFg = const Color(0xFF059669);
    } else if (grade == 'B' || grade == 'C') {
      gradeBg = const Color(0xFFDBEAFE);
      gradeFg = const Color(0xFF2563EB);
    } else if (grade == 'D' || grade == 'E') {
      gradeBg = const Color(0xFFFEF3C7);
      gradeFg = const Color(0xFFD97706);
    } else if (grade == 'F') {
      gradeBg = const Color(0xFFFEE2E2);
      gradeFg = const Color(0xFFDC2626);
    }

    final bool isExceeding = !entry.isAbsent &&
        entry.obtainedMarks != null &&
        entry.obtainedMarks! > _totalMarks;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExceeding
              ? Colors.red
              : (isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
          width: isExceeding ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Roll No Badge
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                entry.rollNumber.isNotEmpty ? entry.rollNumber : "${index + 1}",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4F46E5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Avatar / Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.studentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Roll: ${entry.rollNumber.isNotEmpty ? entry.rollNumber : 'N/A'}",
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),

          // Absent Toggle Button
          GestureDetector(
            onTap: isExamLocked
                ? null
                : () {
                    setState(() {
                      entry.isAbsent = !entry.isAbsent;
                      _isModified = true;
                      if (entry.isAbsent) {
                        controller?.clear();
                        entry.obtainedMarks = null;
                      }
                    });
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: entry.isAbsent
                    ? const Color(0xFFEF4444)
                    : (isExamLocked ? (isLight ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A)) : Colors.transparent),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: entry.isAbsent
                      ? const Color(0xFFEF4444)
                      : (isExamLocked ? Colors.transparent : const Color(0xFFCBD5E1)),
                ),
              ),
              child: Text(
                "ABS",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: entry.isAbsent
                      ? Colors.white
                      : (isExamLocked
                          ? (isDark ? Colors.white24 : Colors.grey.shade400)
                          : (isDark ? Colors.white60 : const Color(0xFF64748B))),
                ),
              ),
            ),
          ),

          // Marks Input Field
          SizedBox(
            width: 65,
            height: 40,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !isExamLocked && !entry.isAbsent,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              textInputAction: index < totalCount - 1 ? TextInputAction.next : TextInputAction.done,
              onSubmitted: (_) {
                if (index < totalCount - 1) {
                  final nextEntry = _entries[index + 1];
                  _focusNodes[nextEntry.studentId]?.requestFocus();
                }
              },
              onChanged: (val) {
                final parsed = double.tryParse(val.trim());
                setState(() {
                  entry.obtainedMarks = parsed;
                  _isModified = true;
                });
              },
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isExceeding ? Colors.red : (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                hintText: entry.isAbsent ? '-' : '0',
                filled: true,
                fillColor: entry.isAbsent
                    ? (isLight ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A))
                    : (isExamLocked
                        ? (isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A).withOpacity(0.5))
                        : (isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A))),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isExceeding ? Colors.red : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                  ),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Grade Badge
          Container(
            width: 38,
            height: 36,
            decoration: BoxDecoration(
              color: gradeBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                grade,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: gradeFg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveActionBar(
    Map<String, dynamic>? teacherData,
    dynamic authUser,
    MarksSaveState saveState,
    bool isExamLocked,
  ) {
    final isLight = Theme.of(context).brightness == Brightness.light;

    // Calculate Summary
    final int totalCount = _entries.length;
    final int enteredCount = _entries.where((e) => e.obtainedMarks != null || e.isAbsent).length;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF1E293B),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Entered: $enteredCount / $totalCount",
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Text(
                _selectedSubject,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          const Spacer(),
          if (isExamLocked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF334155),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Text(
                    "Exam Completed (Locked)",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isLight ? const Color(0xFF475569) : Colors.white70,
                    ),
                  ),
                ],
              ),
            )
          else
            ElevatedButton(
              onPressed: saveState.isLoading
                  ? null
                  : () => _performSave(teacherData, authUser),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              child: saveState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Row(
                      children: [
                        Icon(Icons.save_outlined, size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Save Marks",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  void _showExamsStatusDialog(BuildContext context, List<ExamModel> exams) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isLight ? Colors.white : const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        actionsPadding: const EdgeInsets.all(14),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.assignment_outlined, color: Color(0xFF4F46E5), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Exams & Status",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Academic Examination Schedule",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(height: 1),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: exams.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final ex = exams[i];
                    final isLocked = ex.isCompletedOrLocked;
                    final isUpcoming = ex.status.toLowerCase() == 'upcoming';

                    Color statusBg;
                    Color statusFg;
                    String statusLabel;
                    IconData statusIcon;

                    if (isLocked) {
                      statusBg = const Color(0xFFFEE2E2);
                      statusFg = const Color(0xFFDC2626);
                      statusLabel = "Completed";
                      statusIcon = Icons.lock_outline;
                    } else if (isUpcoming) {
                      statusBg = const Color(0xFFDBEAFE);
                      statusFg = const Color(0xFF2563EB);
                      statusLabel = "Upcoming";
                      statusIcon = Icons.schedule;
                    } else {
                      statusBg = const Color(0xFFD1FAE5);
                      statusFg = const Color(0xFF059669);
                      statusLabel = "Active / Open";
                      statusIcon = Icons.check_circle_outline;
                    }

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  ex.title,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(statusIcon, size: 11, color: statusFg),
                                    const SizedBox(width: 4),
                                    Text(
                                      statusLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: statusFg,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  ex.session.isNotEmpty ? "Session: ${ex.session}" : "Session",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white54 : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4F46E5).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "Max: ${ex.defaultTotalMarks} | Pass: ${ex.passingMarks}",
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF4F46E5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 15, color: Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Exam definitions, marks scales, and completion locks are controlled via the Principal Webapp.",
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? Colors.white60 : const Color(0xFF64748B),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  List<ExamModel> _getFallbackExams() {
    return [
      ExamModel(id: 'first_term_2026', title: 'First Term Examination 2026', session: '2025-2026', defaultTotalMarks: 100, passingMarks: 33),
      ExamModel(id: 'mid_term_2026', title: 'Mid Term Examination 2026', session: '2025-2026', defaultTotalMarks: 50, passingMarks: 17),
      ExamModel(id: 'monthly_test', title: 'Monthly Class Test', session: '2025-2026', defaultTotalMarks: 25, passingMarks: 10),
      ExamModel(id: 'final_term_2026', title: 'Annual / Final Examination 2026', session: '2025-2026', defaultTotalMarks: 100, passingMarks: 33),
    ];
  }
}
