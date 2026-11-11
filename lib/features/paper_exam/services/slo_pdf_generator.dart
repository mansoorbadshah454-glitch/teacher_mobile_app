import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:teacher_mobile_app/features/paper_exam/models/slo_paper_models.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/urdu_reshaper.dart';

class SloPdfGenerator {
  static final List<String> _romanNumerals = [
    "(i)", "(ii)", "(iii)", "(iv)", "(v)", "(vi)", "(vii)", "(viii)", "(ix)", "(x)",
    "(xi)", "(xii)", "(xiii)", "(xiv)", "(xv)", "(xvi)", "(xvii)", "(xviii)", "(xix)", "(xx)"
  ];

  /// Format string based on language (applies Urdu Reshaping for cursive joined letters)
  static String _fmt(String text, bool isRtl) {
    if (isRtl || UrduReshaper.containsUrdu(text)) {
      return UrduReshaper.reshapeForPdf(text);
    }
    return text;
  }

  static pw.ThemeData? _cachedRtlTheme;
  static pw.ThemeData? _cachedLtrTheme;

  /// Loads authentic font theme for Urdu (Amiri TTF offline asset with network fallback)
  static Future<pw.ThemeData> _loadTheme(bool isRtl) async {
    if (!isRtl) {
      _cachedLtrTheme ??= pw.ThemeData.base();
      return _cachedLtrTheme!;
    }
    if (_cachedRtlTheme != null) return _cachedRtlTheme!;

    try {
      // 1. First try bundled offline TTF font from assets (instant, 100% offline)
      final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      final fontBoldData = await rootBundle.load('assets/fonts/Amiri-Bold.ttf');
      final font = pw.Font.ttf(fontData);
      final fontBold = pw.Font.ttf(fontBoldData);
      _cachedRtlTheme = pw.ThemeData.withFont(base: font, bold: fontBold);
      return _cachedRtlTheme!;
    } catch (_) {
      try {
        // 2. Fallback to Google Fonts Amiri over network if asset bundle is missing
        final font = await PdfGoogleFonts.amiriRegular();
        final fontBold = await PdfGoogleFonts.amiriBold();
        _cachedRtlTheme = pw.ThemeData.withFont(base: font, bold: fontBold);
        return _cachedRtlTheme!;
      } catch (_) {
        _cachedRtlTheme = pw.ThemeData.base();
        return _cachedRtlTheme!;
      }
    }
  }

  /// Generates the Official Pakistani Board Standard Student Question Paper PDF
  static Future<Uint8List> generateQuestionPaperPdf({
    required PaperBlueprintConfig blueprint,
    required ChapterBankDoc chapterBank,
    required List<SloQuestion> questions,
    Uint8List? schoolLogoBytes,
    bool showCognitiveTags = false,
  }) async {
    final pdf = pw.Document();

    final mcqs = questions.where((q) => q.type == 'MCQ').toList();
    final shorts = questions.where((q) => q.type == 'SHORT').toList();
    final longs = questions.where((q) => q.type == 'LONG').toList();
    final isRtl = chapterBank.isRtl;
    final theme = await _loadTheme(isRtl);

    final mcqMarksEach = blueprint.mcqMarksEach;
    final shortMarksEach = blueprint.shortMarksEach;
    final longMarksEach = blueprint.longMarksEach;

    final attemptShorts = (blueprint.shortAttemptCount > 0 && blueprint.shortAttemptCount < shorts.length)
        ? blueprint.shortAttemptCount
        : shorts.length;
    final hasShortChoice = attemptShorts < shorts.length;
    final secBMarks = attemptShorts * shortMarksEach;

    final attemptLongs = (blueprint.longAttemptCount > 0 && blueprint.longAttemptCount < longs.length)
        ? blueprint.longAttemptCount
        : longs.length;
    final hasLongChoice = attemptLongs < longs.length;
    final secCMarks = attemptLongs * longMarksEach;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        theme: theme,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => _buildOfficialHeader(
          blueprint: blueprint,
          chapterBank: chapterBank,
          schoolLogoBytes: schoolLogoBytes,
          pageNumber: context.pageNumber,
          pageCount: context.pagesCount,
          isRtl: isRtl,
        ),
        build: (context) => [
          // Section A: MCQs
          if (mcqs.isNotEmpty) ...[
            _buildSectionHeader(
              title: isRtl
                  ? _fmt("حصہ اوّل: معروضی سوالات (MCQs)", true)
                  : "SECTION 'A' (Multiple Choice Questions - MCQs)",
              marks: isRtl
                  ? _fmt("کل نمبر: ${mcqs.length * mcqMarksEach} | وقت: ۱۵ منٹ", true)
                  : "Marks: ${mcqs.length * mcqMarksEach} | Time: 15 Mins",
              instructions: isRtl
                  ? _fmt("نوٹ: تمام سوالات لازمی ہیں۔ دیئے گئے اختیارات میں سے درست جواب کا انتخاب کریں۔ کاٹ کر یا دوبارہ لکھنے پر نمبر نہیں ملیں گے۔", true)
                  : "NOTE: Attempt all questions. Each question carries $mcqMarksEach ${mcqMarksEach == 1 ? 'Mark' : 'Marks'}. Encircle the correct option (A / B / C / D). Overwriting or cutting will result in zero marks.",
              isRtl: isRtl,
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              isRtl
                  ? _fmt("سوال نمبر ۱: دیئے گئے اختیارات میں سے درست جواب کا انتخاب کریں:", true)
                  : "Q.1  Choose the correct answer for each from the given options:",
              style: pw.TextStyle(
                fontSize: isRtl ? 10.5 : 9.5,
                fontWeight: pw.FontWeight.bold,
                lineSpacing: isRtl ? 4 : 0,
              ),
            ),
            pw.SizedBox(height: 4),
            ...mcqs.asMap().entries.map((entry) {
              final index = entry.key + 1;
              final q = entry.value;
              return _buildMcqItem(index, q, showCognitiveTags, isRtl);
            }),
            pw.SizedBox(height: 10),
          ],

          // Section B: Short Questions
          if (shorts.isNotEmpty) ...[
            _buildSectionHeader(
              title: isRtl
                  ? _fmt("حصہ دوم: مختصر جواب کے سوالات (Short Questions)", true)
                  : "SECTION 'B' (Short Answer Questions)",
              marks: isRtl
                  ? _fmt("کل نمبر: $secBMarks", true)
                  : "Marks: $secBMarks",
              instructions: isRtl
                  ? _fmt(
                      hasShortChoice
                          ? "نوٹ: دیئے گئے (${shorts.length}) میں سے کوئی سے ($attemptShorts) سوالات کے مختصر جوابات تحریر کریں۔ تمام سوالات کے نمبر مساوی ہیں ($attemptShorts x $shortMarksEach = $secBMarks نمبر)۔"
                          : "نوٹ: تمام (${shorts.length}) سوالات کے مختصر جوابات تحریر کریں۔ تمام سوالات کے نمبر مساوی ہیں (${shorts.length} x $shortMarksEach = $secBMarks نمبر)۔",
                      true,
                    )
                  : hasShortChoice
                      ? "NOTE: Attempt any ($attemptShorts) out of (${shorts.length}) questions. All questions carry equal marks ($attemptShorts x $shortMarksEach = $secBMarks Marks). Answer briefly on your answer sheet."
                      : "NOTE: Attempt all (${shorts.length}) questions. All questions carry equal marks (${shorts.length} x $shortMarksEach = $secBMarks Marks). Answer briefly on your answer sheet.",
              isRtl: isRtl,
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              isRtl
                  ? _fmt(
                      hasShortChoice
                          ? "سوال نمبر ۲: مندرجہ ذیل میں سے کوئی سے ($attemptShorts) سوالات کے مختصر جوابات تحریر کریں:"
                          : "سوال نمبر ۲: مندرجہ ذیل سوالات کے مختصر جوابات تحریر کریں:",
                      true,
                    )
                  : hasShortChoice
                      ? "Q.2  Answer any ($attemptShorts) of the following short questions:"
                      : "Q.2  Answer the following short questions:",
              style: pw.TextStyle(
                fontSize: isRtl ? 10.5 : 9.5,
                fontWeight: pw.FontWeight.bold,
                lineSpacing: isRtl ? 4 : 0,
              ),
            ),
            pw.SizedBox(height: 4),
            ...shorts.asMap().entries.map((entry) {
              final index = entry.key + 1;
              final q = entry.value;
              return _buildShortQuestionItem(index, q, showCognitiveTags, isRtl, shortMarksEach);
            }),
            pw.SizedBox(height: 10),
          ],

          // Section C: Long Questions
          if (longs.isNotEmpty) ...[
            _buildSectionHeader(
              title: isRtl
                  ? _fmt("حصہ سوم: تفصیلی سوالات (Long Questions)", true)
                  : "SECTION 'C' (Detailed / Long Questions)",
              marks: isRtl
                  ? _fmt("کل نمبر: $secCMarks", true)
                  : "Marks: $secCMarks",
              instructions: isRtl
                  ? _fmt(
                      hasLongChoice
                          ? "نوٹ: دیئے گئے (${longs.length}) میں سے کوئی سے ($attemptLongs) سوالات کے تفصیلی جوابات تحریر کریں۔ جہاں ضروری ہو لیبل شدہ خاکے بنائیں۔ ($attemptLongs x $longMarksEach = $secCMarks نمبر)۔"
                          : "نوٹ: تمام (${longs.length}) سوالات کے تفصیلی جوابات تحریر کریں۔ جہاں ضروری ہو لیبل شدہ خاکے بنائیں۔ (${longs.length} x $longMarksEach = $secCMarks نمبر)۔",
                      true,
                    )
                  : hasLongChoice
                      ? "NOTE: Attempt any ($attemptLongs) out of (${longs.length}) questions in detail. Draw neat and labelled diagrams where necessary ($attemptLongs x $longMarksEach = $secCMarks Marks)."
                      : "NOTE: Attempt all (${longs.length}) questions in detail. Draw neat and labelled diagrams where necessary (${longs.length} x $longMarksEach = $secCMarks Marks).",
              isRtl: isRtl,
            ),
            pw.SizedBox(height: 6),
            ...longs.asMap().entries.map((entry) {
              final index = entry.key + 1;
              final q = entry.value;
              return _buildLongQuestionItem(index, q, showCognitiveTags, isRtl, longMarksEach);
            }),
            pw.SizedBox(height: 16),
          ],

          // Board Signatures & Final Ending
          _buildSignatureBlock(isRtl),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                "Smart SLO Paper Engine  •  Board Curriculum Standard",
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
              pw.Text(
                context.pageNumber < context.pagesCount
                    ? "*** Please Turn Over (P.T.O.) ***"
                    : "*** END OF EXAMINATION PAPER ***",
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
              ),
              pw.Text(
                "Page ${context.pageNumber} of ${context.pagesCount}",
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ],
          ),
        ),
      ),
    );

    return pdf.save();
  }

  /// Generates Teacher Answer Key and Rubrics PDF
  static Future<Uint8List> generateAnswerKeyPdf({
    required PaperBlueprintConfig blueprint,
    required ChapterBankDoc chapterBank,
    required List<SloQuestion> questions,
    Uint8List? schoolLogoBytes,
  }) async {
    final pdf = pw.Document();

    final mcqs = questions.where((q) => q.type == 'MCQ').toList();
    final shorts = questions.where((q) => q.type == 'SHORT').toList();
    final longs = questions.where((q) => q.type == 'LONG').toList();
    final isRtl = chapterBank.isRtl;
    final theme = await _loadTheme(isRtl);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        theme: theme,
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          margin: const pw.EdgeInsets.only(bottom: 12),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 1.5, color: PdfColors.black)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  if (schoolLogoBytes != null)
                    pw.Container(
                      margin: const pw.EdgeInsets.only(right: 10),
                      child: pw.Image(pw.MemoryImage(schoolLogoBytes), width: 36, height: 36),
                    ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        blueprint.schoolName.toUpperCase(),
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                      ),
                      pw.Text(
                        "${blueprint.examTitle.toUpperCase()}  •  TEACHER MARKING KEY (CONFIDENTIAL)",
                        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Text(
                "Class: ${chapterBank.grade}th  |  ${chapterBank.subject}",
                style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ],
          ),
        ),
        build: (context) => [
          // Section A Answers
          if (mcqs.isNotEmpty) ...[
            _buildSectionHeader(
              title: "SECTION 'A' ANSWER KEY (MCQs)",
              marks: "${mcqs.length} Questions",
              instructions: "Official scoring options for objective sheet evaluation.",
              isRtl: false,
            ),
            pw.SizedBox(height: 6),
            pw.Wrap(
              spacing: 8,
              runSpacing: 6,
              children: mcqs.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final q = entry.value;
                return pw.Container(
                  width: 105,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(4),
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
                  ),
                  child: pw.Text(
                    "Q$idx: ${_fmt(q.correctAnswer, isRtl)}",
                    style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                  ),
                );
              }).toList(),
            ),
            pw.SizedBox(height: 12),
          ],

          // Section B Rubrics
          if (shorts.isNotEmpty) ...[
            _buildSectionHeader(
              title: "SECTION 'B' MARKING RUBRIC (Short Questions)",
              marks: "${shorts.length} Questions",
              instructions: "Award marks based on core concepts and key terms.",
              isRtl: false,
            ),
            pw.SizedBox(height: 6),
            ...shorts.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final q = entry.value;
              final diagWidget = _buildDiagramPdfWidget(q, isRtl);
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "Q.2 ($idx): ${_fmt(q.questionText, isRtl)} [${q.cognitiveLevel}]",
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
                    if (diagWidget != null) diagWidget,
                    pw.SizedBox(height: 2),
                    pw.Text(
                      "Expected Answer / Rubric: ${_fmt(q.rubric.isNotEmpty ? q.rubric : q.correctAnswer, isRtl)}",
                      style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.indigo900),
                    ),
                  ],
                ),
              );
            }),
            pw.SizedBox(height: 12),
          ],

          // Section C Rubrics
          if (longs.isNotEmpty) ...[
            _buildSectionHeader(
              title: "SECTION 'C' MARKING RUBRIC (Detailed Questions)",
              marks: "${longs.length} Questions",
              instructions: "Marking breakdown for comprehensive descriptive answers.",
              isRtl: false,
            ),
            pw.SizedBox(height: 6),
            ...longs.asMap().entries.map((entry) {
              final idx = entry.key + 1;
              final q = entry.value;
              final diagWidget = _buildDiagramPdfWidget(q, isRtl);
              return pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 8),
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      "Q.${idx + 2}: ${_fmt(q.questionText, isRtl)} [${q.cognitiveLevel}]",
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
                    if (diagWidget != null) diagWidget,
                    pw.SizedBox(height: 2),
                    pw.Text(
                      "Model Solution / Rubric: ${_fmt(q.rubric.isNotEmpty ? q.rubric : q.correctAnswer, isRtl)}",
                      style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.indigo900),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  // --- Helper Layout Builders ---

  static pw.Widget _buildOfficialHeader({
    required PaperBlueprintConfig blueprint,
    required ChapterBankDoc chapterBank,
    required Uint8List? schoolLogoBytes,
    required int pageNumber,
    required int pageCount,
    required bool isRtl,
  }) {
    if (pageNumber > 1) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.only(bottom: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.8, color: PdfColors.black)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              "${blueprint.schoolName}  •  ${blueprint.examTitle}",
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
            ),
            pw.Text(
              "Subject: ${chapterBank.subject}  |  Class: ${chapterBank.grade}th",
              style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
            ),
          ],
        ),
      );
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        children: [
          // Symmetrical Masthead with School Logo & Centered Typography
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // Left Logo
              if (schoolLogoBytes != null)
                pw.Container(
                  width: 58,
                  height: 58,
                  margin: const pw.EdgeInsets.only(right: 12),
                  child: pw.Image(pw.MemoryImage(schoolLogoBytes), fit: pw.BoxFit.contain),
                )
              else
                pw.Container(
                  width: 52,
                  height: 52,
                  margin: const pw.EdgeInsets.only(right: 12),
                  decoration: pw.BoxDecoration(
                    shape: pw.BoxShape.circle,
                    border: pw.Border.all(color: PdfColors.black, width: 1.5),
                  ),
                  child: pw.Center(
                    child: pw.Text(
                      blueprint.schoolName.isNotEmpty ? blueprint.schoolName[0] : "S",
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                    ),
                  ),
                ),

              // Center: Official Pakistani School Header
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      blueprint.schoolName.toUpperCase(),
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.6,
                        color: PdfColors.black,
                      ),
                    ),
                    if (blueprint.campusOrAddress != null && blueprint.campusOrAddress!.isNotEmpty) ...[
                      pw.SizedBox(height: 1.5),
                      pw.Text(
                        blueprint.campusOrAddress!.toUpperCase(),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                      ),
                    ],
                    pw.SizedBox(height: 3),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(width: 1.2, color: PdfColors.black),
                          bottom: pw.BorderSide(width: 1.2, color: PdfColors.black),
                        ),
                      ),
                      child: pw.Text(
                        blueprint.examTitle.toUpperCase(),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 1.2,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                    if (blueprint.boardAffiliation != null && blueprint.boardAffiliation!.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(
                        blueprint.boardAffiliation!,
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                      ),
                    ],
                  ],
                ),
              ),

              // Right Symmetrical Monogram
              pw.Container(
                width: 58,
                height: 58,
                margin: const pw.EdgeInsets.only(left: 12),
                child: schoolLogoBytes != null
                    ? pw.Image(pw.MemoryImage(schoolLogoBytes), fit: pw.BoxFit.contain)
                    : pw.Container(
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          border: pw.Border.all(color: PdfColors.black, width: 1.5),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            blueprint.schoolName.isNotEmpty ? blueprint.schoolName[0] : "S",
                            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                          ),
                        ),
                      ),
              ),
            ],
          ),

          pw.SizedBox(height: 8),

          // Official Examination Details Block (Pakistani Board Standard Grid)
          pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.0),
            ),
            child: pw.Column(
              children: [
                // Row 1: Student Name & Roll No Boxes
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Row(
                        children: [
                          pw.Text("Student Name: ", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                          pw.Text("___________________________________________", style: const pw.TextStyle(fontSize: 9.5)),
                        ],
                      ),
                      pw.Row(
                        children: [
                          pw.Text("Roll No: ", style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                          ...List.generate(
                            5,
                            (_) => pw.Container(
                              width: 15,
                              height: 15,
                              margin: const pw.EdgeInsets.only(left: 2),
                              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 0.8)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Row 2: Class, Subject, Time, Total Marks, Marks Obtained
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                  color: PdfColors.grey100,
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Class: ${chapterBank.grade}th", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text("Subject: ${chapterBank.subject}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text("Time Allowed: ${blueprint.timeAllowed}", style: const pw.TextStyle(fontSize: 9)),
                      pw.Text("Total Marks: ${blueprint.totalMarks}", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text("Marks Obtained: _______", style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSectionHeader({
    required String title,
    required String marks,
    required String instructions,
    required bool isRtl,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey200,
        border: pw.Border(
          top: pw.BorderSide(width: 1.2, color: PdfColors.black),
          bottom: pw.BorderSide(width: 1.2, color: PdfColors.black),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
              pw.Text(
                marks,
                style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            instructions,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
          ),
        ],
      ),
    );
  }

  static pw.Widget? _buildDiagramPdfWidget(SloQuestion q, bool isRtl) {
    final bytes = q.diagramBytes;
    if (bytes == null || bytes.isEmpty) return null;
    return pw.Container(
      margin: pw.EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isRtl ? 0 : 18,
        right: isRtl ? 18 : 0,
      ),
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Image(
        pw.MemoryImage(bytes),
        height: 95,
        fit: pw.BoxFit.contain,
      ),
    );
  }

  static pw.Widget _buildMcqItem(int index, SloQuestion q, bool showTags, bool isRtl) {
    final diagramWidget = _buildDiagramPdfWidget(q, isRtl);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        crossAxisAlignment: isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                "($index) ",
                style: pw.TextStyle(
                  fontSize: isRtl ? 10 : 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  _fmt(q.questionText, isRtl),
                  style: pw.TextStyle(
                    fontSize: isRtl ? 10 : 9.5,
                    lineSpacing: isRtl ? 4 : 1,
                  ),
                ),
              ),
              if (showTags)
                pw.Text(
                  " [${q.cognitiveLevel[0]}]",
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                ),
            ],
          ),
          if (diagramWidget != null) diagramWidget,
          pw.SizedBox(height: 3),
          // Clean horizontal row of 4 options
          pw.Padding(
            padding: pw.EdgeInsets.only(
              left: isRtl ? 0 : 18,
              right: isRtl ? 18 : 0,
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: q.options.map((opt) {
                return pw.Expanded(
                  child: pw.Text(
                    _fmt(opt, isRtl),
                    style: pw.TextStyle(
                      fontSize: isRtl ? 9.5 : 8.5,
                      lineSpacing: isRtl ? 3 : 1,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildShortQuestionItem(int index, SloQuestion q, bool showTags, bool isRtl, int marksEach) {
    final label = index <= _romanNumerals.length ? _romanNumerals[index - 1] : "($index)";
    final diagramWidget = _buildDiagramPdfWidget(q, isRtl);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Column(
        crossAxisAlignment: isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 26,
                child: pw.Text(
                  label,
                  style: pw.TextStyle(
                    fontSize: isRtl ? 10 : 9.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  _fmt(q.questionText, isRtl),
                  style: pw.TextStyle(
                    fontSize: isRtl ? 10 : 9.5,
                    lineSpacing: isRtl ? 4 : 1,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                isRtl ? _fmt("($marksEach نمبر)", true) : "($marksEach Marks)${showTags ? " [${q.cognitiveLevel[0]}]" : ""}",
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
              ),
            ],
          ),
          if (diagramWidget != null) diagramWidget,
        ],
      ),
    );
  }

  static pw.Widget _buildLongQuestionItem(int index, SloQuestion q, bool showTags, bool isRtl, int marksEach) {
    final qNum = index + 2; // Q.3, Q.4, Q.5 ...
    final diagramWidget = _buildDiagramPdfWidget(q, isRtl);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        crossAxisAlignment: isRtl ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                isRtl ? _fmt("سوال نمبر $qNum:  ", true) : "Q.$qNum  ",
                style: pw.TextStyle(
                  fontSize: isRtl ? 10 : 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  _fmt(q.questionText, isRtl),
                  style: pw.TextStyle(
                    fontSize: isRtl ? 10 : 9.5,
                    lineSpacing: isRtl ? 4 : 1,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                isRtl ? _fmt("($marksEach نمبر)", true) : "($marksEach Marks)${showTags ? " [${q.cognitiveLevel[0]}]" : ""}",
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
              ),
            ],
          ),
          if (diagramWidget != null) diagramWidget,
        ],
      ),
    );
  }

  static pw.Widget _buildSignatureBlock(bool isRtl) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 18, bottom: 4),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(width: 0.8, color: PdfColors.black)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("____________________________", style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 2),
              pw.Text(
                isRtl ? _fmt("دستخط متعلقہ استاد", true) : "Subject Teacher Signature",
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text("____________________________", style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 2),
              pw.Text(
                isRtl ? _fmt("دستخط پرنسپل / کنٹرولر امتحانات", true) : "Principal / Exam Controller",
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Print or Share directly via the device's native print dialogue
  static Future<void> printOrSharePdf({
    required Uint8List pdfBytes,
    required String docName,
  }) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: docName,
    );
  }
}
