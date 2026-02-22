import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/my_class/providers/my_class_provider.dart';
import 'package:teacher_mobile_app/features/attendance/providers/attendance_provider.dart';
import 'package:teacher_mobile_app/features/attendance/presentation/screens/attendance_screen.dart'; // Reusing StudentAvatar

class AllStudentsResultScreen extends ConsumerWidget {
  const AllStudentsResultScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(classStudentsProvider);
    final teacherDataAsync = ref.watch(teacherDataProvider);
    final searchQuery = ref.watch(myClassSearchQueryProvider);

    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: isDark ? Colors.white : const Color(0xFF6366f1), size: 30),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Upload Result Cards",
              style: TextStyle(color: isDark ? Colors.white : Colors.indigo[900], fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              "for parents",
              style: TextStyle(color: isDark ? Colors.grey : Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: studentsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.indigoAccent)),
          error: (e, st) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
          data: (students) {
            final teacherData = teacherDataAsync.value;
            if (teacherData == null) return const SizedBox.shrink();

            final String schoolId = teacherData['schoolId'];

            List<Map<String, dynamic>> filteredStudents = students.where((s) {
              final nameMatches = s['name'].toString().toLowerCase().contains(searchQuery.toLowerCase());
              final rollMatches = (s['rollNo']?.toString() ?? s['roll']?.toString() ?? '').toLowerCase().contains(searchQuery.toLowerCase());
              return nameMatches || rollMatches;
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: isDark ? Colors.transparent : Colors.black.withOpacity(0.05)),
                      boxShadow: isLight ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))] : [],
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
                
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                  child: Text("Select Student to Upload Result", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey)),
                ),

                Expanded(
                  child: filteredStudents.isEmpty
                      ? const Center(child: Text("No students found.", style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filteredStudents.length,
                          itemBuilder: (context, index) {
                            final student = filteredStudents[index];
                            final hasResult = student['uploadedResultUrl'] != null;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                  if (hasResult)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text("Uploaded", style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: () {
                                      context.push('/my-class/upload-result/${student['id']}');
                                    },
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: isLight ? const Color(0xFF6366f1) : Colors.indigoAccent,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        minimumSize: Size.zero,
                                        elevation: isLight ? 4 : 0,
                                        shadowColor: const Color(0xFF6366f1).withOpacity(0.5),
                                    ),
                                    child: const Text("Upload", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
