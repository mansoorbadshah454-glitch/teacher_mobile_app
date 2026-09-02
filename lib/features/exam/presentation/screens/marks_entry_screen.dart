import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
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
        const SnackBar(content: Text("Exam or School ID missing")),
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

    // Auto-select first exam if not selected
    examsAsync.whenData((exams) {
      if (exams.isNotEmpty && _selectedExamId == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _selectedExamId = exams.first.id;
              _selectedExamTitle = exams.first.title;
              _totalMarks = exams.first.defaultTotalMarks;
              _passingMarks = exams.first.passingMarks;
              _isDataLoaded = false;
            });
          }
        });
      }
    });

    // Listen to Save State for alerts
    ref.listen<MarksSaveState>(marksSaveProvider, (previous, next) {
      if (next.isSuccess && (previous == null || !previous.isSuccess)) {
        _isModified = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Marks for $_selectedSubject saved successfully!",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
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
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white),
              tooltip: "Total Marks Config",
              onPressed: () => _showTotalMarksDialog(),
            ),
          ],
        ),
      body: Column(
        children: [
          // Top Control Panel: Exam Selector & Subject Chips
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
                      child: Builder(
                        builder: (context) {
                          final exams = (examsAsync.value != null && examsAsync.value!.isNotEmpty)
                              ? examsAsync.value!
                              : [
                                  ExamModel(id: 'first_term_2026', title: 'First Term Examination 2026', session: '2025-2026', defaultTotalMarks: 100, passingMarks: 33),
                                  ExamModel(id: 'mid_term_2026', title: 'Mid Term Examination 2026', session: '2025-2026', defaultTotalMarks: 50, passingMarks: 17),
                                  ExamModel(id: 'monthly_test', title: 'Monthly Class Test', session: '2025-2026', defaultTotalMarks: 25, passingMarks: 10),
                                  ExamModel(id: 'final_term_2026', title: 'Annual / Final Examination 2026', session: '2025-2026', defaultTotalMarks: 100, passingMarks: 33),
                                ];

                          final currentVal = exams.any((e) => e.id == _selectedExamId)
                              ? _selectedExamId
                              : (exams.isNotEmpty ? exams.first.id : null);

                          return Container(
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
                                isExpanded: true,
                                icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF4F46E5)),
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                dropdownColor: isLight ? Colors.white : const Color(0xFF1E293B),
                                items: exams.map((exam) {
                                  return DropdownMenuItem<String>(
                                    value: exam.id,
                                    child: Text(exam.title),
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
                          );
                        },
                      ),
                    ),
                  ],
                ),

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

                // Search and Total Marks Bar
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
            ),
          ),

          // Students Marks Sheet
          Expanded(
            child: _selectedExamId == null
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
                : _buildStudentsSheet(),
          ),

          // Bottom Floating Action Button to Save Marks
          _buildSaveActionBar(teacherData, authUser, saveState),
        ],
      ),
    ),
  );
}

  Widget _buildStudentsSheet() {
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

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: filteredEntries.length,
          itemBuilder: (context, index) {
            final entry = filteredEntries[index];
            return _buildStudentMarkRow(entry, index, filteredEntries.length);
          },
        );
      },
    );
  }

  Widget _buildStudentMarkRow(StudentMarksEntry entry, int index, int totalCount) {
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
            onTap: () {
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
                color: entry.isAbsent ? const Color(0xFFEF4444) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: entry.isAbsent ? const Color(0xFFEF4444) : const Color(0xFFCBD5E1),
                ),
              ),
              child: Text(
                "ABS",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: entry.isAbsent ? Colors.white : (isDark ? Colors.white60 : const Color(0xFF64748B)),
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
              enabled: !entry.isAbsent,
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
                    : (isLight ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: isExceeding ? Colors.red : (isLight ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                  ),
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

  Widget _buildSaveActionBar(Map<String, dynamic>? teacherData, dynamic authUser, MarksSaveState saveState) {
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

  void _showTotalMarksDialog() {
    final totalCtrl = TextEditingController(text: _totalMarks.toString());
    final passCtrl = TextEditingController(text: _passingMarks.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Configure Exam Marks", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: totalCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Total Maximum Marks",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Passing Marks",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final newTotal = int.tryParse(totalCtrl.text.trim());
              final newPass = int.tryParse(passCtrl.text.trim());
              if (newTotal != null && newTotal > 0) {
                setState(() {
                  _totalMarks = newTotal;
                  _passingMarks = newPass ?? (_totalMarks * 0.33).toInt();
                });
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5)),
            child: const Text("Apply", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
