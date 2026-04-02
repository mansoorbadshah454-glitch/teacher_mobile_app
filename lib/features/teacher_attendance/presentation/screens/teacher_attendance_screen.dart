import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';
import 'package:teacher_mobile_app/features/teacher_attendance/providers/teacher_attendance_provider.dart';

class TeacherAttendanceScreen extends ConsumerStatefulWidget {
  const TeacherAttendanceScreen({super.key});

  @override
  ConsumerState<TeacherAttendanceScreen> createState() => _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState extends ConsumerState<TeacherAttendanceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // Header with Back button and Title
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              bottom: 16,
              left: 16,
              right: 16,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)], // Purple theme
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 4))
              ],
            ),
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
                const SizedBox(width: 16),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("My Attendance", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                    Text("Daily Check-in & Check-out", style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
          
          // Persistent Top Menu Tabs
          Container(
            color: isDark ? theme.colorScheme.surface : Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primary,
              unselectedLabelColor: Colors.grey,
              indicatorColor: AppTheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              tabs: const [
                Tab(text: "Scan Barcode"),
                Tab(text: "History"),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _ScanTabContent(),
                _HistoryTabContent(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanTabContent extends ConsumerWidget {
  const _ScanTabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(teacherAttendanceProvider);
    final todayLogAsync = ref.watch(todayTeacherAttendanceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final settingsAsync = ref.watch(schoolSettingsProvider);
    String startTime = "08:00";
    String endTime = "14:00";
    if (settingsAsync is AsyncData<Map<String, dynamic>>) {
       final data = settingsAsync.value;
       startTime = data['teacherStartTime'] ?? "08:00";
       endTime = data['teacherEndTime'] ?? "14:00";
    }
    final dutyString = "Duty Time: $startTime - $endTime";

    // Listen to state changes to show SnackBar on Success/Error
    ref.listen<TeacherAttendanceState>(teacherAttendanceProvider, (previous, next) {
      if (next.error != null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Scan Error", style: TextStyle(color: Colors.red)),
            content: Text(next.error!),
            actions: [
              TextButton(
                onPressed: () {
                  ref.read(teacherAttendanceProvider.notifier).clearMessages();
                  Navigator.of(context).pop();
                },
                child: const Text("Try Again"),
              ),
            ],
          ),
        );
      } else if (next.successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.successMessage!),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          )
        );
        ref.read(teacherAttendanceProvider.notifier).clearMessages();
      }
    });

    return todayLogAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      error: (e, st) => Center(child: Text("Error loading duty status: $e")),
      data: (todayLog) {
        final hasCheckedIn = todayLog != null && todayLog['checkIn'] != null;
        final hasCheckedOut = todayLog != null && todayLog['checkOut'] != null;

        if (hasCheckedOut) {
          // STATE C: Duty Completed
          return _buildDutyCompletedUI(context, todayLog, isDark, dutyString);
        } else if (hasCheckedIn) {
          // STATE B: Duty Active
          return _buildDutyActiveUI(context, ref, state, todayLog, isDark, dutyString);
        } else {
          // STATE A: Unscanned / Check-In phase
          return _buildCheckInUI(context, ref, state, isDark, dutyString);
        }
      },
    );
  }

  Widget _buildCheckInUI(BuildContext context, WidgetRef ref, TeacherAttendanceState state, bool isDark, String dutyString) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.qr_code_scanner, size: 80, color: AppTheme.primary.withOpacity(0.9)),
          ),
          const SizedBox(height: 32),
          const Text(
            "Mark Your Attendance",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            "Please scan the Daily Check-in Code provided by the school Principal to log your arrival.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: isDark ? Colors.grey[400] : Colors.grey[600], height: 1.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              dutyString,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primary),
            ),
          ),
          const SizedBox(height: 32),
          
          if (state.isLoading)
            const CircularProgressIndicator(color: AppTheme.primary)
          else
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => _openScanner(context, ref),
                icon: const Icon(Icons.camera_alt, color: Colors.white),
                label: const Text(
                  "Scan Barcode",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                  shadowColor: AppTheme.primary.withOpacity(0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDutyActiveUI(BuildContext context, WidgetRef ref, TeacherAttendanceState state, Map<String, dynamic> log, bool isDark, String dutyString) {
    final checkInTime = log['checkIn'] != null ? DateFormat('hh:mm a').format((log['checkIn'] as Timestamp).toDate()) : '--:--';
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated / Glowing Icon
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.green.withOpacity(0.2), blurRadius: 20, spreadRadius: 5),
              ]
            ),
            child: const Icon(Icons.check_circle, size: 80, color: Colors.green),
          ),
          const SizedBox(height: 32),
          const Text("Duty Active", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.green)),
          const SizedBox(height: 8),
          Text(dateStr, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.grey[400] : Colors.grey[600])),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              dutyString,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green),
            ),
          ),
          
          const SizedBox(height: 32),
          // Info Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: isDark ? [] : [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
              border: isDark ? Border.all(color: Colors.grey[700]!) : Border.all(color: Colors.grey[100]!),
            ),
            child: Column(
              children: [
                const Text("CHECKED IN AT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                Text(checkInTime, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
              ],
            ),
          ),
          
          const SizedBox(height: 48),
          if (state.isLoading)
            const CircularProgressIndicator(color: Colors.orange)
          else
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => _openScanner(context, ref),
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text(
                  "Scan for Check-out",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[600],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                  shadowColor: Colors.orange.withOpacity(0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDutyCompletedUI(BuildContext context, Map<String, dynamic> log, bool isDark, String dutyString) {
    final checkInTime = log['checkIn'] != null ? DateFormat('hh:mm a').format((log['checkIn'] as Timestamp).toDate()) : '--:--';
    final checkOutTime = log['checkOut'] != null ? DateFormat('hh:mm a').format((log['checkOut'] as Timestamp).toDate()) : '--:--';
    final dateStr = DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now());

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified, size: 80, color: Colors.blue),
          ),
          const SizedBox(height: 32),
          const Text("Duty Completed", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.blue)),
          const SizedBox(height: 8),
          Text(dateStr, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.grey[400] : Colors.grey[600])),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              dutyString,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ),
          
          const SizedBox(height: 32),
          // Info Cards Row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      const Text("IN", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                      const SizedBox(height: 8),
                      Text(checkInTime, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      const Text("OUT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                      const SizedBox(height: 8),
                      Text(checkOutTime, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_clock, size: 18, color: Colors.grey[500]),
                const SizedBox(width: 8),
                Text(
                  "Scanner locked for today",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openScanner(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ScannerView(
          onDetect: (String barcode) {
            Navigator.pop(context); // Close scanner view
            ref.read(teacherAttendanceProvider.notifier).scanBarcode(barcode);
          },
        ),
      ),
    );
  }
}

// History Tab Content
class _HistoryTabContent extends ConsumerWidget {
  const _HistoryTabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(attendanceMonthProvider);
    final year = ref.watch(attendanceYearProvider);
    final historyAsync = ref.watch(monthlyTeacherAttendanceProvider);
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Webapp Colors matched, but dulled slightly in Dark mode
    Color presentColor = isDark ? const Color(0xFF0D9467) : const Color(0xFF10b981);
    Color absentColor = isDark ? const Color(0xFFC83838) : const Color(0xFFef4444);
    Color halfDayColor = isDark ? const Color(0xFFD08304) : const Color(0xFFf59e0b);
    Color holidayColor = isDark ? const Color(0xFF2C6BD2) : const Color(0xFF3b82f6);
    Color upcomingColor = isDark ? Colors.grey[800]! : const Color(0xFFf1f5f9);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstDayOfMonth = DateTime(year, month, 1).weekday; // 1 (Mon) to 7 (Sun)
    
    // Dart's weekday uses 1=Mon, 7=Sun. We want 0=Sun to 6=Sat
    final frontEmptyCells = firstDayOfMonth == 7 ? 0 : firstDayOfMonth;

    return Column(
      children: [
        // Top Controls: Month/Year Dropdowns & Legend
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFf8fafc),
            border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : const Color(0xFFe2e8f0))),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_month, size: 20, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: month,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.arrow_drop_down),
                        items: List.generate(12, (index) {
                          final pMonth = index + 1;
                          final monthName = DateFormat('MMMM').format(DateTime(2020, pMonth));
                          return DropdownMenuItem(value: pMonth, child: Text(monthName, style: const TextStyle(fontWeight: FontWeight.bold)));
                        }),
                        onChanged: (val) {
                          if (val != null) ref.read(attendanceMonthProvider.notifier).state = val;
                        },
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: year,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.arrow_drop_down),
                        items: [
                          DropdownMenuItem(value: now.year, child: Text("${now.year}", style: const TextStyle(fontWeight: FontWeight.bold))),
                          DropdownMenuItem(value: now.year - 1, child: Text("${now.year - 1}", style: const TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        onChanged: (val) {
                          if (val != null) ref.read(attendanceYearProvider.notifier).state = val;
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Legend row
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _buildLegendDot("Present", presentColor, isDark),
                  _buildLegendDot("Half Day", halfDayColor, isDark),
                  _buildLegendDot("Absent", absentColor, isDark),
                  _buildLegendDot("Holiday", holidayColor, isDark),
                ],
              )
            ],
          ),
        ),
        
        // Days Row Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map((d) => Expanded(child: Text(d, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey[600], fontSize: 13))))
                .toList(),
          ),
        ),

        // Grid Calendar
        Expanded(
          child: historyAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            error: (e, st) => Center(child: Text("Error: $e")),
            data: (historyMap) {
              return GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 0.85,
                ),
                itemCount: frontEmptyCells + daysInMonth,
                itemBuilder: (context, index) {
                  if (index < frontEmptyCells) {
                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.02) : const Color(0xFFf8fafc),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  }
                  
                  final day = index - frontEmptyCells + 1;
                  final dateObj = DateTime(year, month, day);
                  final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
                  
                  final log = historyMap[dateStr];
                  // If no log exists but date is in the past, consider it absent or holiday (mock logic fallback). 
                  // But usually, real systems generate "Absent" automatically. If missing, we assume "Absent" or "Holiday" for Sundays.
                  String status = "Upcoming";
                  // Make today upcoming instead of absent if log is missing
                  if (!dateObj.isBefore(today)) {
                    status = "Upcoming";
                  } else if (dateObj.weekday == 7) {
                    status = "Holiday"; // Sunday
                  } else if (log != null) {
                    status = log['status'] ?? "Present";
                  } else {
                    status = "Absent"; // Missing log for past day
                  }

                  Color bgColor;
                  Color textColor = Colors.white;
                  
                  if (status == "Present") bgColor = presentColor;
                  else if (status == "Half Day") bgColor = halfDayColor;
                  else if (status == "Absent") bgColor = absentColor;
                  else if (status == "Holiday") bgColor = holidayColor;
                  else {
                    bgColor = upcomingColor;
                    textColor = isDark ? Colors.grey[400]! : Colors.grey[600]!;
                  }

                  return GestureDetector(
                    onTap: () {
                      if (log != null && (status == "Present" || status == "Half Day")) {
                        _showDayDetailsBottomSheet(context, log, dateStr);
                      } else if (status == "Holiday" || status == "Absent") {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Marked as $status"), duration: const Duration(seconds: 1)));
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: status != "Upcoming" && !isDark 
                            ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))] 
                            : [],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("$day", style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(
                            status == "Upcoming" ? "-" : status, 
                            style: TextStyle(color: textColor.withOpacity(0.9), fontWeight: FontWeight.bold, fontSize: 8),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLegendDot(String label, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.grey[300] : Colors.grey[700])),
      ],
    );
  }

  void _showDayDetailsBottomSheet(BuildContext context, Map<String, dynamic> log, String dateStr) {
    final checkInTime = log['checkIn'] != null ? DateFormat('hh:mm a').format(log['checkIn'].toDate()) : '--:--';
    final checkOutTime = log['checkOut'] != null ? DateFormat('hh:mm a').format(log['checkOut'].toDate()) : '--:--';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      backgroundColor: isDark ? Theme.of(context).colorScheme.surface : Colors.white,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 24),
              Text("Attendance Details", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary)),
              Text(dateStr, style: TextStyle(color: Colors.grey[500])),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.login, size: 16, color: Colors.green),
                              SizedBox(width: 6),
                              Text("Check In", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(checkInTime, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.logout, size: 16, color: Colors.orange),
                              SizedBox(width: 6),
                              Text("Check Out", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(checkOutTime, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.grey[800] : Colors.grey[100],
                    foregroundColor: isDark ? Colors.white : Colors.black87,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text("Close", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Scanner Screen
class ScannerView extends StatefulWidget {
  final Function(String) onDetect;
  
  const ScannerView({super.key, required this.onDetect});

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> {
  bool _isProcessing = false;
  MobileScannerController controller = MobileScannerController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Scan QR Code"),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.switch_camera),
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (capture) {
              if (_isProcessing) return;
              
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                if (barcode.rawValue != null) {
                  setState(() => _isProcessing = true);
                  widget.onDetect(barcode.rawValue!);
                  break;
                }
              }
            },
          ),
          // Scanner Overlay Mask
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primary, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              "Center the code inside the frame",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
