import 'package:escrow/features/profile/live_selfie_camera_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const imageWidth = 640;
  const imageHeight = 480;

  Rect centeredBox({required double widthFraction}) {
    final w = imageWidth * widthFraction;
    final h = w * 1.3; // roughly face-shaped, not a perfect square
    return Rect.fromCenter(
      center: const Offset(imageWidth / 2, imageHeight / 2),
      width: w,
      height: h,
    );
  }

  group('classifyFaceFit — the actual gate behind "can this be captured"', () {
    test('no face at all is never good', () {
      final fit = classifyFaceFit(
        faceCount: 0,
        boundingBox: null,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      expect(fit, FaceFit.none);
    });

    test(
      'more than one face in frame is refused, even if perfectly placed',
      () {
        final fit = classifyFaceFit(
          faceCount: 2,
          boundingBox: centeredBox(widthFraction: 0.3),
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        );
        expect(fit, FaceFit.multiple);
      },
    );

    test('a well-centered, reasonably-sized single face is good', () {
      final fit = classifyFaceFit(
        faceCount: 1,
        boundingBox: centeredBox(widthFraction: 0.3),
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      expect(fit, FaceFit.good);
    });

    test(
      'a tiny face (far from the camera) is tooFar, not silently accepted',
      () {
        final fit = classifyFaceFit(
          faceCount: 1,
          boundingBox: centeredBox(widthFraction: 0.08),
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        );
        expect(fit, FaceFit.tooFar);
      },
    );

    test('a huge face (right up against the lens) is tooClose', () {
      final fit = classifyFaceFit(
        faceCount: 1,
        boundingBox: centeredBox(widthFraction: 0.8),
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      expect(fit, FaceFit.tooClose);
    });

    test('a good-sized face pushed to the edge of frame is offCenter', () {
      final box = Rect.fromCenter(
        center: const Offset(imageWidth * 0.85, imageHeight / 2),
        width: imageWidth * 0.3,
        height: imageWidth * 0.3 * 1.3,
      );
      final fit = classifyFaceFit(
        faceCount: 1,
        boundingBox: box,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      expect(fit, FaceFit.offCenter);
    });

    test(
      'offCenter is checked before size, so a small AND off-center face reports offCenter',
      () {
        final box = Rect.fromCenter(
          center: const Offset(imageWidth * 0.9, imageHeight * 0.9),
          width: imageWidth * 0.05,
          height: imageWidth * 0.05 * 1.3,
        );
        final fit = classifyFaceFit(
          faceCount: 1,
          boundingBox: box,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        );
        expect(fit, FaceFit.offCenter);
      },
    );
  });
}
