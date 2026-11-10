class UrduReshaper {
  // Mapping table: [isolated, final, initial, medial]
  // If a character only has isolated and final (right-joining), initial and medial are empty.
  static final Map<int, List<int>> _glyphMap = {
    // Alef with madda
    0x0622: [0xFE81, 0xFE82, 0xFE81, 0xFE82],
    // Alef
    0x0627: [0xFE8D, 0xFE8E, 0xFE8D, 0xFE8E],
    // Bay
    0x0628: [0xFE8F, 0xFE90, 0xFE91, 0xFE92],
    // Pay (Urdu)
    0x067E: [0xFB56, 0xFB57, 0xFB58, 0xFB59],
    // Tay
    0x062A: [0xFE95, 0xFE96, 0xFE97, 0xFE98],
    // Ttay (Urdu)
    0x0679: [0xFB66, 0xFB67, 0xFB68, 0xFB69],
    // Say
    0x062B: [0xFE99, 0xFE9A, 0xFE9B, 0xFE9C],
    // Jeem
    0x062C: [0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0],
    // Chey (Urdu)
    0x0686: [0xFB7A, 0xFB7B, 0xFB7C, 0xFB7D],
    // Bari Hey
    0x062D: [0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4],
    // Khay
    0x062E: [0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8],
    // Daal
    0x062F: [0xFEA9, 0xFEAA, 0xFEA9, 0xFEAA],
    // Ddaal (Urdu)
    0x0688: [0xFB84, 0xFB85, 0xFB84, 0xFB85],
    // Zaal
    0x0630: [0xFEAB, 0xFEAC, 0xFEAB, 0xFEAC],
    // Ray
    0x0631: [0xFEAD, 0xFEAE, 0xFEAD, 0xFEAE],
    // Rray (Urdu)
    0x0691: [0xFB8C, 0xFB8D, 0xFB8C, 0xFB8D],
    // Zay
    0x0632: [0xFEAF, 0xFEB0, 0xFEAF, 0xFEB0],
    // Zzay (Urdu)
    0x0698: [0xFB8A, 0xFB8B, 0xFB8A, 0xFB8B],
    // Seen
    0x0633: [0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4],
    // Sheen
    0x0634: [0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8],
    // Swaad
    0x0635: [0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC],
    // Zwaad
    0x0636: [0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0],
    // Toye
    0x0637: [0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4],
    // Zoye
    0x0638: [0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8],
    // Ain
    0x0639: [0xFEC9, 0xFECA, 0xFECB, 0xFECC],
    // Ghain
    0x063A: [0xFECD, 0xFECE, 0xFECF, 0xFED0],
    // Fay
    0x0641: [0xFED1, 0xFED2, 0xFED3, 0xFED4],
    // Qaaf
    0x0642: [0xFED5, 0xFED6, 0xFED7, 0xFED8],
    // Kaaf
    0x0643: [0xFED9, 0xFEDA, 0xFEDB, 0xFEDC],
    0x06A9: [0xFED9, 0xFEDA, 0xFEDB, 0xFEDC], // Keheh (Urdu Kaaf)
    // Gaaf (Urdu)
    0x06AF: [0xFB92, 0xFB93, 0xFB94, 0xFB95],
    // Laam
    0x0644: [0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0],
    // Meem
    0x0645: [0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4],
    // Noon
    0x0646: [0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8],
    // Noon Ghunna (Urdu)
    0x06BA: [0xFB9E, 0xFB9F, 0xFB9E, 0xFB9F],
    // Wao
    0x0648: [0xFEED, 0xFEEE, 0xFEED, 0xFEEE],
    // Chhoti Hey / Goal Hey
    0x0647: [0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC],
    0x06C1: [0xFBAA, 0xFBAB, 0xFBAC, 0xFBAD], // Urdu Goal He
    // Do Chashmi Hey (Urdu)
    0x06BE: [0xFBAC, 0xFBAD, 0xFBAC, 0xFBAD],
    // Hamza
    0x0621: [0xFE80, 0xFE80, 0xFE80, 0xFE80],
    // Chhoti Yay
    0x064A: [0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4],
    0x06CC: [0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4], // Farsi/Urdu Yeh
    // Bari Yay (Urdu)
    0x06D2: [0xFBAE, 0xFBAF, 0xFBAE, 0xFBAF],
  };

  // Right-joining only characters (Cannot connect to the left/following character)
  static final Set<int> _rightJoinOnly = {
    0x0622, // Alef Madda
    0x0627, // Alef
    0x062F, // Daal
    0x0688, // Ddaal
    0x0630, // Zaal
    0x0631, // Ray
    0x0691, // Rray
    0x0632, // Zay
    0x0698, // Zzay
    0x0648, // Wao
    0x06BA, // Noon Ghunna
    0x06D2, // Bari Yay
    0x0621, // Hamza
  };

  /// Returns true if character is in Urdu / Arabic unicode range
  static bool isUrduChar(int codeUnit) {
    return (codeUnit >= 0x0600 && codeUnit <= 0x06FF) ||
           (codeUnit >= 0xFB50 && codeUnit <= 0xFDFF) ||
           (codeUnit >= 0xFE70 && codeUnit <= 0xFEFF);
  }

  /// Checks if any part of the text contains Urdu/Arabic
  static bool containsUrdu(String text) {
    for (int i = 0; i < text.length; i++) {
      if (isUrduChar(text.codeUnitAt(i))) return true;
    }
    return false;
  }

  /// Shapes and connects an individual Urdu word
  static String shapeWord(String word) {
    if (word.isEmpty) return word;

    final runes = word.runes.toList();
    final shaped = <int>[];
    final length = runes.length;

    for (int i = 0; i < length; i++) {
      final current = runes[i];

      // Handle Lam-Alef ligature (لا)
      if (current == 0x0644 && i + 1 < length && (runes[i + 1] == 0x0627 || runes[i + 1] == 0x0622)) {
        final isAlefMadda = runes[i + 1] == 0x0622;
        final bool prevCanConnect = i > 0 &&
            _glyphMap.containsKey(runes[i - 1]) &&
            !_rightJoinOnly.contains(runes[i - 1]);

        if (isAlefMadda) {
          shaped.add(prevCanConnect ? 0xFEF6 : 0xFEF5);
        } else {
          shaped.add(prevCanConnect ? 0xFEFC : 0xFEFB);
        }
        i++; // skip next alef
        continue;
      }

      final mapping = _glyphMap[current];
      if (mapping == null) {
        // Not an Arabic/Urdu shaped char, keep raw
        shaped.add(current);
        continue;
      }

      // Check connection with previous character
      final bool prevCanConnect = i > 0 &&
          _glyphMap.containsKey(runes[i - 1]) &&
          !_rightJoinOnly.contains(runes[i - 1]);

      // Check connection with next character
      final bool nextCanConnect = (i + 1 < length) &&
          _glyphMap.containsKey(runes[i + 1]) &&
          !_rightJoinOnly.contains(current);

      if (prevCanConnect && nextCanConnect) {
        // Medial
        shaped.add(mapping[3]);
      } else if (prevCanConnect && !nextCanConnect) {
        // Final
        shaped.add(mapping[1]);
      } else if (!prevCanConnect && nextCanConnect) {
        // Initial
        shaped.add(mapping[2]);
      } else {
        // Isolated
        shaped.add(mapping[0]);
      }
    }

    return String.fromCharCodes(shaped);
  }

  /// Reshapes Arabic/Urdu text by connecting characters with their cursive forms,
  /// preserving natural logical word order for rendering with [pw.TextDirection.rtl].
  static String shapeTextRtl(String text) {
    if (text.isEmpty || !containsUrdu(text)) return text;

    final lines = text.split('\n');
    final shapedLines = <String>[];

    for (final line in lines) {
      if (!containsUrdu(line)) {
        shapedLines.add(line);
        continue;
      }

      final words = line.split(' ');
      final shapedWords = words.map((w) {
        if (containsUrdu(w)) {
          return shapeWord(w);
        }
        return w;
      }).toList();

      shapedLines.add(shapedWords.join(' '));
    }

    return shapedLines.join('\n');
  }

  /// Backward-compatible alias for PDF shaping
  static String reshapeForPdf(String text) {
    return shapeTextRtl(text);
  }
}
