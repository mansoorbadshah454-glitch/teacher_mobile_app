import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  bool _hasUnsavedChanges = false;

  Future<bool> _showDiscardDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Unsaved Changes"),
        content: const Text("You have unsaved changes. Do you want to discard them?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Discard", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final performanceAsync = ref.watch(studentPerformanceProvider(widget.studentId));
    final studentsData = ref.watch(classStudentsProvider).value;
    final assignedClass = ref.watch(assignedClassProvider).value;
    final currentClassName = assignedClass?['name'] ?? '';
    
    final student = studentsData?.firstWhere(
      (s) => s['id'] == widget.studentId, 
      orElse: () => <String, dynamic>{},
    );

    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _showDiscardDialog(context);
        if (shouldPop && context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: performanceAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF6366f1))),
            error: (e, st) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
            data: (data) {
              if (student == null || student.isEmpty || data == null) {
                return Center(
                  child: Text(
                    "Student not found", 
                    style: TextStyle(color: isDark ? Colors.white : Colors.redAccent),
                  ),
                );
              }
              
              return Stack(
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Header ---
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                if (_hasUnsavedChanges) {
                                  final discard = await _showDiscardDialog(context);
                                  if (discard && context.mounted) {
                                    context.pop();
                                  }
                                } else {
                                  context.pop();
                                }
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: isDark ? Colors.transparent : Colors.black.withOpacity(0.05)),
                                  boxShadow: isLight ? [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05), 
                                      blurRadius: 10, 
                                      offset: const Offset(0, 4),
                                    )
                                  ] : [],
                                ),
                                child: Icon(Icons.chevron_left, color: isDark ? Colors.white : const Color(0xFF6366f1)),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    student['name'] ?? 'Student', 
                                    style: TextStyle(
                                      fontSize: 20, 
                                      fontWeight: FontWeight.w800, 
                                      color: isDark ? Colors.white : Colors.indigo[900],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Row(
                                    children: [
                                      if (currentClassName.isNotEmpty) ...[
                                        Text(
                                          currentClassName, 
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF6366f1), fontWeight: FontWeight.bold),
                                        ),
                                        const Text(" • ", style: TextStyle(color: Colors.grey)),
                                      ],
                                      Text(
                                        "Roll No: ${student['rollNo'] ?? student['rollNumber'] ?? '-'}", 
                                        style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600], fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // --- Wellness Profile Card ---
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05)),
                            boxShadow: isLight ? [
                              BoxShadow(
                                color: const Color(0xFF6366f1).withOpacity(0.04), 
                                blurRadius: 20, 
                                offset: const Offset(0, 8),
                              )
                            ] : [],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.pinkAccent.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(Icons.favorite_rounded, color: Colors.pinkAccent, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Wellness & Personality Profile", 
                                          style: TextStyle(
                                            fontSize: 17, 
                                            fontWeight: FontWeight.w800, 
                                            color: isDark ? Colors.white : Colors.indigo[900],
                                          ),
                                        ),
                                        Text(
                                          "Student's personal growth & habits", 
                                          style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // 1. Behavior
                              _buildWellnessSlider(
                                context: context,
                                isDark: isDark,
                                isLight: isLight,
                                icon: Icons.psychology_outlined,
                                title: "Behavior & Ethics",
                                subtitle: "Class discipline, attitude & respect",
                                score: data.wellness['behavior'] ?? 80,
                                accentColor: const Color(0xFF6366f1),
                                onChanged: (val) {
                                  ref.read(studentPerformanceProvider(widget.studentId).notifier).updateWellness('behavior', val);
                                  if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
                                },
                              ),

                              const SizedBox(height: 20),
                              Divider(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100], height: 1),
                              const SizedBox(height: 20),

                              // 2. Health
                              _buildWellnessSlider(
                                context: context,
                                isDark: isDark,
                                isLight: isLight,
                                icon: Icons.health_and_safety_outlined,
                                title: "Health & Active-ness",
                                subtitle: "Energy, physical wellness & sports",
                                score: data.wellness['health'] ?? 80,
                                accentColor: const Color(0xFFEC4899),
                                onChanged: (val) {
                                  ref.read(studentPerformanceProvider(widget.studentId).notifier).updateWellness('health', val);
                                  if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
                                },
                              ),

                              const SizedBox(height: 20),
                              Divider(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100], height: 1),
                              const SizedBox(height: 20),

                              // 3. Hygiene
                              _buildWellnessSlider(
                                context: context,
                                isDark: isDark,
                                isLight: isLight,
                                icon: Icons.clean_hands_outlined,
                                title: "Cleanliness & Hygiene",
                                subtitle: "Uniform cleanliness & grooming",
                                score: data.wellness['hygiene'] ?? 80,
                                accentColor: const Color(0xFF10B981),
                                onChanged: (val) {
                                  ref.read(studentPerformanceProvider(widget.studentId).notifier).updateWellness('hygiene', val);
                                  if (!_hasUnsavedChanges) setState(() => _hasUnsavedChanges = true);
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Guidance Note
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366f1).withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF6366f1).withOpacity(0.12)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Color(0xFF6366f1), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "These wellness evaluations are displayed in the Parent App under the Personality & Wellness section.",
                                  style: TextStyle(
                                    fontSize: 12, 
                                    color: isDark ? Colors.indigo[200] : const Color(0xFF4338CA),
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
                  
                  // --- Save Button ---
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: GestureDetector(
                      onTap: () async {
                        if (_saving) return;
                        setState(() => _saving = true);
                        try {
                          await ref.read(studentPerformanceProvider(widget.studentId).notifier).save();
                          setState(() => _hasUnsavedChanges = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Wellness profile saved & updated!"), 
                                backgroundColor: Color(0xFF10B981),
                              ),
                            );
                            context.pop();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366f1), Color(0xFF4F46E5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366f1).withOpacity(isLight ? 0.35 : 0.5), 
                              blurRadius: 18, 
                              offset: const Offset(0, 8),
                            )
                          ],
                        ),
                        alignment: Alignment.center,
                        child: _saving 
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.save_rounded, color: Colors.white, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    "SAVE WELLNESS PROFILE", 
                                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                  ),
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
      ),
    );
  }

  Widget _buildWellnessSlider({
    required BuildContext context,
    required bool isDark,
    required bool isLight,
    required IconData icon,
    required String title,
    required String subtitle,
    required int score,
    required Color accentColor,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: accentColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title, 
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.indigo[900], 
                      fontSize: 15, 
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    subtitle, 
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "$score%", 
                style: TextStyle(
                  color: accentColor, 
                  fontSize: 14, 
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: accentColor,
            inactiveTrackColor: accentColor.withOpacity(0.15),
            thumbColor: accentColor,
            overlayColor: accentColor.withOpacity(0.12),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          ),
          child: Slider(
            value: score.toDouble(),
            min: 0,
            max: 100,
            onChanged: (val) => onChanged(val.toInt()),
          ),
        ),
      ],
    );
  }
}
