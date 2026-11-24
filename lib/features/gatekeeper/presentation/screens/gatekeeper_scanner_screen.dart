import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:teacher_mobile_app/core/providers/user_data_provider.dart';
import 'package:teacher_mobile_app/features/auth/auth_provider.dart';
import 'package:teacher_mobile_app/features/gatekeeper/services/gatekeeper_service.dart';

class GatekeeperScannerScreen extends ConsumerStatefulWidget {
  const GatekeeperScannerScreen({super.key});

  @override
  ConsumerState<GatekeeperScannerScreen> createState() => _GatekeeperScannerScreenState();
}

class _GatekeeperScannerScreenState extends ConsumerState<GatekeeperScannerScreen> {
  final GatekeeperService _service = GatekeeperService.instance;

  GateScanMode _scanMode = GateScanMode.entry;
  bool _useCamera = true; // true = Mobile Camera, false = USB / Bluetooth Scanner Gun
  bool _torchOn = false;
  bool _isSyncingCache = false;
  bool _isProcessingScan = false;
  bool _initializedSchool = false;

  // Cooldown map to prevent rapid-fire identical frames from camera
  String? _lastRawCode;
  DateTime? _lastScanAt;

  // Latest scan feedback card
  GateScanResult? _lastResult;
  Timer? _feedbackTimer;

  // Camera controller
  MobileScannerController? _cameraController;

  // USB / Bluetooth Hardware QR Gun input controller
  final TextEditingController _gunController = TextEditingController();
  final FocusNode _gunFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _initCameraController();
  }

  void _initCameraController() {
    _cameraController?.dispose();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _cameraController?.dispose();
    _gunController.dispose();
    _gunFocusNode.dispose();
    super.dispose();
  }

  Future<void> _ensureSchoolInitialized(String schoolId) async {
    if (_initializedSchool || schoolId.isEmpty) return;
    _initializedSchool = true;
    setState(() => _isSyncingCache = true);
    await _service.initForSchool(schoolId);
    if (mounted) {
      setState(() => _isSyncingCache = false);
    }
  }

  Future<void> _handleRefreshCache(String schoolId) async {
    if (_isSyncingCache || schoolId.isEmpty) return;
    setState(() => _isSyncingCache = true);
    final count = await _service.syncAllSchoolStudents(schoolId);
    final flushed = await _service.syncPendingQueue(schoolId);
    if (mounted) {
      setState(() => _isSyncingCache = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            flushed > 0
                ? 'Synced $count students & uploaded $flushed pending scan(s).'
                : 'Cache updated: $count students ready for offline scanning.',
          ),
          backgroundColor: const Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onCodeCaptured(
    String rawCode, {
    required String schoolId,
    required String gatekeeperId,
    required String gatekeeperName,
  }) async {
    final trimmed = rawCode.trim();
    if (trimmed.isEmpty || _isProcessingScan || schoolId.isEmpty) return;

    // 2.5-second debounce for identical QR code in camera view
    final now = DateTime.now();
    if (_lastRawCode == trimmed &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!).inMilliseconds < 2500) {
      return;
    }

    _lastRawCode = trimmed;
    _lastScanAt = now;
    _isProcessingScan = true;

    try {
      final result = await _service.processGateScan(
        rawQr: trimmed,
        currentSchoolId: schoolId,
        mode: _scanMode,
        gatekeeperId: gatekeeperId,
        gatekeeperName: gatekeeperName,
      );

      // Instant tactile + audio feedback
      if (result.outcome == GateScanOutcome.successOnline ||
          result.outcome == GateScanOutcome.successOfflineQueued) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
      } else {
        HapticFeedback.heavyImpact();
      }

      if (mounted) {
        setState(() => _lastResult = result);
        _feedbackTimer?.cancel();
        _feedbackTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() => _lastResult = null);
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ [GatekeeperScreen] Scan processing error: $e');
    } finally {
      _isProcessingScan = false;
      if (!_useCamera && mounted) {
        _gunController.clear();
        _gunFocusNode.requestFocus();
      }
    }
  }

  Future<void> _confirmLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout Gatekeeper?'),
        content: const Text(
          'Any pending offline scans will stay saved until synced. Are you sure you want to logout?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(authControllerProvider.notifier).signOut();
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final teacherData = ref.watch(teacherDataProvider).value;
    final schoolData = ref.watch(schoolDataProvider).value;
    final authUser = ref.watch(currentUserProvider);

    final String schoolId = teacherData?['schoolId']?.toString() ?? '';
    final String gatekeeperId = authUser?.uid ?? teacherData?['uid']?.toString() ?? '';
    final String gatekeeperName = teacherData?['name']?.toString() ?? 'Gatekeeper';
    final String schoolName = schoolData?['name']?.toString() ?? 'School Gate Scanner';

    if (schoolId.isNotEmpty && !_initializedSchool) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureSchoolInitialized(schoolId);
      });
    }

    final isEntry = _scanMode == GateScanMode.entry;
    final modeColor = isEntry ? const Color(0xFF059669) : const Color(0xFFDC2626);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 14,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              schoolName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                const Icon(Icons.verified_user, size: 12, color: Color(0xFF34D399)),
                const SizedBox(width: 4),
                Text(
                  'Gatekeeper • $gatekeeperName',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Online / Offline indicator
          ValueListenableBuilder<bool>(
            valueListenable: _service.isOnlineNotifier,
            builder: (_, online, __) => Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: online
                    ? const Color(0xFF059669).withValues(alpha: 0.2)
                    : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: online ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    online ? Icons.wifi : Icons.wifi_off,
                    size: 13,
                    color: online ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    online ? 'ONLINE' : 'OFFLINE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: online ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sync Student Cache & Pending Scans',
            onPressed: _isSyncingCache ? null : () => _handleRefreshCache(schoolId),
            icon: _isSyncingCache
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout, color: Color(0xFFF87171)),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Entry / Exit Mode Toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: _ModeToggleButton(
                    label: 'ENTRY (IN)',
                    icon: Icons.login_rounded,
                    active: isEntry,
                    activeColor: const Color(0xFF059669),
                    onTap: () => setState(() {
                      _scanMode = GateScanMode.entry;
                      _lastRawCode = null;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ModeToggleButton(
                    label: 'EXIT (OUT)',
                    icon: Icons.logout_rounded,
                    active: !isEntry,
                    activeColor: const Color(0xFFDC2626),
                    onTap: () => setState(() {
                      _scanMode = GateScanMode.exit;
                      _lastRawCode = null;
                    }),
                  ),
                ),
              ],
            ),
          ),

          // 2. Scanner Input Mode Switch (Mobile Camera vs USB / Bluetooth Gun)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (!_useCamera) {
                          setState(() => _useCamera = true);
                          _initCameraController();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _useCamera ? const Color(0xFF4F46E5) : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.qr_code_scanner, size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'Mobile Camera',
                              style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_useCamera) {
                          _cameraController?.dispose();
                          _cameraController = null;
                          setState(() {
                            _useCamera = false;
                            _torchOn = false;
                          });
                          Future.delayed(const Duration(milliseconds: 100), () {
                            if (mounted) _gunFocusNode.requestFocus();
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !_useCamera ? const Color(0xFF4F46E5) : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.usb_rounded, size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text(
                              'USB / BT Scanner Gun',
                              style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // 3. Main Scanner Area (Camera OR USB/BT Gun)
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_useCamera && _cameraController != null)
                      MobileScanner(
                        controller: _cameraController!,
                        onDetect: (capture) {
                          for (final barcode in capture.barcodes) {
                            final raw = barcode.rawValue;
                            if (raw != null && raw.isNotEmpty) {
                              _onCodeCaptured(
                                raw,
                                schoolId: schoolId,
                                gatekeeperId: gatekeeperId,
                                gatekeeperName: gatekeeperName,
                              );
                              break;
                            }
                          }
                        },
                      )
                    else
                      _buildHardwareGunPanel(
                        schoolId: schoolId,
                        gatekeeperId: gatekeeperId,
                        gatekeeperName: gatekeeperName,
                        modeColor: modeColor,
                      ),

                    // Viewfinder Frame Overlay (Camera mode)
                    if (_useCamera)
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: modeColor, width: 3.5),
                              boxShadow: [
                                BoxShadow(
                                  color: modeColor.withValues(alpha: 0.25),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Camera Controls (Torch + Flip)
                    if (_useCamera && _cameraController != null)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Column(
                          children: [
                            _CircleIconBtn(
                              icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                              onTap: () {
                                _cameraController?.toggleTorch();
                                setState(() => _torchOn = !_torchOn);
                              },
                            ),
                            const SizedBox(height: 8),
                            _CircleIconBtn(
                              icon: Icons.cameraswitch_rounded,
                              onTap: () => _cameraController?.switchCamera(),
                            ),
                          ],
                        ),
                      ),

                    // Live Student Verification Banner Overlay
                    if (_lastResult != null)
                      Positioned(
                        left: 10,
                        right: 10,
                        bottom: 10,
                        child: _ScanFeedbackCard(result: _lastResult!),
                      ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // 4. Stats Strip (Cached Students + Pending Sync)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _service.cachedStudentsCount,
                    builder: (_, count, __) => _MiniStatPill(
                      icon: Icons.storage_rounded,
                      label: '$count Cached',
                      color: const Color(0xFF818CF8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                    valueListenable: _service.recentScansNotifier,
                    builder: (_, logs, __) => _MiniStatPill(
                      icon: Icons.fact_check_rounded,
                      label: '${logs.length} Today',
                      color: const Color(0xFF34D399),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _service.pendingQueueCount,
                    builder: (_, pending, __) => GestureDetector(
                      onTap: () => _service.syncPendingQueue(schoolId),
                      child: _MiniStatPill(
                        icon: pending > 0 ? Icons.cloud_upload : Icons.cloud_done,
                        label: pending > 0 ? '$pending Pending' : 'All Synced',
                        color: pending > 0 ? const Color(0xFFFBBF24) : const Color(0xFF38BDF8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 5. Recent Scans Log List
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Text(
                      "TODAY'S GATE LOG",
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                      valueListenable: _service.recentScansNotifier,
                      builder: (_, logs, __) {
                        if (logs.isEmpty) {
                          return const Center(
                            child: Text(
                              'Ready to scan Student ID Cards...',
                              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                          itemCount: logs.length,
                          separatorBuilder: (_, __) => const Divider(color: Color(0xFF334155), height: 1),
                          itemBuilder: (_, idx) {
                            final item = logs[idx];
                            final isIn = item['mode'] == 'entry';
                            final synced = item['synced'] == true;
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: isIn
                                    ? const Color(0xFF059669).withValues(alpha: 0.2)
                                    : const Color(0xFFDC2626).withValues(alpha: 0.2),
                                child: Icon(
                                  isIn ? Icons.login_rounded : Icons.logout_rounded,
                                  size: 18,
                                  color: isIn ? const Color(0xFF34D399) : const Color(0xFFF87171),
                                ),
                              ),
                              title: Text(
                                item['studentName']?.toString() ?? 'Student',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${item['className'] ?? ''} • Roll: ${item['rollNo'] ?? '—'}',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    item['timeFormatted']?.toString() ?? '',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        synced ? Icons.cloud_done : Icons.schedule,
                                        size: 12,
                                        color: synced ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        synced ? 'Notified' : 'Queued',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: synced ? const Color(0xFF34D399) : const Color(0xFFFBBF24),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Dedicated ultra-fast Hardware USB OTG / Bluetooth 2D QR Scanner Gun Panel
  Widget _buildHardwareGunPanel({
    required String schoolId,
    required String gatekeeperId,
    required String gatekeeperName,
    required Color modeColor,
  }) {
    return GestureDetector(
      onTap: () => _gunFocusNode.requestFocus(),
      child: Container(
        color: const Color(0xFF1E293B),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: modeColor.withValues(alpha: 0.16),
                border: Border.all(color: modeColor, width: 2),
              ),
              child: Icon(Icons.usb_rounded, size: 44, color: modeColor),
            ),
            const SizedBox(height: 14),
            const Text(
              'USB / Bluetooth QR Gun Ready',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            const Text(
              'Point your 2D QR Scanner Gun at the Student ID Card.\nScans are processed instantly even offline.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _gunController,
              focusNode: _gunFocusNode,
              autofocus: true,
              keyboardType: TextInputType.none, // Keeps Android soft keyboard hidden for USB/BT gun!
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Waiting for scanner gun input...',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                prefixIcon: Icon(Icons.qr_code_2, color: modeColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: modeColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: modeColor.withValues(alpha: 0.5)),
                ),
              ),
              onSubmitted: (value) {
                _onCodeCaptured(
                  value,
                  schoolId: schoolId,
                  gatekeeperId: gatekeeperId,
                  gatekeeperName: gatekeeperName,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _ModeToggleButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? activeColor : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: active ? activeColor : const Color(0xFF334155),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _MiniStatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MiniStatPill({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFeedbackCard extends StatelessWidget {
  final GateScanResult result;

  const _ScanFeedbackCard({required this.result});

  @override
  Widget build(BuildContext context) {
    Color bg;
    IconData icon;
    switch (result.outcome) {
      case GateScanOutcome.successOnline:
        bg = result.mode == GateScanMode.entry ? const Color(0xFF059669) : const Color(0xFF0284C7);
        icon = Icons.check_circle_rounded;
        break;
      case GateScanOutcome.successOfflineQueued:
        bg = const Color(0xFF4F46E5);
        icon = Icons.offline_pin_rounded;
        break;
      case GateScanOutcome.alreadyScanned:
        bg = const Color(0xFFD97706);
        icon = Icons.info_rounded;
        break;
      default:
        bg = const Color(0xFFDC2626);
        icon = Icons.error_rounded;
    }

    final st = result.student;
    final photo = st?['photo']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          if (st != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: photo.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photo,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _avatarFallback(st['name']?.toString() ?? 'S'),
                    )
                  : _avatarFallback(st['name']?.toString() ?? 'S'),
            )
          else
            Icon(icon, color: Colors.white, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (st != null)
                  Text(
                    '${st['name']} (${st['className'] ?? ''})',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  result.message,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12.5),
                ),
                if (result.timeFormatted != null)
                  Text(
                    'Time: ${result.timeFormatted}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          Icon(icon, color: Colors.white, size: 28),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name) {
    return Container(
      width: 50,
      height: 50,
      color: Colors.white24,
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'S',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20),
      ),
    );
  }
}
