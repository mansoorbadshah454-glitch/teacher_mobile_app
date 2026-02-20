import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/attendance/providers/attendance_provider.dart';
import 'package:teacher_mobile_app/features/my_class/providers/student_performance_provider.dart';

class StudentPerformanceScreen extends ConsumerStatefulWidget {
  final String studentId;
  
  const StudentPerformanceScreen({super.key, required this.studentId});

  @override
  ConsumerState<StudentPerformanceScreen> createState() => _StudentPerformanceScreenState();
}

class _StudentPerformanceScreenState extends ConsumerState<StudentPerformanceScreen> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final performanceAsync = ref.watch(studentPerformanceProvider(widget.studentId));
    final studentsData = ref.watch(classStudentsProvider).value;
    final teacherData = ref.watch(teacherDataProvider).value;
    
    final student = studentsData?.firstWhere((s) => s['id'] == widget.studentId, orElse: () => {});
    final teacherAssignedSubjects = List<String>.from(teacherData?['subjects'] ?? []);

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: performanceAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.indigoAccent)),
          error: (e, st) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
          data: (data) {
            if (student == null || student.isEmpty || data == null) {
              return const Center(child: Text("Student not found", style: TextStyle(color: Colors.white)));
            }
            
            return Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Header ---
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
                                Text(student['name'] ?? 'Student', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                                const Text("Editing", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // --- 1. Academic Scores ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.emoji_events, color: Colors.greenAccent, size: 20),
                                  SizedBox(width: 8),
                                  Text("Academic Results", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ...data.academicScores.entries.map((entry) {
                                final isEditable = teacherAssignedSubjects.contains(entry.key);
                                return Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(entry.key, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                        Text("${entry.value}%", style: TextStyle(color: isEditable ? Colors.greenAccent : Colors.grey, fontSize: 14, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    Opacity(
                                      opacity: isEditable ? 1.0 : 0.4,
                                      child: SliderTheme(
                                        data: SliderThemeData(
                                          activeTrackColor: Colors.greenAccent,
                                          inactiveTrackColor: Colors.greenAccent.withOpacity(0.2),
                                          thumbColor: Colors.greenAccent,
                                          overlayColor: Colors.greenAccent.withOpacity(0.1),
                                          trackHeight: 6,
                                        ),
                                        child: Slider(
                                          value: entry.value.toDouble(),
                                          min: 0,
                                          max: 100,
                                          onChanged: isEditable ? (val) {
                                            ref.read(studentPerformanceProvider(widget.studentId).notifier).updateAcademicScore(entry.key, val.toInt());
                                          } : null,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ),

                      // --- 2. Homework Scores ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.assignment, color: Colors.orangeAccent, size: 20),
                                  SizedBox(width: 8),
                                  Text("Homework Scores", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ...data.homeworkScores.entries.map((entry) {
                                final isEditable = teacherAssignedSubjects.contains(entry.key);
                                return Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(entry.key, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                        Text("${entry.value}%", style: TextStyle(color: isEditable ? Colors.orangeAccent : Colors.grey, fontSize: 14, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    Opacity(
                                      opacity: isEditable ? 1.0 : 0.4,
                                      child: SliderTheme(
                                        data: SliderThemeData(
                                          activeTrackColor: Colors.orangeAccent,
                                          inactiveTrackColor: Colors.orangeAccent.withOpacity(0.2),
                                          thumbColor: Colors.orangeAccent,
                                          overlayColor: Colors.orangeAccent.withOpacity(0.1),
                                          trackHeight: 6,
                                        ),
                                        child: Slider(
                                          value: entry.value.toDouble(),
                                          min: 0,
                                          max: 100,
                                          onChanged: isEditable ? (val) {
                                            ref.read(studentPerformanceProvider(widget.studentId).notifier).updateHomeworkScore(entry.key, val.toInt());
                                          } : null,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ),

                      // --- 3. Wellness Profile ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.favorite, color: Colors.pinkAccent, size: 20),
                                  SizedBox(width: 8),
                                  Text("Wellness Profile", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              ...['behavior', 'health', 'hygiene'].map((metric) {
                                final score = data.wellness[metric] ?? 80;
                                return Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(metric[0].toUpperCase() + metric.substring(1), style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w600)),
                                        Text("$score%", style: const TextStyle(color: Color(0xFF6366f1), fontSize: 14, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    SliderTheme(
                                      data: SliderThemeData(
                                        activeTrackColor: const Color(0xFF6366f1),
                                        inactiveTrackColor: const Color(0xFF6366f1).withOpacity(0.2),
                                        thumbColor: const Color(0xFF6366f1),
                                        overlayColor: const Color(0xFF6366f1).withOpacity(0.1),
                                        trackHeight: 6,
                                      ),
                                      child: Slider(
                                        value: score.toDouble(),
                                        min: 0,
                                        max: 100,
                                        onChanged: (val) {
                                          ref.read(studentPerformanceProvider(widget.studentId).notifier).updateWellness(metric, val.toInt());
                                        },
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ),

                      // --- 4. Attendance Percentage ---
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.calendar_today, color: Colors.tealAccent, size: 20),
                                  SizedBox(width: 8),
                                  Text("Attendance Percentage", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Attendance", style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w600)),
                                  Text("${data.attendance}%", style: const TextStyle(color: Colors.tealAccent, fontSize: 14, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: Colors.tealAccent,
                                  inactiveTrackColor: Colors.redAccent,
                                  thumbColor: Colors.tealAccent,
                                  overlayColor: Colors.tealAccent.withOpacity(0.1),
                                  trackHeight: 6,
                                ),
                                child: Slider(
                                  value: data.attendance.toDouble(),
                                  min: 0,
                                  max: 100,
                                  onChanged: (val) {
                                    ref.read(studentPerformanceProvider(widget.studentId).notifier).updateAttendance(val.toInt());
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // --- Save Button ---
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 24,
                  child: GestureDetector(
                    onTap: () async {
                      if (_saving) return;
                      setState(() => _saving = true);
                      try {
                        await ref.read(studentPerformanceProvider(widget.studentId).notifier).save();
                        if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Performance data saved & parent notified!"), backgroundColor: Colors.green));
                            context.pop();
                        }
                      } catch (e) {
                         if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
                         }
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366f1),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: const Color(0xFF6366f1).withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))],
                      ),
                      alignment: Alignment.center,
                      child: _saving 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.save, color: Colors.white),
                                SizedBox(width: 8),
                                Text("SAVE CHANGES", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                              ],
                            ),
                    ),
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

