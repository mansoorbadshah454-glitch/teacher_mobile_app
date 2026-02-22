import 'package:flutter/material.dart';
import 'package:teacher_mobile_app/core/theme/app_theme.dart';

class ClassCard extends StatefulWidget {
  final Map<String, dynamic> cls;
  final VoidCallback onTap;

  const ClassCard({
    Key? key,
    required this.cls,
    required this.onTap,
  }) : super(key: key);

  @override
  State<ClassCard> createState() => _ClassCardState();
}

class _ClassCardState extends State<ClassCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final isDark = !isLight;
    final subjectCount = (widget.cls['subjects'] as List<dynamic>? ?? []).length;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
            ),
            boxShadow: isLight
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(_isPressed ? 0.08 : 0.12),
                      blurRadius: _isPressed ? 12 : 24,
                      offset: _isPressed ? const Offset(0, 4) : const Offset(0, 8),
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isLight ? Colors.indigoAccent.withOpacity(0.1) : AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.people, color: isLight ? Colors.indigoAccent : AppTheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                widget.cls['name'] ?? 'Unknown Class',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.indigo[900],
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "$subjectCount Subjects",
                  style: TextStyle(
                    color: isDark ? Colors.grey : Colors.grey[600],
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
