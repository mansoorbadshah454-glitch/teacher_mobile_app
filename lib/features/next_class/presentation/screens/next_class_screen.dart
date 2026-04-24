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
    String title = "All Classes";
    String subtitle = "Select a class to manage";
    bool showNextBtn = false;

    if (state.viewMode == NextClassViewMode.subjects) {
      title = state.selectedClass?['name'] ?? "Subjects";
      subtitle = "Select a subject";
    } else if (state.viewMode == NextClassViewMode.students) {
      title = state.selectedSubject ?? "Students";
      subtitle = "${state.selectedClass?['name']} • ${state.students.length} Students";
      showNextBtn = true;
    } else if (state.viewMode == NextClassViewMode.scheduleTest) {
      title = "Schedule Test";
      subtitle = state.selectedSubject ?? "Details";
    } else if (state.viewMode == NextClassViewMode.test) {
      title = "Test: ${state.selectedSubject}";
      subtitle = "Enter scores & generate report";
    } else if (state.viewMode == NextClassViewMode.activeTestScore) {
      title = "Record Scores";
      subtitle = "${state.selectedSubject} • ${state.activeScheduledTest?['testType'] ?? ''} Test";
    }

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16, 
        bottom: 16, 
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
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2), // Transparent white
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.chevron_left, color: Colors.white),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (showNextBtn)
            GestureDetector(
              onTap: () => notifier.goToScheduleTestMode(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.3)),
                ),
                child: Row(
                  children: const [
                     Text(
                      "Next",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                     SizedBox(width: 4),
                     Icon(Icons.chevron_right, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
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
        return _buildClassesView(context, state, notifier);
      case NextClassViewMode.subjects:
        return _buildSubjectsView(context, state, notifier, timetableSlots);
      case NextClassViewMode.students:
        return _buildStudentsView(context, state, notifier);
      case NextClassViewMode.scheduleTest:
        return _buildScheduleTestView(context, state, notifier);
      case NextClassViewMode.test:
        return _buildTestView(context, state, notifier, teacherData, schoolData);
      case NextClassViewMode.activeTestScore:
        return _buildActiveTestScoreView(context, state, notifier, teacherData, schoolData);
    }
  }

  Widget _buildClassesView(BuildContext context, NextClassState state, NextClassNotifier notifier) {
    if (state.classes.isEmpty) {
      return const Center(
        child: Text("No classes found.", style: TextStyle(color: Colors.grey)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.9,
      ),
      itemCount: state.classes.length,
      itemBuilder: (context, index) {
        final cls = state.classes[index];
        return ClassCard(
          cls: cls,
          onTap: () => notifier.selectClass(cls),
        );
      },
    );
  }

  Widget _buildSubjectsView(BuildContext context, NextClassState state, NextClassNotifier notifier, List<TimetableSlot> timetableSlots) {
    final subjects = List<String>.from(state.selectedClass?['subjects'] ?? []);
    final className = state.selectedClass?['name'];

    if (subjects.isEmpty) {
      return const Center(
        child: Text("No subjects found for this class.", style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: subjects.length,
      itemBuilder: (context, index) {
        final isLight = Theme.of(context).brightness == Brightness.light;
        final isDark = !isLight;
        final subject = subjects[index];
        final isAssigned = timetableSlots.any((slot) => slot.className == className && slot.subject == subject);

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
              padding: const EdgeInsets.all(20),
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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.menu_book, color: Color(0xFFF43F5E), size: 18),
                  ),
                  const SizedBox(width: 16),
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
                        if (!isAssigned)
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

    return Column(
      children: [
        // Summary Cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.menu_book,
                  title: "$avgAc%",
                  subtitle: "Subject Score",
                  color: const Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  icon: Icons.assignment,
                  title: "$avgHw%",
                  subtitle: "Homework Score",
                  color: const Color(0xFFEAB308),
                ),
              ),
            ],
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
                homeworkScore: notifier.getStudentScore(student, 'homework'),
                onScoreChanged: notifier.updateScore,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTestView(BuildContext context, NextClassState state, NextClassNotifier notifier, Map<String, dynamic>? teacherData, Map<String, dynamic>? schoolData) {
    final filteredStudents = state.students.where((s) {
      final name = (s['name'] ?? '').toString().toLowerCase();
      final roll = (s['rollNo'] ?? '').toString().toLowerCase();
      final q = state.searchTerm.toLowerCase();
      return name.contains(q) || roll.contains(q);
    }).toList();

    return Column(
      children: [
        // Action Buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _showResetDialog(context, notifier),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.refresh, color: Color(0xFFEF4444), size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Reset Scores",
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    PdfGeneratorService.generateTestReport(
                      context: context,
                      schoolName: schoolData?['name'] ?? teacherData?['schoolName'] ?? "School App",
                      className: state.selectedClass?['name'] ?? "Class",
                      teacherName: teacherData?['name'] ?? "Teacher",
                      subject: state.selectedSubject ?? "Subject",
                      chapterName: state.testChapter.trim(),
                      students: state.students,
                      testScores: state.testScores,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.picture_as_pdf, color: Color(0xFF3B82F6), size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Create PDF",
                          style: TextStyle(
                            color: Color(0xFF3B82F6),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Search Bar & Chapter Input
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Chapter Input
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.transparent : Colors.black.withOpacity(0.05)),
                ),
                child: TextField(
                  onChanged: notifier.setTestChapter,
                  style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
                  decoration: const InputDecoration(
                    icon: Icon(Icons.book, color: Colors.indigoAccent, size: 20),
                    border: InputBorder.none,
                    hintText: "Chapter (Optional)...",
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Search Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? Colors.transparent : Colors.black.withOpacity(0.05)),
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
            ],
          ),
        ),

        // Student List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: filteredStudents.length,
            itemBuilder: (context, index) {
              final student = filteredStudents[index];
              return StudentScoreCard(
                student: student,
                isTestMode: true,
                testScore: state.testScores[student['id']] ?? 0,
                onTestScoreChanged: notifier.updateTestScore,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showResetDialog(BuildContext context, NextClassNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppTheme.surfaceDark : Colors.white,
        title: Text("Reset Test Scores?", style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.indigo[900])),
        content: Text("Are you sure you want to reset all test scores to 0?", style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey : Colors.grey[600])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              notifier.resetTestScores();
              Navigator.pop(ctx);
            },
            child: const Text("Reset", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleTestView(BuildContext context, NextClassState state, NextClassNotifier notifier) {
    if (state.isFetchingTest) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    
    if (state.activeScheduledTest != null && state.activeScheduledTest!.isNotEmpty) {
      return _buildScheduledTestDetailsWidget(context, state, notifier);
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
               // INSTANT UI UPDATE
               notifier.saveScheduledTest();
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


  Widget _buildScheduledTestDetailsWidget(BuildContext context, NextClassState state, NextClassNotifier notifier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final test = state.activeScheduledTest!;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366f1), Color(0xFF4f46e5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: const Color(0xFF6366f1).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                  child: Text("${test['testType']} Test", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(height: 16),
                const Icon(Icons.event_available, color: Colors.white, size: 48),
                const SizedBox(height: 16),
                Text(test['subject'] ?? "Subject", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(test['chapter'] ?? "", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16), textAlign: TextAlign.center),
                if ((test['paragraphs'] ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text("Topic: ${test['paragraphs']}", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildDetailCard(context, Icons.calendar_today, "Date", test['dateStr'] ?? "TBD")),
              const SizedBox(width: 16),
              Expanded(child: _buildDetailCard(context, Icons.access_time, "Time", test['timeStr'] ?? "TBD")),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailCard(context, Icons.score, "Max Marks", "${test['maxMarks'] ?? 10} Marks", fullWidth: true),
          const SizedBox(height: 40),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: state.isSaving ? null : () => _showCancelDialog(context, notifier),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.red.withOpacity(0.2) : Colors.red[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.withOpacity(0.5)),
                    ),
                    alignment: Alignment.center,
                    child: state.isSaving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.red, strokeWidth: 2))
                        : const Text("Cancel Test", style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: state.isSaving ? null : () => notifier.completeScheduledTest(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10b981), Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: const Color(0xFF10b981).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 8))],
                    ),
                    alignment: Alignment.center,
                    child: state.isSaving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Completed", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: state.isSaving ? null : () => notifier.goToActiveTestScoreMode(),
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
              child: const Text("Start Test", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(BuildContext context, IconData icon, String title, String value, {bool fullWidth = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.transparent : Colors.black.withOpacity(0.05)),
        boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF6366f1).withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: const Color(0xFF6366f1), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ],
            ),
          ),
        ],
      ),
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
          Text("Enter Test Scores", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isDark ? Colors.white : Colors.indigo[900])),
          const SizedBox(height: 16),

          // Students List
          ...state.students.map((student) {
            final studentId = student['id'];
            final maxMarks = test['maxMarks'] ?? 10;
            int maxM = (maxMarks is int) ? maxMarks : int.tryParse(maxMarks.toString()) ?? 10;
            double currentScore = (state.testScores[studentId] ?? 0).toDouble();

            Color sliderColor;
            double percentage = maxM > 0 ? currentScore / maxM : 0.0;
            if (percentage <= 0.3) {
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
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? Colors.transparent : Colors.grey[200]!),
                boxShadow: isDark ? [] : [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFF6366f1).withOpacity(0.1),
                        radius: 20,
                        child: Text(
                          student['name']?.substring(0, 1).toUpperCase() ?? "?",
                          style: const TextStyle(color: Color(0xFF6366f1), fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(student['name'] ?? 'Unknown', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
                            Text("Roll No: ${student['rollNo'] ?? '-'}", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: sliderColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: sliderColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          "${currentScore.toInt()} / $maxM",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: sliderColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                if (!state.testScores.containsKey(student['id'])) {
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
}
