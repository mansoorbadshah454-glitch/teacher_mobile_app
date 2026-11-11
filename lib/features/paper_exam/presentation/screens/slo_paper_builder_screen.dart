import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/features/paper_exam/config/slo_ai_config.dart';
import 'package:teacher_mobile_app/features/paper_exam/models/slo_paper_models.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/ocr_and_image_service.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/slo_gemini_service.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/slo_pdf_generator.dart';
import 'package:teacher_mobile_app/features/paper_exam/services/slo_repository.dart';

class _SloPaperDraftState {
  int currentStep = 0;
  String selectedPublisher = "KPK Textbook Board (KP-TB)";
  String selectedGrade = "9";
  String selectedSubject = "Biology";
  int chapterNumber = 1;
  Set<int> selectedChapters = {1};
  Map<int, ChapterBankDoc> cachedBanksByChapter = {};
  String chapterTitle = "";
  String customPublisher = "";
  bool isRtlSubject = false;
  bool isCustomPublisher = false;
  ChapterBankDoc? loadedBank;
  Set<String> selectedSloCodes = {};
  int mcqCount = 10;
  int shortCount = 8;
  int longCount = 3;
  int shortAttemptCount = 5;
  int longAttemptCount = 2;
  int mcqMarksEach = 1;
  int shortMarksEach = 3;
  int longMarksEach = 6;
  String schoolName = "Smart Public School";
  String campus = "Main Campus";
  String board = "Affiliated with Board of Intermediate & Secondary Education";
  String examTitle = "First Term Examination 2026";
  String timeAllowed = "2 Hours";
  int totalMarks = 37;
  List<SloQuestion> activePaperQuestions = [];
  String? submittedPaperId;
  int step3ViewMode = 0;
  bool previewIsAnswerKey = false;
  String? activePaperDocId;
  Map<int, List<SloQuestion>> slotHistory = {};
  Map<int, int> slotHistoryIndex = {};
  Uint8List? cachedPaperPdfBytes;
  Uint8List? cachedAnswerKeyPdfBytes;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'currentStep': currentStep,
      'selectedPublisher': selectedPublisher,
      'selectedGrade': selectedGrade,
      'selectedSubject': selectedSubject,
      'chapterNumber': chapterNumber,
      'selectedChapters': selectedChapters.toList(),
      'cachedBanksByChapter': {
        for (final e in cachedBanksByChapter.entries) e.key.toString(): e.value.toJson(),
      },
      'chapterTitle': chapterTitle,
      'customPublisher': customPublisher,
      'isRtlSubject': isRtlSubject,
      'isCustomPublisher': isCustomPublisher,
      'loadedBank': loadedBank?.toJson(),
      'selectedSloCodes': selectedSloCodes.toList(),
      'mcqCount': mcqCount,
      'shortCount': shortCount,
      'longCount': longCount,
      'shortAttemptCount': shortAttemptCount,
      'longAttemptCount': longAttemptCount,
      'mcqMarksEach': mcqMarksEach,
      'shortMarksEach': shortMarksEach,
      'longMarksEach': longMarksEach,
      'schoolName': schoolName,
      'campus': campus,
      'board': board,
      'examTitle': examTitle,
      'timeAllowed': timeAllowed,
      'totalMarks': totalMarks,
      'activePaperQuestions': activePaperQuestions.map((q) => q.toJson()).toList(),
      'submittedPaperId': submittedPaperId,
      'step3ViewMode': step3ViewMode,
      'previewIsAnswerKey': previewIsAnswerKey,
      'activePaperDocId': activePaperDocId,
      'slotHistory': {
        for (final e in slotHistory.entries)
          e.key.toString(): e.value.map((q) => q.toJson()).toList(),
      },
      'slotHistoryIndex': {
        for (final e in slotHistoryIndex.entries) e.key.toString(): e.value,
      },
    };
  }

  static _SloPaperDraftState? fromJson(Map<String, dynamic> json) {
    try {
      final d = _SloPaperDraftState();
      d.currentStep = (json['currentStep'] as num?)?.toInt() ?? 0;
      d.selectedPublisher = (json['selectedPublisher'] ?? d.selectedPublisher).toString();
      d.selectedGrade = (json['selectedGrade'] ?? d.selectedGrade).toString();
      d.selectedSubject = (json['selectedSubject'] ?? d.selectedSubject).toString();
      d.chapterNumber = (json['chapterNumber'] as num?)?.toInt() ?? 1;

      final rawChs = json['selectedChapters'];
      if (rawChs is List && rawChs.isNotEmpty) {
        d.selectedChapters = rawChs
            .map((e) => int.tryParse(e.toString()) ?? 1)
            .toSet();
      }

      final rawBanks = json['cachedBanksByChapter'];
      if (rawBanks is Map) {
        rawBanks.forEach((k, v) {
          final chKey = int.tryParse(k.toString());
          if (chKey != null && v is Map) {
            d.cachedBanksByChapter[chKey] = ChapterBankDoc.fromJson(Map<String, dynamic>.from(v));
          }
        });
      }

      d.chapterTitle = (json['chapterTitle'] ?? '').toString();
      d.customPublisher = (json['customPublisher'] ?? '').toString();
      d.isRtlSubject = json['isRtlSubject'] == true;
      d.isCustomPublisher = json['isCustomPublisher'] == true;

      if (json['loadedBank'] is Map) {
        d.loadedBank = ChapterBankDoc.fromJson(Map<String, dynamic>.from(json['loadedBank']));
      }

      final rawSlos = json['selectedSloCodes'];
      if (rawSlos is List) {
        d.selectedSloCodes = rawSlos.map((e) => e.toString()).toSet();
      }

      d.mcqCount = (json['mcqCount'] as num?)?.toInt() ?? 10;
      d.shortCount = (json['shortCount'] as num?)?.toInt() ?? 8;
      d.longCount = (json['longCount'] as num?)?.toInt() ?? 3;
      d.shortAttemptCount = (json['shortAttemptCount'] as num?)?.toInt() ?? 5;
      d.longAttemptCount = (json['longAttemptCount'] as num?)?.toInt() ?? 2;
      d.mcqMarksEach = (json['mcqMarksEach'] as num?)?.toInt() ?? 1;
      d.shortMarksEach = (json['shortMarksEach'] as num?)?.toInt() ?? 3;
      d.longMarksEach = (json['longMarksEach'] as num?)?.toInt() ?? 6;
      d.schoolName = (json['schoolName'] ?? d.schoolName).toString();
      d.campus = (json['campus'] ?? d.campus).toString();
      d.board = (json['board'] ?? d.board).toString();
      d.examTitle = (json['examTitle'] ?? d.examTitle).toString();
      d.timeAllowed = (json['timeAllowed'] ?? d.timeAllowed).toString();
      d.totalMarks = (json['totalMarks'] as num?)?.toInt() ?? 37;

      final rawQs = json['activePaperQuestions'];
      if (rawQs is List) {
        d.activePaperQuestions = rawQs
            .whereType<Map>()
            .map((e) => SloQuestion.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      d.submittedPaperId = json['submittedPaperId']?.toString();
      d.step3ViewMode = (json['step3ViewMode'] as num?)?.toInt() ?? 0;
      d.previewIsAnswerKey = json['previewIsAnswerKey'] == true;
      d.activePaperDocId = json['activePaperDocId']?.toString();

      final rawHist = json['slotHistory'];
      if (rawHist is Map) {
        rawHist.forEach((k, v) {
          final slotKey = int.tryParse(k.toString());
          if (slotKey != null && v is List) {
            d.slotHistory[slotKey] = v
                .whereType<Map>()
                .map((e) => SloQuestion.fromJson(Map<String, dynamic>.from(e)))
                .toList();
          }
        });
      }

      final rawHistIdx = json['slotHistoryIndex'];
      if (rawHistIdx is Map) {
        rawHistIdx.forEach((k, v) {
          final slotKey = int.tryParse(k.toString());
          final idxVal = int.tryParse(v.toString());
          if (slotKey != null && idxVal != null) {
            d.slotHistoryIndex[slotKey] = idxVal;
          }
        });
      }

      return d;
    } catch (_) {
      return null;
    }
  }
}

class SloPaperBuilderScreen extends ConsumerStatefulWidget {
  const SloPaperBuilderScreen({super.key});

  @override
  ConsumerState<SloPaperBuilderScreen> createState() => _SloPaperBuilderScreenState();
}

class _SloPaperBuilderScreenState extends ConsumerState<SloPaperBuilderScreen> {
  static _SloPaperDraftState? _savedDraft;
  static Uint8List? _cachedLogoBytesStatic;
  static const String _localDraftCacheKey = 'slo_paper_builder_draft_v2';
  static const String _localLogoCacheKey = 'slo_school_logo_b64_v1';
  static const String _localBrandingCacheKey = 'slo_school_branding_v1';
  Timer? _draftSaveDebounce;

  int _currentStep = 0; // 0 = Chapter, 1 = Blueprint, 2 = Live Preview

  // --- Step 1 Inputs ---
  String _selectedPublisher = "KPK Textbook Board (KP-TB)";
  String _selectedGrade = "9";
  String _selectedSubject = "Biology";
  int _chapterNumber = 1;
  final Set<int> _selectedChapters = {1};
  final Map<int, ChapterBankDoc> _cachedBanksByChapter = {};
  final TextEditingController _chapterTitleCtrl = TextEditingController();
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
  int _shortAttemptCount = 5; // Default Pakistani Board: Attempt 5 out of 8
  int _longAttemptCount = 2; // Default Pakistani Board: Attempt 2 out of 3
  int _mcqMarksEach = 1;
  int _shortMarksEach = 3;
  int _longMarksEach = 6;
  final TextEditingController _schoolNameCtrl = TextEditingController(text: "Smart Public School");
  final TextEditingController _campusCtrl = TextEditingController(text: "Main Campus");
  final TextEditingController _boardCtrl = TextEditingController(text: "Affiliated with Board of Intermediate & Secondary Education");
  final TextEditingController _examTitleCtrl = TextEditingController(text: "First Term Examination 2026");
  final TextEditingController _timeAllowedCtrl = TextEditingController(text: "2 Hours");
  final TextEditingController _totalMarksCtrl = TextEditingController(text: "37");
  int _totalMarks = 37; // MCQs (10*1) + Shorts (5*3=15) + Longs (2*6=12) = 37
  bool _hasSyncedSchoolData = false;

  int get _effectiveShortAttempt =>
      (_shortAttemptCount > 0 && _shortAttemptCount <= _shortCount) ? _shortAttemptCount : _shortCount;

  int get _effectiveLongAttempt =>
      (_longAttemptCount > 0 && _longAttemptCount <= _longCount) ? _longAttemptCount : _longCount;

  void _recalculateTotalMarks() {
    _totalMarks = (_mcqCount * _mcqMarksEach) +
        (_effectiveShortAttempt * _shortMarksEach) +
        (_effectiveLongAttempt * _longMarksEach);
    _totalMarksCtrl.text = _totalMarks.toString();
    _cachedPaperPdfBytes = null;
    _cachedAnswerKeyPdfBytes = null;
    _persistToDraft();
  }

  /// Determines which chapter should be scanned next when multiple chapters are selected
  int get _targetScanChapter {
    final sorted = _selectedChapters.toList()..sort();
    for (final ch in sorted) {
      if (!_cachedBanksByChapter.containsKey(ch)) {
        return ch;
      }
    }
    return _chapterNumber;
  }

  // --- Step 3 Preview State ---
  List<SloQuestion> _activePaperQuestions = [];
  String? _activePaperDocId;
  Map<int, List<SloQuestion>> _slotHistory = {};
  Map<int, int> _slotHistoryIndex = {};
  Uint8List? _cachedPaperPdfBytes;
  Uint8List? _cachedAnswerKeyPdfBytes;
  bool _isSendingToPrincipal = false;
  String? _submittedPaperId;
  int _step3ViewMode = 0; // 0 = Edit Paper, 1 = Preview
  bool _previewIsAnswerKey = false;
  Uint8List? _schoolLogoBytes;
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
    _restoreOfflineBrandingAndLogoSync();

    if (_savedDraft == null) {
      final rawLocalDraft = LocalDbService.getCache(_localDraftCacheKey);
      if (rawLocalDraft is Map) {
        _savedDraft = _SloPaperDraftState.fromJson(Map<String, dynamic>.from(rawLocalDraft));
      }
    }

    if (_savedDraft != null) {
      _restoreFromDraft(_savedDraft!);
    } else {
      _recalculateTotalMarks();
      _checkFirestoreCache();
    }
    _zoomController.addListener(_onZoomChanged);
  }

  void _restoreOfflineBrandingAndLogoSync() {
    try {
      if (_cachedLogoBytesStatic != null) {
        _schoolLogoBytes = _cachedLogoBytesStatic;
      } else {
        final cachedLogoB64 = LocalDbService.getCache(_localLogoCacheKey);
        if (cachedLogoB64 is String && cachedLogoB64.isNotEmpty) {
          _schoolLogoBytes = base64Decode(cachedLogoB64);
          _cachedLogoBytesStatic = _schoolLogoBytes;
        }
      }

      final cachedBranding = LocalDbService.getCache(_localBrandingCacheKey);
      if (cachedBranding is Map) {
        final name = (cachedBranding['name'] ?? '').toString();
        final campus = (cachedBranding['campus'] ?? '').toString();
        final board = (cachedBranding['board'] ?? '').toString();
        if (name.isNotEmpty) _schoolNameCtrl.text = name;
        if (campus.isNotEmpty) _campusCtrl.text = campus;
        if (board.isNotEmpty) _boardCtrl.text = board;
      }
    } catch (_) {}
  }

  void _restoreFromDraft(_SloPaperDraftState d) {
    _currentStep = d.currentStep;
    _selectedPublisher = d.selectedPublisher;
    _selectedGrade = d.selectedGrade;
    _selectedSubject = d.selectedSubject;
    _chapterNumber = d.chapterNumber;
    _selectedChapters
      ..clear()
      ..addAll(d.selectedChapters.isNotEmpty ? d.selectedChapters : {d.chapterNumber});
    _cachedBanksByChapter
      ..clear()
      ..addAll(d.cachedBanksByChapter);
    _chapterTitleCtrl.text = d.chapterTitle;
    _customPublisherCtrl.text = d.customPublisher;
    _isRtlSubject = d.isRtlSubject;
    _isCustomPublisher = d.isCustomPublisher;
    _loadedBank = d.loadedBank;
    _isCacheAvailable = d.loadedBank != null && d.loadedBank!.questions.isNotEmpty;
    if (_isCacheAvailable) {
      _statusMessage = "⚡ Instant SLO Bank Available (${_loadedBank!.questions.length} questions in cache)";
    }
    _selectedSloCodes
      ..clear()
      ..addAll(d.selectedSloCodes);
    _mcqCount = d.mcqCount;
    _shortCount = d.shortCount;
    _longCount = d.longCount;
    _shortAttemptCount = d.shortAttemptCount;
    _longAttemptCount = d.longAttemptCount;
    _mcqMarksEach = d.mcqMarksEach;
    _shortMarksEach = d.shortMarksEach;
    _longMarksEach = d.longMarksEach;
    _schoolNameCtrl.text = d.schoolName;
    _campusCtrl.text = d.campus;
    _boardCtrl.text = d.board;
    _examTitleCtrl.text = d.examTitle;
    _timeAllowedCtrl.text = d.timeAllowed;
    _totalMarks = d.totalMarks;
    _totalMarksCtrl.text = d.totalMarks.toString();
    _activePaperQuestions = List<SloQuestion>.from(d.activePaperQuestions);
    _activePaperDocId = d.activePaperDocId;
    _submittedPaperId = d.submittedPaperId;
    _step3ViewMode = d.step3ViewMode;
    _previewIsAnswerKey = d.previewIsAnswerKey;
    _slotHistory = {
      for (final entry in d.slotHistory.entries) entry.key: List<SloQuestion>.from(entry.value),
    };
    _slotHistoryIndex = Map<int, int>.from(d.slotHistoryIndex);
    _cachedPaperPdfBytes = d.cachedPaperPdfBytes;
    _cachedAnswerKeyPdfBytes = d.cachedAnswerKeyPdfBytes;

    if (_loadedBank == null) {
      _checkFirestoreCache();
    }
  }

  void _persistToDraft({bool flushImmediately = false}) {
    final d = _SloPaperDraftState()
      ..currentStep = _currentStep
      ..selectedPublisher = _selectedPublisher
      ..selectedGrade = _selectedGrade
      ..selectedSubject = _selectedSubject
      ..chapterNumber = _chapterNumber
      ..selectedChapters = Set<int>.from(_selectedChapters)
      ..cachedBanksByChapter = Map<int, ChapterBankDoc>.from(_cachedBanksByChapter)
      ..chapterTitle = _chapterTitleCtrl.text
      ..customPublisher = _customPublisherCtrl.text
      ..isRtlSubject = _isRtlSubject
      ..isCustomPublisher = _isCustomPublisher
      ..loadedBank = _loadedBank
      ..selectedSloCodes = Set<String>.from(_selectedSloCodes)
      ..mcqCount = _mcqCount
      ..shortCount = _shortCount
      ..longCount = _longCount
      ..shortAttemptCount = _shortAttemptCount
      ..longAttemptCount = _longAttemptCount
      ..mcqMarksEach = _mcqMarksEach
      ..shortMarksEach = _shortMarksEach
      ..longMarksEach = _longMarksEach
      ..schoolName = _schoolNameCtrl.text
      ..campus = _campusCtrl.text
      ..board = _boardCtrl.text
      ..examTitle = _examTitleCtrl.text
      ..timeAllowed = _timeAllowedCtrl.text
      ..totalMarks = _totalMarks
      ..activePaperQuestions = List<SloQuestion>.from(_activePaperQuestions)
      ..activePaperDocId = _activePaperDocId
      ..submittedPaperId = _submittedPaperId
      ..step3ViewMode = _step3ViewMode
      ..previewIsAnswerKey = _previewIsAnswerKey
      ..slotHistory = {
        for (final entry in _slotHistory.entries) entry.key: List<SloQuestion>.from(entry.value),
      }
      ..slotHistoryIndex = Map<int, int>.from(_slotHistoryIndex)
      ..cachedPaperPdfBytes = _cachedPaperPdfBytes
      ..cachedAnswerKeyPdfBytes = _cachedAnswerKeyPdfBytes;
    _savedDraft = d;

    _draftSaveDebounce?.cancel();
    if (flushImmediately) {
      LocalDbService.saveCache(_localDraftCacheKey, d.toJson());
    } else {
      _draftSaveDebounce = Timer(const Duration(milliseconds: 300), () {
        LocalDbService.saveCache(_localDraftCacheKey, d.toJson());
      });
    }
  }

  Future<void> _invalidateAndPrewarmPdf() async {
    _cachedPaperPdfBytes = null;
    _cachedAnswerKeyPdfBytes = null;
    if (mounted) {
      setState(() {});
    }
    _persistToDraft();
  }

  void _handleBackNavigation() {
    if (_currentStep == 2 && _step3ViewMode == 1) {
      // From Preview -> Edit Paper
      setState(() => _step3ViewMode = 0);
      _persistToDraft();
    } else if (_currentStep == 2 && _step3ViewMode == 0) {
      // From Edit Paper -> Step 2 (Blueprint)
      setState(() => _currentStep = 1);
      _persistToDraft();
    } else if (_currentStep == 1) {
      // From Step 2 (Blueprint) -> Step 1 (Chapter)
      setState(() => _currentStep = 0);
      _persistToDraft();
    } else {
      // Exit screen while preserving draft state
      _persistToDraft();
      if (context.canPop()) {
        context.pop();
      }
    }
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
    _draftSaveDebounce?.cancel();
    _persistToDraft(flushImmediately: true);
    _chapterTitleCtrl.dispose();
    _customPublisherCtrl.dispose();
    _schoolNameCtrl.dispose();
    _campusCtrl.dispose();
    _boardCtrl.dispose();
    _examTitleCtrl.dispose();
    _timeAllowedCtrl.dispose();
    _totalMarksCtrl.dispose();
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

  void _applyFetchedBanksToState(List<int> sortedChs, Map<int, ChapterBankDoc> fetchedBanks, {required bool isChecking}) {
    _isCheckingCache = isChecking;
    _cachedBanksByChapter
      ..clear()
      ..addAll(fetchedBanks);

    if (fetchedBanks.isNotEmpty) {
      final mergedSlos = <String, SloItem>{};
      final mergedQuestions = <String, SloQuestion>{};
      final titles = <String>[];

      for (final ch in sortedChs) {
        final b = fetchedBanks[ch];
        if (b != null) {
          if (b.chapterTitle.isNotEmpty) titles.add("Ch $ch: ${b.chapterTitle}");
          for (final s in b.slos) {
            mergedSlos[s.sloCode] = s;
          }
          for (final q in b.questions) {
            mergedQuestions["ch${ch}_${q.id}"] = q.copyWith(id: "ch${ch}_${q.id}");
          }
        }
      }

      final combinedDocId = ChapterBankDoc.generateDocId(
            publisher: _effectivePublisher,
            grade: _selectedGrade,
            subject: _selectedSubject,
            chapterNumber: sortedChs.first,
          ) +
          (sortedChs.length > 1 ? "_CHS_${sortedChs.join('_')}" : "");

      _loadedBank = ChapterBankDoc(
        docId: combinedDocId,
        publisher: _effectivePublisher,
        grade: _selectedGrade,
        subject: _selectedSubject,
        chapterNumber: sortedChs.first,
        chapterTitle: titles.isNotEmpty ? titles.join(" • ") : "Chapters ${sortedChs.join(', ')}",
        isRtl: _isRtlSubject,
        slos: mergedSlos.values.toList(),
        questions: mergedQuestions.values.toList(),
      );
      _isCacheAvailable = true;
      _selectedSloCodes
        ..clear()
        ..addAll(_loadedBank!.slos.map((s) => s.sloCode));

      final missingChs = sortedChs.where((c) => !fetchedBanks.containsKey(c)).toList();
      if (missingChs.isEmpty) {
        _statusMessage =
            "⚡ SLO Bank Ready (${_loadedBank!.questions.length} Qs from Ch ${sortedChs.join(', ')})";
      } else {
        _statusMessage =
            "⚡ ${fetchedBanks.length}/${sortedChs.length} Chapters Ready (${_loadedBank!.questions.length} Qs) • Tap Ch ${missingChs.join(', ')} to scan";
      }
    } else if (!isChecking) {
      _loadedBank = null;
      _isCacheAvailable = false;
      _statusMessage = "No bank found for Ch ${sortedChs.join(', ')}. Scan chapter pages to generate.";
    }
  }

  Future<void> _checkFirestoreCache() async {
    if (_selectedChapters.isEmpty) {
      _selectedChapters.add(_chapterNumber);
    }

    final sortedChs = _selectedChapters.toList()..sort();
    final Map<int, ChapterBankDoc> localBanks = {};

    // 1. 0ms Synchronous Check in Local Offline Cache (RAM + Hive)
    for (final ch in sortedChs) {
      final docId = ChapterBankDoc.generateDocId(
        publisher: _effectivePublisher,
        grade: _selectedGrade,
        subject: _selectedSubject,
        chapterNumber: ch,
      );
      final local = SloRepository.getChapterBankLocalSync(docId);
      if (local != null && local.questions.isNotEmpty) {
        localBanks[ch] = local;
      }
    }

    // If all selected chapters are already in local offline cache, populate immediately in 0ms!
    if (localBanks.length == sortedChs.length) {
      setState(() {
        _applyFetchedBanksToState(sortedChs, localBanks, isChecking: false);
      });
      _persistToDraft();
      return;
    }

    // Otherwise show any partially cached local chapters immediately while checking remote for remaining
    setState(() {
      if (localBanks.isNotEmpty) {
        _applyFetchedBanksToState(sortedChs, localBanks, isChecking: true);
      } else {
        _isCheckingCache = true;
        _isCacheAvailable = false;
        _statusMessage = "Checking SLO question bank...";
      }
    });

    try {
      final Map<int, ChapterBankDoc> fetchedBanks = Map<int, ChapterBankDoc>.from(localBanks);

      await Future.wait(sortedChs.map((ch) async {
        if (fetchedBanks.containsKey(ch)) return;
        final docId = ChapterBankDoc.generateDocId(
          publisher: _effectivePublisher,
          grade: _selectedGrade,
          subject: _selectedSubject,
          chapterNumber: ch,
        );
        final bank = await SloRepository.getChapterBank(docId);
        if (bank != null && bank.questions.isNotEmpty) {
          fetchedBanks[ch] = bank;
        }
      }));

      if (!mounted) return;

      setState(() {
        _applyFetchedBanksToState(sortedChs, fetchedBanks, isChecking: false);
      });
      _persistToDraft();
    } catch (e) {
      if (mounted) {
        setState(() {
          _applyFetchedBanksToState(sortedChs, localBanks, isChecking: false);
        });
      }
    }
  }

  /// Opens clean bottom sheet with 2 options: Camera | Choose from Phone
  Future<void> _showScanChapterOptions() async {
    if (_cooldownSecondsRemaining > 0) {
      _showToast("Please wait $_cooldownSecondsRemaining seconds before scanning again.");
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _selectedChapters.length > 1
                    ? "Scan Chapter Pages (Ch $_targetScanChapter)"
                    : "Scan Chapter Pages",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF4F46E5)),
                title: const Text(
                  "Camera",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF10B981)),
                title: const Text(
                  "Choose from Phone",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                onTap: () => Navigator.pop(ctx, 'phone'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == 'camera') {
      await _startMultiPageCameraCapture();
    } else if (choice == 'phone') {
      await _scanFromGallery();
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
        subject: _selectedSubject,
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

      final targetCh = _targetScanChapter;

      final generatedBank = await SloGeminiService.generateChapterBank(
        publisher: _effectivePublisher,
        grade: _selectedGrade,
        subject: _selectedSubject,
        chapterNumber: targetCh,
        chapterTitle: "",
        isRtlSubject: _isRtlSubject,
        bookContent: content,
      );

      setState(() {
        _statusMessage = "Saving to crowdsourced Firestore cache...";
      });

      await SloRepository.saveOrMergeChapterBank(generatedBank);
      _startCooldown();

      if (mounted) {
        setState(() {
          _isGeneratingAi = false;
        });
        await _checkFirestoreCache();
        if (mounted && _isCacheAvailable) {
          setState(() => _currentStep = 1);
          _persistToDraft();
        }
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
        subject: _selectedSubject,
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

      final targetCh = _targetScanChapter;

      final generatedBank = await SloGeminiService.generateChapterBank(
        publisher: _effectivePublisher,
        grade: _selectedGrade,
        subject: _selectedSubject,
        chapterNumber: targetCh,
        chapterTitle: "",
        isRtlSubject: _isRtlSubject,
        bookContent: content,
      );

      setState(() {
        _statusMessage = "Saving to crowdsourced Firestore cache...";
      });

      await SloRepository.saveOrMergeChapterBank(generatedBank);
      _startCooldown();

      if (mounted) {
        setState(() {
          _isGeneratingAi = false;
        });
        await _checkFirestoreCache();
        if (mounted && _isCacheAvailable) {
          setState(() => _currentStep = 1);
          _persistToDraft();
        }
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

  void _buildPaperQuestions({bool forceFresh = false}) {
    if (_loadedBank == null || _loadedBank!.questions.isEmpty) {
      _showToast("No questions available in the bank.");
      return;
    }

    final currentDocId = _loadedBank!.docId;

    // Preserve edited/selected questions if same chapter bank is active and not forcing fresh
    if (!forceFresh && _activePaperQuestions.isNotEmpty && _activePaperDocId == currentDocId) {
      final existingMcqs = _activePaperQuestions.where((q) => q.type == 'MCQ').toList();
      final existingShorts = _activePaperQuestions.where((q) => q.type == 'SHORT').toList();
      final existingLongs = _activePaperQuestions.where((q) => q.type == 'LONG').toList();

      if (existingMcqs.length == _mcqCount &&
          existingShorts.length == _shortCount &&
          existingLongs.length == _longCount) {
        setState(() {
          _currentStep = 2;
        });
        _invalidateAndPrewarmPdf();
        _persistToDraft();
        return;
      }

      // Adjust counts while preserving already edited questions
      final freshPool = SloRepository.buildCustomPaperFromBank(
        bank: _loadedBank!,
        selectedSloCodes: _selectedSloCodes,
        mcqCount: _mcqCount + 10,
        shortCount: _shortCount + 10,
        longCount: _longCount + 10,
      );

      final usedIds = _activePaperQuestions.map((q) => q.id).toSet();

      List<SloQuestion> adjustList(List<SloQuestion> existing, String type, int target) {
        if (existing.length >= target) {
          return existing.sublist(0, target);
        }
        final result = List<SloQuestion>.from(existing);
        for (final cand in freshPool.where((q) => q.type == type)) {
          if (result.length >= target) break;
          if (!usedIds.contains(cand.id)) {
            result.add(cand);
            usedIds.add(cand.id);
          }
        }
        return result;
      }

      final updatedList = <SloQuestion>[
        ...adjustList(existingMcqs, 'MCQ', _mcqCount),
        ...adjustList(existingShorts, 'SHORT', _shortCount),
        ...adjustList(existingLongs, 'LONG', _longCount),
      ];

      setState(() {
        _activePaperQuestions = updatedList;
        _slotHistory.clear();
        _slotHistoryIndex.clear();
        for (int i = 0; i < _activePaperQuestions.length; i++) {
          _slotHistory[i] = [_activePaperQuestions[i]];
          _slotHistoryIndex[i] = 0;
        }
        _currentStep = 2;
      });
      _invalidateAndPrewarmPdf();
      _persistToDraft();
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
      _activePaperDocId = currentDocId;
      _slotHistory.clear();
      _slotHistoryIndex.clear();
      for (int i = 0; i < _activePaperQuestions.length; i++) {
        _slotHistory[i] = [_activePaperQuestions[i]];
        _slotHistoryIndex[i] = 0;
      }
      _currentStep = 2; // Move to preview
    });
    _invalidateAndPrewarmPdf();
    _persistToDraft();
  }

  void _navigateNextQuestion(SloQuestion q) {
    if (_loadedBank == null) return;
    final slotIdx = _activePaperQuestions.indexWhere((item) => item.id == q.id);
    if (slotIdx == -1) return;

    final history = _slotHistory.putIfAbsent(slotIdx, () => [q]);
    final currentPos = _slotHistoryIndex[slotIdx] ?? 0;

    // 1. If forward history already exists, move forward immediately
    if (currentPos < history.length - 1) {
      final nextPos = currentPos + 1;
      setState(() {
        _slotHistoryIndex[slotIdx] = nextPos;
        _activePaperQuestions[slotIdx] = history[nextPos];
      });
      _invalidateAndPrewarmPdf();
      _persistToDraft();
      return;
    }

    // 2. Otherwise fetch a new question from bank that isn't in active paper or this slot's history
    final excludedQuestions = <SloQuestion>[
      ..._activePaperQuestions,
      ...history,
    ];

    final replacement = SloRepository.swapQuestion(
      currentQuestion: q,
      bank: _loadedBank!,
      currentlySelected: excludedQuestions,
      selectedSloCodes: _selectedSloCodes,
    );

    if (replacement != null) {
      setState(() {
        history.add(replacement);
        _slotHistoryIndex[slotIdx] = history.length - 1;
        _activePaperQuestions[slotIdx] = replacement;
      });
      _invalidateAndPrewarmPdf();
      _persistToDraft();
    } else {
      _showToast("No more alternative questions in bank for this slot.");
    }
  }

  void _navigatePrevQuestion(SloQuestion q) {
    final slotIdx = _activePaperQuestions.indexWhere((item) => item.id == q.id);
    if (slotIdx == -1) return;

    final history = _slotHistory[slotIdx];
    final currentPos = _slotHistoryIndex[slotIdx] ?? 0;
    if (history == null || currentPos <= 0) return;

    final prevPos = currentPos - 1;
    setState(() {
      _slotHistoryIndex[slotIdx] = prevPos;
      _activePaperQuestions[slotIdx] = history[prevPos];
    });
    _invalidateAndPrewarmPdf();
    _persistToDraft();
  }

  Future<void> _pickAndCropDiagram(SloQuestion q) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Ask Camera or Phone
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Add Diagram",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF4F46E5)),
                title: const Text("Take Photo of Diagram", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF10B981)),
                title: const Text("Choose from Phone", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1400,
        maxHeight: 1400,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      final rawBytes = await picked.readAsBytes();
      if (!mounted) return;

      // Open Interactive Pinch/Pan Crop Dialog
      final croppedBytes = await _showInteractiveDiagramCropDialog(rawBytes);
      if (croppedBytes == null || !mounted) return;

      final b64 = base64Encode(croppedBytes);
      final index = _activePaperQuestions.indexWhere((item) => item.id == q.id);
      if (index != -1) {
        final updatedQ = _activePaperQuestions[index].copyWith(diagramBase64: b64);
        setState(() {
          _activePaperQuestions[index] = updatedQ;
          final history = _slotHistory.putIfAbsent(index, () => [updatedQ]);
          final pos = _slotHistoryIndex[index] ?? 0;
          if (pos >= 0 && pos < history.length) {
            history[pos] = updatedQ;
          }
        });
        _invalidateAndPrewarmPdf();
        _persistToDraft();
      }
    } catch (e) {
      _showToast("Could not add diagram: $e");
    }
  }

  Future<Uint8List?> _showInteractiveDiagramCropDialog(Uint8List imageBytes) async {
    final boundaryKey = GlobalKey();
    final transformCtrl = TransformationController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<Uint8List>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            "Crop Diagram",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Pinch and drag the diagram inside the box:",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              Container(
                width: 260,
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF4F46E5), width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: Container(
                      color: Colors.white,
                      child: InteractiveViewer(
                        transformationController: transformCtrl,
                        minScale: 0.5,
                        maxScale: 5.0,
                        boundaryMargin: const EdgeInsets.all(120),
                        child: Center(
                          child: Image.memory(
                            imageBytes,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.crop_rounded, size: 16),
              label: const Text("Use Diagram", style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () async {
                try {
                  final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                  if (boundary != null) {
                    final uiImage = await boundary.toImage(pixelRatio: 2.0);
                    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
                    if (byteData != null && ctx.mounted) {
                      Navigator.pop(ctx, byteData.buffer.asUint8List());
                      return;
                    }
                  }
                } catch (_) {}
                if (ctx.mounted) {
                  Navigator.pop(ctx, imageBytes);
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _removeDiagramFromQuestion(SloQuestion q) {
    final index = _activePaperQuestions.indexWhere((item) => item.id == q.id);
    if (index != -1) {
      final updatedQ = _activePaperQuestions[index].copyWith(clearDiagram: true);
      setState(() {
        _activePaperQuestions[index] = updatedQ;
        final history = _slotHistory.putIfAbsent(index, () => [updatedQ]);
        final pos = _slotHistoryIndex[index] ?? 0;
        if (pos >= 0 && pos < history.length) {
          history[pos] = updatedQ;
        }
      });
      _invalidateAndPrewarmPdf();
      _persistToDraft();
    }
  }

  void _editSingleQuestion(SloQuestion q) {
    final textCtrl = TextEditingController(text: q.questionText);
    final ansCtrl = TextEditingController(text: q.type == 'MCQ' ? q.correctAnswer : (q.rubric.isNotEmpty ? q.rubric : q.correctAnswer));
    final optCtrls = List.generate(
      4,
      (i) => TextEditingController(text: i < q.options.length ? q.options[i] : ""),
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Edit Question", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Question Text",
                  isDense: true,
                ),
              ),
              if (q.type == 'MCQ') ...[
                const SizedBox(height: 10),
                for (int i = 0; i < 4; i++) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: optCtrls[i],
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: "Option ${String.fromCharCode(65 + i)}",
                        isDense: true,
                      ),
                    ),
                  ),
                ],
                TextField(
                  controller: ansCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: "Correct Option (e.g. A) ...)",
                    isDense: true,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                TextField(
                  controller: ansCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: "Answer Key / Rubric",
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final newText = textCtrl.text.trim();
              if (newText.isNotEmpty) {
                final index = _activePaperQuestions.indexWhere((item) => item.id == q.id);
                if (index != -1) {
                  final newOpts = q.type == 'MCQ'
                      ? optCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList()
                      : q.options;
                  final newAns = ansCtrl.text.trim();
                  final updatedQ = q.copyWith(
                    questionText: newText,
                    options: newOpts,
                    correctAnswer: newAns.isNotEmpty ? newAns : q.correctAnswer,
                    rubric: q.type != 'MCQ' && newAns.isNotEmpty ? newAns : q.rubric,
                  );
                  setState(() {
                    _activePaperQuestions[index] = updatedQ;
                    final history = _slotHistory.putIfAbsent(index, () => [updatedQ]);
                    final pos = _slotHistoryIndex[index] ?? 0;
                    if (pos >= 0 && pos < history.length) {
                      history[pos] = updatedQ;
                    }
                  });
                  _invalidateAndPrewarmPdf();
                  _persistToDraft();
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

  void _addCustomQuestion(String type) {
    final textCtrl = TextEditingController();
    final ansCtrl = TextEditingController();
    final optCtrls = [
      TextEditingController(text: _isRtlSubject ? "الف) " : "A) "),
      TextEditingController(text: _isRtlSubject ? "ب) " : "B) "),
      TextEditingController(text: _isRtlSubject ? "ج) " : "C) "),
      TextEditingController(text: _isRtlSubject ? "د) " : "D) "),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Add ${type == 'MCQ' ? 'MCQ' : type == 'SHORT' ? 'Short' : 'Long'} Question",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Question Text",
                  hintText: "Write your question here...",
                  isDense: true,
                ),
              ),
              if (type == 'MCQ') ...[
                const SizedBox(height: 10),
                for (int i = 0; i < 4; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: optCtrls[i],
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        labelText: "Option ${String.fromCharCode(65 + i)}",
                        isDense: true,
                      ),
                    ),
                  ),
                TextField(
                  controller: ansCtrl,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: "Correct Option (e.g. A) ...)",
                    isDense: true,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                TextField(
                  controller: ansCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: "Expected Answer / Rubric (Optional)",
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final qText = textCtrl.text.trim();
              if (qText.isEmpty) return;

              final opts = type == 'MCQ'
                  ? optCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList()
                  : <String>[];
              final ans = ansCtrl.text.trim();

              final newQ = SloQuestion(
                id: "custom_${DateTime.now().millisecondsSinceEpoch}",
                sloCode: "Custom",
                type: type,
                cognitiveLevel: "Understanding",
                questionText: qText,
                options: opts,
                correctAnswer: ans.isNotEmpty ? ans : (opts.isNotEmpty ? opts.first : "Follow textbook rubric"),
                rubric: ans.isNotEmpty ? ans : "Award marks for accurate conceptual answer.",
              );

              setState(() {
                final mcqs = _activePaperQuestions.where((q) => q.type == 'MCQ').toList();
                final shorts = _activePaperQuestions.where((q) => q.type == 'SHORT').toList();
                final longs = _activePaperQuestions.where((q) => q.type == 'LONG').toList();

                if (type == 'MCQ') {
                  mcqs.add(newQ);
                  _mcqCount = mcqs.length;
                } else if (type == 'SHORT') {
                  shorts.add(newQ);
                  if (_shortAttemptCount == _shortCount) {
                    _shortAttemptCount = shorts.length;
                  }
                  _shortCount = shorts.length;
                } else {
                  longs.add(newQ);
                  if (_longAttemptCount == _longCount) {
                    _longAttemptCount = longs.length;
                  }
                  _longCount = longs.length;
                }

                _activePaperQuestions = [...mcqs, ...shorts, ...longs];
                _slotHistory.clear();
                _slotHistoryIndex.clear();
                for (int i = 0; i < _activePaperQuestions.length; i++) {
                  _slotHistory[i] = [_activePaperQuestions[i]];
                  _slotHistoryIndex[i] = 0;
                }
                _recalculateTotalMarks();
              });
              _invalidateAndPrewarmPdf();
              _persistToDraft();
              Navigator.pop(ctx);
            },
            child: const Text("Add"),
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
    if (name.isNotEmpty || campus.isNotEmpty || board.isNotEmpty) {
      LocalDbService.saveCache(_localBrandingCacheKey, <String, dynamic>{
        'name': _schoolNameCtrl.text,
        'campus': _campusCtrl.text,
        'board': _boardCtrl.text,
      });
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
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          _schoolLogoBytes = res.bodyBytes;
          _cachedLogoBytesStatic = res.bodyBytes;
          await LocalDbService.saveCache(_localLogoCacheKey, base64Encode(res.bodyBytes));
          if (mounted) {
            setState(() {});
          }
        }
      }
    } catch (_) {}
  }

  Future<Uint8List?> _getSchoolLogoBytes() async {
    if (_schoolLogoBytes != null) return _schoolLogoBytes;
    if (_cachedLogoBytesStatic != null) {
      _schoolLogoBytes = _cachedLogoBytesStatic;
      return _schoolLogoBytes;
    }
    try {
      final cachedLogoB64 = LocalDbService.getCache(_localLogoCacheKey);
      if (cachedLogoB64 is String && cachedLogoB64.isNotEmpty) {
        _schoolLogoBytes = base64Decode(cachedLogoB64);
        _cachedLogoBytesStatic = _schoolLogoBytes;
        return _schoolLogoBytes;
      }
    } catch (_) {}
    // Non-blocking background fetch so PDF / Preview never waits on network timeout
    final schoolData = ref.read(schoolDataProvider).value;
    final logoUrl = schoolData?['logo'] as String?;
    if (logoUrl != null && logoUrl.isNotEmpty) {
      _fetchLogoFromUrl(logoUrl);
    }
    return null;
  }

  Future<Uint8List> _generatePdfBytes({required bool isAnswerKey}) async {
    if (isAnswerKey && _cachedAnswerKeyPdfBytes != null) {
      return _cachedAnswerKeyPdfBytes!;
    }
    if (!isAnswerKey && _cachedPaperPdfBytes != null) {
      return _cachedPaperPdfBytes!;
    }
    final bytes = await _generatePdfBytesInternal(isAnswerKey: isAnswerKey);
    if (isAnswerKey) {
      _cachedAnswerKeyPdfBytes = bytes;
    } else {
      _cachedPaperPdfBytes = bytes;
    }
    return bytes;
  }

  Future<Uint8List> _generatePdfBytesInternal({required bool isAnswerKey}) async {
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
      shortAttemptCount: _effectiveShortAttempt,
      longAttemptCount: _effectiveLongAttempt,
      mcqMarksEach: _mcqMarksEach,
      shortMarksEach: _shortMarksEach,
      longMarksEach: _longMarksEach,
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
        int marks = _mcqMarksEach;
        if (q.type == 'SHORT') marks = _shortMarksEach;
        if (q.type == 'LONG') marks = _longMarksEach;
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
          if (q.diagramBase64 != null && q.diagramBase64!.isNotEmpty) 'diagramBase64': q.diagramBase64,
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

      final sortedChs = _selectedChapters.toList()..sort();
      final resolvedChapterTitle = (_loadedBank?.chapterTitle != null && _loadedBank!.chapterTitle.trim().isNotEmpty)
          ? _loadedBank!.chapterTitle.trim()
          : "Chapters ${sortedChs.join(', ')}";

      final paperPayload = <String, dynamic>{
        'examTitle': _examTitleCtrl.text.trim().isNotEmpty ? _examTitleCtrl.text.trim() : "First Term Examination 2026",
        'grade': _selectedGrade,
        'subject': _selectedSubject,
        'chapterNumber': _chapterNumber,
        'selectedChapters': sortedChs,
        'chapterTitle': resolvedChapterTitle,
        'publisher': _effectivePublisher,
        'teacherName': teacherName,
        'teacherUid': teacherUid,
        'totalMarks': _totalMarks,
        'timeAllowed': _timeAllowedCtrl.text.trim().isNotEmpty ? _timeAllowedCtrl.text.trim() : "2 Hours",
        'mcqCount': _mcqCount,
        'shortCount': _shortCount,
        'longCount': _longCount,
        'shortAttemptCount': _effectiveShortAttempt,
        'longAttemptCount': _effectiveLongAttempt,
        'mcqMarksEach': _mcqMarksEach,
        'shortMarksEach': _shortMarksEach,
        'longMarksEach': _longMarksEach,
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Scaffold(
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
                    onTap: _handleBackNavigation,
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
                          "Board standard SLO question papers",
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Stepper Header Indicators (Hidden during Preview to give full screen to paper)
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
      ),
    );
  }

  Widget _buildStepPill(int step, String label, IconData icon) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (step < _currentStep ||
              (step == 1 && _loadedBank != null) ||
              (step == 2 && _activePaperQuestions.isNotEmpty)) {
            setState(() => _currentStep = step);
            _persistToDraft();
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

                // Class (Grade) & Subject in 50-50 Row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _grades.contains(_selectedGrade) ? _selectedGrade : _grades.first,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Class",
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
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _subjects.contains(_selectedSubject) ? _selectedSubject : _subjects.first,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Subject",
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Multi-Chapter Selection Pills
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Select Chapters (${_selectedChapters.length} selected)",
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    if (_selectedChapters.length > 1)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedChapters
                              ..clear()
                              ..add(_chapterNumber);
                          });
                          _checkFirestoreCache();
                        },
                        child: const Text(
                          "Reset to 1",
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(15, (i) => i + 1).map((chNum) {
                    final isSelected = _selectedChapters.contains(chNum);
                    final isCached = _cachedBanksByChapter.containsKey(chNum);

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _chapterNumber = chNum;
                          if (isSelected && _selectedChapters.length > 1) {
                            _selectedChapters.remove(chNum);
                            _chapterNumber = _selectedChapters.last;
                          } else {
                            _selectedChapters.add(chNum);
                          }
                        });
                        _checkFirestoreCache();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF4F46E5)
                              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF4F46E5)
                                : isCached
                                    ? const Color(0xFF10B981).withOpacity(0.6)
                                    : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "Ch $chNum",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : (isDark ? Colors.grey.shade300 : const Color(0xFF334155)),
                              ),
                            ),
                            if (isCached) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.check_circle_rounded,
                                size: 12,
                                color: isSelected ? Colors.greenAccent : const Color(0xFF10B981),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),

                // RTL Checkbox
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text("Urdu / Arabic / RTL Subject", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
            label: const Text("Proceed with SLO Bank", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            onPressed: () {
              setState(() => _currentStep = 1);
              _persistToDraft();
            },
          ),
          const SizedBox(height: 12),
        ],

        // Scan Chapter Pages Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          icon: _isGeneratingAi
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.document_scanner_outlined),
          label: Text(
            _isGeneratingAi
                ? "Processing with Gemini AI..."
                : _cooldownSecondsRemaining > 0
                    ? "Cooldown: ${_cooldownSecondsRemaining}s"
                    : _selectedChapters.length > 1
                        ? "Scan Chapter Pages (Ch $_targetScanChapter)"
                        : "Scan Chapter Pages",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          onPressed: (_isGeneratingAi || _cooldownSecondsRemaining > 0)
              ? null
              : _showScanChapterOptions,
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
                  onChanged: (_) {
                    _cachedPaperPdfBytes = null;
                    _cachedAnswerKeyPdfBytes = null;
                    _persistToDraft();
                  },
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
                  onChanged: (_) {
                    _cachedPaperPdfBytes = null;
                    _cachedAnswerKeyPdfBytes = null;
                    _persistToDraft();
                  },
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
                        onChanged: (_) {
                          _cachedPaperPdfBytes = null;
                          _cachedAnswerKeyPdfBytes = null;
                          _persistToDraft();
                        },
                        decoration: const InputDecoration(
                          labelText: "Time Allowed",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.timer_outlined, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _totalMarksCtrl,
                        decoration: const InputDecoration(
                          labelText: "Total Marks",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.grade_outlined, size: 20),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (val) {
                          _totalMarks = int.tryParse(val) ?? _totalMarks;
                          _cachedPaperPdfBytes = null;
                          _cachedAnswerKeyPdfBytes = null;
                          _persistToDraft();
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        "Paper Sections & Marks",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "$_totalMarks Marks",
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  "Bloom's Mix: 30% Knowledge • 50% Understanding • 20% Application",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 14),

                // Section A: MCQs
                _buildCounterRow(
                  label: "Section A: MCQs",
                  marksPerQ: "${_mcqCount * _mcqMarksEach} Marks (${_mcqMarksEach}M each)",
                  count: _mcqCount,
                  onChanged: (val) {
                    setState(() {
                      _mcqCount = val;
                      _recalculateTotalMarks();
                    });
                  },
                ),
                const Divider(),

                // Section B: Short Questions (with Attempt Choice & Marks per Q)
                _buildCounterRow(
                  label: "Section B: Short Questions",
                  marksPerQ: "${_effectiveShortAttempt * _shortMarksEach} Marks (Attempt $_effectiveShortAttempt of $_shortCount • ${_shortMarksEach}M each)",
                  count: _shortCount,
                  attemptCount: _effectiveShortAttempt,
                  onAttemptChanged: (att) {
                    setState(() {
                      _shortAttemptCount = att;
                      _recalculateTotalMarks();
                    });
                  },
                  marksOptions: const [2, 3, 4, 5],
                  selectedMarksEach: _shortMarksEach,
                  onMarksEachChanged: (m) {
                    setState(() {
                      _shortMarksEach = m;
                      _recalculateTotalMarks();
                    });
                  },
                  onChanged: (val) {
                    setState(() {
                      if (_shortAttemptCount == _shortCount || _shortAttemptCount > val) {
                        _shortAttemptCount = val;
                      }
                      _shortCount = val;
                      _recalculateTotalMarks();
                    });
                  },
                ),
                const Divider(),

                // Section C: Long Questions (with Attempt Choice & Marks per Q)
                _buildCounterRow(
                  label: "Section C: Long Questions",
                  marksPerQ: "${_effectiveLongAttempt * _longMarksEach} Marks (Attempt $_effectiveLongAttempt of $_longCount • ${_longMarksEach}M each)",
                  count: _longCount,
                  attemptCount: _effectiveLongAttempt,
                  onAttemptChanged: (att) {
                    setState(() {
                      _longAttemptCount = att;
                      _recalculateTotalMarks();
                    });
                  },
                  marksOptions: const [4, 5, 6, 8, 10],
                  selectedMarksEach: _longMarksEach,
                  onMarksEachChanged: (m) {
                    setState(() {
                      _longMarksEach = m;
                      _recalculateTotalMarks();
                    });
                  },
                  onChanged: (val) {
                    setState(() {
                      if (_longAttemptCount == _longCount || _longAttemptCount > val) {
                        _longAttemptCount = val;
                      }
                      _longCount = val;
                      _recalculateTotalMarks();
                    });
                  },
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
                    Expanded(
                      child: Text(
                        "Select SLOs (${_selectedSloCodes.length}/${slos.length})",
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
          onPressed: () => _buildPaperQuestions(),
          child: Text(
            _activePaperQuestions.isNotEmpty && _activePaperDocId == _loadedBank?.docId
                ? "Continue to Edit Paper & Preview"
                : "Generate Paper Blueprint & Preview",
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        if (_activePaperQuestions.isNotEmpty && _activePaperDocId == _loadedBank?.docId) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _buildPaperQuestions(forceFresh: true),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text("Generate Fresh New Paper (Reset Edits)", style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ],
    );
  }

  Widget _buildCounterRow({
    required String label,
    required String marksPerQ,
    required int count,
    required ValueChanged<int> onChanged,
    int? attemptCount,
    ValueChanged<int>? onAttemptChanged,
    List<int>? marksOptions,
    int? selectedMarksEach,
    ValueChanged<int>? onMarksEachChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  Text(marksPerQ, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.grey, size: 22),
                  visualDensity: VisualDensity.compact,
                  onPressed: count > 0 ? () => onChanged(count - 1) : null,
                ),
                Text("$count", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, color: Color(0xFF4F46E5), size: 22),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onChanged(count + 1),
                ),
              ],
            ),
          ],
        ),
        if (count > 0 && (onAttemptChanged != null || marksOptions != null)) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Choice selector: Attempt X of Y
              if (onAttemptChanged != null && attemptCount != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: attemptCount < count
                          ? const Color(0xFF10B981).withOpacity(0.5)
                          : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Attempt: ", style: TextStyle(fontSize: 11, color: Colors.grey)),
                      InkWell(
                        onTap: attemptCount > 1 ? () => onAttemptChanged(attemptCount - 1) : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.chevron_left_rounded,
                            size: 16,
                            color: attemptCount > 1 ? const Color(0xFF4F46E5) : Colors.grey.withOpacity(0.4),
                          ),
                        ),
                      ),
                      Text(
                        "$attemptCount/$count",
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: attemptCount < count ? const Color(0xFF10B981) : const Color(0xFF4F46E5),
                        ),
                      ),
                      InkWell(
                        onTap: attemptCount < count ? () => onAttemptChanged(attemptCount + 1) : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: attemptCount < count ? const Color(0xFF4F46E5) : Colors.grey.withOpacity(0.4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Marks per question pills (2M, 3M, 4M, etc.)
              if (marksOptions != null && onMarksEachChanged != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: marksOptions.map((m) {
                    final isSel = selectedMarksEach == m;
                    return GestureDetector(
                      onTap: () => onMarksEachChanged(m),
                      child: Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSel
                              ? const Color(0xFF4F46E5)
                              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSel
                                ? const Color(0xFF4F46E5)
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        child: Text(
                          "${m}M",
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isSel ? Colors.white : (isDark ? Colors.grey.shade300 : const Color(0xFF475569)),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
            ],
          ),
        ],
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
        // Mode Switcher Bar: "Edit Paper" vs "Preview" (Hidden during Preview to maximize canvas space)
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
                    onTap: () {
                      setState(() => _step3ViewMode = 0);
                      _persistToDraft();
                    },
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
                            "Edit Paper (${_activePaperQuestions.length})",
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
                    onTap: () {
                      setState(() => _step3ViewMode = 1);
                      _persistToDraft();
                    },
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
                            "Preview",
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

        // Keep both views alive in an IndexedStack so Preview is pre-rendered in background for instant 0ms switching!
        Expanded(
          child: IndexedStack(
            index: _step3ViewMode,
            children: [
              // MODE 0: Questions List with Left/Right History Swap & Edit
              Column(
                children: [
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
                          _buildSectionTitle(
                            "SECTION 'A': MCQs (${mcqs.length * _mcqMarksEach} Marks)",
                            onAdd: () => _addCustomQuestion('MCQ'),
                          ),
                          ...mcqs.asMap().entries.map((entry) {
                            return _buildQuestionCard(entry.key + 1, entry.value);
                          }),
                          const SizedBox(height: 12),
                        ],

                        // Section B
                        if (shorts.isNotEmpty) ...[
                          _buildSectionTitle(
                            "SECTION 'B': Short Qs (${_effectiveShortAttempt * _shortMarksEach} Marks${_effectiveShortAttempt < shorts.length ? ' • Attempt $_effectiveShortAttempt/${shorts.length}' : ''})",
                            onAdd: () => _addCustomQuestion('SHORT'),
                          ),
                          ...shorts.asMap().entries.map((entry) {
                            return _buildQuestionCard(entry.key + 1, entry.value);
                          }),
                          const SizedBox(height: 12),
                        ],

                        // Section C
                        if (longs.isNotEmpty) ...[
                          _buildSectionTitle(
                            "SECTION 'C': Long Qs (${_effectiveLongAttempt * _longMarksEach} Marks${_effectiveLongAttempt < longs.length ? ' • Attempt $_effectiveLongAttempt/${longs.length}' : ''})",
                            onAdd: () => _addCustomQuestion('LONG'),
                          ),
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
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.preview_rounded, size: 20),
                        label: const Text("Preview", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        onPressed: () {
                          setState(() => _step3ViewMode = 1);
                          _persistToDraft();
                        },
                      ),
                    ),
                  ),
                ],
              ),

              // MODE 1: Interactive A4 WYSIWYG Preview
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.of(context).size.width - 20,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 1. Edit Paper Button
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                setState(() => _step3ViewMode = 0);
                                _persistToDraft();
                              },
                              child: Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 9),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.edit_note_rounded,
                                      size: 15,
                                      color: isDark ? Colors.white : const Color(0xFF334155),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Edit Paper",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(width: 6),

                            // 2 & 3. Segmented Toggle: Paper | Answer Key
                            Container(
                              height: 32,
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      if (_previewIsAnswerKey) {
                                        setState(() {
                                          _previewIsAnswerKey = false;
                                          _currentPreviewPageIndex = 0;
                                        });
                                        if (_pagePreviewController.hasClients) {
                                          _pagePreviewController.jumpToPage(0);
                                        }
                                        _resetZoom();
                                        _persistToDraft();
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: !_previewIsAnswerKey ? const Color(0xFF4F46E5) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        "Paper",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: !_previewIsAnswerKey
                                              ? Colors.white
                                              : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      if (!_previewIsAnswerKey) {
                                        setState(() {
                                          _previewIsAnswerKey = true;
                                          _currentPreviewPageIndex = 0;
                                        });
                                        if (_pagePreviewController.hasClients) {
                                          _pagePreviewController.jumpToPage(0);
                                        }
                                        _resetZoom();
                                        _persistToDraft();
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _previewIsAnswerKey ? const Color(0xFF10B981) : Colors.transparent,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        "Answer Key",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: _previewIsAnswerKey
                                              ? Colors.white
                                              : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(width: 6),

                            // 4. Refresh Button
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                _resetZoom();
                                _invalidateAndPrewarmPdf();
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                  color: isDark ? Colors.white : const Color(0xFF334155),
                                ),
                              ),
                            ),

                            const SizedBox(width: 6),

                            // 5. Send to Principal Button
                            SizedBox(
                              height: 32,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _submittedPaperId != null ? Colors.teal.shade700 : const Color(0xFF0D9488),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
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
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                                onPressed: _isSendingToPrincipal ? null : _sendToPrincipal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Instant 0ms Offline Native A4 Paper & Answer Key Canvas
                  Expanded(
                    child: _activePaperQuestions.isEmpty || _loadedBank == null
                        ? const SizedBox.shrink()
                        : _buildGalleryInteractiveCanvas(
                            context,
                            _buildDirectA4PreviewPages(isAnswerKey: _previewIsAnswerKey),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static const List<String> _romanNumerals = [
    "(i)", "(ii)", "(iii)", "(iv)", "(v)", "(vi)", "(vii)", "(viii)", "(ix)", "(x)",
    "(xi)", "(xii)", "(xiii)", "(xiv)", "(xv)", "(xvi)", "(xvii)", "(xviii)", "(xix)", "(xx)"
  ];

  /// Builds 100% offline, 0ms instant vector A4 pages for Question Paper or Answer Key
  List<Widget> _buildDirectA4PreviewPages({required bool isAnswerKey}) {
    final chapterBank = _loadedBank!;
    final isRtl = chapterBank.isRtl;
    final mcqs = _activePaperQuestions.where((q) => q.type == 'MCQ').toList();
    final shorts = _activePaperQuestions.where((q) => q.type == 'SHORT').toList();
    final longs = _activePaperQuestions.where((q) => q.type == 'LONG').toList();

    final schoolName = _schoolNameCtrl.text.trim().isNotEmpty
        ? _schoolNameCtrl.text.trim()
        : "Smart Public School";
    final campus = _campusCtrl.text.trim().isNotEmpty
        ? _campusCtrl.text.trim()
        : "Main Campus";
    final board = _boardCtrl.text.trim().isNotEmpty
        ? _boardCtrl.text.trim()
        : "Affiliated with Board of Intermediate & Secondary Education";
    final examTitle = _examTitleCtrl.text.trim().isNotEmpty
        ? _examTitleCtrl.text.trim()
        : "First Term Examination 2026";
    final timeAllowed = _timeAllowedCtrl.text.trim().isNotEmpty
        ? _timeAllowedCtrl.text.trim()
        : "2 Hours";

    final List<MapEntry<Widget, double>> blocks = [];

    double estimateLines(String text, int charsPerLine, double lineHeight) {
      if (text.isEmpty) return lineHeight;
      final lines = (text.length / charsPerLine).ceil().clamp(1, 15);
      return lines * lineHeight;
    }

    if (!isAnswerKey) {
      final attemptShorts = _effectiveShortAttempt < shorts.length ? _effectiveShortAttempt : shorts.length;
      final hasShortChoice = attemptShorts < shorts.length;
      final secBMarks = attemptShorts * _shortMarksEach;

      final attemptLongs = _effectiveLongAttempt < longs.length ? _effectiveLongAttempt : longs.length;
      final hasLongChoice = attemptLongs < longs.length;
      final secCMarks = attemptLongs * _longMarksEach;

      // Section A: MCQs
      if (mcqs.isNotEmpty) {
        blocks.add(MapEntry(
          _buildA4SectionHeader(
            title: isRtl
                ? "حصہ اوّل: معروضی سوالات (MCQs)"
                : "SECTION 'A' (Multiple Choice Questions - MCQs)",
            marks: isRtl
                ? "کل نمبر: ${mcqs.length * _mcqMarksEach} | وقت: ۱۵ منٹ"
                : "Marks: ${mcqs.length * _mcqMarksEach} | Time: 15 Mins",
            instructions: isRtl
                ? "نوٹ: تمام سوالات لازمی ہیں۔ دیئے گئے اختیارات میں سے درست جواب کا انتخاب کریں۔ کاٹ کر یا دوبارہ لکھنے پر نمبر نہیں ملیں گے۔"
                : "NOTE: Attempt all questions. Each question carries $_mcqMarksEach ${_mcqMarksEach == 1 ? 'Mark' : 'Marks'}. Encircle the correct option (A / B / C / D). Overwriting or cutting will result in zero marks.",
            isRtl: isRtl,
          ),
          46.0,
        ));
        blocks.add(MapEntry(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              isRtl
                  ? "سوال نمبر ۱: دیئے گئے اختیارات میں سے درست جواب کا انتخاب کریں:"
                  : "Q.1  Choose the correct answer for each from the given options:",
              style: TextStyle(
                fontSize: isRtl ? 10.5 : 9.5,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          20.0,
        ));

        for (int i = 0; i < mcqs.length; i++) {
          final q = mcqs[i];
          final diagH = q.diagramBytes != null ? 108.0 : 0.0;
          final qH = estimateLines(q.questionText, 78, 13.5) + 22.0 + diagH;
          blocks.add(MapEntry(_buildA4McqItem(i + 1, q, isRtl), qH));
        }
      }

      // Section B: Short Questions
      if (shorts.isNotEmpty) {
        blocks.add(MapEntry(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _buildA4SectionHeader(
              title: isRtl
                  ? "حصہ دوم: مختصر جواب کے سوالات (Short Questions)"
                  : "SECTION 'B' (Short Answer Questions)",
              marks: isRtl ? "کل نمبر: $secBMarks" : "Marks: $secBMarks",
              instructions: isRtl
                  ? (hasShortChoice
                      ? "نوٹ: دیئے گئے (${shorts.length}) میں سے کوئی سے ($attemptShorts) سوالات کے مختصر جوابات تحریر کریں۔ تمام سوالات کے نمبر مساوی ہیں ($attemptShorts x $_shortMarksEach = $secBMarks نمبر)۔"
                      : "نوٹ: تمام (${shorts.length}) سوالات کے مختصر جوابات تحریر کریں۔ تمام سوالات کے نمبر مساوی ہیں (${shorts.length} x $_shortMarksEach = $secBMarks نمبر)۔")
                  : (hasShortChoice
                      ? "NOTE: Attempt any ($attemptShorts) out of (${shorts.length}) questions. All questions carry equal marks ($attemptShorts x $_shortMarksEach = $secBMarks Marks). Answer briefly on your answer sheet."
                      : "NOTE: Attempt all (${shorts.length}) questions. All questions carry equal marks (${shorts.length} x $_shortMarksEach = $secBMarks Marks). Answer briefly on your answer sheet."),
              isRtl: isRtl,
            ),
          ),
          52.0,
        ));
        blocks.add(MapEntry(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              isRtl
                  ? (hasShortChoice
                      ? "سوال نمبر ۲: مندرجہ ذیل میں سے کوئی سے ($attemptShorts) سوالات کے مختصر جوابات تحریر کریں:"
                      : "سوال نمبر ۲: مندرجہ ذیل سوالات کے مختصر جوابات تحریر کریں:")
                  : (hasShortChoice
                      ? "Q.2  Answer any ($attemptShorts) of the following short questions:"
                      : "Q.2  Answer the following short questions:"),
              style: TextStyle(
                fontSize: isRtl ? 10.5 : 9.5,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          20.0,
        ));

        for (int i = 0; i < shorts.length; i++) {
          final q = shorts[i];
          final diagH = q.diagramBytes != null ? 108.0 : 0.0;
          final qH = estimateLines(q.questionText, 72, 14.0) + 7.0 + diagH;
          blocks.add(MapEntry(_buildA4ShortItem(i + 1, q, isRtl, _shortMarksEach), qH));
        }
      }

      // Section C: Long Questions
      if (longs.isNotEmpty) {
        blocks.add(MapEntry(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _buildA4SectionHeader(
              title: isRtl
                  ? "حصہ سوم: تفصیلی سوالات (Long Questions)"
                  : "SECTION 'C' (Detailed / Long Questions)",
              marks: isRtl ? "کل نمبر: $secCMarks" : "Marks: $secCMarks",
              instructions: isRtl
                  ? (hasLongChoice
                      ? "نوٹ: دیئے گئے (${longs.length}) میں سے کوئی سے ($attemptLongs) سوالات کے تفصیلی جوابات تحریر کریں۔ جہاں ضروری ہو لیبل شدہ خاکے بنائیں۔ ($attemptLongs x $_longMarksEach = $secCMarks نمبر)۔"
                      : "نوٹ: تمام (${longs.length}) سوالات کے تفصیلی جوابات تحریر کریں۔ جہاں ضروری ہو لیبل شدہ خاکے بنائیں۔ (${longs.length} x $_longMarksEach = $secCMarks نمبر)۔")
                  : (hasLongChoice
                      ? "NOTE: Attempt any ($attemptLongs) out of (${longs.length}) questions in detail. Draw neat and labelled diagrams where necessary ($attemptLongs x $_longMarksEach = $secCMarks Marks)."
                      : "NOTE: Attempt all (${longs.length}) questions in detail. Draw neat and labelled diagrams where necessary (${longs.length} x $_longMarksEach = $secCMarks Marks)."),
              isRtl: isRtl,
            ),
          ),
          52.0,
        ));

        for (int i = 0; i < longs.length; i++) {
          final q = longs[i];
          final diagH = q.diagramBytes != null ? 108.0 : 0.0;
          final qH = estimateLines(q.questionText, 72, 14.0) + 8.0 + diagH;
          blocks.add(MapEntry(_buildA4LongItem(i + 1, q, isRtl, _longMarksEach), qH));
        }
      }

      // Signature block
      blocks.add(MapEntry(_buildA4SignatureBlock(isRtl), 50.0));
    } else {
      // Answer Key & Rubrics Blocks
      if (mcqs.isNotEmpty) {
        blocks.add(MapEntry(
          _buildA4SectionHeader(
            title: "SECTION 'A' ANSWER KEY (MCQs)",
            marks: "${mcqs.length} Questions",
            instructions: "Official scoring options for objective sheet evaluation.",
            isRtl: false,
          ),
          40.0,
        ));
        final rows = (mcqs.length / 4).ceil().clamp(1, 20);
        blocks.add(MapEntry(
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: mcqs.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final q = entry.value;
                return Container(
                  width: 128,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF9CA3AF), width: 0.6),
                  ),
                  child: Text(
                    "Q$idx: ${q.correctAnswer}",
                    style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                );
              }).toList(),
            ),
          ),
          rows * 26.0 + 16.0,
        ));
      }

      if (shorts.isNotEmpty) {
        blocks.add(MapEntry(
          _buildA4SectionHeader(
            title: "SECTION 'B' MARKING RUBRIC (Short Questions)",
            marks: "${shorts.length} Questions",
            instructions: "Award marks based on core concepts and key terms.",
            isRtl: false,
          ),
          40.0,
        ));
        for (int i = 0; i < shorts.length; i++) {
          final q = shorts[i];
          final ansText = q.rubric.isNotEmpty ? q.rubric : q.correctAnswer;
          final diagH = q.diagramBytes != null ? 105.0 : 0.0;
          final h = estimateLines(q.questionText, 75, 13.0) +
              estimateLines(ansText, 80, 12.5) +
              24.0 +
              diagH;
          blocks.add(MapEntry(_buildA4RubricCard("Q.2 (${i + 1})", q, ansText, "Expected Answer / Rubric", isRtl), h));
        }
      }

      if (longs.isNotEmpty) {
        blocks.add(MapEntry(
          _buildA4SectionHeader(
            title: "SECTION 'C' MARKING RUBRIC (Detailed Questions)",
            marks: "${longs.length} Questions",
            instructions: "Marking breakdown for comprehensive descriptive answers.",
            isRtl: false,
          ),
          40.0,
        ));
        for (int i = 0; i < longs.length; i++) {
          final q = longs[i];
          final ansText = q.rubric.isNotEmpty ? q.rubric : q.correctAnswer;
          final diagH = q.diagramBytes != null ? 105.0 : 0.0;
          final h = estimateLines(q.questionText, 75, 13.0) +
              estimateLines(ansText, 80, 12.5) +
              24.0 +
              diagH;
          blocks.add(MapEntry(_buildA4RubricCard("Q.${i + 3}", q, ansText, "Model Solution / Rubric", isRtl), h));
        }
      }
    }

    // Paginate blocks across A4 pages (595 x 842 pt)
    final List<List<Widget>> paginatedWidgetLists = [];
    List<Widget> currentPageWidgets = [];
    double currentHeight = 0.0;
    int pageIndex = 0;

    double maxBodyHeightForPage(int pIdx) {
      if (isAnswerKey) return 710.0;
      return pIdx == 0 ? 635.0 : 735.0;
    }

    for (final block in blocks) {
      final limit = maxBodyHeightForPage(pageIndex);
      if (currentPageWidgets.isNotEmpty && (currentHeight + block.value) > limit) {
        paginatedWidgetLists.add(currentPageWidgets);
        currentPageWidgets = [block.key];
        currentHeight = block.value;
        pageIndex++;
      } else {
        currentPageWidgets.add(block.key);
        currentHeight += block.value;
      }
    }
    if (currentPageWidgets.isNotEmpty || paginatedWidgetLists.isEmpty) {
      paginatedWidgetLists.add(currentPageWidgets);
    }

    final totalPages = paginatedWidgetLists.length;

    return List.generate(totalPages, (idx) {
      final pageNum = idx + 1;
      final bodyItems = paginatedWidgetLists[idx];

      return AspectRatio(
        aspectRatio: 595.0 / 842.0,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 595.0,
            height: 842.0,
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.black, fontFamily: 'Roboto'),
              child: Directionality(
                textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Page Header
                      if (isAnswerKey)
                        _buildA4AnswerKeyHeader(
                          schoolName: schoolName,
                          examTitle: examTitle,
                          grade: chapterBank.grade,
                          subject: chapterBank.subject,
                        )
                      else
                        _buildA4OfficialHeader(
                          schoolName: schoolName,
                          campus: campus,
                          board: board,
                          examTitle: examTitle,
                          timeAllowed: timeAllowed,
                          totalMarks: _totalMarks,
                          grade: chapterBank.grade,
                          subject: chapterBank.subject,
                          pageNumber: pageNum,
                        ),

                      // Page Body
                      Expanded(
                        child: ClipRect(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: bodyItems,
                          ),
                        ),
                      ),

                      // Page Footer
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Container(
                          margin: const EdgeInsets.only(top: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "Smart SLO Paper Engine  •  Board Curriculum Standard",
                                style: TextStyle(fontSize: 8, color: Color(0xFF616161)),
                              ),
                              Text(
                                isAnswerKey
                                    ? "*** CONFIDENTIAL MARKING KEY ***"
                                    : (pageNum < totalPages
                                        ? "*** Please Turn Over (P.T.O.) ***"
                                        : "*** END OF EXAMINATION PAPER ***"),
                                style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF424242)),
                              ),
                              Text(
                                "Page $pageNum of $totalPages",
                                style: const TextStyle(fontSize: 8, color: Color(0xFF616161)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildA4OfficialHeader({
    required String schoolName,
    required String campus,
    required String board,
    required String examTitle,
    required String timeAllowed,
    required int totalMarks,
    required String grade,
    required String subject,
    required int pageNumber,
  }) {
    if (pageNumber > 1) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.only(bottom: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(width: 0.8, color: Colors.black)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$schoolName  •  $examTitle",
                style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              Text(
                "Subject: $subject  |  Class: ${grade}th",
                style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildLogoBox(EdgeInsets margin) {
      if (_schoolLogoBytes != null) {
        return Container(
          width: 56,
          height: 56,
          margin: margin,
          child: Image.memory(_schoolLogoBytes!, fit: BoxFit.contain),
        );
      }
      return Container(
        width: 50,
        height: 50,
        margin: margin,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black, width: 1.5),
        ),
        child: Center(
          child: Text(
            schoolName.isNotEmpty ? schoolName[0].toUpperCase() : "S",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                buildLogoBox(const EdgeInsets.only(right: 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        schoolName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 17.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                          color: Colors.black,
                        ),
                      ),
                      if (campus.isNotEmpty) ...[
                        const SizedBox(height: 1.5),
                        Text(
                          campus.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF424242)),
                        ),
                      ],
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(width: 1.2, color: Colors.black),
                            bottom: BorderSide(width: 1.2, color: Colors.black),
                          ),
                        ),
                        child: Text(
                          examTitle.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      if (board.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          board,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 8, color: Color(0xFF616161)),
                        ),
                      ],
                    ],
                  ),
                ),
                buildLogoBox(const EdgeInsets.only(left: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1.0),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.black, width: 0.8)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Text("Student Name: ", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black)),
                            Text("___________________________________________", style: TextStyle(fontSize: 9.5, color: Colors.black)),
                          ],
                        ),
                        Row(
                          children: [
                            const Text("Roll No: ", style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black)),
                            ...List.generate(
                              5,
                              (_) => Container(
                                width: 15,
                                height: 15,
                                margin: const EdgeInsets.only(left: 2),
                                decoration: BoxDecoration(border: Border.all(color: Colors.black, width: 0.8)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    color: const Color(0xFFF5F5F5),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Class: ${grade}th", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                        Text("Subject: $subject", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                        Text("Time Allowed: $timeAllowed", style: const TextStyle(fontSize: 9, color: Colors.black)),
                        Text("Total Marks: $totalMarks", style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                        const Text("Marks Obtained: _______", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildA4AnswerKeyHeader({
    required String schoolName,
    required String examTitle,
    required String grade,
    required String subject,
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.only(bottom: 8),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(width: 1.5, color: Colors.black)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (_schoolLogoBytes != null)
                  Container(
                    margin: const EdgeInsets.only(right: 10),
                    width: 36,
                    height: 36,
                    child: Image.memory(_schoolLogoBytes!, fit: BoxFit.contain),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      schoolName.toUpperCase(),
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.black),
                    ),
                    Text(
                      "${examTitle.toUpperCase()}  •  TEACHER MARKING KEY (CONFIDENTIAL)",
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFB91C1C)),
                    ),
                  ],
                ),
              ],
            ),
            Text(
              "Class: ${grade}th  |  $subject",
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildA4SectionHeader({
    required String title,
    required String marks,
    required String instructions,
    required bool isRtl,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFFEEEEEE),
        border: Border(
          top: BorderSide(width: 1.2, color: Colors.black),
          bottom: BorderSide(width: 1.2, color: Colors.black),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              Text(
                marks,
                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            instructions,
            style: const TextStyle(fontSize: 8, color: Color(0xFF424242)),
          ),
        ],
      ),
    );
  }

  Widget? _buildA4DiagramWidget(SloQuestion q, bool isRtl) {
    final bytes = q.diagramBytes;
    if (bytes == null || bytes.isEmpty) return null;
    return Container(
      margin: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isRtl ? 0 : 18,
        right: isRtl ? 18 : 0,
      ),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF9E9E9E), width: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Image.memory(
        bytes,
        height: 92,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildA4McqItem(int index, SloQuestion q, bool isRtl) {
    final diag = _buildA4DiagramWidget(q, isRtl);
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "($index) ",
                style: TextStyle(fontSize: isRtl ? 10 : 9.5, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              Expanded(
                child: Text(
                  q.questionText,
                  style: TextStyle(fontSize: isRtl ? 10 : 9.5, height: 1.25, color: Colors.black),
                ),
              ),
            ],
          ),
          if (diag != null) diag,
          const SizedBox(height: 2.5),
          Padding(
            padding: EdgeInsets.only(left: isRtl ? 0 : 18, right: isRtl ? 18 : 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: q.options.map((opt) {
                return Expanded(
                  child: Text(
                    opt,
                    style: TextStyle(fontSize: isRtl ? 9.5 : 8.5, color: Colors.black),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildA4ShortItem(int index, SloQuestion q, bool isRtl, int marksEach) {
    final label = index <= _romanNumerals.length ? _romanNumerals[index - 1] : "($index)";
    final diag = _buildA4DiagramWidget(q, isRtl);
    return Container(
      margin: const EdgeInsets.only(bottom: 4.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 26,
                child: Text(
                  label,
                  style: TextStyle(fontSize: isRtl ? 10 : 9.5, fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
              Expanded(
                child: Text(
                  q.questionText,
                  style: TextStyle(fontSize: isRtl ? 10 : 9.5, height: 1.25, color: Colors.black),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isRtl ? "($marksEach نمبر)" : "($marksEach Marks)",
                style: const TextStyle(fontSize: 8.5, color: Color(0xFF424242)),
              ),
            ],
          ),
          if (diag != null) diag,
        ],
      ),
    );
  }

  Widget _buildA4LongItem(int index, SloQuestion q, bool isRtl, int marksEach) {
    final qNum = index + 2;
    final diag = _buildA4DiagramWidget(q, isRtl);
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isRtl ? "سوال نمبر $qNum:  " : "Q.$qNum  ",
                style: TextStyle(fontSize: isRtl ? 10 : 9.5, fontWeight: FontWeight.bold, color: Colors.black),
              ),
              Expanded(
                child: Text(
                  q.questionText,
                  style: TextStyle(fontSize: isRtl ? 10 : 9.5, height: 1.25, color: Colors.black),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isRtl ? "($marksEach نمبر)" : "($marksEach Marks)",
                style: const TextStyle(fontSize: 8.5, color: Color(0xFF424242)),
              ),
            ],
          ),
          if (diag != null) diag,
        ],
      ),
    );
  }

  Widget _buildA4RubricCard(String qPrefix, SloQuestion q, String ansText, String rubricLabel, bool isRtl) {
    final diag = _buildA4DiagramWidget(q, isRtl);
    return Container(
      margin: const EdgeInsets.only(top: 5),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$qPrefix: ${q.questionText} [${q.cognitiveLevel}]",
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
          ),
          if (diag != null) diag,
          const SizedBox(height: 2),
          Text(
            "$rubricLabel: $ansText",
            style: const TextStyle(fontSize: 8.5, color: Color(0xFF1E1B4B)),
          ),
        ],
      ),
    );
  }

  Widget _buildA4SignatureBlock(bool isRtl) {
    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 2),
      padding: const EdgeInsets.only(top: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(width: 0.8, color: Colors.black)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("____________________________", style: TextStyle(fontSize: 9, color: Colors.black)),
              const SizedBox(height: 2),
              Text(
                isRtl ? "دستخط متعلقہ استاد" : "Subject Teacher Signature",
                style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text("____________________________", style: TextStyle(fontSize: 9, color: Colors.black)),
              const SizedBox(height: 2),
              Text(
                isRtl ? "دستخط پرنسپل / کنٹرولر امتحانات" : "Principal / Exam Controller",
                style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Colors.black),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryInteractiveCanvas(BuildContext context, List<Widget> pages) {
    if (pages.isEmpty) {
      return const SizedBox.shrink();
    }

    final safePageIndex = _currentPreviewPageIndex.clamp(0, pages.length - 1);
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
                                  child: pages[i],
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
                        final pageWidget = pages[idx];

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
                                  child: pageWidget,
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
                            onPressed: safePageIndex > 0
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
                              "${safePageIndex + 1}/${pages.length}",
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                          // Next page
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 18),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(3),
                            tooltip: "Next Page",
                            onPressed: safePageIndex < pages.length - 1
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

  Widget _buildSectionTitle(String title, {VoidCallback? onAdd}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
            ),
          ),
          if (onAdd != null)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF4F46E5).withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 14, color: Color(0xFF4F46E5)),
                    SizedBox(width: 2),
                    Text(
                      "Add Q",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(int index, SloQuestion q) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final slotIdx = _activePaperQuestions.indexWhere((item) => item.id == q.id);
    final currentOptionNum = slotIdx != -1 ? ((_slotHistoryIndex[slotIdx] ?? 0) + 1) : 1;
    final canGoPrev = currentOptionNum > 1;
    final diagBytes = q.diagramBytes;

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

            // Attached Diagram Preview (if present)
            if (diagBytes != null) ...[
              const SizedBox(height: 8),
              Stack(
                children: [
                  Container(
                    height: 110,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.withOpacity(0.35)),
                    ),
                    child: Image.memory(
                      diagBytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeDiagramFromQuestion(q),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],

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
                // Previous / Next Question Switcher Pill (◀ 1 ▶)
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF4F46E5).withOpacity(0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                        onTap: canGoPrev ? () => _navigatePrevQuestion(q) : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Icon(
                            Icons.chevron_left_rounded,
                            size: 18,
                            color: canGoPrev
                                ? const Color(0xFF4F46E5)
                                : Colors.grey.withOpacity(0.4),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            vertical: BorderSide(
                              color: const Color(0xFF4F46E5).withOpacity(0.18),
                            ),
                          ),
                        ),
                        child: Text(
                          "$currentOptionNum",
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                        onTap: () => _navigateNextQuestion(q),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Diagram Button
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: Icon(
                    diagBytes != null ? Icons.image_rounded : Icons.add_photo_alternate_outlined,
                    size: 15,
                    color: diagBytes != null ? const Color(0xFF10B981) : null,
                  ),
                  label: Text(
                    "Diagram",
                    style: TextStyle(
                      fontSize: 12,
                      color: diagBytes != null ? const Color(0xFF10B981) : null,
                      fontWeight: diagBytes != null ? FontWeight.bold : null,
                    ),
                  ),
                  onPressed: () => _pickAndCropDiagram(q),
                ),
                // Edit Button
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
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
