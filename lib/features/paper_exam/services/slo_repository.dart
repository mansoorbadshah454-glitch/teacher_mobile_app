import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:teacher_mobile_app/features/paper_exam/models/slo_paper_models.dart';

class SloRepository {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String collectionPath = 'global_slo_chapter_banks';

  /// 1 Read: Fetches the entire chapter bank from Firestore
  static Future<ChapterBankDoc?> getChapterBank(String docId) async {
    try {
      final docSnap = await _firestore.collection(collectionPath).doc(docId).get();
      if (!docSnap.exists || docSnap.data() == null) {
        return null;
      }
      return ChapterBankDoc.fromJson(docSnap.data()!);
    } catch (e) {
      debugPrint('⚠️ Error fetching chapter bank ($docId): $e');
      return null;
    }
  }

  /// Saves or merges newly generated SLOs and questions into the single Firestore document
  /// without duplicating existing questions.
  static Future<void> saveOrMergeChapterBank(ChapterBankDoc newDoc) async {
    try {
      final docRef = _firestore.collection(collectionPath).doc(newDoc.docId);
      final existingDoc = await docRef.get();

      if (!existingDoc.exists || existingDoc.data() == null) {
        // Document does not exist yet -> Write fresh
        await docRef.set(newDoc.toJson());
        debugPrint('✅ [SloRepository] Created new chapter bank: ${newDoc.docId}');
        return;
      }

      // Merge with existing
      final currentBank = ChapterBankDoc.fromJson(existingDoc.data()!);

      // Merge SLOs (by sloCode)
      final Map<String, SloItem> mergedSlos = {
        for (var s in currentBank.slos) s.sloCode: s,
      };
      for (var s in newDoc.slos) {
        mergedSlos[s.sloCode] = s;
      }

      // Merge Questions (by id or normalized question text)
      final Map<String, SloQuestion> mergedQuestions = {
        for (var q in currentBank.questions) q.questionText.trim().toLowerCase(): q,
      };
      for (var q in newDoc.questions) {
        mergedQuestions[q.questionText.trim().toLowerCase()] = q;
      }

      final updatedBank = currentBank.copyWith(
        chapterTitle: currentBank.chapterTitle.isNotEmpty
            ? currentBank.chapterTitle
            : newDoc.chapterTitle,
        slos: mergedSlos.values.toList(),
        questions: mergedQuestions.values.toList(),
        updatedAt: FieldValue.serverTimestamp(),
      );

      await docRef.set(updatedBank.toJson(), SetOptions(merge: true));
      debugPrint('✅ [SloRepository] Merged into chapter bank: ${newDoc.docId}');
    } catch (e) {
      debugPrint('⚠️ Error saving chapter bank: $e');
      rethrow;
    }
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
