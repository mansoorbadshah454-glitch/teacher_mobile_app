import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/next_class/providers/next_class_provider.dart';
import 'package:teacher_mobile_app/features/next_class/presentation/widgets/student_score_card.dart';
import 'package:teacher_mobile_app/features/next_class/services/pdf_generator_service.dart';

class NextClassScreen extends ConsumerWidget {
  const NextClassScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nextClassProvider);
    final notifier = ref.read(nextClassProvider.notifier);
    final teacherData = ref.watch(teacherDataProvider).value;
    final schoolData = ref.watch(schoolDataProvider).value;

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(context, state, notifier),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildBody(context, state, notifier, teacherData, schoolData),
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
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.4),
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
    } else if (state.viewMode == NextClassViewMode.test) {
      title = "Test: ${state.selectedSubject}";
      subtitle = "Enter scores & generate report";
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(14),
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (showNextBtn)
            GestureDetector(
              onTap: () => notifier.goToTestMode(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
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

  Widget _buildBody(BuildContext context, NextClassState state, NextClassNotifier notifier, Map<String, dynamic>? teacherData, Map<String, dynamic>? schoolData) {
    if (state.isLoading && state.classes.isEmpty && state.students.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    switch (state.viewMode) {
      case NextClassViewMode.classes:
        return _buildClassesView(state, notifier);
      case NextClassViewMode.subjects:
        return _buildSubjectsView(state, notifier, teacherData);
      case NextClassViewMode.students:
        return _buildStudentsView(state, notifier);
      case NextClassViewMode.test:
        return _buildTestView(context, state, notifier, teacherData, schoolData);
    }
  }

  Widget _buildClassesView(NextClassState state, NextClassNotifier notifier) {
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
        final subjectCount = (cls['subjects'] as List<dynamic>? ?? []).length;

        return GestureDetector(
          onTap: () => notifier.selectClass(cls),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.people, color: AppTheme.primary),
                ),
                const SizedBox(height: 16),
                Text(
                  cls['name'] ?? 'Unknown Class',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "$subjectCount Subjects",
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubjectsView(NextClassState state, NextClassNotifier notifier, Map<String, dynamic>? teacherData) {
    final subjects = List<String>.from(state.selectedClass?['subjects'] ?? []);
    final assignedSubjects = List<String>.from(teacherData?['subjects'] ?? []);

    if (subjects.isEmpty) {
      return const Center(
        child: Text("No subjects found for this class.", style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: subjects.length,
      itemBuilder: (context, index) {
        final subject = subjects[index];
        final isAssigned = assignedSubjects.contains(subject);

        return GestureDetector(
          onTap: isAssigned ? () => notifier.selectSubject(subject) : () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("You are not assigned to teach this subject.")),
            );
          },
          child: Opacity(
            opacity: isAssigned ? 1.0 : 0.5,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isAssigned ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isAssigned ? Colors.white.withOpacity(0.1) : Colors.transparent,
                ),
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!isAssigned)
                          const Text(
                            "Not Assigned",
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

  Widget _buildStudentsView(NextClassState state, NextClassNotifier notifier) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
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
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              onChanged: notifier.setSearchTerm,
              style: const TextStyle(color: Colors.white),
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
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  onChanged: notifier.setTestChapter,
                  style: const TextStyle(color: Colors.white),
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
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  onChanged: notifier.setSearchTerm,
                  style: const TextStyle(color: Colors.white),
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
        backgroundColor: AppTheme.surfaceDark,
        title: const Text("Reset Test Scores?", style: TextStyle(color: Colors.white)),
        content: const Text("Are you sure you want to reset all test scores to 0?", style: TextStyle(color: Colors.grey)),
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
}
