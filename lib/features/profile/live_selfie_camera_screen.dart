import 'dart:async';
import 'dart:io' show Platform;
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
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _frontCamera;
  late final FaceDetector _faceDetector;

  bool _initError = false;
  bool _isDetecting = false;
  bool _capturing = false;
  FaceFit _fit = FaceFit.none;

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

  String get _statusMessage => switch (_fit) {
    FaceFit.none => 'Position your face in the oval',
    FaceFit.multiple => 'Only one person should be in frame',
    FaceFit.tooFar => 'Move a little closer',
    FaceFit.tooClose => 'Move back a little',
    FaceFit.offCenter => 'Center your face in the oval',
    FaceFit.good => 'Perfect — hold still and capture',
  };

  Color get _guideColor => switch (_fit) {
    FaceFit.good => AppColors.success,
    FaceFit.none => Colors.white54,
    _ => AppColors.warning,
  };

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
            : _buildCameraUi(context),
      ),
    );
  }

  Widget _buildCameraUi(BuildContext context) {
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
        const Positioned.fill(child: _OvalMask()),
        Positioned(
          top: AppSizes.md,
          left: AppSizes.md,
          child: _CircleIconButton(
            icon: Icons.close_rounded,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.08),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 260,
            height: 340,
            decoration: BoxDecoration(
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(160),
              border: Border.all(color: _guideColor, width: 3),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 140,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _statusMessage,
              key: ValueKey(_statusMessage),
              textAlign: TextAlign.center,
              style: AppText.bodyStrong.copyWith(color: Colors.white),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: AppSizes.xl,
          child: Center(
            child: _CaptureButton(
              enabled: _fit == FaceFit.good && !_capturing,
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
  const _OvalMask();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: CustomPaint(painter: _OvalMaskPainter()));
  }
}

class _OvalMaskPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final center = Offset(size.width / 2, size.height * 0.42);
    final hole = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: center, width: 260, height: 340),
          const Radius.circular(160),
        ),
      );
    final masked = Path.combine(PathOperation.difference, overlay, hole);
    canvas.drawPath(
      masked,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
        duration: const Duration(milliseconds: 220),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? Colors.white : Colors.white24,
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(20),
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
