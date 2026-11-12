import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:teacher_mobile_app/core/services/local_db_service.dart';
import 'package:teacher_mobile_app/features/paper_exam/models/slo_paper_models.dart';

class SloRepository {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String collectionPath = 'global_slo_chapter_banks';
  static const String _localBankKeyPrefix = 'slo_bank_v1_';

  /// In-memory ultra-fast cache for 0ms synchronous access
  static final Map<String, ChapterBankDoc> _memoryCache = <String, ChapterBankDoc>{};

  /// Detects legacy dummy/template fallback questions so they can never pollute any paper again
  static bool isDummyOrCorruptedQuestion(SloQuestion q) {
    final text = q.questionText.trim();
    final ans = q.correctAnswer.trim();
    final rub = q.rubric.trim();
    final opts = q.options.join(' ');

    if (text.isEmpty) return true;

    // Urdu dummy fallback signatures
    if (text.contains('کے مطابق درست بیان کا انتخاب کریں') ||
        text.contains('سے متعلق اہم نکتہ کیا ہے') ||
        opts.contains('بنیادی اصول اور تعریف') ||
        opts.contains('ثانوی عمل') ||
        opts.contains('غیر متعلقہ عنصر') ||
        ans == 'الف) بنیادی اصول اور تعریف' ||
        ans == 'مختصر تعریف کے ۲ نمبر اور درست مثال کا ۱ نمبر۔' ||
        rub == 'واضح تعریف اور درست تصور پیش کرنے پر پورے نمبر دیں۔') {
      return true;
    }

    // English dummy fallback signatures
    if (text.contains('which statement best aligns with:') ||
        opts.contains('It represents a core principle of') ||
        opts.contains('It contradicts the standard law') ||
        (text.startsWith('Briefly explain the concept and significance of: "') &&
            rub == 'Award 2 marks for accurate explanation and 1 mark for relevant textbook example.')) {
      return true;
    }

    return false;
  }

  /// Detects legacy dummy SLO statements
  static bool _isDummySlo(SloItem s) {
    final st = s.statement.trim();
    return st.contains('کے بنیادی تصورات اور تعریفات کو سمجھنا') ||
        st == 'اہم اصولوں کی وضاحت اور مثالوں سے اطلاق کرنا' ||
        st == 'تفصیلی سوالات اور عملی مسائل حل کرنا';
  }

  /// Cleans out any dummy questions from a bank; returns null if no authentic questions remain
  static ChapterBankDoc? cleanAndValidateBank(ChapterBankDoc? bank) {
    if (bank == null) return null;
    final validQuestions = bank.questions.where((q) => !isDummyOrCorruptedQuestion(q)).toList();
    if (validQuestions.isEmpty) {
      return null;
    }
    final validSlos = bank.slos.where((s) => !_isDummySlo(s)).toList();
    final cleanTitle = bank.chapterTitle.replaceAll(RegExp(r'\s*\(Urdu\)\s*', caseSensitive: false), '').trim();

    return bank.copyWith(
      chapterTitle: cleanTitle.isNotEmpty ? cleanTitle : bank.chapterTitle,
      slos: validSlos.isNotEmpty ? validSlos : bank.slos,
      questions: validQuestions,
    );
  }

  /// Purges a corrupted/dummy bank from local cache and Firestore
  static Future<void> purgeCorruptedBank(String docId) async {
    _memoryCache.remove(docId);
    try {
      await LocalDbService.saveCache('$_localBankKeyPrefix$docId', <String, dynamic>{});
    } catch (_) {}
    try {
      await _firestore.collection(collectionPath).doc(docId).delete().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// 0ms Synchronous lookup from RAM or Hive Offline Storage (with automatic dummy purge)
  static ChapterBankDoc? getChapterBankLocalSync(String docId) {
    if (_memoryCache.containsKey(docId)) {
      final cleaned = cleanAndValidateBank(_memoryCache[docId]);
      if (cleaned == null) {
        _memoryCache.remove(docId);
        return null;
      }
      return cleaned;
    }
    try {
      final raw = LocalDbService.getCache('$_localBankKeyPrefix$docId');
      if (raw is Map && raw.isNotEmpty) {
        final bank = ChapterBankDoc.fromJson(Map<String, dynamic>.from(raw));
        final cleaned = cleanAndValidateBank(bank);
        if (cleaned != null && cleaned.questions.isNotEmpty) {
          _memoryCache[docId] = cleaned;
          return cleaned;
        } else {
          // Purge poisoned local cache
          LocalDbService.saveCache('$_localBankKeyPrefix$docId', <String, dynamic>{});
        }
      }
    } catch (e) {
      debugPrint('⚠️ [SloRepository] Local cache read error ($docId): $e');
    }
    return null;
  }

  /// Saves a chapter bank to RAM + Hive Offline Storage immediately
  static Future<void> saveBankToLocalCache(ChapterBankDoc bank) async {
    final cleaned = cleanAndValidateBank(bank);
    if (cleaned == null) return;
    _memoryCache[cleaned.docId] = cleaned;
    try {
      await LocalDbService.saveCache('$_localBankKeyPrefix${cleaned.docId}', cleaned.toJson());
    } catch (e) {
      debugPrint('⚠️ [SloRepository] Local cache write error (${cleaned.docId}): $e');
    }
  }

  /// Fetches the chapter bank:
  /// 1. Returns instant local offline cache if available (unless [forceRemote] is true).
  /// 2. Falls back to Firestore cache -> Firestore server with short timeout so offline never hangs.
  static Future<ChapterBankDoc?> getChapterBank(String docId, {bool forceRemote = false}) async {
    final localBank = getChapterBankLocalSync(docId);
    if (localBank != null && !forceRemote) {
      // Trigger a silent non-blocking background refresh from Firestore
      _refreshBankInBackground(docId);
      return localBank;
    }

    // Try Firestore local persistence cache first for instant offline response
    if (!forceRemote) {
      try {
        final cacheSnap = await _firestore
            .collection(collectionPath)
            .doc(docId)
            .get(const GetOptions(source: Source.cache));
        if (cacheSnap.exists && cacheSnap.data() != null) {
          final cachedBank = cleanAndValidateBank(ChapterBankDoc.fromJson(cacheSnap.data()!));
          if (cachedBank != null && cachedBank.questions.isNotEmpty) {
            await saveBankToLocalCache(cachedBank);
            _refreshBankInBackground(docId);
            return cachedBank;
          }
        }
      } catch (_) {}
    }

    // Try server with a fast 3-second timeout so weak/offline internet never freezes UI
    try {
      final docSnap = await _firestore
          .collection(collectionPath)
          .doc(docId)
          .get()
          .timeout(const Duration(seconds: 3));
      if (!docSnap.exists || docSnap.data() == null) {
        return localBank;
      }
      final remoteBank = cleanAndValidateBank(ChapterBankDoc.fromJson(docSnap.data()!));
      if (remoteBank != null && remoteBank.questions.isNotEmpty) {
        await saveBankToLocalCache(remoteBank);
        return remoteBank;
      } else {
        // Remote doc was dummy/corrupted -> purge it
        purgeCorruptedBank(docId);
        return localBank;
      }
    } catch (e) {
      debugPrint('⚠️ [SloRepository] Offline or timeout fetching chapter bank ($docId): $e');
      return localBank;
    }
  }

  static Future<void> _refreshBankInBackground(String docId) async {
    try {
      final docSnap = await _firestore
          .collection(collectionPath)
          .doc(docId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 4));
      if (docSnap.exists && docSnap.data() != null) {
        final remoteBank = cleanAndValidateBank(ChapterBankDoc.fromJson(docSnap.data()!));
        if (remoteBank != null && remoteBank.questions.isNotEmpty) {
          await saveBankToLocalCache(remoteBank);
        }
      }
    } catch (_) {
      // Ignore background refresh errors when offline
    }
  }

  /// Saves or merges newly generated SLOs and questions into both Local Offline Cache and Firestore
  /// without duplicating existing questions. When [replaceExisting] is true (e.g. fresh AI scan),
  /// replaces old chapter bank cleanly.
  static Future<void> saveOrMergeChapterBank(
    ChapterBankDoc newDoc, {
    bool replaceExisting = false,
  }) async {
    final cleanedNew = cleanAndValidateBank(newDoc);
    if (cleanedNew == null) return;

    // 1. Update local bank immediately
    final existingLocal = replaceExisting ? null : getChapterBankLocalSync(cleanedNew.docId);
    if (existingLocal != null) {
      final mergedLocal = _mergeBanks(existingLocal, cleanedNew);
      await saveBankToLocalCache(mergedLocal);
    } else {
      await saveBankToLocalCache(cleanedNew);
    }

    try {
      final docRef = _firestore.collection(collectionPath).doc(cleanedNew.docId);
      if (replaceExisting) {
        await docRef.set(cleanedNew.toJson()).timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
        debugPrint('✅ [SloRepository] Replaced chapter bank with fresh AI scan: ${cleanedNew.docId}');
        return;
      }

      DocumentSnapshot<Map<String, dynamic>>? existingDoc;
      try {
        existingDoc = await docRef.get().timeout(const Duration(seconds: 4));
      } catch (_) {
        existingDoc = null;
      }

      if (existingDoc == null || !existingDoc.exists || existingDoc.data() == null) {
        final bankToSave = getChapterBankLocalSync(cleanedNew.docId) ?? cleanedNew;
        await docRef.set(bankToSave.toJson(), SetOptions(merge: true)).timeout(
          const Duration(seconds: 4),
          onTimeout: () {},
        );
        debugPrint('✅ [SloRepository] Saved chapter bank: ${cleanedNew.docId}');
        return;
      }

      final currentBank = cleanAndValidateBank(ChapterBankDoc.fromJson(existingDoc.data()!));
      final updatedBank = currentBank != null ? _mergeBanks(currentBank, cleanedNew) : cleanedNew;

      await saveBankToLocalCache(updatedBank);
      await docRef.set(updatedBank.toJson()).timeout(
        const Duration(seconds: 4),
        onTimeout: () {},
      );
      debugPrint('✅ [SloRepository] Merged into chapter bank: ${cleanedNew.docId}');
    } catch (e) {
      debugPrint('⚠️ [SloRepository] Saved locally, Firestore sync deferred: $e');
    }
  }

  static ChapterBankDoc _mergeBanks(ChapterBankDoc currentBank, ChapterBankDoc newDoc) {
    final Map<String, SloItem> mergedSlos = {
      for (var s in currentBank.slos) s.sloCode: s,
    };
    for (var s in newDoc.slos) {
      mergedSlos[s.sloCode] = s;
    }

    final Map<String, SloQuestion> mergedQuestions = {
      for (var q in currentBank.questions) q.questionText.trim().toLowerCase(): q,
    };
    for (var q in newDoc.questions) {
      mergedQuestions[q.questionText.trim().toLowerCase()] = q;
    }

    return currentBank.copyWith(
      chapterTitle: currentBank.chapterTitle.isNotEmpty
          ? currentBank.chapterTitle
          : newDoc.chapterTitle,
      slos: mergedSlos.values.toList(),
      questions: mergedQuestions.values.toList(),
      updatedAt: FieldValue.serverTimestamp(),
    );
  }

  /// Builds a customized question paper based on selected SLOs and blueprint ratios
  static List<SloQuestion> buildCustomPaperFromBank({
    required ChapterBankDoc bank,
    required Set<String> selectedSloCodes,
    required int mcqCount,
    required int shortCount,
    required int longCount,
    double knowledgeRatio = 0.30,
    double understandingRatio = 0.50,
    double applicationRatio = 0.20,
  }) {
    // 1. Filter by selected SLOs (or all if empty)
    final pool = bank.questions.where((q) {
      if (selectedSloCodes.isEmpty) return true;
      return selectedSloCodes.contains(q.sloCode);
    }).toList();

    // Separate by question type
    final mcqs = pool.where((q) => q.type == 'MCQ').toList()..shuffle();
    final shorts = pool.where((q) => q.type == 'SHORT').toList()..shuffle();
    final longs = pool.where((q) => q.type == 'LONG').toList()..shuffle();

    List<SloQuestion> selectedList = [];

    // Helper to pick questions respecting cognitive levels as much as possible
    List<SloQuestion> pickByCognitiveMix(List<SloQuestion> candidates, int targetCount) {
      if (candidates.length <= targetCount) return List.from(candidates);

      final kList = candidates.where((q) => q.cognitiveLevel == 'Knowledge').toList();
      final uList = candidates.where((q) => q.cognitiveLevel == 'Understanding').toList();
      final aList = candidates.where((q) => q.cognitiveLevel == 'Application').toList();

      int targetK = (targetCount * knowledgeRatio).round();
      int targetU = (targetCount * understandingRatio).round();
      int targetA = targetCount - targetK - targetU;
      if (targetA < 0) targetA = 0;

      final Set<SloQuestion> picked = {};

      void takeFrom(List<SloQuestion> src, int count) {
        for (var item in src) {
          if (picked.length >= targetCount) break;
          if (count <= 0) break;
          if (picked.add(item)) count--;
        }
      }

      takeFrom(kList, targetK);
      takeFrom(uList, targetU);
      takeFrom(aList, targetA);

      // If still need more, fill from remaining
      for (var item in candidates) {
        if (picked.length >= targetCount) break;
        picked.add(item);
      }

      return picked.toList();
    }

    selectedList.addAll(pickByCognitiveMix(mcqs, mcqCount));
    selectedList.addAll(pickByCognitiveMix(shorts, shortCount));
    selectedList.addAll(pickByCognitiveMix(longs, longCount));

    return selectedList;
  }

  /// 1-Click Swap: Swaps a single question with another unused question from the cache
  /// matching the same question type (MCQ, SHORT, LONG) without calling AI.
  static SloQuestion? swapQuestion({
    required SloQuestion currentQuestion,
    required ChapterBankDoc bank,
    required List<SloQuestion> currentlySelected,
    Set<String>? selectedSloCodes,
  }) {
    final selectedIds = currentlySelected.map((q) => q.id).toSet();

    // Look for candidates with same type and unused
    final candidates = bank.questions.where((q) {
      if (q.id == currentQuestion.id || selectedIds.contains(q.id)) return false;
      if (q.type != currentQuestion.type) return false;
      if (selectedSloCodes != null && selectedSloCodes.isNotEmpty) {
        return selectedSloCodes.contains(q.sloCode);
      }
      return true;
    }).toList();

    if (candidates.isEmpty) {
      // Relax SLO filter if no candidate with exact SLO was found
      final relaxedCandidates = bank.questions.where((q) {
        return q.id != currentQuestion.id &&
            !selectedIds.contains(q.id) &&
            q.type == currentQuestion.type;
      }).toList();

      if (relaxedCandidates.isEmpty) return null;
      relaxedCandidates.shuffle();
      return relaxedCandidates.first;
    }

    // Prefer candidates with the same cognitive level
    final sameCognitive = candidates
        .where((q) => q.cognitiveLevel == currentQuestion.cognitiveLevel)
        .toList();

    if (sameCognitive.isNotEmpty) {
      sameCognitive.shuffle();
      return sameCognitive.first;
    }

    candidates.shuffle();
    return candidates.first;
  }
}
