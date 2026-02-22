import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:teacher_mobile_app/features/attendance/providers/attendance_provider.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

class AttendanceReportScreen extends ConsumerStatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  ConsumerState<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends ConsumerState<AttendanceReportScreen> {
  String _reportType = 'monthly'; // 'monthly' | 'yearly'
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  bool _loading = false;

  final List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  Future<void> _handleDownloadPDF() async {
    final teacherData = await ref.read(teacherDataProvider.future);
    final assignedClass = await ref.read(assignedClassProvider.future);
    final students = await ref.read(classStudentsProvider.future);

    if (teacherData == null || assignedClass == null || students.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Class info or students missing"), backgroundColor: Colors.red));
        return;
    }

    setState(() => _loading = true);

    try {
      final schoolId = teacherData['schoolId'] as String;
      final classId = assignedClass['id'] as String;
      final className = assignedClass['name'] as String;
      final teacherName = teacherData['name'] as String;

      // 1. Map students to keep track of absences
      final List<Map<String, dynamic>> studentsTrack = students.map((s) => {
        ...s,
        'absentCount': 0
      }).toList();

      // 2. Fetch Attendance
      final attendanceSnap = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .collection('attendance')
          .where('classId', isEqualTo: classId)
          .get();

      // 3. Process Attendance based on Report Type
      // Selected date formatting strings
      final monthStr = _selectedMonth.toString().padLeft(2, '0');
      final targetPrefix = _reportType == 'monthly' ? '$_selectedYear-$monthStr' : '$_selectedYear';

      for (var doc in attendanceSnap.docs) {
        final data = doc.data();
        final date = data['date'] as String;
        
        if (date.startsWith(targetPrefix)) {
          final records = data['records'] as List<dynamic>? ?? [];
          for (var r in records) {
             if (r['status'] == 'absent') {
                final studentMap = studentsTrack.firstWhere((s) => s['id'] == r['id'], orElse: () => {});
                if (studentMap.isNotEmpty) {
                    studentMap['absentCount'] = (studentMap['absentCount'] as int) + 1;
                }
             }
          }
        }
      }

      // 4. Sort by Absent Count (Low to High)
      studentsTrack.sort((a, b) => (a['absentCount'] as int).compareTo(b['absentCount'] as int));

      // 5. Generate PDF
      final pdf = pw.Document();
      
      final reportTitle = _reportType == 'monthly' ? "Attendance Report" : "Annual Attendance Report";
      final dateSubtitle = _reportType == 'monthly' ? "${_months[_selectedMonth - 1]} $_selectedYear" : "Year: $_selectedYear";

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              // Header
              pw.Container(
                color: PdfColor.fromHex('#4338ca'), // Deep Indigo
                padding: const pw.EdgeInsets.symmetric(vertical: 20),
                alignment: pw.Alignment.center,
                child: pw.Column(
                  children: [
                    pw.Text(reportTitle, style: pw.TextStyle(color: PdfColors.white, fontSize: 24, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text(dateSubtitle, style: const pw.TextStyle(color: PdfColors.white, fontSize: 14)),
                  ]
                )
              ),
              pw.SizedBox(height: 20),

              // Meta Info Box
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Class: $className', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      pw.SizedBox(height: 4),
                      pw.Text('Total Students: ${students.length}', style: const pw.TextStyle(fontSize: 12)),
                      pw.SizedBox(height: 4),
                      pw.Text('Teacher: $teacherName', style: const pw.TextStyle(fontSize: 12)),
                    ]
                  ),
                  pw.Text('Generated: ${DateTime.now().toString().split(' ')[0]}', style: const pw.TextStyle(fontSize: 12)),
                ]
              ),
              pw.SizedBox(height: 20),

              // Table
              pw.TableHelper.fromTextArray(
                headers: ['Roll No', 'Student Name', 'Total Absent Days'],
                data: studentsTrack.map((s) => [
                  s['rollNo']?.toString() ?? s['roll']?.toString() ?? '-',
                  s['name'] ?? 'Unknown',
                  s['absentCount'].toString()
                ]).toList(),
                border: pw.TableBorder.all(color: PdfColors.grey300),
                headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#6366f1')),
                cellAlignment: pw.Alignment.center,
                cellStyle: const pw.TextStyle(fontSize: 11),
                oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#f9fafb')),
              ),
            ];
          },
        )
      );

      // 6. Save and Share
      final output = await getTemporaryDirectory();
       final fileName = _reportType == 'monthly'
          ? "Attendance_Report_${className}_${dateSubtitle.replaceAll(' ', '_')}.pdf"
          : "Annual_Attendance_Report_${className}_$_selectedYear.pdf";
      
      final file = File("${output.path}/$fileName");
      await file.writeAsBytes(await pdf.save());

      if (mounted) {
         Share.shareXFiles([XFile(file.path)], text: 'Here is the $reportTitle');
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assignedClassAsync = ref.watch(assignedClassProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: assignedClassAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.indigoAccent)),
          error: (e, st) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
          data: (assignedClass) {
            if (assignedClass == null) {
              return Center(
                child: Text('No Class Assigned', style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
              );
            }

            return Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                            boxShadow: !isDark ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))] : [],
                          ),
                          child: Icon(Icons.chevron_left, color: isDark ? Colors.white : const Color(0xFF6366f1)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Attendance Report", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: isDark ? Colors.white : Colors.indigo[900])),
                          const Text("Download detailed reports", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),

                // Main Content
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                          boxShadow: !isDark ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 10))] : [],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 100, height: 100,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366f1).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.description, size: 48, color: Color(0xFF6366f1)),
                            ),
                            const SizedBox(height: 32),

                            // Toggle Type
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
                                borderRadius: BorderRadius.circular(16)
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _reportType = 'monthly'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(
                                          color: _reportType == 'monthly' ? const Color(0xFF6366f1) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(12)
                                        ),
                                        alignment: Alignment.center,
                                        child: Text("Monthly", style: TextStyle(color: _reportType == 'monthly' ? Colors.white : (isDark ? Colors.grey : Colors.grey[600]), fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(() => _reportType = 'yearly'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        decoration: BoxDecoration(
                                          color: _reportType == 'yearly' ? const Color(0xFF6366f1) : Colors.transparent,
                                          borderRadius: BorderRadius.circular(12)
                                        ),
                                        alignment: Alignment.center,
                                        child: Text("Yearly", style: TextStyle(color: _reportType == 'yearly' ? Colors.white : (isDark ? Colors.grey : Colors.grey[600]), fontWeight: FontWeight.bold)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Selectors
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(_reportType == 'monthly' ? "Select Month" : "Select Year", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            const SizedBox(height: 8),

                            if (_reportType == 'monthly')
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white : Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: const Color(0xFF6366f1).withOpacity(isDark ? 0.3 : 0.5), width: 2),
                                        boxShadow: [BoxShadow(color: const Color(0xFF6366f1).withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<int>(
                                          value: _selectedMonth,
                                          isExpanded: true,
                                          dropdownColor: Colors.white,
                                          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6366f1)),
                                          items: List.generate(12, (i) => DropdownMenuItem(
                                            value: i + 1,
                                            child: Text(_months[i], style: const TextStyle(color: Color(0xFF6366f1), fontWeight: FontWeight.bold)),
                                          )),
                                          onChanged: (val) => setState(() => _selectedMonth = val!),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 1,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white : Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: const Color(0xFF6366f1).withOpacity(isDark ? 0.3 : 0.5), width: 2),
                                        boxShadow: [BoxShadow(color: const Color(0xFF6366f1).withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<int>(
                                          value: _selectedYear,
                                          isExpanded: true,
                                          dropdownColor: Colors.white,
                                          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6366f1)),
                                          items: List.generate(5, (i) => DateTime.now().year - i).map((y) => DropdownMenuItem(
                                            value: y,
                                            child: Text(y.toString(), style: const TextStyle(color: Color(0xFF6366f1), fontWeight: FontWeight.bold)),
                                          )).toList(),
                                          onChanged: (val) => setState(() => _selectedYear = val!),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFF6366f1).withOpacity(isDark ? 0.3 : 0.5), width: 2),
                                  boxShadow: [BoxShadow(color: const Color(0xFF6366f1).withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _selectedYear,
                                    isExpanded: true,
                                    dropdownColor: Colors.white,
                                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6366f1)),
                                    items: List.generate(5, (i) => DateTime.now().year - i).map((y) => DropdownMenuItem(
                                      value: y,
                                      child: Text(y.toString(), style: const TextStyle(color: Color(0xFF6366f1), fontWeight: FontWeight.bold)),
                                    )).toList(),
                                    onChanged: (val) => setState(() => _selectedYear = val!),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 32),

                            // Download Button
                            GestureDetector(
                               onTap: () {
                                  if (!_loading) _handleDownloadPDF();
                               },
                               child: Container(
                                height: 56,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366f1),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [BoxShadow(color: const Color(0xFF6366f1).withOpacity(isDark ? 0.5 : 0.3), blurRadius: 16, offset: const Offset(0, 8))],
                                ),
                                alignment: Alignment.center,
                                child: _loading 
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                                  : Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(Icons.download, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text("DOWNLOAD REPORT", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                                      ],
                                    ),
                               ),
                            ),
                            const SizedBox(height: 16),
                            Text("This will generate a PDF report for ${assignedClass['name']} containing absence records sorted from lowest to highest.", 
                                 textAlign: TextAlign.center, 
                                 style: const TextStyle(color: Colors.grey, fontSize: 12, height: 1.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
        )
      )
    );
  }
}
