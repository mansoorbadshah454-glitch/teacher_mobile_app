import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/next_class/providers/next_class_provider.dart';
import 'package:teacher_mobile_app/features/next_class/presentation/widgets/student_score_card.dart';
import 'package:teacher_mobile_app/features/next_class/presentation/widgets/class_card.dart';
import 'package:teacher_mobile_app/features/next_class/services/pdf_generator_service.dart';
import 'package:teacher_mobile_app/features/timetable/providers/timetable_provider.dart';
import 'package:teacher_mobile_app/features/next_class/utils/test_report_pdf_generator.dart';
import 'package:share_plus/share_plus.dart';

class NextClassScreen extends ConsumerWidget {
  const NextClassScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nextClassProvider);
    final notifier = ref.read(nextClassProvider.notifier);
    final teacherData = ref.watch(teacherDataProvider).value;
    final schoolData = ref.watch(schoolDataProvider).value;
    final timetableSlots = ref.watch(timetableProvider).value ?? [];

    final isLight = Theme.of(context).brightness == Brightness.light;

    return PopScope(
      canPop: state.viewMode == NextClassViewMode.classes,
      onPopInvoked: (didPop) {
        if (!didPop) {
          notifier.goBack();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(context, state, notifier),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildBody(context, state, notifier, teacherData, schoolData, timetableSlots),
                ),
              ),
            ],
          ),
          
          // Floating Save Button for Students mode
          if (state.viewMode == NextClassViewMode.students && state.scoreUpdates.isNotEmpty)
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: TweenAnimationBuilder(
                tween: Tween<double>(begin: 100, end: 0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                builder: (context, double val, child) {
                  return Transform.translate(
                    offset: Offset(0, val),
                    child: child,
                  );
                },
                child: GestureDetector(
                  onTap: state.isSaving ? null : () => notifier.saveAllScores(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: isLight ? const Color(0xFF6366f1) : AppTheme.primary,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: (isLight ? const Color(0xFF6366f1) : AppTheme.primary).withOpacity(0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: state.isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            "Save Changes (${state.scoreUpdates.length})",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, NextClassState state, NextClassNotifier notifier) {
    String title = "My Classes";
    String subtitle = "Select an assigned class";
    bool showActionButtons = false;

    if (state.viewMode == NextClassViewMode.subjects) {
      title = state.selectedClass?['name'] ?? "Subjects";
      subtitle = "Select a subject";
    } else if (state.viewMode == NextClassViewMode.students) {
      title = state.selectedSubject ?? "Students";
      subtitle = "${state.selectedClass?['name']} • ${state.students.length} Students";
      showActionButtons = true;
    } else if (state.viewMode == NextClassViewMode.homework) {
      title = "Homework Dashboard";
      subtitle = "${state.selectedSubject} • Reports & Tasks";
    } else if (state.viewMode == NextClassViewMode.assignHomework) {
      title = "Assign Homework";
      subtitle = "${state.selectedSubject} • New Assignment";
    } else if (state.viewMode == NextClassViewMode.scheduleTest) {
      title = "Test Dashboard";
      subtitle = "${state.selectedSubject} • Reports & Assessments";
    } else if (state.viewMode == NextClassViewMode.test) {
      title = "Schedule Test";
      subtitle = "${state.selectedSubject} • New Assessment";
    } else if (state.viewMode == NextClassViewMode.activeTestScore) {
      title = "Record Scores";
      subtitle = "${state.selectedSubject} • ${state.activeScheduledTest?['testType'] ?? ''} Test";
    }
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12, 
        bottom: showActionButtons ? 14 : 16, 
        left: 16, 
        right: 16,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF10b981), Color(0xFF059669)], // Emerald/Green theme
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 6, offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (state.viewMode == NextClassViewMode.classes) {
                    context.pop();
                  } else {
                    notifier.goBack();
                  }
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2), // Transparent white
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.chevron_left, color: Colors.white),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.85),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showActionButtons) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => notifier.goToHomeworkMode(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.assignment_outlined, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            "Homework",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => notifier.goToScheduleTestMode(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.quiz_outlined, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            "Test",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, NextClassState state, NextClassNotifier notifier, Map<String, dynamic>? teacherData, Map<String, dynamic>? schoolData, List<TimetableSlot> timetableSlots) {
    if (state.isLoading && state.classes.isEmpty && state.students.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    switch (state.viewMode) {
      case NextClassViewMode.classes:
        return _buildClassesView(context, state, notifier, timetableSlots);
      case NextClassViewMode.subjects:
        return _buildSubjectsView(context, state, notifier, timetableSlots);
      case NextClassViewMode.students:
        return _buildStudentsView(context, state, notifier);
      case NextClassViewMode.homework:
        return _buildHomeworkDashboardView(context, state, notifier, teacherData, schoolData);
      case NextClassViewMode.assignHomework:
        return _buildAssignHomeworkFormView(context, state, notifier);
      case NextClassViewMode.scheduleTest:
        return _buildTestDashboardView(context, state, notifier, teacherData, schoolData);
      case NextClassViewMode.test:
        return _buildScheduleTestFormView(context, state, notifier);
      case NextClassViewMode.activeTestScore:
        return _buildActiveTestScoreView(context, state, notifier, teacherData, schoolData);
    }
  }

  Widget _buildClassesView(BuildContext context, NextClassState state, NextClassNotifier notifier, List<TimetableSlot> timetableSlots) {
    if (state.isLoading && state.classes.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    // Filter classes to only those assigned to the teacher in the timetable
    final assignedClasses = state.classes.where((cls) {
      final clsName = (cls['name'] ?? '').toString().trim().toLowerCase();
      return timetableSlots.any((slot) =>
          !slot.isFree &&
          !slot.isBreak &&
          slot.className.trim().toLowerCase() == clsName);
    }).toList();

    if (assignedClasses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF10b981).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_busy_rounded, color: Color(0xFF10b981), size: 42),
              ),
              const SizedBox(height: 18),
              const Text(
                "No Assigned Classes",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "No timetable periods are assigned to you for any class yet. Please contact your principal to update the school timetable.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: assignedClasses.length,
      itemBuilder: (context, index) {
        final cls = assignedClasses[index];
        final clsName = (cls['name'] ?? '').toString().trim().toLowerCase();
        final assignedSlots = timetableSlots.where((slot) =>
            !slot.isFree &&
            !slot.isBreak &&
            slot.className.trim().toLowerCase() == clsName).toList();

        return ClassCard(
          cls: cls,
          assignedSlots: assignedSlots,
          onTap: () => notifier.selectClass(cls),
        );
      },
    );
  }

  Widget _buildSubjectsView(BuildContext context, NextClassState state, NextClassNotifier notifier, List<TimetableSlot> timetableSlots) {
    final subjects = List<String>.from(state.selectedClass?['subjects'] ?? []);
    final className = (state.selectedClass?['name'] ?? '').toString().trim();

    if (subjects.isEmpty) {
      return const Center(
        child: Text("No subjects found for this class.", style: TextStyle(color: Colors.grey)),
      );
    }

    // Sort subjects so assigned subjects appear first
    final sortedSubjects = List<String>.from(subjects)
      ..sort((a, b) {
        final aAssigned = timetableSlots.any((slot) =>
            !slot.isFree &&
            !slot.isBreak &&
            slot.className.trim().toLowerCase() == className.toLowerCase() &&
            slot.subject.trim().toLowerCase() == a.trim().toLowerCase());
        final bAssigned = timetableSlots.any((slot) =>
            !slot.isFree &&
            !slot.isBreak &&
            slot.className.trim().toLowerCase() == className.toLowerCase() &&
            slot.subject.trim().toLowerCase() == b.trim().toLowerCase());
        if (aAssigned && !bAssigned) return -1;
        if (!aAssigned && bAssigned) return 1;
        return a.compareTo(b);
      });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedSubjects.length,
      itemBuilder: (context, index) {
        final isLight = Theme.of(context).brightness == Brightness.light;
        final isDark = !isLight;
        final subject = sortedSubjects[index];
        final assignedSlots = timetableSlots.where((slot) =>
            !slot.isFree &&
            !slot.isBreak &&
            slot.className.trim().toLowerCase() == className.toLowerCase() &&
            slot.subject.trim().toLowerCase() == subject.trim().toLowerCase()).toList();
        final isAssigned = assignedSlots.isNotEmpty;

        return GestureDetector(
          onTap: isAssigned ? () => notifier.selectSubject(subject) : () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("No period assigned on timetable for this specific subject/class.")),
            );
          },
          child: Opacity(
            opacity: isAssigned ? 1.0 : 0.5,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isAssigned
                    ? (isDark ? Colors.white.withOpacity(0.05) : Colors.white)
                    : (isDark ? Colors.black.withOpacity(0.2) : Colors.grey[100]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isAssigned
                      ? (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05))
                      : Colors.transparent,
                ),
                boxShadow: isLight && isAssigned ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))] : [],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10b981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.menu_book_rounded, color: Color(0xFF10b981), size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.indigo[900],
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isAssigned) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: assignedSlots.map((s) => Text(
                              "${s.period}${s.time.isNotEmpty ? ' (${s.time})' : ''}",
                              style: const TextStyle(
                                color: Color(0xFF059669),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            )).toList(),
                          ),
                        ] else
                          const Text(
                            "No Period on Timetable",
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isAssigned)
                    const Icon(Icons.chevron_right, color: Colors.grey)
                  else
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.lock, color: Colors.grey, size: 14),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentsView(BuildContext context, NextClassState state, NextClassNotifier notifier) {
    if (state.isLoading) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor));
    }

    final filteredStudents = state.students.where((s) {
      final name = (s['name'] ?? '').toString().toLowerCase();
      final roll = (s['rollNo'] ?? '').toString().toLowerCase();
      final q = state.searchTerm.toLowerCase();
      return name.contains(q) || roll.contains(q);
    }).toList();

    // Calculate Averages
    int totalAc = 0;
    int totalHw = 0;
    for (var s in state.students) {
      totalAc += notifier.getStudentScore(s, 'academic');
      totalHw += notifier.getStudentScore(s, 'homework');
    }
    final avgAc = state.students.isEmpty ? 0 : (totalAc / state.students.length).round();
    final avgHw = state.students.isEmpty ? 0 : (totalHw / state.students.length).round();
    final bool hasActiveHw = state.activeHomework != null &&
        state.activeHomework!.isNotEmpty &&
        state.activeHomework!['subject'] == state.selectedSubject;

    return Column(
      children: [
        // Unified Performance & Homework Horizontal Card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildUnifiedPerformanceCard(
            context: context,
            subjectPerformance: avgAc,
            homeworkScore: avgHw,
            isDark: Theme.of(context).brightness == Brightness.dark,
          ),
        ),
        
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.transparent : Colors.black.withOpacity(0.05)),
              boxShadow: Theme.of(context).brightness == Brightness.light ? [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))] : [],
            ),
            child: TextField(
              onChanged: notifier.setSearchTerm,
              style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
              decoration: const InputDecoration(
                icon: Icon(Icons.search, color: Colors.grey, size: 20),
                border: InputBorder.none,
                hintText: "Search student...",
                hintStyle: TextStyle(color: Colors.grey),
              ),
            ),
          ),
        ),

        // Student List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 100), // padding for FAB
            itemCount: filteredStudents.length,
            itemBuilder: (context, index) {
              final student = filteredStudents[index];
              return StudentScoreCard(
                student: student,
                academicScore: notifier.getStudentScore(student, 'academic'),
                homeworkScore: notifier.getStudentHomeworkStatus(student),
                hasActiveHomework: hasActiveHw,
                onScoreChanged: notifier.updateScore,
              );
            },
          ),
        ),
      ],
    );
  }


  Widget _buildUnifiedPerformanceCard({
    required BuildContext context,
    required int subjectPerformance,
    required int homeworkScore,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Row(
        children: [
          // Left: Subject Performance
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "$subjectPerformance%",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF1E3A8A),
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Subject Performance",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Center Divider
          Container(
            height: 32,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: isDark ? Colors.white.withOpacity(0.12) : Colors.grey[200],
          ),

          // Right: Homework Score
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.assignment_rounded,
                    color: Color(0xFFD97706),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "$homeworkScore%",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF92400E),
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Homework Score",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildScheduleTestFormView(BuildContext context, NextClassState state, NextClassNotifier notifier) {
    if (state.isFetchingTest) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Test Type Chips
          Text("Test Type", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.indigo[900])),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['Written', 'Oral', 'Practical', 'Surprise'].map((type) {
                final isSelected = state.testType == type;
                return GestureDetector(
                  onTap: () => notifier.setTestType(type),
                  child: Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF6366f1) : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isSelected ? Colors.transparent : (isDark ? Colors.transparent : Colors.grey[300]!)),
                    ),
                    child: Text(
                      type,
                      style: TextStyle(
                        color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),

          // Chapter and Paragraphs
          _buildInputSection(
            context,
            title: "Chapter Name",
            hint: "e.g., Chapter 4: Photosynthesis",
            icon: Icons.menu_book,
            onChanged: notifier.setTestChapter,
            initialValue: state.testChapter,
          ),
          const SizedBox(height: 16),
          _buildInputSection(
            context,
            title: "Paragraph / Topic Details",
            hint: "e.g., Paragraphs 1 to 5",
            icon: Icons.format_list_bulleted,
            onChanged: notifier.setScheduleParagraphs,
            initialValue: state.scheduleParagraphs,
          ),
          const SizedBox(height: 16),
          _buildInputSection(
            context,
            title: "Max Marks",
            hint: "10",
            icon: Icons.score,
            isNumber: true,
            onChanged: (val) => notifier.setMaxMarks(int.tryParse(val) ?? 10),
            initialValue: state.maxMarks.toString(),
          ),
          const SizedBox(height: 24),

          // Date and Time Row
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: state.scheduleDate ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) notifier.setScheduleDate(date);
                  },
                  child: _buildDateTimeWidget(
                    context, 
                    title: "Date",
                    value: state.scheduleDate != null ? "${state.scheduleDate!.day}/${state.scheduleDate!.month}/${state.scheduleDate!.year}" : "Select Date",
                    icon: Icons.calendar_today,
                    isSelected: state.scheduleDate != null,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: state.scheduleTime ?? TimeOfDay.now(),
                    );
                    if (time != null) notifier.setScheduleTime(time);
                  },
                  child: _buildDateTimeWidget(
                    context, 
                    title: "Time",
                    value: state.scheduleTime != null ? state.scheduleTime!.format(context) : "Select Time",
                    icon: Icons.access_time,
                    isSelected: state.scheduleTime != null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),

          // Save Button
          GestureDetector(
            onTap: state.isSaving ? null : () async {
               if (state.testChapter.isEmpty || state.scheduleDate == null || state.scheduleTime == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please select a Date, Time, and Chapter")),
                  );
                  return;
               }
               try {
                 final synced = await notifier.saveScheduledTest();
                 if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(
                       content: Text(synced 
                           ? "Test scheduled and parents alerted!" 
                           : "Test saved offline! Parents will be alerted once online."),
                       backgroundColor: const Color(0xFF10B981),
                     ),
                   );
                 }
               } catch (e) {
                 if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(
                       content: Text("Failed to schedule test: $e"),
                       backgroundColor: Colors.red,
                     ),
                   );
                 }
               }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366f1), Color(0xFF4f46e5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF6366f1).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 8)),
                ],
              ),
              alignment: Alignment.center,
              child: state.isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Schedule & Alert Parents", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 100), // padding
        ],
      ),
    );
  }

  Widget _buildInputSection(BuildContext context, {required String title, required String hint, required IconData icon, required Function(String) onChanged, String? initialValue, bool isNumber = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white70 : Colors.grey[700])),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? Colors.transparent : Colors.grey[200]!),
          ),
          child: TextFormField(
            initialValue: initialValue,
            onChanged: onChanged,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
            decoration: InputDecoration(
              icon: Icon(icon, color: const Color(0xFF6366f1), size: 20),
              border: InputBorder.none,
              hintText: hint,
              hintStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateTimeWidget(BuildContext context, {required String title, required String value, required IconData icon, required bool isSelected}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF6366f1).withOpacity(0.1) : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isSelected ? const Color(0xFF6366f1).withOpacity(0.5) : (isDark ? Colors.transparent : Colors.grey[200]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: isSelected ? const Color(0xFF6366f1) : Colors.grey, size: 24),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black)),
        ],
      ),
    );
  }


  Widget _buildTestDashboardView(BuildContext context, NextClassState state, NextClassNotifier notifier, Map<String, dynamic>? teacherData, Map<String, dynamic>? schoolData) {
    if (state.isFetchingTest && state.testReportsList.isEmpty && (state.activeScheduledTest == null || state.activeScheduledTest!.isEmpty)) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasActiveTest = state.activeScheduledTest != null && state.activeScheduledTest!.isNotEmpty;
    final testReports = state.testReportsList;

    const int pageSize = 4;
    final int totalReports = testReports.length;
    final int totalPages = totalReports > 0 ? ((totalReports + pageSize - 1) ~/ pageSize) : 1;
    final int rawPage = state.testReportsPageIndex;
    final int currentPage = rawPage.clamp(0, totalPages - 1);
    final int startIndex = currentPage * pageSize;
    final int endIndex = (startIndex + pageSize < totalReports) ? (startIndex + pageSize) : totalReports;
    final List<Map<String, dynamic>> currentReports = totalReports > 0 ? testReports.sublist(startIndex, endIndex) : [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. STICKY TOP HERO CARD (Active or Schedule) - Always fixed at the top
          if (hasActiveTest)
            _buildActiveTestHeroCard(context, state, notifier)
          else
            _buildNoActiveTestBanner(context, notifier, isDark),
          const SizedBox(height: 16),

          // 2. TEST REPORTS & HISTORY HEADER
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366f1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.analytics_outlined, color: Color(0xFF6366f1), size: 19),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Test Reports & History",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.indigo[950],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.indigo[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.indigo[100]!),
                ),
                child: Text(
                  "$totalReports ${totalReports == 1 ? 'Report' : 'Reports'}",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.indigo[300] : Colors.indigo[600]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. PAGINATED REPORTS (4 items per page with horizontal swipe & bottom > navigation)
          Expanded(
            child: testReports.isEmpty
                ? SingleChildScrollView(child: _buildEmptyReportsCard(context, isDark))
                : GestureDetector(
                    onHorizontalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity < -250 && currentPage < totalPages - 1) {
                        notifier.setTestReportsPage(currentPage + 1);
                      } else if (velocity > 250 && currentPage > 0) {
                        notifier.setTestReportsPage(currentPage - 1);
                      }
                    },
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 6),
                            itemCount: currentReports.length,
                            itemBuilder: (context, idx) {
                              return _buildTestReportCard(
                                context,
                                currentReports[idx],
                                state,
                                notifier,
                                teacherData,
                                schoolData,
                              );
                            },
                          ),
                        ),

                        // Bottom Navigation Bar (Shows < Prev, Page pill, and > Next button)
                        if (totalPages > 1)
                          _buildReportsPaginationBar(
                            context: context,
                            currentPage: currentPage,
                            totalPages: totalPages,
                            startNum: startIndex + 1,
                            endNum: endIndex,
                            totalCount: totalReports,
                            notifier: notifier,
                            isDark: isDark,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportsPaginationBar({
    required BuildContext context,
    required int currentPage,
    required int totalPages,
    required int startNum,
    required int endNum,
    required int totalCount,
    required NextClassNotifier notifier,
    required bool isDark,
  }) {
    final bool hasPrev = currentPage > 0;
    final bool hasNext = currentPage < totalPages - 1;

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
              ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Prev button (<)
          GestureDetector(
            onTap: hasPrev ? () => notifier.setTestReportsPage(currentPage - 1) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: hasPrev
                    ? (isDark ? Colors.white.withOpacity(0.08) : Colors.indigo[50])
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_back_ios_rounded,
                    size: 13,
                    color: hasPrev ? const Color(0xFF6366f1) : Colors.grey[400],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "Prev",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hasPrev ? const Color(0xFF6366f1) : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Page pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF6366f1).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              "$startNum–$endNum of $totalCount (Page ${currentPage + 1}/$totalPages)",
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6366f1),
              ),
            ),
          ),

          // Next button (">")
          GestureDetector(
            onTap: hasNext ? () => notifier.setTestReportsPage(currentPage + 1) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: hasNext
                    ? const Color(0xFF6366f1)
                    : (isDark ? Colors.white.withOpacity(0.03) : Colors.grey[200]),
                borderRadius: BorderRadius.circular(8),
                boxShadow: hasNext
                    ? [
                        BoxShadow(
                          color: const Color(0xFF6366f1).withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  Text(
                    "Next",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hasNext ? Colors.white : Colors.grey[400],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: hasNext ? Colors.white : Colors.grey[400],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoActiveTestBanner(BuildContext context, NextClassNotifier notifier, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
        boxShadow: isDark ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366f1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.quiz_outlined, color: Color(0xFF6366f1), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "No Active Test",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.indigo[950],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Schedule a test to assess students and notify parents.",
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => notifier.goToScheduleTestForm(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366f1), Color(0xFF4f46e5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF6366f1).withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 6)),
                ],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text("Schedule New Test", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTestHeroCard(BuildContext context, NextClassState state, NextClassNotifier notifier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final test = state.activeScheduledTest!;
    final recordedCount = notifier.getTestDraftRecordedCount();
    final isResuming = recordedCount > 0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
        boxShadow: isDark ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // Top gradient header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6366f1), Color(0xFF4f46e5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${test['testType'] ?? 'Written'} Test",
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (test['isPendingSync'] == true)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.sync, color: Colors.amber, size: 12),
                            SizedBox(width: 4),
                            Text("Offline", style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isResuming ? "In Progress" : "Scheduled",
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  test['chapter'] ?? 'Chapter Test',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if ((test['paragraphs'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    "Topic: ${test['paragraphs']}",
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.calendar_today, color: Colors.white.withOpacity(0.8), size: 14),
                    const SizedBox(width: 4),
                    Text(
                      test['dateStr'] ?? '',
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                    ),
                    const SizedBox(width: 14),
                    Icon(Icons.access_time, color: Colors.white.withOpacity(0.8), size: 14),
                    const SizedBox(width: 4),
                    Text(
                      test['timeStr'] ?? '',
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      "Max: ${test['maxMarks'] ?? 10} M",
                      style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions inside Active card
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                GestureDetector(
                  onTap: state.isSaving ? null : () => notifier.goToActiveTestScoreMode(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isResuming
                            ? const [Color(0xFFF59E0B), Color(0xFFD97706)]
                            : const [Color(0xFF6366f1), Color(0xFF4f46e5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: (isResuming ? const Color(0xFFF59E0B) : const Color(0xFF6366f1)).withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isResuming ? Icons.play_circle_fill_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isResuming ? "Resume Test ($recordedCount Recorded)" : "Start Test",
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton.icon(
                      onPressed: state.isSaving ? null : () => _showCancelDialog(context, notifier),
                      icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                      label: const Text("Cancel Test", style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    TextButton.icon(
                      onPressed: state.isSaving ? null : () => notifier.completeScheduledTest(),
                      icon: const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF10b981)),
                      label: const Text("Mark Complete", style: TextStyle(color: Color(0xFF10b981), fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyReportsCard(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(Icons.folder_open_rounded, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            "No Test Reports Yet",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.indigo[950]),
          ),
          const SizedBox(height: 4),
          Text(
            "Once you complete and save a test, official reports and results will appear here.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTestReportCard(
    BuildContext context,
    Map<String, dynamic> report,
    NextClassState state,
    NextClassNotifier notifier,
    Map<String, dynamic>? teacherData,
    Map<String, dynamic>? schoolData,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxMarks = report['maxMarks'] ?? 10;
    final int presentCount = (report['presentCount'] is int)
        ? report['presentCount']
        : ((report['scores'] as Map?)?.length ?? 0);
    final int absentCount = (report['absentCount'] is int)
        ? report['absentCount']
        : ((report['absentStudents'] as List?)?.length ?? 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
        boxShadow: isDark ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.assignment_turned_in, color: Color(0xFF10B981), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report['chapter'] ?? report['subject'] ?? 'Completed Test',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.indigo[950],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${report['testType'] ?? 'Written'} • ${report['dateStr'] ?? ''}",
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  "Completed",
                  style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Chips
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline, size: 13, color: Color(0xFF10B981)),
                    const SizedBox(width: 4),
                    Text("$presentCount Present", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF10B981))),
                  ],
                ),
              ),
              if (absentCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_off_outlined, size: 13, color: Colors.red[700]),
                      const SizedBox(width: 4),
                      Text("$absentCount Absent", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red[700])),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text("Max: $maxMarks M", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.grey[700])),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    _showTestReportModal(
                      context: context,
                      report: report,
                      state: state,
                      notifier: notifier,
                      teacherData: teacherData,
                      schoolData: schoolData,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.08) : Colors.indigo[50],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.visibility_outlined, size: 16, color: isDark ? Colors.indigo[300] : Colors.indigo[700]),
                        const SizedBox(width: 6),
                        Text(
                          "View Report",
                          style: TextStyle(
                            color: isDark ? Colors.indigo[300] : Colors.indigo[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () async {
                  final scoresMap = <String, int>{};
                  if (report['scores'] is Map) {
                    (report['scores'] as Map).forEach((k, v) {
                      final val = int.tryParse(v?.toString() ?? '');
                      if (val != null) scoresMap[k.toString()] = val;
                    });
                  }
                  final absentSet = <String>{};
                  if (report['absentStudents'] is List) {
                    for (var id in report['absentStudents'] as List) {
                      absentSet.add(id.toString());
                    }
                  }

                  final file = await TestReportPdfGenerator.generateReport(
                    schoolData: schoolData ?? {},
                    teacherData: teacherData ?? {},
                    testData: report,
                    students: state.students,
                    testScores: scoresMap,
                    absentStudents: absentSet,
                  );
                  await Share.shareXFiles([XFile(file.path)], text: "Test Report for ${report['subject']} - ${report['chapter']}");
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? Colors.transparent : Colors.grey[300]!),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.picture_as_pdf, size: 16, color: Color(0xFFEF4444)),
                      SizedBox(width: 4),
                      Text("PDF", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFEF4444))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showTestReportModal({
    required BuildContext context,
    required Map<String, dynamic> report,
    required NextClassState state,
    required NextClassNotifier notifier,
    required Map<String, dynamic>? teacherData,
    required Map<String, dynamic>? schoolData,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxMarks = report['maxMarks'] ?? 10;
    int maxM = (maxMarks is int) ? maxMarks : int.tryParse(maxMarks.toString()) ?? 10;

    final Map<String, int> testScores = {};
    if (report['scores'] is Map) {
      (report['scores'] as Map).forEach((k, v) {
        final val = int.tryParse(v?.toString() ?? '');
        if (val != null) testScores[k.toString()] = val;
      });
    }
    final Set<String> absentStudents = {};
    if (report['absentStudents'] is List) {
      for (var id in report['absentStudents'] as List) {
        absentStudents.add(id.toString());
      }
    }

    // Ranking Logic
    List<Map<String, dynamic>> rankedStudents = [];
    List<Map<String, dynamic>> absentList = [];

    for (var s in state.students) {
      final sId = s['id']?.toString() ?? '';
      if (absentStudents.contains(sId)) {
        absentList.add({...s, 'isAbsent': true, 'rank': -1});
      } else {
        int score = testScores[sId] ?? 0;
        rankedStudents.add({...s, 'score': score, 'isAbsent': false});
      }
    }
    rankedStudents.sort((a, b) => ((b['score'] as int?) ?? 0).compareTo((a['score'] as int?) ?? 0));

    int trueRank = 1;
    int displayRank = 1;
    int prevScore = -1;

    for (var i = 0; i < rankedStudents.length; i++) {
      int score = rankedStudents[i]['score'] ?? 0;
      if (score != prevScore) {
        displayRank = trueRank;
      }
      rankedStudents[i]['rank'] = displayRank;
      prevScore = score;
      trueRank++;
    }

    final allDisplayStudents = [...rankedStudents, ...absentList];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            report['chapter'] ?? report['subject'] ?? 'Test Report',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.indigo[950],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            "${report['subject']} • ${report['testType'] ?? 'Written'} • ${report['dateStr'] ?? ''} • Max: $maxM",
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final file = await TestReportPdfGenerator.generateReport(
                            schoolData: schoolData ?? {},
                            teacherData: teacherData ?? {},
                            testData: report,
                            students: state.students,
                            testScores: testScores,
                            absentStudents: absentStudents,
                          );
                          await Share.shareXFiles([XFile(file.path)], text: "Test Report for ${report['subject']} - ${report['chapter']}");
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.picture_as_pdf, color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text("Share PDF", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          _showEditTestScoresDialog(
                            context: context,
                            report: report,
                            state: state,
                            notifier: notifier,
                            initialScores: testScores,
                            initialAbsent: absentStudents,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366f1),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF6366f1).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3)),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.edit, color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text("Edit Scores", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: allDisplayStudents.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final s = allDisplayStudents[index];
                    final bool isAbsent = s['isAbsent'] == true;
                    final int rank = s['rank'] ?? -1;
                    final int score = (s['score'] as int?) ?? 0;
                    double percent = maxM > 0 ? (score / maxM) * 100 : 0.0;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: isAbsent
                                ? Text("-", style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold, fontSize: 14))
                                : Text(
                                    rank == 1 ? "🥇 1st" : (rank == 2 ? "🥈 2nd" : (rank == 3 ? "🥉 3rd" : "$rank")),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: rank <= 3 ? 12 : 14,
                                      color: rank == 1 ? Colors.amber[800] : (isDark ? Colors.white70 : Colors.black87),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s['name'] ?? 'Student',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isDark ? Colors.white : Colors.black87),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text("Roll No: ${s['rollNo'] ?? '-'}", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isAbsent ? Colors.red.withOpacity(0.1) : const Color(0xFF10B981).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isAbsent ? "ABS" : "$score / $maxM",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isAbsent ? Colors.red : const Color(0xFF10B981),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 48,
                            child: Text(
                              isAbsent ? "-" : "${percent.toStringAsFixed(0)}%",
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                color: isAbsent ? Colors.grey[400] : (isDark ? Colors.white70 : Colors.black87),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditTestScoresDialog({
    required BuildContext context,
    required Map<String, dynamic> report,
    required NextClassState state,
    required NextClassNotifier notifier,
    required Map<String, int> initialScores,
    required Set<String> initialAbsent,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxMarks = report['maxMarks'] ?? 10;
    int maxM = (maxMarks is int) ? maxMarks : int.tryParse(maxMarks.toString()) ?? 10;

    final Map<String, int> editScores = Map<String, int>.from(initialScores);
    final Set<String> editAbsent = Set<String>.from(initialAbsent);
    bool notifyParents = false;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.90,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Edit Test Scores",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.indigo[950],
                                ),
                              ),
                              Text(
                                "${report['subject']} • ${report['chapter'] ?? ''} • Max: $maxM",
                                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: state.students.length,
                      itemBuilder: (context, index) {
                        final student = state.students[index];
                        final studentId = student['id']?.toString() ?? '';
                        final bool isAbsent = editAbsent.contains(studentId);
                        double currentScore = (editScores[studentId] ?? 0).toDouble();

                        Color sliderColor;
                        double percentage = maxM > 0 ? currentScore / maxM : 0.0;
                        if (isAbsent) {
                          sliderColor = const Color(0xFFEF4444);
                        } else if (percentage <= 0.3) {
                          sliderColor = const Color(0xFFEF4444);
                        } else if (percentage <= 0.6) {
                          sliderColor = const Color(0xFFF59E0B);
                        } else {
                          sliderColor = const Color(0xFF10B981);
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isAbsent
                                ? (isDark ? Colors.red.withOpacity(0.08) : const Color(0xFFFEF2F2))
                                : (isDark ? Colors.white.withOpacity(0.04) : Colors.grey[50]),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isAbsent ? Colors.red.withOpacity(0.3) : (isDark ? Colors.transparent : Colors.grey[200]!),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isAbsent ? Colors.red.withOpacity(0.15) : const Color(0xFF6366f1).withOpacity(0.1),
                                    radius: 18,
                                    child: Text(
                                      student['name']?.substring(0, 1).toUpperCase() ?? "?",
                                      style: TextStyle(color: isAbsent ? Colors.red : const Color(0xFF6366f1), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          student['name'] ?? 'Student',
                                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDark ? Colors.white : Colors.black87),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text("Roll No: ${student['rollNo'] ?? '-'}", style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      setModalState(() {
                                        if (editAbsent.contains(studentId)) {
                                          editAbsent.remove(studentId);
                                        } else {
                                          editAbsent.add(studentId);
                                          editScores.remove(studentId);
                                        }
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isAbsent ? Colors.red : (isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        "ABS",
                                        style: TextStyle(
                                          color: isAbsent ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[700]),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isAbsent ? Colors.red.withOpacity(0.1) : sliderColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isAbsent ? "ABSENT" : "${currentScore.toInt()} / $maxM",
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isAbsent ? Colors.red : sliderColor),
                                    ),
                                  ),
                                ],
                              ),
                              if (!isAbsent)
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: sliderColor,
                                    thumbColor: sliderColor,
                                    inactiveTrackColor: sliderColor.withOpacity(0.2),
                                    trackHeight: 4,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                                  ),
                                  child: Slider(
                                    value: currentScore,
                                    min: 0,
                                    max: maxM.toDouble(),
                                    divisions: maxM > 0 ? maxM : 1,
                                    onChanged: (val) {
                                      setModalState(() {
                                        editScores[studentId] = val.toInt();
                                        editAbsent.remove(studentId);
                                      });
                                    },
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.03) : Colors.grey[50],
                      border: Border(top: BorderSide(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: notifyParents,
                              activeColor: const Color(0xFF6366f1),
                              onChanged: (v) {
                                setModalState(() => notifyParents = v ?? false);
                              },
                            ),
                            Expanded(
                              child: Text(
                                "Notify parents about updated marks",
                                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.grey[800]),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: isSaving
                              ? null
                              : () async {
                                  setModalState(() => isSaving = true);
                                  final success = await notifier.updateCompletedTestScores(
                                    testId: report['id'],
                                    updatedScores: editScores,
                                    updatedAbsent: editAbsent,
                                    notifyParents: notifyParents,
                                  );
                                  if (context.mounted) {
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(success ? "Test report updated successfully!" : "Failed to update test report"),
                                        backgroundColor: success ? const Color(0xFF10B981) : Colors.red,
                                      ),
                                    );
                                  }
                                },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6366f1), Color(0xFF4f46e5)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: isSaving
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text("Save & Apply Updates", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  void _showCancelDialog(BuildContext context, NextClassNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.surfaceDark : Colors.white,
        title: Text("Cancel Test?", style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.indigo[900])),
        content: Text("Are you sure you want to cancel this scheduled test? Parents will be notified immediately.", style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey : Colors.grey[600])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Keep Test", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.cancelScheduledTest();
            },
            child: const Text("Cancel Test", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTestScoreView(BuildContext context, NextClassState state, NextClassNotifier notifier, Map<String, dynamic>? teacherData, Map<String, dynamic>? schoolData) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final test = state.activeScheduledTest;
    
    if (test == null || test.isEmpty) return const Center(child: Text("No test available."));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Simplified Details Widget (Top)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366f1), Color(0xFF4f46e5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.assignment, color: Colors.white, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${test['subject']} • ${test['testType']}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text("Chapter: ${test['chapter']}", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                      const SizedBox(height: 2),
                      Text("Topic: ${test['paragraphs']}", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                      const SizedBox(height: 4),
                      Text("Max Marks: ${test['maxMarks'] ?? 10}", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Enter Test Scores", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.indigo[900])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.08) : Colors.indigo[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.indigo[100]!),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 14, color: isDark ? Colors.indigo[300] : Colors.indigo[600]),
                    const SizedBox(width: 4),
                    Text(
                      "${state.testScores.length + state.absentTestStudents.length} / ${state.students.length} Recorded",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isDark ? Colors.indigo[300] : Colors.indigo[600]),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Students List
          ...state.students.map((student) {
            final studentId = student['id'];
            final maxMarks = test['maxMarks'] ?? 10;
            int maxM = (maxMarks is int) ? maxMarks : int.tryParse(maxMarks.toString()) ?? 10;
            final bool isAbsent = state.absentTestStudents.contains(studentId);
            final bool hasScore = state.testScores.containsKey(studentId);
            double currentScore = (state.testScores[studentId] ?? 0).toDouble();

            Color sliderColor;
            double percentage = maxM > 0 ? currentScore / maxM : 0.0;
            if (isAbsent) {
              sliderColor = const Color(0xFFEF4444); // Red
            } else if (!hasScore) {
              sliderColor = isDark ? Colors.grey[600]! : Colors.grey[400]!;
            } else if (percentage <= 0.3) {
              sliderColor = const Color(0xFFEF4444); // Red
            } else if (percentage <= 0.6) {
              sliderColor = const Color(0xFFF59E0B); // Amber/Yellow
            } else {
              sliderColor = const Color(0xFF10B981); // Emerald/Green
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isAbsent
                    ? (isDark ? Colors.red.withOpacity(0.08) : const Color(0xFFFEF2F2))
                    : (isDark ? Colors.white.withOpacity(0.05) : Colors.white),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isAbsent
                      ? Colors.red.withOpacity(0.3)
                      : (isDark ? Colors.transparent : Colors.grey[200]!),
                ),
                boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: isAbsent
                            ? Colors.red.withOpacity(0.15)
                            : const Color(0xFF6366f1).withOpacity(0.1),
                        radius: 20,
                        child: Text(
                          student['name']?.substring(0, 1).toUpperCase() ?? "?",
                          style: TextStyle(
                            color: isAbsent ? Colors.red : const Color(0xFF6366f1),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              student['name'] ?? 'Unknown',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text("Roll No: ${student['rollNo'] ?? '-'}", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // ABS Toggle button
                      GestureDetector(
                        onTap: () {
                          notifier.toggleTestAbsent(studentId);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isAbsent ? Colors.red : (isDark ? Colors.white.withOpacity(0.08) : Colors.grey[100]),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isAbsent ? Colors.red : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                            ),
                          ),
                          child: Text(
                            "ABS",
                            style: TextStyle(
                              color: isAbsent ? Colors.white : (isDark ? Colors.grey[400] : Colors.grey[700]),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isAbsent
                              ? Colors.red.withOpacity(0.1)
                              : (hasScore ? sliderColor.withOpacity(0.1) : (isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100])),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isAbsent
                                ? Colors.red.withOpacity(0.3)
                                : (hasScore ? sliderColor.withOpacity(0.3) : (isDark ? Colors.grey[700]! : Colors.grey[300]!)),
                          ),
                        ),
                        child: Text(
                          isAbsent
                              ? "ABSENT"
                              : (hasScore ? "${currentScore.toInt()} / $maxM" : "Pending"),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isAbsent
                                ? Colors.red
                                : (hasScore ? sliderColor : (isDark ? Colors.grey[400] : Colors.grey[600])),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isAbsent)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person_off_rounded, size: 16, color: Colors.red[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Student marked as ABSENT for this test",
                              style: TextStyle(color: Colors.red[700], fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: sliderColor,
                        thumbColor: sliderColor,
                        inactiveTrackColor: sliderColor.withOpacity(0.2),
                        trackHeight: 6,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
                      ),
                      child: Slider(
                        value: currentScore,
                        min: 0,
                        max: maxM.toDouble(),
                        divisions: maxM > 0 ? maxM : 1,
                        onChanged: (val) {
                          notifier.updateTestScore(studentId, val.toInt());
                        },
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
          
          const SizedBox(height: 32),
          // Generate Report Button
          Builder(
            builder: (ctx) {
              bool allScoresSet = true;
              if (state.students.isEmpty) allScoresSet = false;
              for (var student in state.students) {
                final sId = student['id'];
                if (!state.testScores.containsKey(sId) && !state.absentTestStudents.contains(sId)) {
                  allScoresSet = false;
                  break;
                }
              }

              return GestureDetector(
                onTap: (!allScoresSet || state.isSaving) ? null : () async {
                  final file = await TestReportPdfGenerator.generateReport(
                    schoolData: schoolData ?? {},
                    teacherData: teacherData ?? {},
                    testData: test,
                    students: state.students,
                    testScores: state.testScores,
                    absentStudents: state.absentTestStudents,
                  );
                  await Share.shareXFiles([XFile(file.path)], text: "Test Report for ${test['subject']}");
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: allScoresSet ? const Color(0xFFF59E0B) : Colors.grey[400],
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: allScoresSet ? [BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 8))] : [],
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(allScoresSet ? Icons.picture_as_pdf : Icons.lock, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(allScoresSet ? "Generate Report" : "Generate Report (Set all scores)", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              );
            }
          ),
          
          GestureDetector(
            onTap: state.isSaving ? null : () {
               notifier.saveActiveTestScores(""); // Send default message defined in provider
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366f1), Color(0xFF4f46e5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: const Color(0xFF6366f1).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 8))],
              ),
              alignment: Alignment.center,
              child: state.isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("Save & Notify Parents", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildHomeworkDashboardView(BuildContext context, NextClassState state, NextClassNotifier notifier, Map<String, dynamic>? teacherData, Map<String, dynamic>? schoolData) {
    if (state.isFetchingHomework && state.homeworkList.isEmpty && (state.activeHomework == null || state.activeHomework!.isEmpty)) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeHw = state.activeHomework;
    final hasActiveHw = activeHw != null && activeHw.isNotEmpty;
    final homeworkReports = state.homeworkList;

    const int pageSize = 4;
    final int totalReports = homeworkReports.length;
    final int totalPages = totalReports > 0 ? ((totalReports + pageSize - 1) ~/ pageSize) : 1;
    final int rawPage = state.homeworkReportsPageIndex;
    final int currentPage = rawPage.clamp(0, totalPages - 1);
    final int startIndex = currentPage * pageSize;
    final int endIndex = (startIndex + pageSize < totalReports) ? (startIndex + pageSize) : totalReports;
    final List<Map<String, dynamic>> currentReports = totalReports > 0 ? homeworkReports.sublist(startIndex, endIndex) : [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. STICKY TOP HERO CARD (Active or Assign Homework)
          if (hasActiveHw)
            _buildActiveHomeworkHeroCard(context, state, notifier, activeHw, isDark)
          else
            _buildNoActiveHomeworkBanner(context, notifier, isDark),
          const SizedBox(height: 16),

          // 2. REPORTS HEADER (LAST 7 DAYS)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assignment_turned_in_outlined, color: Color(0xFFD97706), size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Homework Reports",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.indigo[950],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF59E0B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFF59E0B).withOpacity(0.2)),
                ),
                child: Text(
                  "$totalReports • 7 Days",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.amber[300] : const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. PAGINATED REPORTS (4 items per page with horizontal swipe & bottom pagination)
          Expanded(
            child: homeworkReports.isEmpty
                ? SingleChildScrollView(child: _buildEmptyHomeworkReportsCard(context, isDark, notifier))
                : GestureDetector(
                    onHorizontalDragEnd: (details) {
                      final velocity = details.primaryVelocity ?? 0;
                      if (velocity < -250 && currentPage < totalPages - 1) {
                        notifier.setHomeworkReportsPage(currentPage + 1);
                      } else if (velocity > 250 && currentPage > 0) {
                        notifier.setHomeworkReportsPage(currentPage - 1);
                      }
                    },
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 6),
                            itemCount: currentReports.length,
                            itemBuilder: (context, idx) {
                              return _buildHomeworkReportCard(
                                context,
                                currentReports[idx],
                                state,
                                notifier,
                                isDark,
                              );
                            },
                          ),
                        ),

                        // Bottom Navigation Bar
                        if (totalPages > 1)
                          _buildHomeworkPaginationBar(
                            context: context,
                            currentPage: currentPage,
                            totalPages: totalPages,
                            startNum: startIndex + 1,
                            endNum: endIndex,
                            totalCount: totalReports,
                            notifier: notifier,
                            isDark: isDark,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoActiveHomeworkBanner(BuildContext context, NextClassNotifier notifier, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
        boxShadow: isDark ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.assignment_add, color: Color(0xFFD97706), size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "No Active Homework",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.indigo[950],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Assign homework to keep students engaged and notify parents.",
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => notifier.goToAssignHomeworkMode(),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 6)),
                ],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.add_circle_outline, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text("Assign Homework", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveHomeworkHeroCard(BuildContext context, NextClassState state, NextClassNotifier notifier, Map<String, dynamic> activeHw, bool isDark) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
        boxShadow: isDark ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // Top gradient header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFD97706)], // Warm Amber
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.push_pin, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            "Active Homework",
                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        if (activeHw['isPendingSync'] == true)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text("Offline", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        GestureDetector(
                          onTap: () => _showHomeworkReportModal(
                            context: context,
                            hw: activeHw,
                            state: state,
                            notifier: notifier,
                            isDark: isDark,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.visibility_outlined, color: Colors.white, size: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => notifier.goToAssignHomeworkMode(editHw: activeHw),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.edit, color: Colors.white, size: 16),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _showDeleteHomeworkDialog(context, notifier, activeHw['id']),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                            child: const Icon(Icons.delete_outline, color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if ((activeHw['chapter'] ?? '').isNotEmpty)
                  Text(
                    activeHw['chapter'] ?? '',
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                Text(
                  activeHw['topic'] ?? 'Homework Assigned',
                  style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                ),
                if ((activeHw['description'] ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    activeHw['description'] ?? '',
                    style: TextStyle(color: Colors.white.withOpacity(0.92), fontSize: 13, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Bottom dates & action bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 13, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          "Due: ${activeHw['dueDate'] ?? 'Tomorrow'}",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isDark ? Colors.white70 : Colors.indigo[900]),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => notifier.goToAssignHomeworkMode(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.add, color: Color(0xFFD97706), size: 14),
                        SizedBox(width: 4),
                        Text(
                          "New Task",
                          style: TextStyle(color: Color(0xFFD97706), fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeworkReportCard(BuildContext context, Map<String, dynamic> hw, NextClassState state, NextClassNotifier notifier, bool isDark) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showHomeworkReportModal(
        context: context,
        hw: hw,
        state: state,
        notifier: notifier,
        isDark: isDark,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
          boxShadow: isDark ? [] : [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.assignment, color: Color(0xFFD97706), size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hw['topic'] ?? 'Homework',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.indigo[950],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if ((hw['chapter'] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hw['chapter'] ?? '',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10b981).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "Due: ${hw['dueDate'] ?? '-'}",
                          style: const TextStyle(
                            color: Color(0xFF059669),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if ((hw['assignedDate'] ?? '').isNotEmpty)
                        Text(
                          "• ${hw['assignedDate']}",
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => _showHomeworkReportModal(
                    context: context,
                    hw: hw,
                    state: state,
                    notifier: notifier,
                    isDark: isDark,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.visibility_outlined, size: 16, color: Color(0xFFD97706)),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => notifier.goToAssignHomeworkMode(editHw: hw),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.edit_outlined, size: 16, color: isDark ? Colors.white70 : Colors.grey[700]),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _showDeleteHomeworkDialog(context, notifier, hw['id']),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showHomeworkReportModal({
    required BuildContext context,
    required Map<String, dynamic> hw,
    required NextClassState state,
    required NextClassNotifier notifier,
    required bool isDark,
  }) {
    final submissions = hw['submissions'] is Map ? (hw['submissions'] as Map) : {};

    String getStudentStatus(Map<String, dynamic> student) {
      final sId = student['id']?.toString() ?? '';
      if (submissions.containsKey(sId)) {
        final sub = submissions[sId];
        if (sub is Map) {
          final st = sub['status']?.toString().toLowerCase();
          if (st == 'done') return 'done';
          if (st == 'incomplete') return 'incomplete';
          if (st == 'not_done' || st == 'notdone') return 'not_done';
          final sc = int.tryParse(sub['score']?.toString() ?? '');
          if (sc != null) {
            if (sc >= 75) return 'done';
            if (sc >= 25) return 'incomplete';
            return 'not_done';
          }
        } else if (sub is num) {
          if (sub >= 75) return 'done';
          if (sub >= 25) return 'incomplete';
          return 'not_done';
        }
      }

      final hwScores = List<dynamic>.from(student['homeworkScores'] ?? []);
      final hwId = hw['id']?.toString();
      final entry = hwScores.firstWhere(
        (s) => (hwId != null && s['homeworkId'] == hwId),
        orElse: () => null,
      );
      if (entry is Map) {
        final st = entry['status']?.toString().toLowerCase();
        if (st == 'done') return 'done';
        if (st == 'incomplete') return 'incomplete';
        if (st == 'not_done' || st == 'notdone') return 'not_done';
        final sc = int.tryParse(entry['score']?.toString() ?? '');
        if (sc != null) {
          if (sc >= 75) return 'done';
          if (sc >= 25) return 'incomplete';
          return 'not_done';
        }
      }
      return 'unmarked';
    }

    int doneCount = 0;
    int incompleteCount = 0;
    int notDoneCount = 0;
    int unmarkedCount = 0;

    for (var s in state.students) {
      final st = getStudentStatus(s);
      if (st == 'done') doneCount++;
      else if (st == 'incomplete') incompleteCount++;
      else if (st == 'not_done') notDoneCount++;
      else unmarkedCount++;
    }

    final totalStudents = state.students.length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.assignment, color: Color(0xFFD97706), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hw['topic'] ?? 'Homework Overview',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.indigo[950],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            "${hw['subject'] ?? state.selectedSubject ?? ''} • Due: ${hw['dueDate'] ?? '-'}",
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((hw['chapter'] ?? '').isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                hw['chapter'] ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          Text(
                            hw['topic'] ?? 'Homework Details',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((hw['description'] ?? '').isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.notes_rounded, color: Colors.white70, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      hw['description'] ?? '',
                                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Assigned: ${hw['assignedDate'] ?? '-'}",
                                style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11),
                              ),
                              Text(
                                "Due: ${hw['dueDate'] ?? '-'}",
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildHwStatBadge(
                          label: "Done",
                          count: doneCount,
                          color: const Color(0xFF10B981),
                          bgColor: const Color(0xFF10B981).withOpacity(0.1),
                          icon: Icons.check_circle_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildHwStatBadge(
                          label: "Incomplete",
                          count: incompleteCount,
                          color: const Color(0xFFF59E0B),
                          bgColor: const Color(0xFFF59E0B).withOpacity(0.1),
                          icon: Icons.timelapse_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildHwStatBadge(
                          label: "Not Done",
                          count: notDoneCount,
                          color: const Color(0xFFEF4444),
                          bgColor: const Color(0xFFEF4444).withOpacity(0.1),
                          icon: Icons.cancel_rounded,
                        ),
                        const SizedBox(width: 8),
                        _buildHwStatBadge(
                          label: "Unmarked",
                          count: unmarkedCount,
                          color: Colors.grey[600]!,
                          bgColor: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[100]!,
                          icon: Icons.help_outline_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Student Submissions",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.indigo[950],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.08) : Colors.indigo[50],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "$totalStudents Students",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.indigo[300] : Colors.indigo[700],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...state.students.map((student) {
                      final status = getStudentStatus(student);
                      Color statusColor;
                      Color statusBg;
                      IconData statusIcon;
                      String statusText;

                      if (status == 'done') {
                        statusColor = const Color(0xFF10B981);
                        statusBg = const Color(0xFF10B981).withOpacity(0.1);
                        statusIcon = Icons.check_circle_rounded;
                        statusText = "Done";
                      } else if (status == 'incomplete') {
                        statusColor = const Color(0xFFF59E0B);
                        statusBg = const Color(0xFFF59E0B).withOpacity(0.1);
                        statusIcon = Icons.timelapse_rounded;
                        statusText = "Incomplete";
                      } else if (status == 'not_done') {
                        statusColor = const Color(0xFFEF4444);
                        statusBg = const Color(0xFFEF4444).withOpacity(0.1);
                        statusIcon = Icons.cancel_rounded;
                        statusText = "Not Done";
                      } else {
                        statusColor = Colors.grey[500]!;
                        statusBg = isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100]!;
                        statusIcon = Icons.help_outline_rounded;
                        statusText = "Unmarked";
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.04) : Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: const Color(0xFFF59E0B).withOpacity(0.12),
                              child: Text(
                                (student['name'] ?? '?').substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFFD97706),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    student['name'] ?? 'Student',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    "Roll No: ${student['rollNo'] ?? '-'}",
                                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon, size: 12, color: statusColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHwStatBadge({
    required String label,
    required int count,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(
              "$count",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeworkPaginationBar({
    required BuildContext context,
    required int currentPage,
    required int totalPages,
    required int startNum,
    required int endNum,
    required int totalCount,
    required NextClassNotifier notifier,
    required bool isDark,
  }) {
    final bool hasPrev = currentPage > 0;
    final bool hasNext = currentPage < totalPages - 1;

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.08) : Colors.grey[200]!),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
              ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Prev button (<)
          GestureDetector(
            onTap: hasPrev ? () => notifier.setHomeworkReportsPage(currentPage - 1) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: hasPrev
                    ? (isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF59E0B).withOpacity(0.1))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_back_ios_rounded,
                    size: 13,
                    color: hasPrev ? const Color(0xFFD97706) : Colors.grey[400],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "Prev",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hasPrev ? const Color(0xFFD97706) : Colors.grey[400],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Page pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              "$startNum–$endNum of $totalCount (Page ${currentPage + 1}/$totalPages)",
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD97706),
              ),
            ),
          ),

          // Next button (">")
          GestureDetector(
            onTap: hasNext ? () => notifier.setHomeworkReportsPage(currentPage + 1) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: hasNext
                    ? const Color(0xFFD97706)
                    : (isDark ? Colors.white.withOpacity(0.03) : Colors.grey[200]),
                borderRadius: BorderRadius.circular(8),
                boxShadow: hasNext
                    ? [
                        BoxShadow(
                          color: const Color(0xFFD97706).withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  Text(
                    "Next",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hasNext ? Colors.white : Colors.grey[400],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: hasNext ? Colors.white : Colors.grey[400],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHomeworkReportsCard(BuildContext context, bool isDark, NextClassNotifier notifier) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.assignment_turned_in_outlined, color: Color(0xFFD97706), size: 36),
          ),
          const SizedBox(height: 14),
          Text(
            "No Homework in Last 7 Days",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: isDark ? Colors.white : Colors.indigo[950],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Older homework is automatically pruned after 1 week to keep your app fast.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignHomeworkFormView(BuildContext context, NextClassState state, NextClassNotifier notifier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultDueDate = DateTime.now().add(const Duration(days: 1));
    final currentDueDate = state.homeworkDueDate ?? defaultDueDate;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_note, color: Color(0xFFD97706), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Assign Homework Task",
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.indigo[900],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Chapter Input (Optional)
          _buildInputSection(
            context,
            title: "Chapter / Unit (Optional)",
            hint: "e.g., Chapter 4: Photosynthesis",
            icon: Icons.menu_book,
            onChanged: notifier.setHomeworkChapter,
            initialValue: state.homeworkChapter,
          ),
          const SizedBox(height: 16),

          // Topic / Task Title (Required)
          _buildInputSection(
            context,
            title: "Homework Task / Topic *",
            hint: "e.g., Book Page 45, Exercise 3.2 (Q1 to Q5)",
            icon: Icons.assignment,
            onChanged: notifier.setHomeworkTopic,
            initialValue: state.homeworkTopic,
          ),
          const SizedBox(height: 16),

          // Detailed Instructions
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Instructions / Details",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.transparent : Colors.grey[200]!),
                ),
                child: TextFormField(
                  initialValue: state.homeworkDescription,
                  onChanged: notifier.setHomeworkDescription,
                  maxLines: 3,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    icon: const Icon(Icons.description_outlined, color: Color(0xFFF59E0B), size: 20),
                    border: InputBorder.none,
                    hintText: "e.g., Solve questions on homework notebook and draw clean diagrams.",
                    hintStyle: TextStyle(color: isDark ? Colors.grey[600] : Colors.grey[400], fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Due Date Picker
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: currentDueDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                notifier.setHomeworkDueDate(picked);
              }
            },
            child: _buildDateTimeWidget(
              context,
              title: "Due Date (Submission)",
              value: "${currentDueDate.day}/${currentDueDate.month}/${currentDueDate.year}",
              icon: Icons.calendar_today,
              isSelected: state.homeworkDueDate != null,
            ),
          ),
          const SizedBox(height: 28),

          // Save & Notify Button
          GestureDetector(
            onTap: state.isSaving ? null : () async {
              final topic = state.homeworkTopic.trim();
              final chapter = state.homeworkChapter.trim();
              if (topic.isEmpty && chapter.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Please provide a Task/Topic or Chapter for the homework.")),
                );
                return;
              }

              try {
                final synced = await notifier.saveHomework();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(synced 
                          ? "Homework saved successfully for ${state.selectedClass?['name']}!" 
                          : "Homework saved offline! Will sync automatically once online."),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Failed to save: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: state.isSaving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.assignment_turned_in_outlined, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Assign Homework",
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  void _showDeleteHomeworkDialog(BuildContext context, NextClassNotifier notifier, String homeworkId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.surfaceDark : Colors.white,
        title: Text(
          "Delete Homework?",
          style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.indigo[900]),
        ),
        content: Text(
          "Are you sure you want to delete this homework record?",
          style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey : Colors.grey[600]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              notifier.deleteHomework(homeworkId);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Homework deleted.")),
              );
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
