import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:teacher_mobile_app/features/paper_exam/config/slo_ai_config.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/slo_gemini_service.dart';
import 'package:teacher_mobile_app/features/syllabus/providers/syllabus_provider.dart';

class ScanBookIndexScreen extends ConsumerStatefulWidget {
  const ScanBookIndexScreen({super.key});

  @override
  ConsumerState<ScanBookIndexScreen> createState() => _ScanBookIndexScreenState();
}

class _ScanBookIndexScreenState extends ConsumerState<ScanBookIndexScreen> {
  final ImagePicker _picker = ImagePicker();
  SyllabusAssignment? _selectedAssignment;
  bool _isScanning = false;
  bool _isSaving = false;
  String _statusMessage = '';
  List<Map<String, dynamic>> _extractedChapters = [];

  bool _isRtlSubject(String subject) {
    final s = subject.trim().toLowerCase();
    return s.contains('urdu') ||
        s.contains('islam') ||
        s.contains('arabic') ||
        s.contains('quran') ||
        s.contains('pashto') ||
        s.contains('sindhi');
  }

  Future<void> _scanIndexPages(ImageSource source) async {
    final assignment = _selectedAssignment;
    if (assignment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a Class & Subject first.")),
      );
      return;
    }

    List<XFile> pickedFiles = [];
    try {
      if (source == ImageSource.gallery) {
        pickedFiles = await _picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
      } else {
        final single = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (single != null) pickedFiles = [single];
      }
    } catch (e) {
      debugPrint("Image pick error: $e");
    }

    if (pickedFiles.isEmpty) return;

    setState(() {
      _isScanning = true;
      _statusMessage = 'Reading book index page...';
    });

    try {
      final isRtl = _isRtlSubject(assignment.subject);
      final StringBuffer ocrBuffer = StringBuffer();
      final List<Uint8List> compressedImages = [];

      TextRecognizer? recognizer;
      if (!isRtl) {
        try {
          recognizer = TextRecognizer(script: TextRecognitionScript.latin);
        } catch (_) {}
      }

      try {
        for (int i = 0; i < pickedFiles.length; i++) {
          final fileObj = File(pickedFiles[i].path);

          // 1. Free On-Device ML Kit OCR (0 Cost, Instant, Works Offline)
          if (recognizer != null) {
            try {
              final inputImage = InputImage.fromFilePath(fileObj.path);
              final recognized = await recognizer.processImage(inputImage);
              if (recognized.text.trim().isNotEmpty) {
                ocrBuffer.writeln(recognized.text.trim());
              }
            } catch (e) {
              debugPrint("On-device OCR error: $e");
            }
          }

          // 2. Compress image in case we need Gemini Vision (for Urdu or complex layouts)
          final compressed = await _compressImage(fileObj);
          if (compressed != null) {
            compressedImages.add(compressed);
          }

          // Clean up temp file
          try {
            if (await fileObj.exists()) await fileObj.delete();
          } catch (_) {}
        }
      } finally {
        recognizer?.close();
      }

      final extractedText = ocrBuffer.toString().trim();
      List<Map<String, dynamic>> chapters = [];

      // Try AI structured extraction first if online & API key exists
      try {
        setState(() {
          _statusMessage = 'Extracting chapters & topics...';
        });
        chapters = await _extractWithGemini(
          subject: assignment.subject,
          className: assignment.className,
          isRtl: isRtl,
          ocrText: extractedText,
          images: compressedImages,
        );
      } catch (aiErr) {
        debugPrint("AI extraction fallback to local parser: $aiErr");
      }

      // Offline / Zero-Cost Fallback: Smart Local Index Parser from On-Device OCR
      if (chapters.isEmpty && extractedText.isNotEmpty) {
        chapters = _parseIndexOfflineFromOcr(extractedText);
      }

      if (chapters.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Could not detect clear chapter titles. You can try a clearer photo or add/edit chapters manually below.",
              ),
            ),
          );
        }
      } else {
        setState(() {
          _extractedChapters = chapters;
          _statusMessage = '';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<Uint8List?> _compressImage(File file) async {
    try {
      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 1280,
        minHeight: 1280,
        quality: 75,
        format: CompressFormat.jpeg,
      );
      if (result != null) return result;
    } catch (_) {}
    try {
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {}
    return null;
  }

  /// Calls Gemini Flash using Text-Only (0 Image Tokens if OCR text is clear) or Vision (for Urdu / low OCR)
  Future<List<Map<String, dynamic>>> _extractWithGemini({
    required String subject,
    required String className,
    required bool isRtl,
    required String ocrText,
    required List<Uint8List> images,
  }) async {
    final apiKey = await SloGeminiService.getApiKey().timeout(
      const Duration(seconds: 3),
      onTimeout: () => SloAiConfig.fallbackGeminiApiKey,
    );

    if (apiKey.isEmpty || apiKey == "YOUR_GEMINI_API_KEY_HERE") {
      return [];
    }

    final prompt = """
You are an expert school curriculum parser. Extract the list of chapters from this textbook Table of Contents / Index page for Class "$className" - Subject "$subject".
Rules:
1. Ignore preface, foreword, glossary, or answer key pages. Only extract actual chapters/units/poems/lessons.
2. Clean out page numbers, dots (....), and serial noise from the chapter title.
3. If sub-topics or sub-headings are listed under a chapter in the index, include up to 4 concise sub-topics in "topics".
4. If the book index is in Urdu/Arabic script, keep the chapter titles and topics in pure authentic Urdu/Arabic script.
5. Return STRICT JSON array:
[
  {
    "title": "Chapter Title",
    "time": "2 Weeks",
    "topics": ["Subtopic 1", "Subtopic 2"]
  }
]
""";

    final List<Map<String, dynamic>> parts = [
      {"text": prompt}
    ];

    // Zero-cost optimization: if English/Latin OCR extracted >= 80 chars, send text ONLY (0 image bytes!)
    if (!isRtl && ocrText.length >= 80) {
      parts.add({"text": "\n=== BOOK INDEX OCR TEXT ===\n$ocrText"});
    } else {
      if (ocrText.isNotEmpty) {
        parts.add({"text": "\n=== OCR HINT ===\n$ocrText"});
      }
      for (final img in images) {
        parts.add({
          "inline_data": {
            "mime_type": "image/jpeg",
            "data": base64Encode(img),
          }
        });
      }
    }

    final requestBody = {
      "contents": [
        {"role": "user", "parts": parts}
      ],
      "generationConfig": {
        "temperature": 0.1,
        "responseMimeType": "application/json",
      }
    };

    final models = [
      "gemini-2.5-flash",
      "gemini-2.0-flash-lite",
      "gemini-2.0-flash",
      "gemini-1.5-flash",
    ];

    for (final model in models) {
      try {
        final uri = Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey",
        );
        final res = await http
            .post(
              uri,
              headers: {"Content-Type": "application/json"},
              body: jsonEncode(requestBody),
            )
            .timeout(const Duration(seconds: 12));

        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          final candidates = decoded['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            String rawText =
                (candidates.first['content']?['parts']?.first?['text'] ?? '[]')
                    .toString()
                    .trim();
            if (rawText.startsWith('```')) {
              rawText = rawText
                  .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
                  .replaceFirst(RegExp(r'\s*```$'), '')
                  .trim();
            }
            final dynamic jsonVal = jsonDecode(rawText);
            final List listData = jsonVal is List
                ? jsonVal
                : (jsonVal is Map && jsonVal['chapters'] is List
                    ? jsonVal['chapters'] as List
                    : []);

            final List<Map<String, dynamic>> out = [];
            for (final item in listData) {
              if (item is Map) {
                final title = (item['title'] ?? '').toString().trim();
                if (title.isNotEmpty) {
                  final topics = (item['topics'] as List?)
                          ?.map((e) => e.toString().trim())
                          .where((e) => e.isNotEmpty)
                          .toList() ??
                      <String>[];
                  out.add({
                    'title': title,
                    'time': (item['time'] ?? '2 Weeks').toString(),
                    'topics': topics,
                    'status': 'Pending',
                  });
                }
              }
            }
            if (out.isNotEmpty) return out;
          }
        }
      } catch (e) {
        debugPrint("Model $model error: $e");
      }
    }
    return [];
  }

  /// 100% Free & Offline Smart Index Parser from On-Device ML Kit OCR
  List<Map<String, dynamic>> _parseIndexOfflineFromOcr(String rawOcr) {
    final lines = rawOcr
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.length >= 3)
        .toList();

    final ignoreWords = RegExp(
      r'^(contents|table of contents|index|sr\.?\s*no|chapter\s*no|page\s*no|page|unit|chapters|preface|glossary|bibliography|answers|appendix)$',
      caseSensitive: false,
    );

    final List<Map<String, dynamic>> results = [];

    for (String line in lines) {
      if (ignoreWords.hasMatch(line)) continue;

      // Remove trailing page numbers and leader dots e.g. "1. Photosynthesis ........ 14"
      String cleaned = line
          .replaceAll(RegExp(r'[\.\-_]{2,}\s*\d*$'), '')
          .replaceAll(RegExp(r'\s+\d{1,3}$'), '')
          .trim();

      // Remove leading serial/chapter prefix like "Chapter 1:", "Unit 02 -", "1."
      cleaned = cleaned
          .replaceFirst(
            RegExp(
              r'^(?:(?:chapter|unit|ch|lesson)\s*\d+\s*[:\-\.]?\s*|\d{1,2}\s*[\.\)\-:]\s*)',
              caseSensitive: false,
            ),
            '',
          )
          .trim();

      // Must contain letters and be a reasonable title length
      if (cleaned.length < 3 || cleaned.length > 90) continue;
      if (!RegExp(r'[a-zA-Z]{3,}').hasMatch(cleaned)) continue;
      if (ignoreWords.hasMatch(cleaned)) continue;

      // Avoid duplicates
      if (!results.any(
          (r) => r['title'].toString().toLowerCase() == cleaned.toLowerCase())) {
        results.add({
          'title': cleaned,
          'time': '2 Weeks',
          'topics': <String>[],
          'status': 'Pending',
        });
      }
    }

    return results;
  }

  Future<void> _saveToSyllabus() async {
    final assignment = _selectedAssignment;
    if (assignment == null || _extractedChapters.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await ref.read(syllabusServiceProvider).saveScannedChapters(
            assignment: assignment,
            scannedChapters: _extractedChapters,
            replaceExisting: true,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            content: Text(
              "Saved ${_extractedChapters.length} chapters to ${assignment.className} • ${assignment.subject}!",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving chapters: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showEditOrAddChapterDialog({int? index}) {
    final isEdit = index != null;
    final existing = isEdit ? _extractedChapters[index] : null;
    final titleCtrl = TextEditingController(text: existing?['title']?.toString() ?? '');
    final topicsCtrl = TextEditingController(
      text: (existing?['topics'] as List?)?.join(', ') ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(isEdit ? "Edit Chapter" : "Add Chapter"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: "Chapter Name",
                hintText: "e.g. Photosynthesis & Respiration",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: topicsCtrl,
              decoration: const InputDecoration(
                labelText: "Topics (comma separated, optional)",
                hintText: "e.g. Light Reaction, Dark Reaction",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10b981),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final title = titleCtrl.text.trim();
              if (title.isEmpty) return;
              final topics = topicsCtrl.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();

              setState(() {
                final item = {
                  'title': title,
                  'time': existing?['time'] ?? '2 Weeks',
                  'topics': topics,
                  'status': existing?['status'] ?? 'Pending',
                };
                if (isEdit) {
                  _extractedChapters[index] = item;
                } else {
                  _extractedChapters.add(item);
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final syllabusesAsync = ref.watch(mySyllabusesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Clean Theme Header ---
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              bottom: 16,
              left: 16,
              right: 16,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10b981), Color(0xFF059669)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                )
              ],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.chevron_left, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Scan Book Index",
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        "Snap index page to auto-build syllabus",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: syllabusesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF10b981)),
              ),
              error: (e, st) => Center(child: Text("Error: $e")),
              data: (assignments) {
                if (assignments.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        "No assigned classes or subjects found in your timetable.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                // Default select first assignment if not selected yet
                if (_selectedAssignment == null ||
                    !assignments.contains(_selectedAssignment)) {
                  _selectedAssignment = assignments.first;
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // --- Step 1: Select Assigned Class & Subject ---
                    Text(
                      "1. Select Your Class & Subject",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: assignments.map((item) {
                        final isSelected = _selectedAssignment == item;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedAssignment = item;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF10b981)
                                  : (isDark
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.white),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF10b981)
                                    : (isDark
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.black.withOpacity(0.08)),
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF10b981)
                                            .withOpacity(0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      )
                                    ]
                                  : [],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.auto_stories_rounded,
                                  size: 16,
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF10b981),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "${item.className} • ${item.subject}",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? Colors.white
                                        : (isDark
                                            ? Colors.white
                                            : const Color(0xFF1E293B)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    // --- Step 2: Clean Camera / Gallery Index Scanner Card ---
                    Text(
                      "2. Capture Book Index (Table of Contents)",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.04)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFF10b981).withOpacity(0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10b981).withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.document_scanner_rounded,
                              color: Color(0xFF10b981),
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Snap or pick the Book Index page",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Chapters & topics will be extracted automatically (works offline & online).",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_isScanning)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                children: [
                                  const CircularProgressIndicator(
                                    color: Color(0xFF10b981),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _statusMessage,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF10b981),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _scanIndexPages(ImageSource.camera),
                                    icon: const Icon(
                                      Icons.camera_alt_rounded,
                                      size: 18,
                                    ),
                                    label: const Text("Camera"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10b981),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _scanIndexPages(ImageSource.gallery),
                                    icon: const Icon(
                                      Icons.photo_library_rounded,
                                      size: 18,
                                    ),
                                    label: const Text("Gallery"),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF10b981),
                                      side: const BorderSide(
                                        color: Color(0xFF10b981),
                                        width: 1.4,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // --- Step 3: Preview & Edit Extracted Chapters on Notebook Paper ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "3. Extracted Chapters (${_extractedChapters.length})",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF475569),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _showEditOrAddChapterDialog(),
                          icon: const Icon(
                            Icons.add_circle_outline_rounded,
                            size: 16,
                            color: Color(0xFF10b981),
                          ),
                          label: const Text(
                            "Add Manually",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF10b981),
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (_extractedChapters.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.02)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.06)
                                : Colors.black.withOpacity(0.06),
                          ),
                        ),
                        child: Text(
                          "No chapters scanned yet. Use Camera or Gallery above to scan the book index page.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.grey[500],
                          ),
                        ),
                      )
                    else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDF7),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFE5DEC9),
                            width: 1.4,
                          ),
                        ),
                        child: Column(
                          children: List.generate(
                            _extractedChapters.length,
                            (idx) {
                              final ch = _extractedChapters[idx];
                              final topics = (ch['topics'] as List?)
                                      ?.map((e) => e.toString())
                                      .toList() ??
                                  [];
                              return Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: const Color(0xFFBFDBFE)
                                          .withOpacity(0.65),
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 32,
                                      child: Text(
                                        "${idx + 1}.",
                                        style: GoogleFonts.caveat(
                                          fontSize: 21,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ch['title']?.toString() ?? '',
                                            style: GoogleFonts.caveat(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF1E293B),
                                              height: 1.15,
                                            ),
                                          ),
                                          if (topics.isNotEmpty)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 2),
                                              child: Text(
                                                topics
                                                    .map((t) => "• $t")
                                                    .join("   "),
                                                style: GoogleFonts.patrickHand(
                                                  fontSize: 13.5,
                                                  color:
                                                      const Color(0xFF64748B),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: Color(0xFF64748B),
                                      ),
                                      onPressed: () =>
                                          _showEditOrAddChapterDialog(
                                              index: idx),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: Color(0xFFEF4444),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _extractedChapters.removeAt(idx);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveToSyllabus,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_circle_rounded),
                          label: Text(
                            _isSaving
                                ? "Saving Syllabus..."
                                : "Save ${_extractedChapters.length} Chapters to Syllabus",
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
