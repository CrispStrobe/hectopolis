// SPDX-License-Identifier: AGPL-3.0-or-later
part of '../map_view.dart';

/// The still layer drawn once into an image, then shown as that image.
///
/// On the web there is no raster cache: a `RepaintBoundary` keeps a picture,
/// and CanvasKit replays every one of its draw calls in every frame the moving
/// layer above it changes. Replaying the still layer was a third of an idle
/// frame. An image costs one textured quad instead.
class _StillRaster extends StatefulWidget {
  const _StillRaster({required this.painter, required this.size});

  final _MapPainter painter;
  final Size size;

  @override
  State<_StillRaster> createState() => _StillRasterState();
}

class _StillRasterState extends State<_StillRaster> {
  ui.Image? _image;
  Object? _key;
  double _ratio = 0;

  /// Texture side limit; past it a zoomed-in map is upscaled slightly.
  static const _maxSide = 4096.0;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final painter = widget.painter;
    // The resolution steps in powers of 1.25, rounded up, so a pinch or a
    // wheel zoom re-rasterises when it crosses a step rather than on every
    // frame of the gesture; in between the image is scaled a little.
    final wanted = MediaQuery.devicePixelRatioOf(context) * painter.scale;
    final step = math.pow(1.25, (math.log(wanted) / math.log(1.25)).ceil());
    final ratio = math.min(step.toDouble(), _maxSide / size.longestSide);
    final key = (painter._stillKey, painter._lowDetail, size, ratio);
    if (key != _key || _image == null) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(ratio);
      painter.paint(canvas, size);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(
        (size.width * ratio).ceil(),
        (size.height * ratio).ceil(),
      );
      picture.dispose();
      _image?.dispose();
      _image = image;
      _key = key;
      _ratio = ratio;
    }
    return RawImage(
      image: _image,
      width: size.width,
      height: size.height,
      scale: _ratio,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }
}
