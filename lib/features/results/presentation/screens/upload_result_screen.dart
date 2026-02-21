import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/my_class/providers/my_class_provider.dart';
import 'package:teacher_mobile_app/features/attendance/providers/attendance_provider.dart';
import 'package:teacher_mobile_app/features/results/providers/result_upload_provider.dart';
import 'package:teacher_mobile_app/features/attendance/presentation/screens/attendance_screen.dart';

class UploadResultScreen extends ConsumerStatefulWidget {
  final String studentId;

  const UploadResultScreen({super.key, required this.studentId});

  @override
  ConsumerState<UploadResultScreen> createState() => _UploadResultScreenState();
}

class _UploadResultScreenState extends ConsumerState<UploadResultScreen> {
  @override
  void initState() {
    super.initState();
    // Clear state when opening
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(resultUploadProvider.notifier).clearState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(classStudentsProvider);
    final teacherDataAsync = ref.watch(teacherDataProvider);
    final uploadState = ref.watch(resultUploadProvider);

    // Listen for success to show snackbar
    ref.listen<ResultUploadState>(resultUploadProvider, (previous, next) {
      if (next.isSuccess && (previous == null || !previous.isSuccess)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Result Card Uploaded Successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh student data so "Uploaded" badge appears
        ref.invalidate(classStudentsProvider);
        context.pop();
      }
      if (next.error != null && (previous == null || previous.error != next.error)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30),
          onPressed: () => context.pop(),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Upload Result Cards",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              "for parents",
              style: TextStyle(color: Colors.grey, fontSize: 12),
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
            
            // Find specific student
            final studentIdx = students.indexWhere((s) => s['id'] == widget.studentId);
            if (studentIdx == -1) {
              return const Center(child: Text('Student not found', style: TextStyle(color: Colors.white)));
            }
            final student = students[studentIdx];
            final hasResult = student['uploadedResultUrl'] != null;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Student Info Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        StudentAvatar(
                          studentId: student['id'],
                          schoolId: schoolId,
                          profilePic: student['profilePic'] ?? student['avatar'],
                          size: 100,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          student['name'] ?? 'Unknown',
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Roll No: ${student['rollNo'] ?? student['roll'] ?? '-'}",
                          style: const TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        if (hasResult) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.withOpacity(0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  "Result Already Uploaded",
                                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Upload Button Area
                  if (uploadState.selectedFile == null)
                    GestureDetector(
                      onTap: () {
                        ref.read(resultUploadProvider.notifier).pickFile();
                      },
                      child: Container(
                        width: double.infinity,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.indigoAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.indigoAccent.withOpacity(0.5), style: BorderStyle.solid, width: 2),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.upload_file, color: Colors.indigoAccent, size: 64),
                            SizedBox(height: 16),
                            Text(
                              "Tap to Select File",
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 8),
                            Text(
                              "Supported: PDF, JPG, PNG",
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.indigoAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.indigoAccent.withOpacity(0.5)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.insert_drive_file, color: Colors.indigoAccent, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            uploadState.fileName ?? "Selected File",
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton(
                                onPressed: uploadState.isLoading
                                    ? null
                                    : () => ref.read(resultUploadProvider.notifier).clearState(),
                                child: const Text("Change File", style: TextStyle(color: Colors.grey)),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton(
                                onPressed: uploadState.isLoading
                                    ? null
                                    : () => ref.read(resultUploadProvider.notifier).uploadResult(student['id']),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigoAccent,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: uploadState.isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                      )
                                    : const Text("Upload Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
