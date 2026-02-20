import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/attendance/providers/attendance_provider.dart';
import 'package:teacher_mobile_app/features/my_class/providers/my_class_provider.dart';
import 'package:teacher_mobile_app/features/attendance/presentation/screens/attendance_screen.dart'; // Reusing StudentAvatar

class MyClassScreen extends ConsumerWidget {
  const MyClassScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teacherDataAsync = ref.watch(teacherDataProvider);
    final assignedClassAsync = ref.watch(assignedClassProvider);
    final studentsAsync = ref.watch(classStudentsProvider);
    final metricsAsync = ref.watch(classMetricsProvider);
    final absentCountAsync = ref.watch(todaysAbsentCountProvider);
    final searchQuery = ref.watch(myClassSearchQueryProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: assignedClassAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.indigoAccent)),
          error: (e, st) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
          data: (assignedClass) {
            if (assignedClass == null) {
              return Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.red.withOpacity(0.2)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No Class Assigned', style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Text('You are not assigned to any specific class. Please contact the Principal to assign you a class.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => context.pop(),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366f1)),
                        child: const Text('Go Back'),
                      )
                    ],
                  ),
                ),
              );
            }

            return studentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.indigoAccent)),
              error: (e, st) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
              data: (students) {
                final teacherData = teacherDataAsync.value;
                if (teacherData == null) return const SizedBox.shrink();

                final String schoolId = teacherData['schoolId'];
                final absentCount = absentCountAsync.value ?? 0;
                final metrics = metricsAsync.value ?? ClassMetrics();

                List<Map<String, dynamic>> filteredStudents = students.where((s) {
                  final nameMatches = s['name'].toString().toLowerCase().contains(searchQuery.toLowerCase());
                  final rollMatches = (s['rollNo']?.toString() ?? s['roll']?.toString() ?? '').toLowerCase().contains(searchQuery.toLowerCase());
                  return nameMatches || rollMatches;
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- 1. Header ---
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => context.pop(),
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
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Performance", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                              Text("${assignedClass['name']} • ${students.length} Students • $absentCount Absent Today", style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // --- 2. Summary Cards ---
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          // Class Score
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.trending_up, color: Colors.blueAccent),
                                  const SizedBox(height: 8),
                                  Text("${metrics.classScore}%", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                                  const Text("Class Score", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Subject Score
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.menu_book, color: Colors.orangeAccent),
                                  const SizedBox(height: 8),
                                  Text("${metrics.subjectScore}%", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                                  const Text("Subject Score", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Homework Score
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withOpacity(0.05)),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                              ),
                              child: Column(
                                children: [
                                  const Icon(Icons.assignment, color: Colors.purpleAccent),
                                  const SizedBox(height: 8),
                                  Text("${metrics.homeworkScore}%", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                                  const Text("Homework", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // --- 3. Search Bar ---
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: TextField(
                          style: const TextStyle(color: Colors.white),
                          onChanged: (val) => ref.read(myClassSearchQueryProvider.notifier).state = val,
                          decoration: const InputDecoration(
                            hintText: "Search students...",
                            hintStyle: TextStyle(color: Colors.grey),
                            prefixIcon: Icon(Icons.search, color: Colors.grey),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(16),
                          ),
                        ),
                      ),
                    ),

                    // --- 4. Student List ---
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                            child: Text("All Students", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey)),
                          ),
                          Expanded(
                            child: filteredStudents.isEmpty
                                ? const Center(child: Text("No students found.", style: TextStyle(color: Colors.grey)))
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    itemCount: filteredStudents.length,
                                    itemBuilder: (context, index) {
                                      final student = filteredStudents[index];
                                      return GestureDetector(
                                        onTap: () {
                                          context.push('/my-class/student/${student['id']}');
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(bottom: 12),
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.03),
                                            borderRadius: BorderRadius.circular(22),
                                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                                          ),
                                          child: Row(
                                            children: [
                                               StudentAvatar(
                                                  studentId: student['id'],
                                                  schoolId: schoolId,
                                                  profilePic: student['profilePic'] ?? student['avatar'],
                                                  size: 48,
                                                ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(student['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                                                    const SizedBox(height: 4),
                                                    Text("Roll No: ${student['rollNo'] ?? student['roll'] ?? '-'}", style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                                                  ],
                                                ),
                                              ),
                                              const Icon(Icons.school, color: Colors.indigoAccent, size: 24),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

