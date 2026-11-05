import 'package:flutter/material.dart';
import 'package:teacher_mobile_app/features/timetable/providers/timetable_provider.dart';

class ClassCard extends StatefulWidget {
  final Map<String, dynamic> cls;
  final List<TimetableSlot> assignedSlots;
  final VoidCallback onTap;

  const ClassCard({
    Key? key,
    required this.cls,
    this.assignedSlots = const [],
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
    final className = widget.cls['name']?.toString() ?? 'Unknown Class';
    final periodCount = widget.assignedSlots.length;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
            ),
            boxShadow: isLight
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(_isPressed ? 0.04 : 0.06),
                      blurRadius: _isPressed ? 8 : 16,
                      offset: _isPressed ? const Offset(0, 2) : const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Class Icon, Class Name, Period Count Badge, Chevron
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF10B981).withOpacity(0.25), const Color(0xFF059669).withOpacity(0.25)]
                            : [const Color(0xFFECFDF5), const Color(0xFFD1FAE5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.school_rounded,
                      color: Color(0xFF059669),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          className,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          periodCount == 1 ? "1 Period Assigned" : "$periodCount Periods Assigned",
                          style: TextStyle(
                            color: isDark ? const Color(0xFF10B981) : const Color(0xFF059669),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  ),
                ],
              ),

              // Assigned Period Details Breakdown
              if (widget.assignedSlots.isNotEmpty) ...[
                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                ),
                const SizedBox(height: 12),

                // Assigned Period Items
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.assignedSlots.map((slot) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.07) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              slot.period.isNotEmpty ? slot.period : 'Period',
                              style: const TextStyle(
                                color: Color(0xFF059669),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            slot.subject.isNotEmpty ? slot.subject : 'Subject',
                            style: TextStyle(
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          if (slot.time.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              "•",
                              style: TextStyle(
                                color: isDark ? Colors.white38 : Colors.grey[400],
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.access_time_rounded,
                              size: 11,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                            ),
                            const SizedBox(width: 3),
                            Text(
                              slot.time,
                              style: TextStyle(
                                color: isDark ? Colors.white70 : Colors.grey[700],
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
