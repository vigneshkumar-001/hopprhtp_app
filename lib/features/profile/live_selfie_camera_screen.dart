import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show cos, pi, sin;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_sizes.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/feedback/app_snackbar.dart';

/// Live, in-app selfie capture for KYC — replaces the old flow (the device's
/// stock camera app via image_picker, which accepted literally any photo).
/// Runs on-device face detection against the live camera stream and only
/// enables the capture button once a single, well-centered, properly-sized
/// face is actually being seen — never lets a blank/miss-aimed/multi-person
/// shot through. Never uploads anything itself; on capture it just returns
/// the file path, same contract [TakeSelfieScreen] already had.
class LiveSelfieCameraScreen extends StatefulWidget {
  const LiveSelfieCameraScreen({super.key});

  @override
  State<LiveSelfieCameraScreen> createState() => _LiveSelfieCameraScreenState();
}

/// How well the current frame's single detected face matches what a usable
/// KYC selfie needs. Ordered roughly worst → best only for readability —
/// nothing here relies on ordinal comparison.
enum FaceFit { none, multiple, tooFar, tooClose, offCenter, good }

/// A face only counts as "good" when it's alone in frame, roughly centred,
/// and large enough to actually be a usable identity match — never just "a
/// face was detected somewhere". Tolerances are deliberately generous (this
/// is a live camera held by hand, not a scanner) — the goal is rejecting
/// genuinely unusable frames, not demanding pixel-perfect framing.
///
/// A free function (not a widget method) specifically so this geometry —
/// the actual accept/reject decision behind "can this be submitted" — is
/// unit-testable without a real camera or ML Kit's native Face type.
FaceFit classifyFaceFit({
  required int faceCount,
  required Rect? boundingBox,
  required int imageWidth,
  required int imageHeight,
}) {
  if (faceCount == 0) return FaceFit.none;
  if (faceCount > 1) return FaceFit.multiple;
  final box = boundingBox!;

  final imageArea = imageWidth * imageHeight;
  final faceAreaRatio = (box.width * box.height) / imageArea;

  final centerX = box.left + box.width / 2;
  final centerY = box.top + box.height / 2;
  final dxRatio = (centerX - imageWidth / 2).abs() / imageWidth;
  final dyRatio = (centerY - imageHeight / 2).abs() / imageHeight;
  if (dxRatio > 0.18 || dyRatio > 0.18) return FaceFit.offCenter;

  if (faceAreaRatio < 0.06) return FaceFit.tooFar;
  if (faceAreaRatio > 0.45) return FaceFit.tooClose;
  return FaceFit.good;
}

class _LiveSelfieCameraScreenState extends State<LiveSelfieCameraScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  CameraDescription? _frontCamera;
  late final FaceDetector _faceDetector;

  bool _initError = false;
  bool _isDetecting = false;
  bool _capturing = false;
  FaceFit _fit = FaceFit.none;

  /// A slow, continuous breathe — always running, but only ever drawn (see
  /// _buildCameraUi) while [_fit] is good. Left running rather than
  /// started/stopped on every fit change so there's no start-up frame lag
  /// right when the guide first turns green.
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  /// Drives the scanning light-band that sweeps the guide while a face
  /// hasn't locked in yet — always running (cheap, purely decorative), only
  /// ever faded in while [_fit] isn't good (see _buildCameraUi).
  late final AnimationController _scanController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  /// Plays forward once, from 0, the moment [_fit] becomes good — the filled
  /// arc drawn from its value is both the "hold still" feedback and the
  /// auto-capture countdown. Reset (not just stopped) the moment the face
  /// stops fitting well, so a hand wobble part-way through never leaves a
  /// stale partial ring behind on the next good frame.
  late final AnimationController _holdController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..addStatusListener((status) {
    if (status == AnimationStatus.completed &&
        _fit == FaceFit.good &&
        !_capturing) {
      _capture();
    }
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableTracking: false,
      ),
    );
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      _frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        _frontCamera!,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      await controller.startImageStream(_onFrame);
    } catch (_) {
      if (mounted) setState(() => _initError = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _faceDetector.close();
    _pulseController.dispose();
    _scanController.dispose();
    _holdController.dispose();
    super.dispose();
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_isDetecting || _capturing) return;
    _isDetecting = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await _faceDetector.processImage(input);
      final fit = classifyFaceFit(
        faceCount: faces.length,
        boundingBox: faces.isEmpty ? null : faces.first.boundingBox,
        imageWidth: image.width,
        imageHeight: image.height,
      );
      if (mounted && fit != _fit) {
        final wasGood = _fit == FaceFit.good;
        setState(() => _fit = fit);
        // One tick exactly on the good <-> not-good boundary — not on every
        // in-between change (offCenter -> tooClose etc. would otherwise
        // buzz continuously while the user adjusts).
        if (fit == FaceFit.good && !wasGood) {
          HapticFeedback.selectionClick();
          _holdController.forward(from: 0);
        } else if (wasGood && fit != FaceFit.good) {
          // Face moved out of frame mid-hold — cancel the countdown rather
          // than let it finish and auto-capture a frame that's no longer good.
          _holdController.stop();
          _holdController.value = 0;
        }
      }
    } catch (_) {
      // A single bad/unreadable frame is never fatal — just skip it, the
      // next frame tries again a moment later.
    } finally {
      _isDetecting = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final camera = _frontCamera;
    final controller = _controller;
    if (camera == null || controller == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      // Front camera sensors are mounted mirrored relative to back cameras —
      // rotation compensation adds (not subtracts) the device's own
      // orientation for a front lens, same as google_mlkit's own reference
      // camera-stream example.
      var rotationCompensation =
          _androidDeviceOrientationDegrees[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    // Only single-plane formats are supported here — matches the
    // ImageFormatGroup forced at CameraController construction (nv21 on
    // Android, bgra8888 on iOS), which always yields exactly one plane.
    if (format == null || image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _fit != FaceFit.good || _capturing) return;
    setState(() => _capturing = true);
    HapticFeedback.heavyImpact();
    try {
      await controller.stopImageStream();
      final file = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(file);
    } catch (_) {
      if (mounted) {
        AppSnackbar.error(
          context,
          'Could not capture the photo. Please try again.',
        );
        setState(() => _capturing = false);
      }
    }
  }

  String get _statusMessage {
    if (_capturing) return 'Capturing…';
    return switch (_fit) {
      FaceFit.none => 'Position your face in the frame',
      FaceFit.multiple => 'Only one person should be in frame',
      FaceFit.tooFar => 'Move a little closer',
      FaceFit.tooClose => 'Move back a little',
      FaceFit.offCenter => 'Center your face in the frame',
      FaceFit.good => 'Perfect — hold still, capturing automatically',
    };
  }

  Color get _guideColor => switch (_fit) {
    FaceFit.good => AppColors.success,
    FaceFit.none => Colors.white70,
    _ => AppColors.warning,
  };

  /// The single source of truth for where the oval sits — sized relative to
  /// the actual screen (not fixed pixels) so it comfortably frames a whole
  /// face (forehead to chin, ear to ear) on any device, and shared between
  /// the darkened mask and the drawn ring so the two can never drift out of
  /// sync with each other.
  Rect _ovalRect(Size screen) {
    final width = (screen.width * 0.82).clamp(260.0, 380.0);
    final height = width * 1.38;
    final center = Offset(screen.width / 2, screen.height * 0.4);
    return Rect.fromCenter(center: center, width: width, height: height);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _initError
            ? _PermissionOrErrorView(
                onRetry: () {
                  setState(() => _initError = false);
                  _init();
                },
              )
            : _controller == null || !_controller!.value.isInitialized
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : LayoutBuilder(
                builder: (context, constraints) => _buildCameraUi(
                  context,
                  Size(constraints.maxWidth, constraints.maxHeight),
                ),
              ),
      ),
    );
  }

  Widget _buildCameraUi(BuildContext context, Size screen) {
    final oval = _ovalRect(screen);
    final isGood = _fit == FaceFit.good;

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: 1 / _controller!.value.aspectRatio,
            child: CameraPreview(_controller!),
          ),
        ),
        // Darkens everything outside the oval guide so attention lands on
        // exactly where the face needs to go — a plain full-bleed preview
        // gives no sense of "where do I put my face".
        Positioned.fill(child: _OvalMask(oval: oval)),
        // Decorative facial-topology mesh — reads as a biometric face scan,
        // brightening the closer the live frame gets to "good".
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _FaceMeshPainter(
                oval: oval,
                color: _guideColor,
                opacity: switch (_fit) {
                  FaceFit.none => 0.28,
                  FaceFit.good => 0.85,
                  _ => 0.5,
                },
              ),
            ),
          ),
        ),
        // A light band that sweeps the guide while still searching for a
        // good frame — signals "actively scanning" — and fades out the
        // moment a good frame locks in, handing off to the hold ring below.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: isGood ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              child: AnimatedBuilder(
                animation: _scanController,
                builder: (context, _) => CustomPaint(
                  painter: _ScanSweepPainter(
                    oval: oval,
                    color: _guideColor,
                    progress: _scanController.value,
                  ),
                ),
              ),
            ),
          ),
        ),
        // The animated ring itself, plus a soft glow that only ever
        // breathes while the fit is genuinely good — the pulse conveys
        // "ready" the same way a modern Face-ID-style scanner does, instead
        // of a flat static border that just snaps between colors.
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            final pulse = isGood
                ? Curves.easeInOut.transform(_pulseController.value)
                : 0.0;
            return Positioned.fromRect(
              rect: oval.inflate(pulse * 6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(oval.width),
                  border: Border.all(color: _guideColor, width: isGood ? 4 : 3),
                  boxShadow: isGood
                      ? [
                          BoxShadow(
                            color: AppColors.success.withValues(
                              alpha: 0.25 + pulse * 0.25,
                            ),
                            blurRadius: 20 + pulse * 16,
                            spreadRadius: 1 + pulse * 3,
                          ),
                        ]
                      : const [],
                ),
              ),
            );
          },
        ),
        // Fills in around the ring the moment a good frame locks in — both
        // the "hold still" feedback and the auto-capture countdown, so the
        // user can see exactly how long they need to stay still.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _holdController,
              builder: (context, _) => CustomPaint(
                painter: _HoldRingPainter(
                  oval: oval,
                  progress: _holdController.value,
                ),
              ),
            ),
          ),
        ),
        // Corner scan brackets — the "locked onto a target" cue a
        // biometric-scan UI reads as, drawn just outside the guide.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final pulse = isGood
                    ? Curves.easeInOut.transform(_pulseController.value)
                    : 0.0;
                return CustomPaint(
                  painter: _CornerBracketsPainter(
                    oval: oval.inflate(6 + pulse * 3),
                    color: _guideColor,
                    opacity: _fit == FaceFit.none ? 0.55 : 1,
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          top: AppSizes.md,
          left: AppSizes.md,
          child: _CircleIconButton(
            icon: Icons.close_rounded,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          // Anchored to the bottom (like the capture button below it) rather
          // than hung off the oval's own bottom edge — the oval's height
          // varies with screen size, and a bottom anchor guarantees this
          // never creeps down into the capture button on a short screen.
          bottom: 132,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Padding(
              key: ValueKey(_statusMessage),
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isGood
                        ? Icons.check_circle_rounded
                        : Icons.face_retouching_natural_rounded,
                    size: 16,
                    color: _guideColor,
                  ),
                  const SizedBox(width: AppSizes.xs),
                  Flexible(
                    child: Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: AppText.bodyStrong.copyWith(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSizes.xl,
          child: Center(
            child: _CaptureButton(
              enabled: isGood && !_capturing,
              busy: _capturing,
              onTap: _capture,
            ),
          ),
        ),
      ],
    );
  }
}

/// Front-camera-relative rotation degrees per reported device orientation —
/// same lookup table google_mlkit_face_detection's own camera example uses.
const _androidDeviceOrientationDegrees = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

class _OvalMask extends StatelessWidget {
  const _OvalMask({required this.oval});
  final Rect oval;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(painter: _OvalMaskPainter(oval)));
  }
}

class _OvalMaskPainter extends CustomPainter {
  _OvalMaskPainter(this.oval);
  final Rect oval;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()
      ..addRRect(RRect.fromRectAndRadius(oval, Radius.circular(oval.width)));
    final masked = Path.combine(PathOperation.difference, overlay, hole);
    canvas.drawPath(
      masked,
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _OvalMaskPainter oldDelegate) =>
      oldDelegate.oval != oval;
}

/// Decorative facial-topology mesh (dots + connecting guide lines) drawn
/// inside the oval guide — evokes a biometric face scan the way KYC/Face-ID
/// style apps do. Purely cosmetic: the points are fixed proportions of
/// [oval], not the live detector's actual landmarks — the fast-mode
/// detector used here only returns a bounding box, and adding contour
/// tracking would cost real per-frame latency for a cosmetic effect only.
class _FaceMeshPainter extends CustomPainter {
  _FaceMeshPainter({
    required this.oval,
    required this.color,
    required this.opacity,
  });

  final Rect oval;
  final Color color;
  final double opacity;

  Offset _at(double fx, double fy) =>
      Offset(oval.left + fx * oval.width, oval.top + fy * oval.height);

  List<Offset> _arc(
    double cx,
    double cy,
    double rx,
    double ry,
    int count, {
    double startDeg = 0,
    double endDeg = 360,
  }) {
    final start = startDeg * pi / 180;
    final end = endDeg * pi / 180;
    return List.generate(count, (i) {
      final t = count == 1 ? 0.0 : i / (count - 1);
      final angle = start + (end - start) * t;
      return _at(cx + rx * cos(angle), cy + ry * sin(angle));
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final dotPaint = Paint()
      ..color = color.withValues(alpha: (opacity * 0.9).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = color.withValues(alpha: (opacity * 0.45).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    void polyline(List<Offset> points, {bool closed = false}) {
      if (points.length < 2) return;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      if (closed) path.close();
      canvas.drawPath(path, linePaint);
      for (final p in points) {
        canvas.drawCircle(p, 1.6, dotPaint);
      }
    }

    // Jawline hugs the oval's own boundary so it can never visually drift
    // from the ring drawn around it.
    polyline(_arc(0.5, 0.5, 0.5, 0.5, 13, startDeg: 200, endDeg: 340));

    // Vertical midline: forehead to chin.
    polyline([_at(0.5, 0.08), _at(0.5, 0.22), _at(0.5, 0.36)]);
    polyline([_at(0.5, 0.67), _at(0.5, 0.86), _at(0.5, 0.93)]);

    // Eyebrows.
    polyline([_at(0.26, 0.37), _at(0.32, 0.34), _at(0.38, 0.34), _at(0.43, 0.36)]);
    polyline([_at(0.74, 0.37), _at(0.68, 0.34), _at(0.62, 0.34), _at(0.57, 0.36)]);

    // Eyes — a closed loop plus a pupil dot.
    final leftEye = _arc(0.335, 0.45, 0.075, 0.032, 8);
    final rightEye = _arc(0.665, 0.45, 0.075, 0.032, 8);
    polyline(leftEye, closed: true);
    polyline(rightEye, closed: true);
    canvas.drawCircle(_at(0.335, 0.45), 1.8, dotPaint);
    canvas.drawCircle(_at(0.665, 0.45), 1.8, dotPaint);

    // Nose bridge to tip and wings.
    polyline([
      _at(0.5, 0.50),
      _at(0.5, 0.58),
      _at(0.46, 0.65),
      _at(0.5, 0.67),
      _at(0.54, 0.65),
    ]);

    // Cheeks.
    polyline([_at(0.20, 0.55), _at(0.19, 0.66), _at(0.21, 0.75)]);
    polyline([_at(0.80, 0.55), _at(0.81, 0.66), _at(0.79, 0.75)]);

    // Mouth outline.
    polyline(_arc(0.5, 0.80, 0.135, 0.04, 10), closed: true);

    // Triangulation connectors radiating from the nose tip — the
    // converging-lines look the reference face-scan UI has.
    final noseTip = _at(0.5, 0.67);
    for (final target in [
      _at(0.335, 0.45),
      _at(0.665, 0.45),
      _at(0.37, 0.80),
      _at(0.63, 0.80),
      _at(0.20, 0.66),
      _at(0.80, 0.66),
    ]) {
      canvas.drawLine(noseTip, target, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FaceMeshPainter oldDelegate) =>
      oldDelegate.oval != oval ||
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity;
}

/// A soft light band that sweeps top-to-bottom inside the oval guide,
/// clipped to its shape — reads as "actively scanning" while no good frame
/// has locked in yet (see the [AnimatedOpacity] wrapping this in
/// _buildCameraUi, which fades it out the instant [FaceFit.good] hits).
class _ScanSweepPainter extends CustomPainter {
  _ScanSweepPainter({
    required this.oval,
    required this.color,
    required this.progress,
  });

  final Rect oval;
  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipPath(
      Path()..addRRect(RRect.fromRectAndRadius(oval, Radius.circular(oval.width))),
    );
    final bandHeight = oval.height * 0.16;
    final y = oval.top + progress * (oval.height + bandHeight) - bandHeight;
    final band = Rect.fromLTWH(oval.left, y, oval.width, bandHeight);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.5),
          color.withValues(alpha: 0),
        ],
      ).createShader(band);
    canvas.drawRect(band, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScanSweepPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.oval != oval ||
      oldDelegate.color != color;
}

/// The bright arc that fills in around the oval guide as the "hold still"
/// countdown plays — full circle == the auto-capture is about to fire.
class _HoldRingPainter extends CustomPainter {
  _HoldRingPainter({required this.oval, required this.progress});

  final Rect oval;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(oval, -pi / 2, 2 * pi * progress, false, paint);
  }

  @override
  bool shouldRepaint(covariant _HoldRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.oval != oval;
}

/// Four L-shaped corner brackets around the guide's bounding box — the
/// "locked onto a target" cue a scanner-style UI reads as, independent of
/// the rounded guide curve itself.
class _CornerBracketsPainter extends CustomPainter {
  _CornerBracketsPainter({
    required this.oval,
    required this.color,
    required this.opacity,
  });

  final Rect oval;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final arm = oval.width * 0.14;

    void bracket(Offset corner, Offset dx, Offset dy) {
      canvas.drawLine(corner, corner + dx, paint);
      canvas.drawLine(corner, corner + dy, paint);
    }

    bracket(oval.topLeft, Offset(arm, 0), Offset(0, arm));
    bracket(oval.topRight, Offset(-arm, 0), Offset(0, arm));
    bracket(oval.bottomLeft, Offset(arm, 0), Offset(0, -arm));
    bracket(oval.bottomRight, Offset(-arm, 0), Offset(0, -arm));
  }

  @override
  bool shouldRepaint(covariant _CornerBracketsPainter oldDelegate) =>
      oldDelegate.oval != oval ||
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity;
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? Colors.white : Colors.white24,
          border: Border.all(
            color: enabled ? AppColors.success : Colors.white,
            width: 4,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.45),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(21),
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : null,
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _PermissionOrErrorView extends StatelessWidget {
  const _PermissionOrErrorView({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 48,
              color: Colors.white70,
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              'Could not access the camera. Please allow camera access in your device settings and try again.',
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSizes.lg),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Try again',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
