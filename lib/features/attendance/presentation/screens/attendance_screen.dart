import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:teacher_mobile_app/features/attendance/providers/attendance_provider.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/features/attendance/screens/leave_letter_screen.dart';
import 'package:teacher_mobile_app/core/services/sync_queue_service.dart';

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

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant StudentAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId || oldWidget.profilePic != widget.profilePic) {
      _resolveImage();
    }
  }

  void _resolveImage() {
    // Phase 1: Immediate synchronous resolution from document data
    if (widget.profilePic != null && widget.profilePic!.isNotEmpty) {
      String resolvedPic = widget.profilePic!;

      if (resolvedPic.contains('api.dicebear.com') && resolvedPic.contains('/svg')) {
        resolvedPic = resolvedPic.replaceAll('/svg', '/png');
      }

      if (resolvedPic.startsWith('http') || resolvedPic.startsWith('data:image')) {
        _imageUrl = resolvedPic;
        return;
      }
    }

    _imageUrl = null;

    // Phase 2: Background Storage fetch ONLY if online (never block UI or hang offline)
    _fetchStorageImageInBackground();
  }

  Future<void> _fetchStorageImageInBackground() async {
    try {
      final bool online = await SyncQueueService.isOnline();
      if (!online) return; // Zero network hang if offline

      final storagePath = 'schools/${widget.schoolId}/students/${widget.studentId}/profile.jpg';
      final ref = FirebaseStorage.instance.ref(storagePath);
      final url = await ref.getDownloadURL();
      if (mounted) {
        setState(() {
          _imageUrl = url;
        });
      }
    } catch (_) {
      // Graceful fallback - no UI bricking or infinite spinning
    }
  }

  Widget _buildFallback(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05), width: 2),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.person, size: widget.size * 0.5, color: isDark ? Colors.grey : Colors.grey[400]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_imageUrl != null && _imageUrl!.startsWith('http')) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05), width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: _imageUrl!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 100),
            placeholder: (context, url) => _buildFallback(context),
            errorWidget: (context, url, error) => _buildFallback(context),
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
            border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05), width: 2),
            image: DecorationImage(
              image: MemoryImage(bytes),
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (e) {
        return _buildFallback(context);
      }
    }

    return _buildFallback(context);
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
    final isMarkedToday = ref.watch(isAttendanceMarkedTodayProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: assignedClassAsync.when(
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
                
                final String schoolId = teacherData['schoolId']?.toString() ?? '';
                final Map<String, String> attendanceMap = attendanceState.value ?? {};
                final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

                // Helper to resolve live status directly from Firestore student doc (updated live by Gatekeeper QR)
                String resolveLiveStatus(Map<String, dynamic> s) {
                  final sId = s['id']?.toString() ?? '';
                  if (s['lastAttendanceDate']?.toString() == todayStr &&
                      (s['status']?.toString().isNotEmpty ?? false)) {
                    return s['status'].toString();
                  }
                  final activeLeave = s['activeLeave'];
                  if (activeLeave is Map && activeLeave['status'] == 'granted') {
                    final startStr = activeLeave['startDate']?.toString().split('T')[0] ?? '';
                    final endStr = activeLeave['endDate']?.toString().split('T')[0] ?? '';
                    if (startStr.isNotEmpty &&
                        endStr.isNotEmpty &&
                        todayStr.compareTo(startStr) >= 0 &&
                        todayStr.compareTo(endStr) <= 0) {
                      return 'leave_granted';
                    }
                  }
                  return attendanceMap[sId] ?? 'absent';
                }

                bool hasPendingLeave(Map<String, dynamic> s, String liveStatus) {
                  if (liveStatus == 'leave_granted') return false;
                  final activeLeave = s['activeLeave'];
                  if (activeLeave is Map && activeLeave['status'] == 'pending') {
                    final endStr = activeLeave['endDate']?.toString().split('T')[0] ?? '';
                    if (endStr.isNotEmpty && todayStr.compareTo(endStr) <= 0) {
                      return true;
                    }
                  }
                  return false;
                }

                int presentCount = students.where((s) => resolveLiveStatus(s) == 'present').length;
                int absentCount = students.length - presentCount;

                List<Map<String, dynamic>> filteredStudents = students.where((s) {
                  final nameMatches = (s['name']?.toString() ?? '').toLowerCase().contains(searchFilter.toLowerCase());
                  final rollMatches = (s['rollNo']?.toString() ?? s['roll']?.toString() ?? '').toLowerCase().contains(searchFilter.toLowerCase());
                  final searchMatch = nameMatches || rollMatches;

                  final status = resolveLiveStatus(s);
                  if (statsFilter == 'present') return searchMatch && status == 'present';
                  if (statsFilter == 'absent') return searchMatch && (status == 'absent' || status == 'leave_granted');
                  return searchMatch;
                }).toList();

                // Sort: Pending Leave & Approved Leave ALWAYS at the TOP, then Present, then Absent
                filteredStudents.sort((a, b) {
                  int priority(Map<String, dynamic> s) {
                    final st = resolveLiveStatus(s);
                    if (hasPendingLeave(s, st)) return 0;
                    if (st == 'leave_granted') return 1;
                    if (st == 'present') return 2;
                    return 3;
                  }
                  final pDiff = priority(a).compareTo(priority(b));
                  if (pDiff != 0) return pDiff;
                  return (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? '');
                });

                return Stack(
                  children: [
                    Column(
                      children: [
                        // Header Container
                        Container(
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
                              Expanded(
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () => context.pop(),
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
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              const Flexible(
                                                child: Text(
                                                  "Class Attendance",
                                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withOpacity(0.22),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  "VIEW ONLY",
                                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.4),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            "${assignedClass['name']} • ${DateFormat('EEEE, MMMM d').format(DateTime.now())}",
                                            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.8)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Row(
                                children: [
                                  ValueListenableBuilder<int>(
                                    valueListenable: SyncQueueService.pendingCountNotifier,
                                    builder: (context, pendingCount, _) {
                                      if (pendingCount == 0) return const SizedBox.shrink();
                                      return Container(
                                        margin: const EdgeInsets.only(right: 8),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.25),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.white.withOpacity(0.4)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.cloud_queue, size: 14, color: Colors.white),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$pendingCount Queued',
                                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  GestureDetector(
                                    onTap: () => context.push('/attendance-report'),
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                                      ),
                                      child: const Icon(Icons.chevron_right, color: Colors.white),
                                    ),
                                  ),
                                ],
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
                                      color: statsFilter == 'present' 
                                          ? Colors.greenAccent.withOpacity(0.1) 
                                          : (isDark ? Colors.white.withOpacity(0.03) : Colors.white),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: statsFilter == 'present' 
                                            ? Colors.greenAccent 
                                            : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                                        width: statsFilter == 'present' ? 2 : 1,
                                      ),
                                      boxShadow: !isDark ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))] : [],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("TOTAL PRESENTS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statsFilter == 'present' ? (isDark ? Colors.greenAccent : Colors.green[700]) : Colors.grey)),
                                        const SizedBox(height: 4),
                                        Text("$presentCount", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
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
                                      color: statsFilter == 'absent' 
                                          ? Colors.pinkAccent.withOpacity(0.1) 
                                          : (isDark ? Colors.white.withOpacity(0.03) : Colors.white),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: statsFilter == 'absent' 
                                            ? Colors.pinkAccent 
                                            : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                                        width: statsFilter == 'absent' ? 2 : 1,
                                      ),
                                      boxShadow: !isDark ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))] : [],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("TOTAL ABSENTS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statsFilter == 'absent' ? (isDark ? Colors.pinkAccent : Colors.pink[700]) : Colors.grey)),
                                        const SizedBox(height: 4),
                                        Text("$absentCount", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.black87)),
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
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                              boxShadow: !isDark ? [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))] : [],
                            ),
                            child: TextField(
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                              onChanged: (val) => ref.read(classSearchQueryProvider.notifier).state = val,
                              decoration: InputDecoration(
                                hintText: "Search by Name or Roll No...",
                                hintStyle: TextStyle(color: isDark ? Colors.grey : Colors.grey[500]),
                                prefixIcon: Icon(Icons.search, color: isDark ? Colors.grey : Colors.grey[500]),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(16),
                              ),
                            ),
                          ),
                        ),

                        // List
                        Expanded(
                          child: filteredStudents.isEmpty
                              ? const Center(child: Text("No records found.", style: TextStyle(color: Colors.grey)))
                              : ListView.builder(
                                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
                                  itemCount: filteredStudents.length,
                                  itemBuilder: (context, index) {
                                    final student = filteredStudents[index];
                                    final sId = student['id']?.toString() ?? '';
                                    final status = resolveLiveStatus(student);
                                    final isPresent = status == 'present';
                                    final isLeave = status == 'leave_granted' || hasPendingLeave(student, status);

                                    final gateLogs = student['gateLogs'] is Map ? student['gateLogs'] as Map : null;
                                    final todayGate = (gateLogs != null && gateLogs[todayStr] is Map)
                                        ? Map<String, dynamic>.from(gateLogs[todayStr] as Map)
                                        : <String, dynamic>{};
                                    final String? gateInTime = (student['gateInDate']?.toString() == todayStr &&
                                            (student['gateInTime']?.toString().isNotEmpty ?? false))
                                        ? student['gateInTime'].toString()
                                        : todayGate['inTime']?.toString();
                                    final String? gateOutTime = (student['gateOutDate']?.toString() == todayStr &&
                                            (student['gateOutTime']?.toString().isNotEmpty ?? false))
                                        ? student['gateOutTime'].toString()
                                        : todayGate['outTime']?.toString();

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(
                                          color: isLeave
                                              ? Colors.orangeAccent
                                              : (isPresent
                                                  ? const Color(0xFF10b981)
                                                  : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05))),
                                        ),
                                        boxShadow: !isDark ? [BoxShadow(color: (isPresent ? const Color(0xFF10b981) : Colors.black).withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))] : [],
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
                                                Text(student['name'] ?? 'Unknown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.indigo[900])),
                                                const SizedBox(height: 4),
                                                Text("Roll: ${student['rollNo'] ?? student['roll'] ?? '-'} • Class: ${assignedClass['name']}", style: TextStyle(fontSize: 12, color: isDark ? Colors.grey : Colors.grey[600], fontWeight: FontWeight.w500)),
                                                if ((gateInTime != null && gateInTime.isNotEmpty) || (gateOutTime != null && gateOutTime.isNotEmpty)) ...[
                                                  const SizedBox(height: 6),
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    children: [
                                                      if (gateInTime != null && gateInTime.isNotEmpty)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFF10b981).withOpacity(0.12),
                                                            borderRadius: BorderRadius.circular(8),
                                                          ),
                                                          child: Text(
                                                            'In: $gateInTime',
                                                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF059669)),
                                                          ),
                                                        ),
                                                      if (gateOutTime != null && gateOutTime.isNotEmpty)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.deepOrange.withOpacity(0.12),
                                                            borderRadius: BorderRadius.circular(8),
                                                          ),
                                                          child: Text(
                                                            'Out: $gateOutTime',
                                                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.deepOrange),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          Builder(builder: (context) {
                                            final activeLeave = student['activeLeave'];
                                            bool hasPendingLeaveToday = false;
                                            bool isLeaveGranted = status == 'leave_granted';

                                            if (!isLeaveGranted && activeLeave != null && activeLeave['status'] == 'pending') {
                                              final endStr = activeLeave['endDate'].toString().split('T')[0];
                                              final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

                                              // Show pending action if leave has not expired yet
                                              if (todayStr.compareTo(endStr) <= 0) {
                                                hasPendingLeaveToday = true;
                                              }
                                            }

                                            if (hasPendingLeaveToday) {
                                              return Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(Icons.picture_as_pdf, color: Colors.blueAccent),
                                                    onPressed: () {
                                                      Navigator.push(context, MaterialPageRoute(
                                                        builder: (_) => LeaveLetterScreen(
                                                          studentData: student,
                                                          schoolName: teacherData['schoolName'] ?? 'School',
                                                        )
                                                      ));
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.check_circle, color: Colors.green),
                                                    onPressed: () async {
                                                      // Grant
                                                      ref.read(attendanceProvider.notifier).setStatus(sId, 'leave_granted');
                                                      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                                                      final Map<String, dynamic> updatePayload = {
                                                        'activeLeave.status': 'granted',
                                                        'status': 'leave_granted',
                                                        'lastAttendanceDate': todayStr,
                                                        'attendanceHistory.$todayStr': 'leave_granted',
                                                      };

                                                      // Pre-populate all dates in range for multi-day leaves
                                                      try {
                                                        final start = DateTime.parse(activeLeave['startDate'].toString().split('T')[0]);
                                                        final end = DateTime.parse(activeLeave['endDate'].toString().split('T')[0]);
                                                        var curr = start;
                                                        while (!curr.isAfter(end)) {
                                                          final dStr = DateFormat('yyyy-MM-dd').format(curr);
                                                          updatePayload['attendanceHistory.$dStr'] = 'leave_granted';
                                                          curr = curr.add(const Duration(days: 1));
                                                        }
                                                      } catch (_) {}

                                                      await FirebaseFirestore.instance
                                                        .collection('schools').doc(schoolId)
                                                        .collection('classes').doc(assignedClass['id'])
                                                        .collection('students').doc(sId)
                                                        .update(updatePayload);
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                                    onPressed: () async {
                                                      // Reject
                                                      ref.read(attendanceProvider.notifier).setStatus(sId, 'absent');
                                                      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                                                      await FirebaseFirestore.instance
                                                        .collection('schools').doc(schoolId)
                                                        .collection('classes').doc(assignedClass['id'])
                                                        .collection('students').doc(sId)
                                                        .update({
                                                          'activeLeave.status': 'rejected',
                                                          'attendanceHistory.$todayStr': 'absent'
                                                        });
                                                    },
                                                  ),
                                                ],
                                              );
                                            }

                                            if (isLeaveGranted) {
                                              return Container(
                                                width: 90,
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                                decoration: BoxDecoration(
                                                  color: Colors.orangeAccent.withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(14),
                                                  border: Border.all(color: Colors.orangeAccent),
                                                ),
                                                alignment: Alignment.center,
                                                child: const Text("ON LEAVE", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                              );
                                            }

                                            // View-Only Attendance Badge (Managed automatically by Gatekeeper QR Scanner)
                                            return Container(
                                              width: 90,
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                              decoration: BoxDecoration(
                                                color: isPresent
                                                    ? const Color(0xFF10b981).withOpacity(0.14)
                                                    : Colors.redAccent.withOpacity(0.10),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: isPresent
                                                      ? const Color(0xFF10b981)
                                                      : Colors.redAccent.withOpacity(0.45),
                                                ),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                isPresent ? "PRESENT" : "ABSENT",
                                                style: TextStyle(
                                                  color: isPresent ? const Color(0xFF059669) : Colors.redAccent,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
    );
  }
}
