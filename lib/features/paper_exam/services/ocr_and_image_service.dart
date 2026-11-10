import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class ExtractedBookContent {
  final String text;
  final List<Uint8List> compressedImages;
  final int pageCount;

  const ExtractedBookContent({
    required this.text,
    required this.compressedImages,
    required this.pageCount,
  });

  bool get isEmpty => text.trim().isEmpty && compressedImages.isEmpty;
  bool get hasText => text.trim().isNotEmpty;
  bool get hasImages => compressedImages.isNotEmpty;
}

class OcrAndImageService {
  final ImagePicker _picker = ImagePicker();

  Future<XFile?> pickSinglePage({required ImageSource source}) async {
    try {
      return await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
    } catch (e) {
      debugPrint('⚠️ Error capturing page: $e');
      return null;
    }
  }

  /// Processes multiple pages (from camera loop or multi-image gallery pick).
  /// Runs on-device OCR for English/Science/Math.
  /// Compresses images for RTL subjects (Urdu/Islamiyat) or when OCR text < 50 characters.
  Future<ExtractedBookContent> captureAndProcessPages({
    required bool isRtlSubject,
    ImageSource source = ImageSource.camera,
    List<XFile>? preCapturedFiles,
  }) async {
    List<XFile> pickedFiles = preCapturedFiles ?? [];

    if (pickedFiles.isEmpty) {
      if (source == ImageSource.gallery) {
        // Pick multiple from gallery
        try {
          pickedFiles = await _picker.pickMultiImage(
            maxWidth: 1600,
            maxHeight: 1600,
            imageQuality: 85,
          );
        } catch (e) {
          debugPrint('⚠️ Error picking multiple images: $e');
          final single = await _picker.pickImage(source: ImageSource.gallery);
          if (single != null) pickedFiles = [single];
        }
      } else {
        // Single Camera capture
        final single = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 85,
        );
        if (single != null) pickedFiles = [single];
      }
    }

    if (pickedFiles.isEmpty) {
      return const ExtractedBookContent(text: '', compressedImages: [], pageCount: 0);
    }

    final StringBuffer fullExtractedText = StringBuffer();
    final List<Uint8List> compressedImages = [];

    TextRecognizer? textRecognizer;
    if (!isRtlSubject) {
      try {
        textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      } catch (e) {
        debugPrint('⚠️ TextRecognizer init error: $e');
      }
    }

    try {
      for (final file in pickedFiles) {
        final filePath = file.path;
        final fileObj = File(filePath);

        if (!isRtlSubject && textRecognizer != null) {
          // Free On-Device OCR First
          try {
            final inputImage = InputImage.fromFilePath(filePath);
            final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
            final pageText = recognizedText.text.trim();

            if (pageText.length >= 50) {
              fullExtractedText.writeln(pageText);
              fullExtractedText.writeln('\n--- PAGE BREAK ---\n');
            } else {
              // OCR text is too short (< 50 chars), fallback to compressed image for this page
              final compressedBytes = await _compressImageFile(fileObj);
              if (compressedBytes != null) {
                compressedImages.add(compressedBytes);
              }
            }
          } catch (e) {
            debugPrint('⚠️ ML Kit OCR error on $filePath: $e');
            // Graceful fallback to compressed image
            final compressedBytes = await _compressImageFile(fileObj);
            if (compressedBytes != null) {
              compressedImages.add(compressedBytes);
            }
          }
        } else {
          // RTL Subject (Urdu, Islamiyat, Arabic) -> Direct compressed image to Gemini
          final compressedBytes = await _compressImageFile(fileObj);
          if (compressedBytes != null) {
            compressedImages.add(compressedBytes);
          }
        }

        // Clean up temporary image file immediately to save device storage
        try {
          if (await fileObj.exists()) {
            await fileObj.delete();
          }
        } catch (e) {
          debugPrint('⚠️ Could not delete temp file: $e');
        }
      }
    } finally {
      textRecognizer?.close();
    }

    return ExtractedBookContent(
      text: fullExtractedText.toString().trim(),
      compressedImages: compressedImages,
      pageCount: pickedFiles.length,
    );
  }

  /// Compress image file to max 1024px width with 65% quality
  Future<Uint8List?> _compressImageFile(File file) async {
    try {
      final result = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 1024,
        minHeight: 1024,
        quality: 65,
        format: CompressFormat.jpeg,
      );
      if (result != null) return result;
    } catch (e) {
      debugPrint('⚠️ FlutterImageCompress failed: $e, falling back to raw bytes');
    }

    // Fallback: Read raw bytes if native compressor fails
    try {
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to read file bytes: $e');
    }
    return null;
  }
}
