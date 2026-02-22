import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                                color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: isDark ? Colors.transparent : Colors.black.withOpacity(0.05)),
                                boxShadow: isLight ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))] : [],
                              ),
                              child: Icon(Icons.chevron_left, color: isDark ? Colors.white : const Color(0xFF6366f1)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Performance", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.indigo[900])),
                                Text(
                                  "${assignedClass['name']} • ${students.length} Students • $absentCount Absent", 
                                  style: TextStyle(fontSize: 12, color: isLight ? Colors.grey[600] : Colors.grey, fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => context.push('/my-class/all-results'),
                            icon: Text("Next", style: TextStyle(color: isLight ? const Color(0xFF6366f1) : Colors.white, fontWeight: FontWeight.bold)),
                            label: Icon(Icons.arrow_forward_ios, color: isLight ? const Color(0xFF6366f1) : Colors.white, size: 14),
                            style: TextButton.styleFrom(
                              backgroundColor: isLight ? const Color(0xFF6366f1).withOpacity(0.1) : Colors.indigoAccent.withOpacity(0.2),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
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
                                color: isLight ? const Color(0xFF6366f1) : Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent),
                                boxShadow: [BoxShadow(color: isLight ? const Color(0xFF6366f1).withOpacity(0.3) : Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.trending_up, color: isLight ? Colors.white : Colors.blueAccent),
                                  const SizedBox(height: 8),
                                  Text("${metrics.classScore}%", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.white)),
                                  Text("Class Score", style: TextStyle(fontSize: 10, color: isLight ? Colors.white70 : Colors.grey, fontWeight: FontWeight.w600)),
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
                                color: isLight ? const Color(0xFF10b981) : Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent),
                                boxShadow: [BoxShadow(color: isLight ? const Color(0xFF10b981).withOpacity(0.3) : Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.menu_book, color: isLight ? Colors.white : Colors.orangeAccent),
                                  const SizedBox(height: 8),
                                  Text("${metrics.subjectScore}%", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.white)),
                                  Text("Subject Score", style: TextStyle(fontSize: 10, color: isLight ? Colors.white70 : Colors.grey, fontWeight: FontWeight.w600)),
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
                                color: isLight ? const Color(0xFFeab308) : Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.transparent),
                                boxShadow: [BoxShadow(color: isLight ? const Color(0xFFeab308).withOpacity(0.3) : Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.assignment, color: isLight ? Colors.white : Colors.purpleAccent),
                                  const SizedBox(height: 8),
                                  Text("${metrics.homeworkScore}%", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.white)),
                                  Text("Homework", style: TextStyle(fontSize: 10, color: isLight ? Colors.white70 : Colors.grey, fontWeight: FontWeight.w600)),
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
                          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: isLight ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))] : [],
                          border: Border.all(color: isDark ? Colors.transparent : Colors.black.withOpacity(0.05)),
                        ),
                        child: TextField(
                          style: TextStyle(color: isDark ? Colors.white : Colors.indigo[900]),
                          onChanged: (val) => ref.read(myClassSearchQueryProvider.notifier).state = val,
                          decoration: InputDecoration(
                            hintText: "Search students...",
                            hintStyle: TextStyle(color: isDark ? Colors.grey : Colors.grey[400]),
                            prefixIcon: Icon(Icons.search, color: isDark ? Colors.grey : Colors.indigo[300]),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
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
                                            color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                                            borderRadius: BorderRadius.circular(22),
                                            border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                                            boxShadow: isLight ? [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))] : [],
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
                                                    Text(student['name'] ?? 'Unknown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.indigo[900])),
                                                    const SizedBox(height: 4),
                                                    Text("Roll No: ${student['rollNo'] ?? student['roll'] ?? '-'}", style: TextStyle(fontSize: 12, color: isLight ? Colors.grey[600] : Colors.grey, fontWeight: FontWeight.w500)),
                                                  ],
                                                ),
                                              ),
                                              Icon(Icons.school, color: isLight ? const Color(0xFF6366f1) : Colors.indigoAccent, size: 24),
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

