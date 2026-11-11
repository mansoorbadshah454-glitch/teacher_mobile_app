import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:teacher_mobile_app/features/paper_exam/config/slo_ai_config.dart';
import 'package:teacher_mobile_app/features/paper_exam/models/slo_paper_models.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/ocr_and_image_service.dart';

class SloGeminiService {
  /// Fetch API key: Checks Super-Admin configs first, then Firestore fallback, then SloAiConfig
  static Future<String> getApiKey() async {
    final firestore = FirebaseFirestore.instance;

    // 1. Check Super-Admin Master Key in curriculums/ai_settings
    try {
      final snap = await firestore.collection('curriculums').doc('ai_settings').get();
      if (snap.exists && snap.data() != null) {
        final key = (snap.data()?['geminiApiKey'] ?? '').toString().trim();
        if (key.isNotEmpty) {
          debugPrint('🔑 [SloGemini] Loaded API key from curriculums/ai_settings');
          return key;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching curriculums/ai_settings: $e');
    }

    // 2. Check Super-Admin Master Key in system_config/ai_settings
    try {
      final snap = await firestore.collection('system_config').doc('ai_settings').get();
      if (snap.exists && snap.data() != null) {
        final key = (snap.data()?['geminiApiKey'] ?? '').toString().trim();
        if (key.isNotEmpty) {
          debugPrint('🔑 [SloGemini] Loaded API key from system_config/ai_settings');
          return key;
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching system_config/ai_settings: $e');
    }

    // 3. Check Super-Admin in system_configs/global
    try {
      final snap = await firestore.collection('system_configs').doc('global').get();
      if (snap.exists && snap.data() != null) {
        final configs = snap.data()?['configs'];
        if (configs is Map) {
          final ai = configs['ai'];
          if (ai is Map) {
            final key = (ai['geminiApiKey'] ?? '').toString().trim();
            if (key.isNotEmpty) {
              debugPrint('🔑 [SloGemini] Loaded API key from system_configs/global');
              return key;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching system_configs/global: $e');
    }

    // 4. Check app_config/global fallback
    try {
      final doc = await firestore.collection('app_config').doc('global').get();
      if (doc.exists && doc.data() != null) {
        final key = (doc.data()?['gemini_api_key'] ?? '').toString().trim();
        if (key.isNotEmpty) return key;
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching app_config/global: $e');
    }

    return SloAiConfig.fallbackGeminiApiKey;
  }

  /// Generate a comprehensive chapter SLO & Question Bank from scanned book content
  static Future<ChapterBankDoc> generateChapterBank({
    required String publisher,
    required String grade,
    required String subject,
    required int chapterNumber,
    required String chapterTitle,
    required bool isRtlSubject,
    required ExtractedBookContent bookContent,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey.isEmpty || apiKey == "YOUR_GEMINI_API_KEY_HERE") {
      throw Exception(
        "Gemini API Key is not configured. Please add your Gemini API Key in SloAiConfig or Firestore (app_config/global).",
      );
    }

    final docId = ChapterBankDoc.generateDocId(
      publisher: publisher,
      grade: grade,
      subject: subject,
      chapterNumber: chapterNumber,
    );

    final String systemInstruction =
        "You are an official Board Exam Setter and Curriculum Specialist. "
        "Your job is to carefully read the scanned textbook pages/text, extract the REAL Student Learning Outcomes (SLOs) and core sub-topics directly from those pages, and build a 100% accurate, textbook-verified question bank. "
        "STRICT RULES:\n"
        "1. REAL SLO EXTRACTION: If an explicit SLO box ('Student Learning Outcomes' / 'تدریسی مقاصد' / 'After studying this chapter, students will be able to...') is present on the page, extract those exact SLOs verbatim. Otherwise, derive precise SLOs directly from the exact headings, definitions, theorems, and exercises visible on the scanned pages using codes like 'SLO-$chapterNumber.1', 'SLO-$chapterNumber.2', etc.\n"
        "2. ZERO HALLUCINATION: Every single question, option, formula, numerical, and answer MUST come strictly from the provided textbook pages.\n"
        "3. URDU / ISLAMIYAT / RTL RULE: When Subject Language is Urdu/RTL, write ALL chapter_title, slo statements, question_text, options, correct_answer, and rubric in 100% pure, authentic Urdu script (اردو). Do NOT write questions or options in English.\n"
        "4. MATH / PHYSICS / CHEMISTRY FORMATTING RULE: Format all mathematical expressions, fractions, powers, roots, and chemical equations using clean, printable Unicode characters (e.g., x², y³, √(a+b), π, θ, Δ, ÷, ×, ≤, ≥, →, H₂SO₄, (a+b)/(c+d)). NEVER output raw LaTeX commands like \\frac, \\sqrt, or \$...\$, because the output is printed directly onto an A4 PDF exam paper.\n"
        "5. BLOOM'S TAXONOMY: Categorize each question strictly as 'Knowledge' (recall/define), 'Understanding' (explain/differentiate/why/how), or 'Application' (solve numerical/analyze/apply concept).";

    final String userPrompt = """
Generate a 100% accurate, textbook-bound Student Learning Outcome (SLO) Question Bank from the provided pages for:
- Publisher/Board: $publisher
- Grade/Class: $grade
- Subject: $subject
- Chapter Number: $chapterNumber
- Chapter Title: ${chapterTitle.isEmpty ? 'Chapter $chapterNumber' : chapterTitle}
- Subject Language/Direction: ${isRtlSubject ? 'Urdu / RTL (Write all SLOs, questions, options, and answers in pure Urdu script)' : 'English / LTR'}

CRITICAL REQUIREMENT:
1. Extract all real SLOs covered in the scanned pages (use codes like SLO-$chapterNumber.1, SLO-$chapterNumber.2, ...).
2. Generate at least:
   - 15 Multiple Choice Questions (MCQs) with 4 realistic options (${isRtlSubject ? 'الف) ..., ب) ..., ج) ..., د) ...' : 'A) ..., B) ..., C) ..., D) ...'}) and exact correct_answer.
   - 12 Short Questions (including definitions, conceptual reasons, or short numericals/exercises from the pages) with clear expected answer rubric (3 marks each).
   - 5 Long / Detailed Questions (comprehensive explanations, theorems, derivations, or multi-step problems from the pages) with step-by-step marking rubric (6 marks each).

Return your response in STRICT JSON format adhering to this exact structure:
{
  "chapter_title": "Exact chapter title from the textbook page",
  "slos": [
    {
      "slo_code": "SLO-$chapterNumber.1",
      "statement": "Exact learning outcome statement from the textbook"
    }
  ],
  "questions": [
    {
      "id": "q1",
      "slo_code": "SLO-$chapterNumber.1",
      "type": "MCQ",
      "cognitive_level": "Knowledge",
      "question_text": "The text of the question",
      "options": ["A) Option 1", "B) Option 2", "C) Option 3", "D) Option 4"],
      "correct_answer": "A) Option 1",
      "rubric": "Marking criteria or model answer"
    }
  ]
}
""";

    // Build request contents (multimodal: text + images)
    final List<Map<String, dynamic>> parts = [];

    // 1. Text Prompt
    parts.add({"text": userPrompt});

    // 2. Extracted OCR Text if available
    if (bookContent.hasText) {
      parts.add({
        "text": "\n=== EXTRACTED TEXTBOOK CONTENT ===\n${bookContent.text}\n=== END OF CONTENT ==="
      });
    }

    // 3. Compressed Images for RTL or fallback
    if (bookContent.hasImages) {
      for (final Uint8List imageBytes in bookContent.compressedImages) {
        final base64Image = base64Encode(imageBytes);
        parts.add({
          "inline_data": {
            "mime_type": "image/jpeg",
            "data": base64Image,
          }
        });
      }
    }

    final Map<String, dynamic> requestBody = {
      "system_instruction": {
        "parts": [
          {"text": systemInstruction}
        ]
      },
      "contents": [
        {
          "role": "user",
          "parts": parts,
        }
      ],
      "generationConfig": {
        "temperature": 0.2,
        "responseMimeType": "application/json",
      }
    };

    final candidateModels = [
      SloAiConfig.geminiModel, // "gemini-2.5-flash"
      "gemini-2.0-flash",
      "gemini-2.0-flash-lite",
      "gemini-1.5-flash",
      "gemini-1.5-pro",
    ];

    http.Response? response;
    String lastError = "";

    for (final modelName in candidateModels) {
      final String url =
          "https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey";

      try {
        debugPrint("🤖 Calling Gemini model: $modelName...");
        response = await http.post(
          Uri.parse(url),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(requestBody),
        );

        if (response.statusCode == 200) {
          debugPrint("✅ Gemini model $modelName succeeded!");
          break;
        } else if (response.statusCode == 404 || response.statusCode == 429 || response.statusCode == 503) {
          debugPrint("⚠️ Model $modelName returned ${response.statusCode}, trying next model...");
          lastError = response.body;
          continue;
        } else {
          lastError = response.body;
          break;
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    if (response == null || response.statusCode != 200) {
      debugPrint("❌ All Gemini models failed: $lastError");
      throw Exception(
        "Gemini AI Generation failed: $lastError",
      );
    }

    final Map<String, dynamic> responseJson = jsonDecode(response.body);
    final candidates = responseJson['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception("No response generated by Gemini AI.");
    }

    final candidate = candidates.first;
    final content = candidate['content'];
    final candidateParts = content?['parts'] as List?;
    if (candidateParts == null || candidateParts.isEmpty) {
      throw Exception("Empty content in Gemini AI response.");
    }

    String rawJsonText = (candidateParts.first['text'] as String? ?? "{}").trim();
    if (rawJsonText.startsWith('```')) {
      rawJsonText = rawJsonText
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }
    final Map<String, dynamic> parsedData = jsonDecode(rawJsonText);

    final resolvedTitle = (parsedData['chapter_title'] ?? chapterTitle).toString().trim();

    final List<SloItem> parsedSlos = [];
    if (parsedData['slos'] is List) {
      for (var s in parsedData['slos']) {
        if (s is Map<String, dynamic>) {
          parsedSlos.add(SloItem.fromJson(s));
        }
      }
    }

    final List<SloQuestion> parsedQuestions = [];
    if (parsedData['questions'] is List) {
      int idx = 1;
      for (var q in parsedData['questions']) {
        if (q is Map<String, dynamic>) {
          // Ensure a unique ID
          final qMap = Map<String, dynamic>.from(q);
          if ((qMap['id'] ?? '').toString().isEmpty) {
            qMap['id'] = '${docId}_q$idx';
          }
          parsedQuestions.add(SloQuestion.fromJson(qMap));
          idx++;
        }
      }
    }

    return ChapterBankDoc(
      docId: docId,
      publisher: publisher,
      grade: grade,
      subject: subject,
      chapterNumber: chapterNumber,
      chapterTitle: resolvedTitle.isNotEmpty ? resolvedTitle : 'Chapter $chapterNumber',
      isRtl: isRtlSubject,
      slos: parsedSlos,
      questions: parsedQuestions,
      updatedAt: FieldValue.serverTimestamp(),
    );
  }
}
