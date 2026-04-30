import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:teacher_mobile_app/core/theme/theme_colors.dart';

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
                'Subject: Application for ${leave['template']}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 30),

              // Salutation
              pw.Text('Respected Sir/Madam,'),
              pw.SizedBox(height: 15),

              // Body
              pw.Paragraph(
                text: 'With due respect, this is to inform you that my child, ${studentData['name']} '
                    '(Roll No: ${studentData['rollNo']}), studying in your class, will not be able to attend school '
                    'from ${leave['startDate']} to ${leave['endDate']} due to ${leave['template']}.',
              ),
              pw.Paragraph(
                text: 'I kindly request you to grant leave for the mentioned dates. I will ensure that the missed '
                    'coursework is completed upon return.',
              ),
              pw.SizedBox(height: 30),

              // Conclusion
              pw.Text('Thank you for your understanding.'),
              pw.SizedBox(height: 40),

              // Sign-off
              pw.Text('Yours Sincerely,'),
              pw.SizedBox(height: 5),
              pw.Text('Parent/Guardian of ${studentData['name']}'),
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
        backgroundColor: ThemeColors.primaryPurple,
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
                    'Subject: Application for ${leave['template']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                  ),
                  const SizedBox(height: 24),
                  const Text('Respected Sir/Madam,'),
                  const SizedBox(height: 16),
                  Text(
                    'With due respect, this is to inform you that my child, ${studentData['name']} (Roll No: ${studentData['rollNo']}), '
                    'studying in your class, will not be able to attend school from ${leave['startDate']} to ${leave['endDate']} '
                    'due to ${leave['template']}.',
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
                  Text('Parent/Guardian of ${studentData['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _generatePdf(context),
        backgroundColor: ThemeColors.primaryPurple,
        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
        label: const Text('Download PDF', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
