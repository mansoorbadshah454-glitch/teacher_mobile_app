import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/features/paper_exam/config/slo_ai_config.dart';
import 'package:teacher_mobile_app/features/paper_exam/models/slo_paper_models.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/ocr_and_image_service.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/slo_gemini_service.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/slo_pdf_generator.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/slo_repository.dart';

class SloPaperBuilderScreen extends ConsumerStatefulWidget {
  const SloPaperBuilderScreen({super.key});

  @override
  ConsumerState<SloPaperBuilderScreen> createState() => _SloPaperBuilderScreenState();
}

class _SloPaperBuilderScreenState extends ConsumerState<SloPaperBuilderScreen> {
  int _currentStep = 0; // 0 = Chapter, 1 = Blueprint, 2 = Live Preview

  // --- Step 1 Inputs ---
  String _selectedPublisher = "KPK Textbook Board (KP-TB)";
  String _selectedGrade = "9";
  String _selectedSubject = "Biology";
  int _chapterNumber = 1;
  final TextEditingController _chapterTitleCtrl = TextEditingController(text: "Introduction to Biology");
  final TextEditingController _customPublisherCtrl = TextEditingController();
  bool _isRtlSubject = false;
  bool _isCustomPublisher = false;

  // Cache & Processing State
  bool _isCheckingCache = false;
  bool _isCacheAvailable = false;
  bool _isGeneratingAi = false;
  String _statusMessage = "";
  ChapterBankDoc? _loadedBank;

  // 30-Second Cooldown Timer
  int _cooldownSecondsRemaining = 0;
  Timer? _cooldownTimer;

  // --- Step 2 Blueprint Inputs ---
  final Set<String> _selectedSloCodes = {};
  int _mcqCount = 10;
  int _shortCount = 8;
  int _longCount = 3;
  final TextEditingController _schoolNameCtrl = TextEditingController(text: "Smart Public School");
  final TextEditingController _campusCtrl = TextEditingController(text: "Main Campus");
  final TextEditingController _boardCtrl = TextEditingController(text: "Affiliated with Board of Intermediate & Secondary Education");
  final TextEditingController _examTitleCtrl = TextEditingController(text: "First Term Examination 2026");
  final TextEditingController _timeAllowedCtrl = TextEditingController(text: "2 Hours");
  int _totalMarks = 50; // MCQs (10*1) + Shorts (8*3=24) + Longs (3*6=18) = 52 ~ 50
  bool _hasSyncedSchoolData = false;

  // --- Step 3 Preview State ---
  List<SloQuestion> _activePaperQuestions = [];
  bool _isGeneratingPdf = false;
  bool _isSendingToPrincipal = false;
  String? _submittedPaperId;
  int _step3ViewMode = 0; // 0 = Edit & Swap Questions, 1 = Canva A4 Preview
  bool _previewIsAnswerKey = false;
  Uint8List? _schoolLogoBytes;
  Key _pdfPreviewKey = UniqueKey();
  final TransformationController _zoomController = TransformationController();
  final PageController _pagePreviewController = PageController();
  int _currentPreviewPageIndex = 0;
  bool _previewContinuousScroll = false;
  final ValueNotifier<double> _zoomLevelNotifier = ValueNotifier<double>(1.0);

  final List<String> _publishers = [
    "KPK Textbook Board (KP-TB)",
    "Punjab Textbook Board (PTB)",
    "Federal / SNC (FBISE)",
    "Afaq (Sun / Iqbal Series)",
    "Oxford University Press (OUP)",
    "Cantab Publisher",
    "Gohar Publisher",
    "Caravan Book House",
    "Paramount Publishing",
    "National Book Foundation (NBF)",
    "Sindh Textbook Board",
    "Balochistan Board",
    "Other / Custom Publisher...",
  ];

  String get _effectivePublisher {
    if (_isCustomPublisher && _customPublisherCtrl.text.trim().isNotEmpty) {
      return _customPublisherCtrl.text.trim();
    }
    return _selectedPublisher;
  }

  final List<String> _grades = [
    "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12"
  ];

  final List<String> _subjects = [
    "Biology",
    "Physics",
    "Chemistry",
    "Mathematics",
    "General Science",
    "Computer Science",
    "English",
    "Urdu",
    "Islamiyat",
    "Pakistan Studies",
  ];

  @override
  void initState() {
    super.initState();
    _checkFirestoreCache();
    _zoomController.addListener(_onZoomChanged);
  }

  void _onZoomChanged() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    if ((scale - _zoomLevelNotifier.value).abs() > 0.02) {
      _zoomLevelNotifier.value = scale;
    }
  }

  void _zoomIn() {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    if (currentScale < 4.5) {
      final newScale = (currentScale * 1.3).clamp(0.5, 5.0);
      _zoomController.value = Matrix4.diagonal3Values(newScale, newScale, 1.0);
      _zoomLevelNotifier.value = newScale;
    }
  }

  void _zoomOut() {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    if (currentScale > 0.6) {
      final newScale = (currentScale / 1.3).clamp(0.5, 5.0);
      _zoomController.value = Matrix4.diagonal3Values(newScale, newScale, 1.0);
      _zoomLevelNotifier.value = newScale;
    }
  }

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
    _zoomLevelNotifier.value = 1.0;
  }

  void _handleDoubleTap() {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    if ((currentScale - 1.0).abs() < 0.15) {
      _zoomController.value = Matrix4.diagonal3Values(2.2, 2.2, 1.0);
      _zoomLevelNotifier.value = 2.2;
    } else {
      _zoomController.value = Matrix4.identity();
      _zoomLevelNotifier.value = 1.0;
    }
  }

  @override
  void dispose() {
    _chapterTitleCtrl.dispose();
    _examTitleCtrl.dispose();
    _timeAllowedCtrl.dispose();
    _pagePreviewController.dispose();
    _zoomController.removeListener(_onZoomChanged);
    _zoomController.dispose();
    _zoomLevelNotifier.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldownSecondsRemaining = SloAiConfig.generationCooldown.inSeconds);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldownSecondsRemaining <= 1) {
        timer.cancel();
        setState(() => _cooldownSecondsRemaining = 0);
      } else {
        setState(() => _cooldownSecondsRemaining--);
      }
    });
  }

  String get _currentDocId => ChapterBankDoc.generateDocId(
        publisher: _effectivePublisher,
        grade: _selectedGrade,
        subject: _selectedSubject,
        chapterNumber: _chapterNumber,
      );

  Future<void> _checkFirestoreCache() async {
    setState(() {
      _isCheckingCache = true;
      _isCacheAvailable = false;
      _statusMessage = "Checking global question bank...";
    });

    try {
      final bank = await SloRepository.getChapterBank(_currentDocId);
      if (mounted) {
        setState(() {
          _isCheckingCache = false;
          if (bank != null && bank.questions.isNotEmpty) {
            _loadedBank = bank;
            _isCacheAvailable = true;
            if (bank.chapterTitle.isNotEmpty) {
              _chapterTitleCtrl.text = bank.chapterTitle;
            }
            _selectedSloCodes.clear();
            _selectedSloCodes.addAll(bank.slos.map((s) => s.sloCode));
            _statusMessage = "⚡ Instant SLO Bank Available (${bank.questions.length} questions in cache)";
          } else {
            _loadedBank = null;
            _isCacheAvailable = false;
            _statusMessage = "No cache found yet. Scan textbook pages to generate.";
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingCache = false;
          _isCacheAvailable = false;
          _statusMessage = "Ready to scan.";
        });
      }
    }
  }

  /// Multi-Page Camera Scanner Flow (Page 1 -> Page 2 -> Page 3...)
  Future<void> _startMultiPageCameraCapture() async {
    if (_cooldownSecondsRemaining > 0) {
      _showToast("Please wait $_cooldownSecondsRemaining seconds before scanning again.");
      return;
    }

    final ocrService = OcrAndImageService();
    // Snap first page immediately
    final firstPage = await ocrService.pickSinglePage(source: ImageSource.camera);
    if (firstPage == null) return;

    final List<XFile> capturedPages = [firstPage];

    if (!mounted) return;

    // Show interactive multi-page sheet
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E293B)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Multi-Page Book Scanner",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "${capturedPages.length} ${capturedPages.length == 1 ? 'Page' : 'Pages'} Snapped",
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "You can capture multiple pages of this chapter one by one. When done, click 'Generate Question Paper'.",
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  // Snap another page button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text("➕ Snap Next Page", style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final next = await ocrService.pickSinglePage(source: ImageSource.camera);
                      if (next != null) {
                        setModalState(() {
                          capturedPages.add(next);
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  // Finish and generate
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      "Generate Paper (${capturedPages.length} Pages)",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _processPagesAndGenerate(capturedPages);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _processPagesAndGenerate(List<XFile> pages) async {
    setState(() {
      _isGeneratingAi = true;
      _statusMessage = "Processing ${pages.length} page(s)...";
    });

    try {
      final ocrService = OcrAndImageService();
      final content = await ocrService.captureAndProcessPages(
        isRtlSubject: _isRtlSubject,
        preCapturedFiles: pages,
      );

      if (content.isEmpty) {
        setState(() {
          _isGeneratingAi = false;
          _statusMessage = "No content extracted from pages.";
        });
        return;
      }

      setState(() {
        _statusMessage = "Generating Board standard questions with Gemini AI...";
      });

      final generatedBank = await SloGeminiService.generateChapterBank(
        publisher: _effectivePublisher,
        grade: _selectedGrade,
        subject: _selectedSubject,
        chapterNumber: _chapterNumber,
        chapterTitle: _chapterTitleCtrl.text.trim(),
        isRtlSubject: _isRtlSubject,
        bookContent: content,
      );

      setState(() {
        _statusMessage = "Saving to crowdsourced Firestore cache...";
      });

      await SloRepository.saveOrMergeChapterBank(generatedBank);
      final updatedDoc = await SloRepository.getChapterBank(generatedBank.docId);
      _startCooldown();

      if (mounted) {
        setState(() {
          _loadedBank = updatedDoc ?? generatedBank;
          _isCacheAvailable = true;
          _isGeneratingAi = false;
          _selectedSloCodes.clear();
          _selectedSloCodes.addAll((_loadedBank?.slos ?? []).map((s) => s.sloCode));
          _statusMessage = "✅ Successfully generated and cached ${_loadedBank?.questions.length ?? 0} questions!";
          _currentStep = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGeneratingAi = false;
          _statusMessage = "Generation error: $e";
        });
        _showToast("Error: $e");
      }
    }
  }

  Future<void> _scanFromGallery() async {
    if (_cooldownSecondsRemaining > 0) {
      _showToast("Please wait $_cooldownSecondsRemaining seconds before scanning again.");
      return;
    }

    setState(() {
      _isGeneratingAi = true;
      _statusMessage = "Picking pages from gallery...";
    });

    try {
      final ocrService = OcrAndImageService();
      final content = await ocrService.captureAndProcessPages(
        isRtlSubject: _isRtlSubject,
        source: ImageSource.gallery,
      );

      if (content.isEmpty) {
        setState(() {
          _isGeneratingAi = false;
          _statusMessage = "No image selected.";
        });
        return;
      }

      setState(() {
        _statusMessage = "Generating Board standard questions with Gemini AI...";
      });

      final generatedBank = await SloGeminiService.generateChapterBank(
        publisher: _effectivePublisher,
        grade: _selectedGrade,
        subject: _selectedSubject,
        chapterNumber: _chapterNumber,
        chapterTitle: _chapterTitleCtrl.text.trim(),
        isRtlSubject: _isRtlSubject,
        bookContent: content,
      );

      setState(() {
        _statusMessage = "Saving to crowdsourced Firestore cache...";
      });

      await SloRepository.saveOrMergeChapterBank(generatedBank);
      final updatedDoc = await SloRepository.getChapterBank(generatedBank.docId);
      _startCooldown();

      if (mounted) {
        setState(() {
          _loadedBank = updatedDoc ?? generatedBank;
          _isCacheAvailable = true;
          _isGeneratingAi = false;
          _selectedSloCodes.clear();
          _selectedSloCodes.addAll((_loadedBank?.slos ?? []).map((s) => s.sloCode));
          _statusMessage = "✅ Successfully generated and cached ${_loadedBank?.questions.length ?? 0} questions!";
          _currentStep = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGeneratingAi = false;
          _statusMessage = "Generation error: $e";
        });
        _showToast("Error: $e");
      }
    }
  }

  void _buildPaperQuestions() {
    if (_loadedBank == null || _loadedBank!.questions.isEmpty) {
      _showToast("No questions available in the bank.");
      return;
    }

    final selected = SloRepository.buildCustomPaperFromBank(
      bank: _loadedBank!,
      selectedSloCodes: _selectedSloCodes,
      mcqCount: _mcqCount,
      shortCount: _shortCount,
      longCount: _longCount,
    );

    setState(() {
      _activePaperQuestions = selected;
      _currentStep = 2; // Move to preview
    });
  }

  void _swapSingleQuestion(SloQuestion q) {
    if (_loadedBank == null) return;
    final replacement = SloRepository.swapQuestion(
      currentQuestion: q,
      bank: _loadedBank!,
      currentlySelected: _activePaperQuestions,
      selectedSloCodes: _selectedSloCodes,
    );

    if (replacement != null) {
      final index = _activePaperQuestions.indexWhere((item) => item.id == q.id);
      if (index != -1) {
        setState(() {
          _activePaperQuestions[index] = replacement;
        });
        _showToast("Question swapped with another from cache!");
      }
    } else {
      _showToast("No more unused questions found for this category in cache.");
    }
  }

  void _editSingleQuestion(SloQuestion q) {
    final textCtrl = TextEditingController(text: q.questionText);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: const Text("Edit Question", style: TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: "Question Text",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final newText = textCtrl.text.trim();
              if (newText.isNotEmpty) {
                final index = _activePaperQuestions.indexWhere((item) => item.id == q.id);
                if (index != -1) {
                  setState(() {
                    _activePaperQuestions[index] = q.copyWith(questionText: newText);
                  });
                }
              }
              Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _syncSchoolData(Map<String, dynamic>? data) {
    if (data == null || _hasSyncedSchoolData) return;
    final name = (data['name'] ?? data['schoolName'] ?? '').toString();
    final campus = (data['campus'] ?? data['address'] ?? '').toString();
    final board = (data['board'] ?? '').toString();
    final logoUrl = (data['logo'] ?? data['profileImage'] ?? '').toString();

    if (name.isNotEmpty) {
      _schoolNameCtrl.text = name;
    }
    if (campus.isNotEmpty) {
      _campusCtrl.text = campus;
    }
    if (board.isNotEmpty) {
      _boardCtrl.text = board;
    }
    if (_schoolLogoBytes == null && logoUrl.isNotEmpty) {
      _fetchLogoFromUrl(logoUrl);
    }
    _hasSyncedSchoolData = true;
  }

  Future<void> _fetchLogoFromUrl(String url) async {
    if (_schoolLogoBytes != null || url.isEmpty) return;
    try {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200 && mounted) {
          setState(() {
            _schoolLogoBytes = res.bodyBytes;
            _pdfPreviewKey = UniqueKey();
          });
        }
      }
    } catch (_) {}
  }


  Future<Uint8List?> _getSchoolLogoBytes() async {
    if (_schoolLogoBytes != null) return _schoolLogoBytes;
    try {
      final schoolData = ref.read(schoolDataProvider).value;
      final logoUrl = schoolData?['logo'] as String?;
      if (logoUrl != null && (logoUrl.startsWith('http://') || logoUrl.startsWith('https://'))) {
        final res = await http.get(Uri.parse(logoUrl)).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          _schoolLogoBytes = res.bodyBytes;
          return _schoolLogoBytes;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List> _generatePdfBytes({required bool isAnswerKey}) async {
    final schoolData = ref.read(schoolDataProvider).value;
    final schoolName = _schoolNameCtrl.text.trim().isNotEmpty
        ? _schoolNameCtrl.text.trim()
        : (schoolData?['name'] ?? "Smart Public School");
    final campus = _campusCtrl.text.trim().isNotEmpty
        ? _campusCtrl.text.trim()
        : (schoolData?['campus'] ?? schoolData?['address'] ?? "Main Campus");
    final board = _boardCtrl.text.trim().isNotEmpty
        ? _boardCtrl.text.trim()
        : "Affiliated with Board of Intermediate & Secondary Education";

    final blueprint = PaperBlueprintConfig(
      schoolName: schoolName,
      campusOrAddress: campus,
      boardAffiliation: board,
      examTitle: _examTitleCtrl.text.trim().isNotEmpty ? _examTitleCtrl.text.trim() : "First Term Examination 2026",
      timeAllowed: _timeAllowedCtrl.text.trim().isNotEmpty ? _timeAllowedCtrl.text.trim() : "2 Hours",
      totalMarks: _totalMarks,
      mcqCount: _mcqCount,
      shortCount: _shortCount,
      longCount: _longCount,
    );

    final logoBytes = _schoolLogoBytes ?? await _getSchoolLogoBytes();

    if (isAnswerKey) {
      return await SloPdfGenerator.generateAnswerKeyPdf(
        blueprint: blueprint,
        chapterBank: _loadedBank!,
        questions: _activePaperQuestions,
        schoolLogoBytes: logoBytes,
      );
    } else {
      return await SloPdfGenerator.generateQuestionPaperPdf(
        blueprint: blueprint,
        chapterBank: _loadedBank!,
        questions: _activePaperQuestions,
        schoolLogoBytes: logoBytes,
      );
    }
  }

  Future<void> _exportPdf({required bool isAnswerKey}) async {
    if (_loadedBank == null || _activePaperQuestions.isEmpty) {
      _showToast("No questions to generate PDF.");
      return;
    }

    setState(() => _isGeneratingPdf = true);

    try {
      final Uint8List pdfBytes = await _generatePdfBytes(isAnswerKey: isAnswerKey);

      final docName = isAnswerKey
          ? "${_selectedSubject}_Class${_selectedGrade}_AnswerKey.pdf"
          : "${_selectedSubject}_Class${_selectedGrade}_QuestionPaper.pdf";

      await SloPdfGenerator.printOrSharePdf(pdfBytes: pdfBytes, docName: docName);
    } catch (e) {
      _showToast("Error generating PDF: $e");
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<void> _sendToPrincipal() async {
    if (_loadedBank == null || _activePaperQuestions.isEmpty) {
      _showToast("No questions to send. Please generate paper first.");
      return;
    }

    // Confirmation dialog before submitting
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.send_rounded, color: Color(0xFF4F46E5), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "Send to Principal?",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Both the Question Paper and confidential Teacher Answer Key will be automatically submitted together to the Principal's Exam Papers Hub for review and printing.",
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "• Paper: ${_examTitleCtrl.text.trim().isNotEmpty ? _examTitleCtrl.text.trim() : 'First Term Exam'}",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    "• Subject: Class $_selectedGrade - $_selectedSubject",
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    "• Questions: ${_activePaperQuestions.length} | Marks: $_totalMarks",
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "• Auto-Sync: Question Paper + Teacher Answer Key (All-in-One)",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text("Submit to Hub", style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSendingToPrincipal = true);

    try {
      final teacherData = ref.read(teacherDataProvider).value;
      final schoolData = ref.read(schoolDataProvider).value;

      // Safe School ID resolution & normalization
      String? rawSchoolId = teacherData?['schoolId'] ?? schoolData?['id'];
      String schoolId = 'SCHOOL_6257';
      if (rawSchoolId != null && rawSchoolId.toString().trim().isNotEmpty) {
        final trimmed = rawSchoolId.toString().trim().toUpperCase();
        if (RegExp(r'^\d+$').hasMatch(trimmed)) {
          schoolId = 'SCHOOL_$trimmed';
        } else {
          schoolId = trimmed;
        }
      }

      final teacherName = (teacherData?['fullName'] ?? teacherData?['name'] ?? teacherData?['displayName'] ?? "Subject Teacher").toString();
      final teacherUid = (teacherData?['uid'] ?? ref.read(currentUserProvider)?.uid ?? "").toString();

      // 1. Generate Both Exact Vector Question Paper PDF & Answer Key PDF Together
      final Uint8List pdfBytes = await _generatePdfBytes(isAnswerKey: false);
      Uint8List? answerPdfBytes;
      try {
        answerPdfBytes = await _generatePdfBytes(isAnswerKey: true);
      } catch (e) {
        debugPrint("Answer key PDF generation error: $e");
      }

      // Reuse existing paper document ID if re-sending or create new
      final paperDocRef = _submittedPaperId != null
          ? FirebaseFirestore.instance.collection('schools').doc(schoolId).collection('exam_papers').doc(_submittedPaperId)
          : FirebaseFirestore.instance.collection('schools').doc(schoolId).collection('exam_papers').doc();

      // 2. Upload both PDFs to Firebase Storage defensively
      String? downloadUrl;
      String? answerDownloadUrl;
      try {
        final storagePath = 'schools/$schoolId/exam_papers/${paperDocRef.id}.pdf';
        final storageRef = FirebaseStorage.instance.ref().child(storagePath);
        final uploadTask = await storageRef.putData(
          pdfBytes,
          SettableMetadata(contentType: 'application/pdf'),
        );
        downloadUrl = await uploadTask.ref.getDownloadURL();

        if (answerPdfBytes != null) {
          final ansPath = 'schools/$schoolId/exam_papers/${paperDocRef.id}_answers.pdf';
          final ansRef = FirebaseStorage.instance.ref().child(ansPath);
          final ansTask = await ansRef.putData(
            answerPdfBytes,
            SettableMetadata(contentType: 'application/pdf'),
          );
          answerDownloadUrl = await ansTask.ref.getDownloadURL();
        }
      } catch (storageError) {
        debugPrint("Warning: Firebase Storage upload failed: $storageError. Continuing with document payload.");
      }

      // 3. Serialize questions list for Canva rendering
      final questionsPayload = _activePaperQuestions.map((q) {
        int marks = 1;
        if (q.type == 'SHORT') marks = 3;
        if (q.type == 'LONG') marks = 6;
        return <String, dynamic>{
          'id': q.id,
          'type': q.type,
          'questionText': q.questionText,
          'options': q.options,
          'correctAnswer': q.correctAnswer,
          'rubric': q.rubric,
          'cognitiveLevel': q.cognitiveLevel,
          'sloCode': q.sloCode,
          'marks': marks,
        };
      }).toList();

      final schoolName = _schoolNameCtrl.text.trim().isNotEmpty
          ? _schoolNameCtrl.text.trim()
          : (schoolData?['name'] ?? "Smart Public School");
      final campus = _campusCtrl.text.trim().isNotEmpty
          ? _campusCtrl.text.trim()
          : (schoolData?['campus'] ?? schoolData?['address'] ?? "Main Campus");
      final board = _boardCtrl.text.trim().isNotEmpty
          ? _boardCtrl.text.trim()
          : (schoolData?['board'] ?? "BISE");

      final paperPayload = <String, dynamic>{
        'examTitle': _examTitleCtrl.text.trim().isNotEmpty ? _examTitleCtrl.text.trim() : "First Term Examination 2026",
        'grade': _selectedGrade,
        'subject': _selectedSubject,
        'chapterNumber': _chapterNumber,
        'chapterTitle': _chapterTitleCtrl.text.trim(),
        'publisher': _effectivePublisher,
        'teacherName': teacherName,
        'teacherUid': teacherUid,
        'totalMarks': _totalMarks,
        'timeAllowed': _timeAllowedCtrl.text.trim().isNotEmpty ? _timeAllowedCtrl.text.trim() : "2 Hours",
        'mcqCount': _mcqCount,
        'shortCount': _shortCount,
        'longCount': _longCount,
        'status': 'pending', // 'pending' | 'approved' | 'printed' | 'needs_revision'
        'submittedAt': FieldValue.serverTimestamp(),
        'pdfUrl': downloadUrl,
        'answerPdfUrl': answerDownloadUrl,
        'schoolBranding': <String, dynamic>{
          'name': schoolName,
          'campus': campus,
          'board': board,
          'logoUrl': schoolData?['logo'] ?? schoolData?['logoUrl'],
        },
        'questions': questionsPayload,
      };

      await paperDocRef.set(paperPayload);

      if (mounted) {
        setState(() {
          _submittedPaperId = paperDocRef.id;
        });
      }

      if (!mounted) return;

      // Show Success Dialog
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 38),
              ),
              const SizedBox(height: 16),
              const Text(
                "Paper Sent to Principal!",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "Both the Question Paper and Answer Sheet have been submitted together to the Exam Papers Hub. Principal can now preview, review, and print both.",
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, size: 14, color: Colors.amber.shade900),
                    const SizedBox(width: 5),
                    Text(
                      "Status: Pending Review",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(double.infinity, 44),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Done", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint("Error sending paper to principal: $e");
      _showToast("Failed to submit paper: $e");
    } finally {
      if (mounted) setState(() => _isSendingToPrincipal = false);
    }
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final schoolAsync = ref.watch(schoolDataProvider);
    _syncSchoolData(schoolAsync.value);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              bottom: 16,
              left: 16,
              right: 16,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "AI Paper Generator",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        "Pakistani Board standard SLO question papers",
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Stepper Header Indicators (Hidden during Canva A4 Preview to give full screen to paper)
          if (!(_currentStep == 2 && _step3ViewMode == 1))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              child: Row(
                children: [
                  _buildStepPill(0, "Chapter", Icons.book_outlined),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  _buildStepPill(1, "Blueprint", Icons.tune_rounded),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  _buildStepPill(2, "Preview & Send", Icons.send_rounded),
                ],
              ),
            ),

          // Step Content
          Expanded(
            child: _currentStep == 0
                ? _buildStep1Chapter()
                : _currentStep == 1
                    ? _buildStep2Blueprint()
                    : _buildStep3Preview(),
          ),
        ],
      ),
    );
  }

  Widget _buildStepPill(int step, String label, IconData icon) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (step < _currentStep || (step == 1 && _loadedBank != null)) {
            setState(() => _currentStep = step);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF4F46E5)
                : isCompleted
                    ? const Color(0xFF10B981).withOpacity(0.15)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF4F46E5)
                  : isCompleted
                      ? const Color(0xFF10B981)
                      : Colors.grey.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isCompleted ? Icons.check_circle : icon,
                size: 14,
                color: isActive
                    ? Colors.white
                    : isCompleted
                        ? const Color(0xFF10B981)
                        : Colors.grey,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isActive
                        ? Colors.white
                        : isCompleted
                            ? const Color(0xFF10B981)
                            : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================= STEP 1: SELECT CHAPTER =================
  Widget _buildStep1Chapter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Quick Demo Test Bar (English & Urdu)
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5).withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: Color(0xFF4F46E5), size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Quick Test Demo Chapters (Zero Scan):",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.science_outlined, size: 14),
                      label: const Text("9th Biology (Eng)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        setState(() {
                          _selectedPublisher = "KPK Textbook Board (KP-TB)";
                          _selectedGrade = "9";
                          _selectedSubject = "Biology";
                          _chapterNumber = 1;
                          _chapterTitleCtrl.text = "Introduction to Biology";
                          _isRtlSubject = false;
                          _isCustomPublisher = false;
                        });
                        _checkFirestoreCache();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.menu_book_outlined, size: 14),
                      label: const Text("7th Urdu (حمد)", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        setState(() {
                          _selectedPublisher = "Afaq (Sun / Iqbal Series)";
                          _selectedGrade = "7";
                          _selectedSubject = "Urdu";
                          _chapterNumber = 1;
                          _chapterTitleCtrl.text = "حمدِ باری تعالیٰ";
                          _isRtlSubject = true;
                          _isCustomPublisher = false;
                        });
                        _checkFirestoreCache();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Dropdown rows
        Card(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Curriculum & Textbook Details",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),

                // Publisher / Board (Full Width)
                DropdownButtonFormField<String>(
                  value: _publishers.contains(_selectedPublisher) ? _selectedPublisher : _publishers.first,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Board / Publisher",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: _publishers
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedPublisher = val;
                        _isCustomPublisher = val == "Other / Custom Publisher...";
                      });
                      _checkFirestoreCache();
                    }
                  },
                ),
                if (_isCustomPublisher) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _customPublisherCtrl,
                    decoration: const InputDecoration(
                      labelText: "Publisher / Book Company Name",
                      hintText: "e.g., Cantab, Gaba, Al-Huda, Moon Light",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onChanged: (_) => _checkFirestoreCache(),
                  ),
                ],
                const SizedBox(height: 12),

                // Class (Grade) & Chapter Number in 50-50 Row
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _grades.contains(_selectedGrade) ? _selectedGrade : _grades.first,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Class / Grade",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        items: _grades
                            .map((g) => DropdownMenuItem(
                                  value: g,
                                  child: Text("Class $g", overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedGrade = val);
                            _checkFirestoreCache();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _chapterNumber,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Chapter #",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        items: List.generate(20, (i) => i + 1)
                            .map((num) => DropdownMenuItem(
                                  value: num,
                                  child: Text("Chapter $num", overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _chapterNumber = val);
                            _checkFirestoreCache();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Subject (Full Width for Long Names like Pakistan Studies, Computer Science)
                DropdownButtonFormField<String>(
                  value: _subjects.contains(_selectedSubject) ? _selectedSubject : _subjects.first,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: "Subject",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  items: _subjects
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedSubject = val;
                        _isRtlSubject = val == "Urdu" || val == "Islamiyat";
                      });
                      _checkFirestoreCache();
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Chapter Title (Full Width)
                TextField(
                  controller: _chapterTitleCtrl,
                  decoration: const InputDecoration(
                    labelText: "Chapter Title",
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 10),

                // RTL Checkbox
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Urdu / Arabic / RTL Subject", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text("Will use high-resolution vision OCR", style: TextStyle(fontSize: 11)),
                  value: _isRtlSubject,
                  onChanged: (val) => setState(() => _isRtlSubject = val ?? false),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Cache Status Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _isCacheAvailable
                ? const Color(0xFF10B981).withOpacity(0.12)
                : const Color(0xFFF59E0B).withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isCacheAvailable ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isCheckingCache
                    ? Icons.hourglass_top_rounded
                    : _isCacheAvailable
                        ? Icons.bolt_rounded
                        : Icons.info_outline,
                color: _isCacheAvailable ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _statusMessage.isNotEmpty ? _statusMessage : "Checking question bank...",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _isCacheAvailable ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Action Buttons
        if (_isCacheAvailable) ...[
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text("Proceed with Cached Bank (0 Cost)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            onPressed: () {
              setState(() => _currentStep = 1);
            },
          ),
          const SizedBox(height: 12),
        ],

        // Scan Book Pages Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: _isGeneratingAi
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.camera_alt_rounded),
          label: Text(
            _isGeneratingAi
                ? "Processing with Gemini AI..."
                : _cooldownSecondsRemaining > 0
                    ? "Cooldown: ${_cooldownSecondsRemaining}s"
                    : _isCacheAvailable
                        ? "📸 Scan More Pages to Enrich Cache"
                        : "📸 Scan Textbook Pages via Camera",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: (_isGeneratingAi || _cooldownSecondsRemaining > 0)
              ? null
              : _startMultiPageCameraCapture,
        ),

        const SizedBox(height: 8),

        // Pick from gallery alternative
        TextButton.icon(
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: const Text("Or pick multiple pages from Phone Gallery"),
          onPressed: (_isGeneratingAi || _cooldownSecondsRemaining > 0)
              ? null
              : _scanFromGallery,
        ),
      ],
    );
  }

  // ================= STEP 2: BLUEPRINT & SLO SELECTION =================
  Widget _buildStep2Blueprint() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slos = _loadedBank?.slos ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // School Branding & Exam Details Card
        Card(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // View-Only Official School Header Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      // View-Only Logo
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF4F46E5).withOpacity(0.1),
                          border: Border.all(
                            color: const Color(0xFF4F46E5).withOpacity(0.25),
                            width: 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child: _schoolLogoBytes != null
                              ? Image.memory(_schoolLogoBytes!, fit: BoxFit.cover)
                              : const Icon(Icons.school_rounded, size: 24, color: Color(0xFF4F46E5)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // School Name & Campus Subtitle (View-Only)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _schoolNameCtrl.text.trim().isNotEmpty
                                        ? _schoolNameCtrl.text.trim().toUpperCase()
                                        : "SMART PUBLIC SCHOOL",
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF10B981)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _campusCtrl.text.trim().isNotEmpty
                                  ? _campusCtrl.text.trim().toUpperCase()
                                  : "MAIN CAMPUS • VERIFIED SCHOOL PROFILE",
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Board Affiliation
                TextField(
                  controller: _boardCtrl,
                  decoration: const InputDecoration(
                    labelText: "Board Affiliation",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.verified_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 10),

                // Exam Title
                TextField(
                  controller: _examTitleCtrl,
                  decoration: const InputDecoration(
                    labelText: "Exam Title",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.assignment_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 10),

                // Time Allowed & Total Marks
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _timeAllowedCtrl,
                        decoration: const InputDecoration(
                          labelText: "Time Allowed",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.timer_outlined, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        initialValue: _totalMarks.toString(),
                        decoration: const InputDecoration(
                          labelText: "Total Marks",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.grade_outlined, size: 20),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (val) {
                          _totalMarks = int.tryParse(val) ?? 50;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Question Counts Setup
        Card(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Question Counts & Bloom's Ratios", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  "Bloom's Mix: 30% Knowledge • 50% Understanding • 20% Application",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 14),

                _buildCounterRow(
                  label: "Section A: MCQs",
                  marksPerQ: "1 Mark each",
                  count: _mcqCount,
                  onChanged: (val) => setState(() => _mcqCount = val),
                ),
                const Divider(),
                _buildCounterRow(
                  label: "Section B: Short Questions",
                  marksPerQ: "3 Marks each",
                  count: _shortCount,
                  onChanged: (val) => setState(() => _shortCount = val),
                ),
                const Divider(),
                _buildCounterRow(
                  label: "Section C: Long Questions",
                  marksPerQ: "6 Marks each",
                  count: _longCount,
                  onChanged: (val) => setState(() => _longCount = val),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // SLO Selection Checkboxes
        Card(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Select SLOs (${_selectedSloCodes.length}/${slos.length})", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (_selectedSloCodes.length == slos.length) {
                            _selectedSloCodes.clear();
                          } else {
                            _selectedSloCodes.addAll(slos.map((s) => s.sloCode));
                          }
                        });
                      },
                      child: Text(_selectedSloCodes.length == slos.length ? "Deselect All" : "Select All"),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (slos.isEmpty)
                  const Text("No specific SLO tags found. Paper will be generated from all questions.", style: TextStyle(fontSize: 12, color: Colors.grey))
                else
                  ...slos.map((slo) {
                    final isChecked = _selectedSloCodes.contains(slo.sloCode);
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: isChecked,
                      title: Text("${slo.sloCode}: ${slo.statement}", style: const TextStyle(fontSize: 12.5)),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedSloCodes.add(slo.sloCode);
                          } else {
                            _selectedSloCodes.remove(slo.sloCode);
                          }
                        });
                      },
                    );
                  }),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F46E5),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _buildPaperQuestions,
          child: const Text("Generate Paper Blueprint & Preview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ],
    );
  }

  Widget _buildCounterRow({
    required String label,
    required String marksPerQ,
    required int count,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            Text(marksPerQ, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.grey),
              onPressed: count > 0 ? () => onChanged(count - 1) : null,
            ),
            Text("$count", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Color(0xFF4F46E5)),
              onPressed: () => onChanged(count + 1),
            ),
          ],
        ),
      ],
    );
  }

  // ================= STEP 3: LIVE PREVIEW, SWAP & PRINT =================
  Widget _buildStep3Preview() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final mcqs = _activePaperQuestions.where((q) => q.type == 'MCQ').toList();
    final shorts = _activePaperQuestions.where((q) => q.type == 'SHORT').toList();
    final longs = _activePaperQuestions.where((q) => q.type == 'LONG').toList();

    return Column(
      children: [
        // Mode Switcher Bar: "Review & Swap" vs "Canva A4 Preview" (Hidden during Canva A4 Preview to maximize canvas space)
        if (_step3ViewMode == 0)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _step3ViewMode = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _step3ViewMode == 0 ? const Color(0xFF4F46E5) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _step3ViewMode == 0
                          ? [BoxShadow(color: const Color(0xFF4F46E5).withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.edit_note_rounded, size: 18, color: _step3ViewMode == 0 ? Colors.white : Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          "Edit & Swap (${_activePaperQuestions.length})",
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: _step3ViewMode == 0 ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _step3ViewMode = 1;
                    _pdfPreviewKey = UniqueKey();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: _step3ViewMode == 1 ? const Color(0xFF4F46E5) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _step3ViewMode == 1
                          ? [BoxShadow(color: const Color(0xFF4F46E5).withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_stories_rounded, size: 18, color: _step3ViewMode == 1 ? Colors.white : Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          "Canva A4 Preview",
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: _step3ViewMode == 1 ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Content Area based on Selected Mode
        if (_step3ViewMode == 0) ...[
          // MODE 0: Questions List with Swap & Edit
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // Summary Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text("Total: ${_activePaperQuestions.length} Qs", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      Text("MCQs: ${mcqs.length}", style: const TextStyle(fontSize: 12)),
                      Text("Short: ${shorts.length}", style: const TextStyle(fontSize: 12)),
                      Text("Long: ${longs.length}", style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Section A
                if (mcqs.isNotEmpty) ...[
                  _buildSectionTitle("SECTION 'A': MCQs (${mcqs.length} Marks)"),
                  ...mcqs.asMap().entries.map((entry) {
                    return _buildQuestionCard(entry.key + 1, entry.value);
                  }),
                  const SizedBox(height: 12),
                ],

                // Section B
                if (shorts.isNotEmpty) ...[
                  _buildSectionTitle("SECTION 'B': Short Questions (${shorts.length * 3} Marks)"),
                  ...shorts.asMap().entries.map((entry) {
                    return _buildQuestionCard(entry.key + 1, entry.value);
                  }),
                  const SizedBox(height: 12),
                ],

                // Section C
                if (longs.isNotEmpty) ...[
                  _buildSectionTitle("SECTION 'C': Long Questions (${longs.length * 6} Marks)"),
                  ...longs.asMap().entries.map((entry) {
                    return _buildQuestionCard(entry.key + 1, entry.value);
                  }),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),

          // Bottom Bar for Mode 0
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                )
              ],
            ),
            child: Row(
              children: [
                // Button to open Canva Preview
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.preview_rounded, size: 20),
                    label: const Text("View Canva A4 Preview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () => setState(() {
                      _step3ViewMode = 1;
                      _pdfPreviewKey = UniqueKey();
                    }),
                  ),
                ),
                const SizedBox(width: 8),

                // Send to Principal
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _submittedPaperId != null ? Colors.teal.shade700 : const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 1,
                    ),
                    icon: _isSendingToPrincipal
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(
                            _submittedPaperId != null ? Icons.check_circle_rounded : Icons.send_rounded,
                            size: 18,
                          ),
                    label: Text(
                      _isSendingToPrincipal
                          ? "Sending..."
                          : (_submittedPaperId != null ? "Re-send to Hub" : "Send to Principal"),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: (_isGeneratingPdf || _isSendingToPrincipal) ? null : _sendToPrincipal,
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // MODE 1: Interactive Canva A4 WYSIWYG Preview
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Toggle Question Paper vs Answer Key
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() {
                              _previewIsAnswerKey = false;
                              _pdfPreviewKey = UniqueKey();
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: !_previewIsAnswerKey ? const Color(0xFF4F46E5) : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "Paper",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: !_previewIsAnswerKey ? Colors.white : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() {
                              _previewIsAnswerKey = true;
                              _pdfPreviewKey = UniqueKey();
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: _previewIsAnswerKey ? const Color(0xFF10B981) : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "Answer Key",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _previewIsAnswerKey ? Colors.white : Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Actions: Send to Principal, Refresh & Edit Questions
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _submittedPaperId != null ? Colors.teal.shade700 : const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: _isSendingToPrincipal
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                                )
                              : Icon(
                                  _submittedPaperId != null ? Icons.check_circle_rounded : Icons.send_rounded,
                                  size: 13,
                                ),
                          label: Text(
                            _isSendingToPrincipal
                                ? "Sending..."
                                : (_submittedPaperId != null ? "Re-send" : "Send to Principal"),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          onPressed: _isSendingToPrincipal ? null : _sendToPrincipal,
                        ),
                        const SizedBox(width: 3),
                        IconButton(
                          tooltip: "Refresh Canvas",
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(5),
                          icon: const Icon(Icons.refresh_rounded, size: 19),
                          onPressed: () {
                            _resetZoom();
                            setState(() {
                              _pdfPreviewKey = UniqueKey();
                            });
                          },
                        ),
                        const SizedBox(width: 3),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          ),
                          icon: const Icon(Icons.arrow_back, size: 14),
                          label: const Text("Edit Questions", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => setState(() => _step3ViewMode = 0),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Interactive PdfPreview Canvas with Pinch, Zoom, Pan & Page Navigation
          Expanded(
            child: PdfPreview.builder(
              key: _pdfPreviewKey,
              build: (format) => _generatePdfBytes(isAnswerKey: _previewIsAnswerKey),
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              dynamicLayout: false,
              useActions: false, // Hides redundant purple bottom bar to reclaim 60px of screen space!
              dpi: 160,
              maxPageWidth: 650,
              pdfFileName: _previewIsAnswerKey
                  ? "${_selectedSubject}_Class${_selectedGrade}_AnswerKey.pdf"
                  : "${_selectedSubject}_Class${_selectedGrade}_QuestionPaper.pdf",
              loadingWidget: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2.5),
                    SizedBox(height: 12),
                    Text("Rendering Canva A4 Preview...", style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                  ],
                ),
              ),
              pagesBuilder: (context, pages) => _buildGalleryInteractiveCanvas(context, pages),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGalleryInteractiveCanvas(BuildContext context, List<PdfPreviewPageData> pages) {
    if (pages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 12),
            Text("Rendering pages...", style: TextStyle(fontSize: 12.5, color: Colors.grey)),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        return Stack(
          children: [
            // 1. Canvas Content
            Container(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
              width: availableWidth,
              height: availableHeight,
              child: _previewContinuousScroll
                  // Continuous Vertical Scroll Mode (All Pages stacked with smooth scrolling)
                  ? GestureDetector(
                      onDoubleTap: _handleDoubleTap,
                      child: InteractiveViewer(
                        transformationController: _zoomController,
                        minScale: 0.5,
                        maxScale: 4.5,
                        panEnabled: true,
                        scaleEnabled: true,
                        boundaryMargin: const EdgeInsets.symmetric(horizontal: 100, vertical: 200),
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(top: 16, bottom: 100, left: 16, right: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (int i = 0; i < pages.length; i++) ...[
                                Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "Page ${i + 1} of ${pages.length}",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  constraints: BoxConstraints(
                                    maxWidth: (availableWidth - 24).clamp(280.0, 620.0),
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.25),
                                        blurRadius: 16,
                                        spreadRadius: 2,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Image(
                                    image: pages[i].image,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                                if (i < pages.length - 1) const SizedBox(height: 24),
                              ],
                            ],
                          ),
                        ),
                      ),
                    )
                  // Default Gallery Mode (Page by Page with 100% Full-Size Fit & Zero Cutoff)
                  : PageView.builder(
                      controller: _pagePreviewController,
                      itemCount: pages.length,
                      onPageChanged: (idx) {
                        setState(() {
                          _currentPreviewPageIndex = idx;
                          _resetZoom();
                        });
                      },
                      itemBuilder: (context, idx) {
                        final page = pages[idx];

                        return GestureDetector(
                          onDoubleTap: _handleDoubleTap,
                          child: InteractiveViewer(
                            transformationController: _zoomController,
                            minScale: 0.8,
                            maxScale: 4.5,
                            panEnabled: true,
                            scaleEnabled: true,
                            boundaryMargin: const EdgeInsets.symmetric(horizontal: 100, vertical: 150),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 75), // Leaves space for bottom floating pill
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.28),
                                        blurRadius: 18,
                                        spreadRadius: 2,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Image(
                                    image: page.image,
                                    fit: BoxFit.contain, // 100% full paper fits from header to footer, ZERO CUTOFF!
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // 2. Floating Zoom & Page Flip Controls Pill at the Bottom Center
            Positioned(
              bottom: 14,
              left: 10,
              right: 10,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.black87,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Zoom Out Button
                        IconButton(
                          icon: const Icon(Icons.zoom_out, color: Colors.white, size: 17),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(5),
                          tooltip: "Zoom Out",
                          onPressed: _zoomOut,
                        ),
                        const SizedBox(width: 2),
                        // Current Zoom percentage badge (tap to reset 100%)
                        GestureDetector(
                          onTap: _resetZoom,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ValueListenableBuilder<double>(
                              valueListenable: _zoomLevelNotifier,
                              builder: (context, scale, _) => Text(
                                "${(scale * 100).toInt()}%",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        // Zoom In Button
                        IconButton(
                          icon: const Icon(Icons.zoom_in, color: Colors.white, size: 17),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(5),
                          tooltip: "Zoom In",
                          onPressed: _zoomIn,
                        ),
                        const SizedBox(width: 3),
                        Container(width: 1, height: 14, color: Colors.white24),
                        const SizedBox(width: 3),
                        // Fit to Screen button
                        IconButton(
                          icon: const Icon(Icons.fit_screen_rounded, color: Colors.white, size: 16),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(5),
                          tooltip: "Fit Screen (Reset)",
                          onPressed: _resetZoom,
                        ),

                        // Multi-page navigation (when more than 1 page exists)
                        if (pages.length > 1) ...[
                          const SizedBox(width: 3),
                          Container(width: 1, height: 14, color: Colors.white24),
                          const SizedBox(width: 3),
                          // Previous page
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 18),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(3),
                            tooltip: "Previous Page",
                            onPressed: _currentPreviewPageIndex > 0
                                ? () {
                                    _pagePreviewController.previousPage(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              "${_currentPreviewPageIndex + 1}/${pages.length}",
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          // Next page
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(3),
                            tooltip: "Next Page",
                            onPressed: _currentPreviewPageIndex < pages.length - 1
                                ? () {
                                    _pagePreviewController.nextPage(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                          ),
                          const SizedBox(width: 3),
                          Container(width: 1, height: 14, color: Colors.white24),
                          const SizedBox(width: 3),
                          // Toggle between Page-by-Page and Continuous Scroll
                          IconButton(
                            icon: Icon(
                              _previewContinuousScroll ? Icons.view_carousel_rounded : Icons.view_agenda_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(5),
                            tooltip: _previewContinuousScroll ? "Switch to Page-by-Page" : "Switch to Continuous Scroll",
                            onPressed: () {
                              setState(() {
                                _previewContinuousScroll = !_previewContinuousScroll;
                                _resetZoom();
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
      ),
    );
  }

  Widget _buildQuestionCard(int index, SloQuestion q) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Q$index. ", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                Expanded(
                  child: Text(
                    q.questionText,
                    style: const TextStyle(fontSize: 13.5, height: 1.3),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    q.cognitiveLevel,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                  ),
                ),
              ],
            ),

            if (q.options.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: q.options.map((opt) {
                  final isCorrect = opt.contains(q.correctAnswer) || q.correctAnswer.contains(opt);
                  return Text(
                    opt,
                    style: TextStyle(
                      fontSize: 12,
                      color: isCorrect ? const Color(0xFF10B981) : Colors.grey,
                      fontWeight: isCorrect ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Swap Button (1-Click Swap from Cache)
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text("Swap", style: TextStyle(fontSize: 12)),
                  onPressed: () => _swapSingleQuestion(q),
                ),
                // Edit Button
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text("Edit", style: TextStyle(fontSize: 12)),
                  onPressed: () => _editSingleQuestion(q),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
