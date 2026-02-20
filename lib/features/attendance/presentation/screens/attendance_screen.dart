import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/attendance/providers/attendance_provider.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:intl/intl.dart';

class StudentAvatar extends StatefulWidget {
  final String studentId;
  final String schoolId;
  final String? profilePic;
  final double size;

  const StudentAvatar({
    super.key,
    required this.studentId,
    required this.schoolId,
    this.profilePic,
    this.size = 52,
  });

  @override
  State<StudentAvatar> createState() => _StudentAvatarState();
}

class _StudentAvatarState extends State<StudentAvatar> {
  String? _imageUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchImage();
  }

  Future<void> _fetchImage() async {
    try {
      final storagePath = 'schools/${widget.schoolId}/students/${widget.studentId}/profile.jpg';
      final ref = FirebaseStorage.instance.ref(storagePath);
      final url = await ref.getDownloadURL();
      setState(() {
        _imageUrl = url;
        _loading = false;
      });
    } catch (e) {
      if (widget.profilePic != null && widget.profilePic!.startsWith('data:image')) {
        setState(() {
          _imageUrl = widget.profilePic;
          _loading = false;
        });
      } else {
        setState(() {
          _imageUrl = widget.profilePic; // Might be a standard http url
          _loading = false;
        });
      }
    }
  }

  Widget _buildFallback() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 2),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.person, size: widget.size * 0.5, color: Colors.grey),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
        ),
      );
    }

    if (_imageUrl != null && _imageUrl!.startsWith('http')) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 2),
          image: DecorationImage(
            image: CachedNetworkImageProvider(_imageUrl!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    if (_imageUrl != null && _imageUrl!.startsWith('data:image')) {
      try {
        final base64String = _imageUrl!.split(',').last;
        final Uint8List bytes = base64Decode(base64String);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 2),
            image: DecorationImage(
              image: MemoryImage(bytes),
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (e) {
        return _buildFallback();
      }
    }

    return _buildFallback();
  }
}

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // After build is complete, refresh state if needed (handled in provider init)
  }

  @override
  Widget build(BuildContext context) {
    final teacherDataAsync = ref.watch(teacherDataProvider);
    final assignedClassAsync = ref.watch(assignedClassProvider);
    final studentsAsync = ref.watch(classStudentsProvider);
    final attendanceState = ref.watch(attendanceProvider);
    final searchFilter = ref.watch(classSearchQueryProvider);
    final statsFilter = ref.watch(statsFilterProvider);

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
                      const Text('You are not assigned to any specific class. Please contact the Principal.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14)),
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
                final Map<String, String> attendanceMap = attendanceState.value ?? {};
                
                int presentCount = attendanceMap.values.where((v) => v == 'present').length;
                int absentCount = students.length - presentCount;

                List<Map<String, dynamic>> filteredStudents = students.where((s) {
                  final nameMatches = s['name'].toString().toLowerCase().contains(searchFilter.toLowerCase());
                  final rollMatches = (s['rollNo']?.toString() ?? s['roll']?.toString() ?? '').toLowerCase().contains(searchFilter.toLowerCase());
                  final searchMatch = nameMatches || rollMatches;

                  final status = attendanceMap[s['id']] ?? 'absent';
                  if (statsFilter == 'present') return searchMatch && status == 'present';
                  if (statsFilter == 'absent') return searchMatch && status == 'absent';
                  return searchMatch;
                }).toList();

                return Stack(
                  children: [
                    Column(
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
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
                                      const Text("Mark Attendance", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                                      Text("${assignedClass['name']} • ${DateFormat('EEEE, MMMM d').format(DateTime.now())}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    ],
                                  ),
                                ],
                              ),
                              GestureDetector(
                                onTap: () => context.push('/attendance-report'),
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366f1),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [BoxShadow(color: const Color(0xFF6366f1).withOpacity(0.5), blurRadius: 12, offset: const Offset(0, 4))],
                                  ),
                                  child: const Icon(Icons.chevron_right, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Stats
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => ref.read(statsFilterProvider.notifier).state = statsFilter == 'present' ? 'all' : 'present',
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: statsFilter == 'present' ? Colors.greenAccent.withOpacity(0.1) : Colors.white.withOpacity(0.03),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: statsFilter == 'present' ? Colors.greenAccent : Colors.white.withOpacity(0.05)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("TOTAL PRESENTS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statsFilter == 'present' ? Colors.greenAccent : Colors.grey)),
                                        const SizedBox(height: 4),
                                        Text("$presentCount", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => ref.read(statsFilterProvider.notifier).state = statsFilter == 'absent' ? 'all' : 'absent',
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: statsFilter == 'absent' ? Colors.pinkAccent.withOpacity(0.1) : Colors.white.withOpacity(0.03),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(color: statsFilter == 'absent' ? Colors.pinkAccent : Colors.white.withOpacity(0.05)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("TOTAL ABSENTS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statsFilter == 'absent' ? Colors.pinkAccent : Colors.grey)),
                                        const SizedBox(height: 4),
                                        Text("$absentCount", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Search
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: TextField(
                              style: const TextStyle(color: Colors.white),
                              onChanged: (val) => ref.read(classSearchQueryProvider.notifier).state = val,
                              decoration: const InputDecoration(
                                hintText: "Search by Name or Roll No...",
                                hintStyle: TextStyle(color: Colors.grey),
                                prefixIcon: Icon(Icons.search, color: Colors.grey),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(16),
                              ),
                            ),
                          ),
                        ),

                        // List
                        Expanded(
                          child: filteredStudents.isEmpty
                              ? const Center(child: Text("No records found.", style: TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 100),
                                  itemCount: filteredStudents.length,
                                  itemBuilder: (context, index) {
                                    final student = filteredStudents[index];
                                    final sId = student['id'];
                                    final status = attendanceMap[sId] ?? 'absent';
                                    final isPresent = status == 'present';

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.03),
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(color: isPresent ? const Color(0xFF6366f1) : Colors.white.withOpacity(0.05)),
                                      ),
                                      child: Row(
                                        children: [
                                          StudentAvatar(
                                            studentId: sId,
                                            schoolId: schoolId,
                                            profilePic: student['profilePic'] ?? student['avatar'],
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(student['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                                                const SizedBox(height: 4),
                                                Text("Roll: ${student['rollNo'] ?? student['roll'] ?? '-'} • Class: ${assignedClass['name']}", style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
                                              ],
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              ref.read(attendanceProvider.notifier).toggleStatus(sId);
                                            },
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 200),
                                              width: 90,
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                              decoration: BoxDecoration(
                                                color: isPresent ? const Color(0xFF6366f1) : Colors.white.withOpacity(0.03),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(color: isPresent ? Colors.transparent : Colors.white.withOpacity(0.05)),
                                                boxShadow: isPresent ? [BoxShadow(color: const Color(0xFF6366f1).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : [],
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                isPresent ? "PRESENT" : "MARK",
                                                style: TextStyle(
                                                  color: isPresent ? Colors.white : Colors.grey,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
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

                    // Bottom Floating Button
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 24,
                      child: GestureDetector(
                        onTap: () async {
                          if (_saving) return;
                          setState(() => _saving = true);
                          try {
                            await ref.read(attendanceProvider.notifier).saveAttendance();
                            if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Attendance marked & parents notified!"), backgroundColor: Colors.green));
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
                                    Icon(Icons.how_to_reg, color: Colors.white),
                                    SizedBox(width: 8),
                                    Text("CONFIRM ATTENDANCE", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                                  ],
                                ),
                        ),
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
