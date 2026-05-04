import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';

String _getSubjectText(String template) {
  final lower = template.toLowerCase();
  if (lower == 'sick leave' || lower == 'urgent work' || lower == 'medical checkup' || lower == 'family event') {
    return 'Application for $template';
  }
  return 'Application for Leave';
}

String _getLeaveBodyText(String template, String name, String rollNo, String startDate, String endDate, String schoolName) {
  String baseIntro = 'With due respect, this is to inform you that my child, $name (Roll No: $rollNo), studying in your class at $schoolName,';
  final lower = template.toLowerCase();
  
  if (lower == 'sick leave') {
    return '$baseIntro is unwell and will not be able to attend school from $startDate to $endDate.';
  } else if (lower == 'urgent work') {
    return '$baseIntro has an urgent piece of work at home and will not be able to attend school from $startDate to $endDate.';
  } else if (lower == 'medical checkup') {
    return '$baseIntro has a scheduled medical appointment and will not be able to attend school from $startDate to $endDate.';
  } else if (lower == 'family event') {
    return '$baseIntro needs to attend an important family event and will not be able to attend school from $startDate to $endDate.';
  } else {
    // Custom reason ("Other")
    return '$baseIntro will not be able to attend school from $startDate to $endDate due to the following reason: $template.';
  }
}

class LeaveLetterScreen extends StatelessWidget {
  final Map<String, dynamic> studentData;
  final String schoolName;

  const LeaveLetterScreen({
    Key? key,
    required this.studentData,
    required this.schoolName,
  }) : super(key: key);

  Future<void> _generatePdf(BuildContext context) async {
    final leave = studentData['activeLeave'] as Map<String, dynamic>;
    final pdf = pw.Document();

    String formatDate(String? dateStr) {
      if (dateStr == null) return '';
      try {
        final DateTime d = DateTime.parse(dateStr);
        return DateFormat('dd/MM/yyyy').format(d);
      } catch (e) {
        return dateStr.split('T')[0];
      }
    }

    final String startDateStr = formatDate(leave['startDate']?.toString());
    final String endDateStr = formatDate(leave['endDate']?.toString());
    final parentName = studentData['parentDetails']?['parentName'] ?? studentData['parentDetails']?['name'] ?? 'Parent/Guardian';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Center(
                child: pw.Text(
                  schoolName.toUpperCase(),
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Center(
                child: pw.Text(
                  'FORMAL LEAVE APPLICATION',
                  style: pw.TextStyle(fontSize: 16, color: PdfColors.grey700),
                ),
              ),
              pw.Divider(thickness: 2),
              pw.SizedBox(height: 30),

              // Date
              pw.Text('Date: ${DateFormat('MMMM dd, yyyy').format(DateTime.now())}'),
              pw.SizedBox(height: 20),

              // Addressed to
              pw.Text('To,'),
              pw.Text('The Class Teacher,'),
              pw.Text('Class ${studentData['className']}'),
              pw.Text(schoolName),
              pw.SizedBox(height: 30),

              // Subject
              pw.Text(
                'Subject: ${_getSubjectText(leave['template'] ?? '')}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 30),

              // Salutation
              pw.Text('Respected Sir/Madam,'),
              pw.SizedBox(height: 15),

              // Body
              pw.Paragraph(
                text: _getLeaveBodyText(
                  leave['template'] ?? '',
                  studentData['name'] ?? '',
                  studentData['rollNo']?.toString() ?? '',
                  startDateStr,
                  endDateStr,
                  schoolName,
                ),
              ),
              pw.Paragraph(
                text: 'I kindly request you to grant leave for the mentioned dates. I will ensure that the missed '
                    'coursework is completed upon return.',
              ),
              pw.SizedBox(height: 30),

              // Conclusion
              pw.Text('Thank you for your understanding.'),
              pw.SizedBox(height: 40),

              pw.Text('Yours Sincerely,'),
              pw.SizedBox(height: 5),
              pw.Text(parentName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('(Parent of ${studentData['name']})', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Leave_${studentData['name']}_${studentData['rollNo']}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final leave = studentData['activeLeave'] as Map<String, dynamic>?;

    String formatDate(String? dateStr) {
      if (dateStr == null) return '';
      try {
        final DateTime d = DateTime.parse(dateStr);
        return DateFormat('dd/MM/yyyy').format(d);
      } catch (e) {
        return dateStr.split('T')[0];
      }
    }

    final String startDateStr = leave != null ? formatDate(leave['startDate']?.toString()) : '';
    final String endDateStr = leave != null ? formatDate(leave['endDate']?.toString()) : '';
    final parentName = studentData['parentDetails']?['parentName'] ?? studentData['parentDetails']?['name'] ?? 'Parent/Guardian';

    if (leave == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Leave Letter')),
        body: const Center(child: Text('No active leave data found.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Leave Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Paper Letter Effect
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      schoolName.toUpperCase(),
                      style: GoogleFonts.merriweather(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'FORMAL LEAVE APPLICATION',
                      style: TextStyle(fontSize: 12, letterSpacing: 1.5, color: Colors.grey[600], fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(thickness: 2),
                  ),
                  Text('Date: ${DateFormat('MMMM dd, yyyy').format(DateTime.now())}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  const Text('To,'),
                  const Text('The Class Teacher,'),
                  Text('Class ${studentData['className']}'),
                  Text(schoolName),
                  const SizedBox(height: 24),
                  Text(
                    'Subject: ${_getSubjectText(leave['template'] ?? '')}',
                    style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                  ),
                  const SizedBox(height: 24),
                  const Text('Respected Sir/Madam,'),
                  const SizedBox(height: 16),
                  Text(
                    _getLeaveBodyText(
                      leave['template'] ?? '',
                      studentData['name'] ?? '',
                      studentData['rollNo']?.toString() ?? '',
                      startDateStr,
                      endDateStr,
                      schoolName,
                    ),
                    style: const TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'I kindly request you to grant leave for the mentioned dates. I will ensure that the missed coursework is completed upon return.',
                    style: TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  const Text('Thank you for your understanding.'),
                  const SizedBox(height: 40),
                  const Text('Yours Sincerely,'),
                  const SizedBox(height: 4),
                  Text(parentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('(Parent of ${studentData['name']})', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _generatePdf(context),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
        label: const Text('Download PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
