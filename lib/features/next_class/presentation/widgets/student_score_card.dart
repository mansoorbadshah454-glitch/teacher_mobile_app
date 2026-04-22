import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/next_class_provider.dart';

class StudentScoreCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> student;
  final bool isTestMode;
  
  // Normal Mode Params
  final int? academicScore;
  final int? homeworkScore;
  final Function(String, String, int)? onScoreChanged;

  // Test Mode Params
  final int? testScore;
  final Function(String, int)? onTestScoreChanged;

  const StudentScoreCard({
    Key? key,
    required this.student,
    this.isTestMode = false,
    this.academicScore,
    this.homeworkScore,
    this.onScoreChanged,
    this.testScore,
    this.onTestScoreChanged,
  }) : super(key: key);

  @override
  ConsumerState<StudentScoreCard> createState() => _StudentScoreCardState();
}

class _StudentScoreCardState extends ConsumerState<StudentScoreCard> {
  bool _isUploadingCard = false;

  Color _getScoreColor(int score) {
    if (score >= 80) return const Color(0xFF10B981); // emerald-500
    if (score >= 50) return const Color(0xFFF59E0B); // amber-500
    return const Color(0xFFEF4444); // red-500
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.student;
    final name = student['name'] ?? 'Unknown';
    final rollNo = student['rollNo']?.toString() ?? 'N/A';
    final profilePic = student['profilePic'];

    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? Colors.transparent : Colors.black.withOpacity(0.05)),
        boxShadow: isLight ? [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))] : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar, Name, Roll No
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? const Color(0xFF334155) : Colors.indigo[50]!, // slate-700 or light indigo
                ),
                clipBehavior: Clip.hardEdge,
                child: profilePic != null && profilePic.isNotEmpty
                    ? Image.network(profilePic, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(Icons.person, color: isDark ? Colors.white : Colors.indigo[200]))
                    : Icon(Icons.person, color: isDark ? Colors.white : Colors.indigo[200]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.indigo[900],
                      ),
                    ),
                    Text(
                      "Roll No: $rollNo",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sliders based on mode
          if (widget.isTestMode)
            _buildSlider(
              context: context,
              label: "Test Score",
              value: widget.testScore ?? 0,
              onChanged: (val) {
                if (widget.onTestScoreChanged != null) {
                  widget.onTestScoreChanged!(student['id'], val.toInt());
                }
              },
            )
          else ...[
            _buildSlider(
              context: context,
              label: "Subject Score",
              value: widget.academicScore ?? 0,
              onChanged: (val) {
                if (widget.onScoreChanged != null) {
                  widget.onScoreChanged!(student['id'], 'academic', val.toInt());
                }
              },
            ),
            const SizedBox(height: 12),
            _buildSlider(
              context: context,
              label: "Homework Score",
              value: widget.homeworkScore ?? 0,
              onChanged: (val) {
                if (widget.onScoreChanged != null) {
                  widget.onScoreChanged!(student['id'], 'homework', val.toInt());
                }
              },
            ),
          ],
          
          const SizedBox(height: 16),
          // Upload Result UI
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withOpacity(0.2) : Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (student['resultCardUrl'] != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isLight ? Colors.greenAccent : Colors.green).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: (isLight ? Colors.greenAccent : Colors.green).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Result Uploaded: ${student['resultCardName'] ?? 'success.pdf'}",
                            style: TextStyle(color: isDark ? Colors.white : Colors.indigo[900], fontWeight: FontWeight.w500, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ElevatedButton.icon(
                  onPressed: _isUploadingCard ? null : () async {
                    try {
                      final fileResult = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                      );
                      if (fileResult != null && fileResult.files.single.path != null) {
                        setState(() => _isUploadingCard = true);
                        final filePath = fileResult.files.single.path!;
                        final fileName = fileResult.files.single.name;
                        
                        await ref.read(nextClassProvider.notifier).uploadResultCard(student['id'], filePath, fileName);
                        
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Result Card Uploaded Successfully!"), backgroundColor: Colors.green));
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload Error: $e"), backgroundColor: Colors.red));
                      }
                    } finally {
                      if (mounted) setState(() => _isUploadingCard = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isLight ? Colors.indigoAccent.withOpacity(0.1) : Colors.white.withOpacity(0.1),
                    foregroundColor: isLight ? Colors.indigoAccent : Colors.white,
                    elevation: 0,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isUploadingCard 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : const Icon(Icons.upload_file, size: 18),
                  label: Text(_isUploadingCard ? "Uploading..." : (student['resultCardUrl'] != null ? "Update Result Card" : "Upload Result Card"), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required BuildContext context,
    required String label,
    required int value,
    required ValueChanged<double> onChanged,
  }) {
    final activeColor = _getScoreColor(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark ? Colors.grey : Colors.grey[600],
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            Text(
              "$value%",
              style: TextStyle(
                color: activeColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: activeColor,
            inactiveTrackColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withOpacity(0.1) : Colors.grey[200],
            thumbColor: activeColor,
            trackHeight: 4.0,
            overlayColor: activeColor.withOpacity(0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
