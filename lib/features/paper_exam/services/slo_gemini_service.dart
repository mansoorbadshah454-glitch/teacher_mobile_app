import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:teacher_mobile_app/core/services/local_db_service.dart';
import 'package:teacher_mobile_app/features/paper_exam/config/slo_ai_config.dart';
import 'package:teacher_mobile_app/features/paper_exam/models/slo_paper_models.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/ocr_and_image_service.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/slo_repository.dart';

class SloGeminiService {
  static String? _cachedApiKey;
  static String? _cachedWorkingModel;
  static List<String>? _cachedDiscoveredModels;
  static String? _cachedRemoteCustomPrompt;

  static const String _localApiKeyCacheKey = 'slo_cached_gemini_api_key_v1';
  static const String _localWorkingModelCacheKey = 'slo_cached_working_model_v2';
  static const String _localRemotePromptCacheKey = 'slo_cached_remote_prompt_v1';

  /// Fetch API key & optional remote AI config (model override / custom training instructions)
  /// from Firestore (`curriculums/ai_settings`, `system_config/ai_settings`, `system_configs/global`).
  /// Allows updating AI models and prompt rules remotely without rebuilding the APK.
  static Future<String> getApiKey({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedApiKey != null && _cachedApiKey!.isNotEmpty) {
      return _cachedApiKey!;
    }

    final firestore = FirebaseFirestore.instance;

    void extractOptionalRemoteConfig(Map<String, dynamic> data) {
      final remoteModel = (data['geminiModel'] ?? data['preferredModel'] ?? '').toString().trim();
      if (remoteModel.isNotEmpty) {
        _cachedWorkingModel = remoteModel.replaceFirst(RegExp(r'^models/'), '');
        try {
          LocalDbService.saveCache(_localWorkingModelCacheKey, _cachedWorkingModel);
        } catch (_) {}
      }

      final remotePrompt = (data['sloSystemPrompt'] ?? data['customInstructions'] ?? '').toString().trim();
      if (remotePrompt.isNotEmpty) {
        _cachedRemoteCustomPrompt = remotePrompt;
        try {
          LocalDbService.saveCache(_localRemotePromptCacheKey, remotePrompt);
        } catch (_) {}
      }
    }

    Future<String?> tryLoadKey() async {
      // 1. Check Super-Admin Master Key in curriculums/ai_settings
      try {
        final snap = await firestore
            .collection('curriculums')
            .doc('ai_settings')
            .get()
            .timeout(const Duration(seconds: 3));
        if (snap.exists && snap.data() != null) {
          final data = snap.data()!;
          extractOptionalRemoteConfig(data);
          final key = (data['geminiApiKey'] ?? '').toString().trim();
          if (key.isNotEmpty) return key;
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching curriculums/ai_settings: $e');
      }

      // 2. Check Super-Admin Master Key in system_config/ai_settings
      try {
        final snap = await firestore
            .collection('system_config')
            .doc('ai_settings')
            .get()
            .timeout(const Duration(seconds: 3));
        if (snap.exists && snap.data() != null) {
          final data = snap.data()!;
          extractOptionalRemoteConfig(data);
          final key = (data['geminiApiKey'] ?? '').toString().trim();
          if (key.isNotEmpty) return key;
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching system_config/ai_settings: $e');
      }

      // 3. Check Super-Admin in system_configs/global
      try {
        final snap = await firestore
            .collection('system_configs')
            .doc('global')
            .get()
            .timeout(const Duration(seconds: 3));
        if (snap.exists && snap.data() != null) {
          final configs = snap.data()?['configs'];
          if (configs is Map) {
            final ai = configs['ai'];
            if (ai is Map) {
              extractOptionalRemoteConfig(Map<String, dynamic>.from(ai));
              final key = (ai['geminiApiKey'] ?? '').toString().trim();
              if (key.isNotEmpty) return key;
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching system_configs/global: $e');
      }

      // 4. Check app_config/global fallback
      try {
        final doc = await firestore
            .collection('app_config')
            .doc('global')
            .get()
            .timeout(const Duration(seconds: 3));
        if (doc.exists && doc.data() != null) {
          extractOptionalRemoteConfig(doc.data()!);
          final key = (doc.data()?['gemini_api_key'] ?? '').toString().trim();
          if (key.isNotEmpty) return key;
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching app_config/global: $e');
      }

      return null;
    }

    final remoteKey = await tryLoadKey();
    if (remoteKey != null && remoteKey.isNotEmpty) {
      _cachedApiKey = remoteKey;
      try {
        await LocalDbService.saveCache(_localApiKeyCacheKey, remoteKey);
      } catch (_) {}
      return remoteKey;
    }

    // Check locally cached key from previous session
    try {
      final cached = LocalDbService.getCache(_localApiKeyCacheKey);
      if (cached is String && cached.trim().isNotEmpty) {
        _cachedApiKey = cached.trim();
        return _cachedApiKey!;
      }
    } catch (_) {}

    return SloAiConfig.fallbackGeminiApiKey;
  }

  /// Dynamically queries Google's ModelService (`/v1beta/models`) to discover all currently active
  /// multimodal/text generation models for the API key. This guarantees that even when Google
  /// retires old models or releases new ones in the future, the app adapts automatically
  /// without ever needing an APK rebuild.
  static Future<List<String>> resolveCandidateModels(
    String apiKey, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedDiscoveredModels != null && _cachedDiscoveredModels!.isNotEmpty) {
      final list = <String>[
        if (_cachedWorkingModel != null && _cachedWorkingModel!.isNotEmpty) _cachedWorkingModel!,
        ..._cachedDiscoveredModels!,
      ];
      return list.toSet().toList();
    }

    // Restore cached working model if available
    if (_cachedWorkingModel == null) {
      try {
        final savedModel = LocalDbService.getCache(_localWorkingModelCacheKey);
        if (savedModel is String && savedModel.trim().isNotEmpty) {
          _cachedWorkingModel = savedModel.trim();
        }
      } catch (_) {}
    }

    final List<String> discovered = [];
    try {
      final uri = Uri.parse(
        "https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey",
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final rawModels = decoded['models'] as List?;
        if (rawModels != null) {
          final excludedKeywords = [
            'tts',
            'image',
            'transcribe',
            'robotics',
            'computer-use',
            'lyria',
            'embedding',
            'deep-research',
            'antigravity',
            'nano-banana',
            'imagen',
            'veo',
            'aqa',
          ];

          final validModels = <String>[];
          for (final item in rawModels) {
            if (item is Map) {
              final name = (item['name'] ?? '').toString().replaceFirst(RegExp(r'^models/'), '').trim();
              final methods = (item['supportedGenerationMethods'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const <String>[];
              if (name.isEmpty || !methods.contains('generateContent')) continue;
              final lower = name.toLowerCase();
              if (!lower.startsWith('gemini-')) continue;
              if (excludedKeywords.any((kw) => lower.contains(kw))) continue;
              validModels.add(name);
            }
          }

          int scoreModel(String m) {
            final l = m.toLowerCase();
            if (l == 'gemini-3.5-flash-lite') return 100;
            if (l == 'gemini-3.5-flash') return 98;
            if (l == 'gemini-3.1-flash-lite') return 95;
            if (l == 'gemini-flash-lite-latest') return 92;
            if (l == 'gemini-3.8-flash') return 88;
            if (l == 'gemini-3.7-flash') return 85;
            if (l == 'gemini-3.6-flash') return 82;
            if (l == 'gemini-flash-latest') return 80;
            if (l.contains('3.5') && l.contains('flash')) return 78;
            if (l.contains('flash') && !l.contains('preview')) return 70;
            if (l.contains('flash')) return 60;
            if (l.contains('pro')) return 45;
            return 20;
          }

          validModels.sort((a, b) => scoreModel(b).compareTo(scoreModel(a)));
          discovered.addAll(validModels);
        }
      }
    } catch (e) {
      debugPrint('⚠️ [SloGemini] Dynamic model discovery warning: $e');
    }

    if (discovered.isNotEmpty) {
      _cachedDiscoveredModels = discovered;
    }

    final combined = <String>[
      if (!forceRefresh && _cachedWorkingModel != null && _cachedWorkingModel!.isNotEmpty)
        _cachedWorkingModel!,
      ...SloAiConfig.defaultCandidateModels,
      ...discovered,
    ];

    // Deduplicate while preserving priority order
    final seen = <String>{};
    return combined.where((m) => m.isNotEmpty && seen.add(m)).toList();
  }

  /// Detects if a text or subject is Urdu / Arabic / RTL
  static bool _detectRtlFromSubjectOrText(String subject, String text) {
    final s = subject.trim().toLowerCase();
    if (s.contains('urdu') ||
        s.contains('islam') ||
        s.contains('arabic') ||
        s.contains('quran') ||
        s.contains('pashto') ||
        s.contains('sindhi') ||
        s.contains('اردو') ||
        s.contains('اسلامیات')) {
      return true;
    }
    // Check if text contains significant Arabic/Urdu Unicode characters
    final urduMatches = RegExp(r'[\u0600-\u06FF]').allMatches(text).length;
    return urduMatches > 15;
  }

  /// Cleans accidental prefixes or meta-references from a generated question
  static String _sanitizeQuestionText(String rawText) {
    String cleaned = rawText.trim();

    // Remove leading numbering like "Q1.", "Q1:", "1.", "(1)", "سوال نمبر 1:"
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(?:Q\d+[\.\:\)\-]?\s*|\(\d+\)\s*|\d+[\.\)\-]\s*|سوال\s*(?:نمبر)?\s*[\d۰-۹]+[\.\:\-\)]?\s*)', caseSensitive: false),
      '',
    );

    // Strip awkward chapter prefix if AI ever added it e.g. 'باب "..." کے مطابق، ' or 'According to Chapter X, '
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(?:باب\s*(?:نمبر\s*[\d۰-۹]+)?\s*["”«]?[^"”»\n]{1,40}["”»]?\s*کے\s*مطابق\s*[،,:\-]?\s*)'),
      '',
    );
    cleaned = cleaned.replaceFirst(
      RegExp(r'^(?:According to (?:Chapter|Unit)\s*\d+[^,\n]{0,40},\s*|In the context of [^,\n]{1,40},\s*)', caseSensitive: false),
      '',
    );

    // Strip trailing "(1)", "(2)" index markers
    cleaned = cleaned.replaceAll(RegExp(r'\s*\(\d+\)\s*[:：]'), ':');

    return cleaned.trim();
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
    final docId = ChapterBankDoc.generateDocId(
      publisher: publisher,
      grade: grade,
      subject: subject,
      chapterNumber: chapterNumber,
    );

    final apiKey = await getApiKey();
    if (apiKey.isEmpty || apiKey == "YOUR_GEMINI_API_KEY_HERE") {
      throw Exception(
        "Gemini AI Key is not configured. Please check internet connection or AI settings in Super Admin.",
      );
    }

    final bool effectiveRtl = isRtlSubject || _detectRtlFromSubjectOrText(subject, bookContent.text);

    // Load optional remote custom instructions if cached
    String extraRemoteRules = _cachedRemoteCustomPrompt ?? '';
    if (extraRemoteRules.isEmpty) {
      try {
        final savedPrompt = LocalDbService.getCache(_localRemotePromptCacheKey);
        if (savedPrompt is String && savedPrompt.trim().isNotEmpty) {
          extraRemoteRules = savedPrompt.trim();
        }
      } catch (_) {}
    }

    final String systemInstruction = """
You are an elite Pakistani Board Examination Paper Setter (BISE / FBISE Curriculum Specialist) with 20+ years of experience designing 100% accurate, textbook-bound exam papers.

YOUR COGNITIVE FILTERING & EXTRACTION BRAIN RULES (MANDATORY):
1. WHAT TO IGNORE (NOISE FILTERING):
   - Completely IGNORE page numbers (such as '۲', '۳', '4', 'Page 12' in circles/headers/footers), running book headers, publisher watermarks, binding shadows, decorative borders, and stray OCR characters.
   - If a sentence at the very top or very bottom edge of a scanned page is cut off mid-sentence (from the previous/next page), ignore the incomplete fragment and focus on complete sentences and paragraphs.

2. ZERO CHAPTER-NAME OR META-TEXT POLLUTION IN QUESTIONS (STRICTLY FORBIDDEN):
   - NEVER mention the chapter number, chapter title, or subject name inside a question!
   - NEVER write artificial phrases like: "باب نمبر 1 کے مطابق...", "باب حُسنِ خُلق کے مطابق...", "اس سبق میں...", "دیے گئے صفحے کے مطابق...", "According to Chapter $chapterNumber...", "In the context of $subject...", or "(Urdu)".
   - Every single question MUST read like a real, standalone Pakistani Board Exam question (e.g., "مجلسِ نبویﷺ میں اگر بعد میں آنے والے کے لیے جگہ باقی نہ رہتی تو آپﷺ کیا فرماتے تھے؟" or "مداومتِ عمل سے کیا مراد ہے اور لفظ 'سنت' اس اصول سے کس طرح پیدا ہوا ہے؟").

3. HOW TO EXTRACT & CREATE 100% ACCURATE QUESTIONS FROM ANY PAGE:
   - CASE A (Exercise Page / مشقی سوالات): If printed exercise questions (MCQs, Short Questions, Long Questions, Numericals) are visible on the scanned pages, extract them verbatim and provide their exact textbook options and answers.
   - CASE B (Lesson / Prose / Reading Pages — e.g. Urdu lessons, Seerah/Akhlaq, Islamiyat, Science, History): Carefully read every heading, paragraph, historical incident (واقعہ), Hadith/saying, definition (تعریف), example (مثال — such as آفتاب سے روشنی، درخت سے پھل اور پھول سے خوشبو), cause-and-effect, and key term on the scanned pages. Transform those exact facts and concepts into:
     • Specific, factual & conceptual MCQs where all 4 options are realistic, meaningful choices from the domain (NEVER use generic filler options like "بنیادی اصول اور تعریف", "ثانوی عمل", "غیر متعلقہ عنصر").
     • Clear, exam-grade Short Questions (مختصر سوالات) asking definitions, reasons, incidents, or explanations directly from the text.
     • Comprehensive Long Questions (تفصیلی سوالات) covering the major headings, themes, and detailed explanations from the scanned pages.

4. LANGUAGE & SCRIPT PURITY:
   - ${effectiveRtl ? 'The scanned textbook is in URDU / RTL script. Write ALL chapter_title, slo statements, question_text, options (الف، ب، ج، د), correct_answer, and rubric in 100% pure, fluent, authentic literary Urdu script (فصیح اردو). Do NOT insert English words or numbers in parentheses.' : 'Write all questions, options (A, B, C, D), answers, and rubrics in clear, formal academic English.'}

5. MATH / SCIENCE UNICODE FORMATTING:
   - Format all mathematical expressions, powers, roots, and chemical formulas using clean printable Unicode (e.g., x², y³, √(a+b), π, θ, Δ, ÷, ×, ≤, ≥, →, H₂SO₄). NEVER output raw LaTeX like \\frac or \\sqrt.
${extraRemoteRules.isNotEmpty ? '\n6. ADDITIONAL ADMIN RULES:\n$extraRemoteRules' : ''}
""";

    final String userPrompt = """
Carefully examine the attached textbook page(s) for:
- Board / Publisher: $publisher
- Class / Grade: $grade
- Subject: $subject
- Chapter Number: $chapterNumber
${chapterTitle.trim().isNotEmpty ? '- Chapter Title Hint: $chapterTitle' : ''}
- Output Language: ${effectiveRtl ? '100% Pure Urdu Script (اردو)' : 'English'}

TASK:
1. Identify the real Chapter/Topic title from the heading on the scanned page(s) (e.g., "حُسنِ خُلق" / "اخلاقِ نبویﷺ" or the actual chapter heading). Do NOT append "(Urdu)" or "Chapter $chapterNumber" to the title.
2. Extract 3 to 5 real Student Learning Outcomes (SLOs) covered in these pages using codes "SLO-$chapterNumber.1", "SLO-$chapterNumber.2", etc.
3. Generate a 100% accurate, textbook-verified Question Bank strictly from the content of these pages:
   - 15 Multiple Choice Questions (MCQs) with 4 realistic, specific options (${effectiveRtl ? 'الف) ..., ب) ..., ج) ..., د) ...' : 'A) ..., B) ..., C) ..., D) ...'}) and the exact matching `correct_answer`.
   - 12 Short Questions (مختصر سوالات - 3 marks each) testing specific definitions, incidents, reasons, and concepts from the pages, with the actual model answer in `correct_answer` and `rubric`.
   - 5 Long Questions (تفصیلی سوالات - 6 marks each) testing comprehensive explanations of the main topics/headings on the pages, with a detailed answer summary in `correct_answer` and `rubric`.

Remember: NEVER write "باب نمبر $chapterNumber کے مطابق" or chapter names inside `question_text`, and NEVER use generic placeholder options!

Return STRICT JSON matching this exact schema:
{
  "chapter_title": "Exact topic/chapter title from the page",
  "slos": [
    {
      "slo_code": "SLO-$chapterNumber.1",
      "statement": "Learning outcome statement"
    }
  ],
  "questions": [
    {
      "id": "q1",
      "slo_code": "SLO-$chapterNumber.1",
      "type": "MCQ",
      "cognitive_level": "Knowledge",
      "question_text": "Direct exam question without chapter prefix",
      "options": [
        "${effectiveRtl ? 'الف) پہلا آپشن' : 'A) First option'}",
        "${effectiveRtl ? 'ب) دوسرا آپشن' : 'B) Second option'}",
        "${effectiveRtl ? 'ج) تیسرا آپشن' : 'C) Third option'}",
        "${effectiveRtl ? 'د) چوتھا آپشن' : 'D) Fourth option'}"
      ],
      "correct_answer": "${effectiveRtl ? 'الف) پہلا آپشن' : 'A) First option'}",
      "rubric": "Model answer or marking criteria"
    }
  ]
}
""";

    // Build multimodal request parts (text + images)
    final List<Map<String, dynamic>> parts = [
      {"text": userPrompt},
    ];

    if (bookContent.hasText) {
      parts.add({
        "text": "\n=== EXTRACTED TEXTBOOK CONTENT ===\n${bookContent.text}\n=== END OF CONTENT ==="
      });
    }

    if (bookContent.hasImages) {
      for (final Uint8List imageBytes in bookContent.compressedImages) {
        parts.add({
          "inline_data": {
            "mime_type": "image/jpeg",
            "data": base64Encode(imageBytes),
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
        "temperature": 0.15,
        "responseMimeType": "application/json",
      }
    };

    // Resolve active models dynamically (cached working model + defaults + live Google API model discovery)
    List<String> candidateModels = await resolveCandidateModels(apiKey);

    ChapterBankDoc? parsedBank;
    String lastError = "";

    for (int pass = 0; pass < 2 && parsedBank == null; pass++) {
      if (pass == 1) {
        // On second pass, force-refresh live models from Google API in case cached models changed
        _cachedWorkingModel = null;
        candidateModels = await resolveCandidateModels(apiKey, forceRefresh: true);
      }

      for (final modelName in candidateModels) {
        final String url =
            "https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey";

        try {
          debugPrint("🤖 [SloGemini] Calling model: $modelName...");
          final response = await http
              .post(
                Uri.parse(url),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode(requestBody),
              )
              .timeout(const Duration(seconds: 35));

          if (response.statusCode == 200) {
            final bank = _parseAndValidateGeminiResponse(
              responseBody: response.body,
              docId: docId,
              publisher: publisher,
              grade: grade,
              subject: subject,
              chapterNumber: chapterNumber,
              fallbackTitle: chapterTitle,
              isRtlSubject: effectiveRtl,
            );
            if (bank != null && bank.questions.isNotEmpty) {
              debugPrint("✅ [SloGemini] Model $modelName succeeded with ${bank.questions.length} authentic questions!");
              _cachedWorkingModel = modelName;
              try {
                await LocalDbService.saveCache(_localWorkingModelCacheKey, modelName);
              } catch (_) {}
              parsedBank = bank;
              break;
            }
          } else {
            debugPrint("⚠️ [SloGemini] Model $modelName returned ${response.statusCode}");
            lastError = "HTTP ${response.statusCode}: ${response.body}";
          }
        } catch (e) {
          debugPrint("⚠️ [SloGemini] Exception on $modelName: $e");
          lastError = e.toString();
        }
      }
    }

    if (parsedBank != null) {
      return parsedBank;
    }

    throw Exception(
      "Could not generate questions from the scanned pages. Please ensure your internet connection is active and the book page photo is clear. ($lastError)",
    );
  }

  /// Parses, sanitizes, and validates Gemini's JSON response
  static ChapterBankDoc? _parseAndValidateGeminiResponse({
    required String responseBody,
    required String docId,
    required String publisher,
    required String grade,
    required String subject,
    required int chapterNumber,
    required String fallbackTitle,
    required bool isRtlSubject,
  }) {
    try {
      final Map<String, dynamic> responseJson =
          Map<String, dynamic>.from(jsonDecode(responseBody) as Map);
      final candidates = responseJson['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;

      final candidate = Map<String, dynamic>.from(candidates.first as Map);
      final content = candidate['content'] is Map
          ? Map<String, dynamic>.from(candidate['content'] as Map)
          : null;
      final candidateParts = content?['parts'] as List?;
      if (candidateParts == null || candidateParts.isEmpty) return null;

      String rawJsonText = "";
      for (final p in candidateParts) {
        if (p is Map && p['text'] != null) {
          final t = p['text'].toString().trim();
          if (t.contains('{')) {
            rawJsonText = t;
            break;
          }
        }
      }
      if (rawJsonText.isEmpty) {
        rawJsonText = (Map<String, dynamic>.from(candidateParts.first as Map)['text'] ?? "{}")
            .toString()
            .trim();
      }

      if (rawJsonText.startsWith('```')) {
        rawJsonText = rawJsonText
            .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
            .replaceFirst(RegExp(r'\s*```$'), '')
            .trim();
      }

      // Extract JSON object if wrapped in extra text
      final firstBrace = rawJsonText.indexOf('{');
      final lastBrace = rawJsonText.lastIndexOf('}');
      if (firstBrace != -1 && lastBrace > firstBrace) {
        rawJsonText = rawJsonText.substring(firstBrace, lastBrace + 1);
      }

      final Map<String, dynamic> parsedData =
          Map<String, dynamic>.from(jsonDecode(rawJsonText) as Map);

      String resolvedTitle = (parsedData['chapter_title'] ?? fallbackTitle)
          .toString()
          .replaceAll(RegExp(r'\s*\(Urdu\)\s*', caseSensitive: false), '')
          .trim();

      if (resolvedTitle.isEmpty) {
        resolvedTitle = isRtlSubject ? 'باب $chapterNumber' : 'Chapter $chapterNumber';
      }

      final List<SloItem> parsedSlos = [];
      if (parsedData['slos'] is List) {
        for (final s in parsedData['slos'] as List) {
          if (s is Map) {
            final item = SloItem.fromJson(Map<String, dynamic>.from(s));
            if (item.statement.trim().isNotEmpty) {
              parsedSlos.add(item);
            }
          }
        }
      }

      final List<SloQuestion> parsedQuestions = [];
      if (parsedData['questions'] is List) {
        int idx = 1;
        for (final q in parsedData['questions'] as List) {
          if (q is Map) {
            final qMap = Map<String, dynamic>.from(q);
            qMap['id'] = '${docId}_q$idx';
            qMap['question_text'] = _sanitizeQuestionText(
              (qMap['question_text'] ?? qMap['questionText'] ?? '').toString(),
            );

            final questionObj = SloQuestion.fromJson(qMap);
            // Strictly reject any empty or dummy-like question
            if (questionObj.questionText.length >= 6 &&
                !SloRepository.isDummyOrCorruptedQuestion(questionObj)) {
              parsedQuestions.add(questionObj);
              idx++;
            }
          }
        }
      }

      if (parsedQuestions.isEmpty) {
        return null;
      }

      if (parsedSlos.isEmpty) {
        final uniqueCodes = parsedQuestions
            .map((q) => q.sloCode)
            .where((c) => c.isNotEmpty)
            .toSet();
        if (uniqueCodes.isEmpty) {
          parsedSlos.add(SloItem(
            sloCode: 'SLO-$chapterNumber.1',
            statement: resolvedTitle,
          ));
        } else {
          for (final code in uniqueCodes) {
            parsedSlos.add(SloItem(
              sloCode: code,
              statement: '$resolvedTitle ($code)',
            ));
          }
        }
      }

      return ChapterBankDoc(
        docId: docId,
        publisher: publisher,
        grade: grade,
        subject: subject,
        chapterNumber: chapterNumber,
        chapterTitle: resolvedTitle,
        isRtl: isRtlSubject,
        slos: parsedSlos,
        questions: parsedQuestions,
        updatedAt: FieldValue.serverTimestamp(),
      );
    } catch (e) {
      debugPrint("⚠️ [SloGemini] Error parsing Gemini JSON: $e");
      return null;
    }
  }
}
