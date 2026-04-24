import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class TestReportPdfGenerator {
  static String _getStarSvg(String hexColor) {
    return '''
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
    <path d="M12 2L15.09 8.26L22 9.27L17 14.14L18.18 21.02L12 17.77L5.82 21.02L7 14.14L2 9.27L8.91 8.26L12 2Z" fill="$hexColor"/>
    </svg>
    ''';
  }

  static Future<File> generateReport({
    required Map<String, dynamic> schoolData,
    required Map<String, dynamic> teacherData,
    required Map<String, dynamic> testData,
    required List<Map<String, dynamic>> students,
    required Map<String, int> testScores,
  }) async {
    final pdf = pw.Document();

    // Ranking Logic
    List<Map<String, dynamic>> rankedStudents = [];
    for (var s in students) {
      int score = testScores[s['id']] ?? 0;
      rankedStudents.add({...s, 'score': score});
    }
    rankedStudents.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    int trueRank = 1;
    int displayRank = 1;
    int prevScore = -1;

    for (var i = 0; i < rankedStudents.length; i++) {
      int score = rankedStudents[i]['score'];
      if (score != prevScore) {
        displayRank = trueRank;
      }
      rankedStudents[i]['rank'] = displayRank;
      prevScore = score;
      trueRank++;
    }

    final maxMarks = testData['maxMarks'] ?? 10;
    int maxM = (maxMarks is int) ? maxMarks : int.tryParse(maxMarks.toString()) ?? 10;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: PdfColors.indigo,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                children: [
                  pw.Text(
                    schoolData['name'] ?? 'School Name',
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 24, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    "Test Result Report",
                    style: const pw.TextStyle(color: PdfColors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 32),
            
            // Test Details
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("Subject: ${testData['subject']}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                    pw.SizedBox(height: 4),
                    pw.Text("Type: ${testData['testType']}"),
                    pw.SizedBox(height: 4),
                    pw.Text("Chapter: ${testData['chapter']}"),
                    pw.SizedBox(height: 4),
                    pw.Text("Topic: ${testData['paragraphs']}"),
                  ]
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text("Date: ${testData['dateStr'] ?? ''}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                    pw.SizedBox(height: 4),
                    pw.Text("Max Marks: $maxM"),
                    pw.SizedBox(height: 12),
                    pw.Text("Subject Teacher:", style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 10)),
                    pw.Text(teacherData['name'] ?? 'Unknown', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  ]
                ),
              ],
            ),
            pw.SizedBox(height: 24),
            pw.Divider(),
            pw.SizedBox(height: 16),
            
            // Table
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.5),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(4),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Rank', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Roll No', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Student Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Score', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Percentage', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                ...rankedStudents.map((s) {
                  int rank = s['rank'];
                  String rankStr = rank.toString();
                  if (rank == 1) rankStr += 'st';
                  else if (rank == 2) rankStr += 'nd';
                  else if (rank == 3) rankStr += 'rd';
                  else rankStr += 'th';

                  pw.Widget rankWidget = pw.Text(rankStr);
                  if (rank <= 3) {
                    String color = rank == 1 ? '#FFD700' : (rank == 2 ? '#C0C0C0' : '#CD7F32');
                    rankWidget = pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(rankStr, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(width: 4),
                        pw.SvgImage(svg: _getStarSvg(color), width: 14, height: 14),
                      ],
                    );
                  }

                  int score = s['score'];
                  double percent = maxM > 0 ? (score / maxM) * 100 : 0.0;
                  String percentStr = "${percent.toStringAsFixed(1)}%";

                  return pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: rankWidget),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(s['rollNo']?.toString() ?? '-')),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(s['name'] ?? 'Unknown')),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text("$score / $maxM")),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(percentStr)),
                    ],
                  );
                }),
              ],
            ),
          ];
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Test_Report_${testData['subject']}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
