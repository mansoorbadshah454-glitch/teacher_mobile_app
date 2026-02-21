import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PdfGeneratorService {
  static Future<void> generateTestReport({
    required BuildContext context,
    required String schoolName,
    required String className,
    required String teacherName,
    required String subject,
    required String chapterName,
    required List<Map<String, dynamic>> students,
    required Map<String, int> testScores,
  }) async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              // 1. Header Section - Colored Background
              pw.Container(
                color: PdfColor.fromHex('#4f46e5'), // Indigo-600
                padding: const pw.EdgeInsets.symmetric(vertical: 20, horizontal: 15),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      schoolName, 
                      style: pw.TextStyle(
                        color: PdfColors.white, 
                        fontSize: 22, 
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      PdfGeneratorService._getFormattedDate(), 
                      style: const pw.TextStyle(
                        color: PdfColors.white, 
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // 2. Test Details
              pw.Text(
                'Test Result: $subject', 
                style: pw.TextStyle(
                  fontSize: 16, 
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (chapterName.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  'Chapter: $chapterName', 
                  style: pw.TextStyle(
                    fontSize: 12, 
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
              pw.SizedBox(height: 10),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Class: $className', 
                        style: const pw.TextStyle(
                          color: PdfColors.grey800, 
                          fontSize: 11,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Teacher: $teacherName', 
                        style: const pw.TextStyle(
                          color: PdfColors.grey800, 
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  pw.Text(
                    'Total Students: ${students.length}', 
                    style: const pw.TextStyle(
                      color: PdfColors.grey800, 
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // 3. Table
              pw.TableHelper.fromTextArray(
                headers: ['Roll No', 'Student Name', 'Test Score'],
                data: students.map((s) {
                  final score = testScores[s['id']] ?? 0;
                  return [
                    s['rollNo']?.toString() ?? 'N/A',
                    s['name'] ?? 'Unknown',
                    '$score%',
                  ];
                }).toList(),
                border: pw.TableBorder.all(color: PdfColors.grey300),
                headerStyle: pw.TextStyle(
                  color: PdfColors.white, 
                  fontWeight: pw.FontWeight.bold,
                ),
                headerDecoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#4f46e5'),
                ),
                cellAlignment: pw.Alignment.centerLeft,
                cellStyle: const pw.TextStyle(fontSize: 10),
                oddRowDecoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#f5f7ff'),
                ),
                cellPadding: const pw.EdgeInsets.all(6),
              ),
              pw.SizedBox(height: 20),

              // 4. Footer
              pw.Center(
                child: pw.Text(
                  "Generated via Teacher App", 
                  style: const pw.TextStyle(
                    color: PdfColors.grey600, 
                    fontSize: 10,
                  ),
                ),
              ),
            ];
          },
        ),
      );

      // Save and Share
      final output = await getTemporaryDirectory();
      final sanitizedClassName = className.replaceAll(' ', '_');
      final sanitizedSubject = subject.replaceAll(' ', '_');
      final fileName = "${sanitizedClassName}_${sanitizedSubject}_Test_Report.pdf";
      
      final file = File("${output.path}/$fileName");
      await file.writeAsBytes(await pdf.save());

      if (context.mounted) {
         Share.shareXFiles(
           [XFile(file.path)], 
           text: 'Here is the Test Report for $className - $subject'
         );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to generate PDF: $e"), 
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static String _getFormattedDate() {
    final now = DateTime.now();
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
    ];
    
    // To match React implementation visually roughly
    // "yyyy-MM-dd" or "weekday, month day, year" format
    return "${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}";
  }
}
