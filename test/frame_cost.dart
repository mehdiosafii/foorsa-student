// What one frame of a widget tree asks the GPU for, counted by painting the
// render tree through a canvas that forwards every call to a real one:
// offscreen layers, and blurs by the way Impeller has to draw them.
//
// A blur on a rectangle, a rounded rectangle, a circle, an oval or a convex
// path is drawn in one pass (Impeller's analytic shadows). A blur on any
// other path, or with a gradient, goes through an offscreen picture and two
// blur passes: a Gaussian here. (impeller/display_list/canvas.cc in the
// Flutter SDK: AttemptDrawBlur, AttemptDrawBlurredPathSource.)

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class FrameCost {
  /// Offscreen layers: saveLayer calls, and their area in points.
  int saveLayers = 0;
  double saveLayerArea = 0;

  /// Blurs drawn in one pass.
  int analyticBlurs = 0;

  /// Blurs drawn through an offscreen picture and two blur passes.
  int gaussianBlurs = 0;

  /// Pictures drawn as images (GlassBake's).
  int images = 0;

  @override
  String toString() => 'gaussian blurs $gaussianBlurs, analytic blurs '
      '$analyticBlurs, offscreen layers $saveLayers, images $images';
}

/// The cost of the frame [tester] last drew.
FrameCost frameCost(WidgetTester tester) {
  final cost = FrameCost();
  final root = tester.binding.renderViews.first.child!;
  root.paint(
      _CountingContext(
          cost, OffsetLayer(), Offset.zero & root.paintBounds.size),
      Offset.zero);
  return cost;
}

/// Paints every render object, repaint boundaries included, onto one
/// counting canvas.
class _CountingContext extends PaintingContext {
  _CountingContext(this.cost, ContainerLayer layer, Rect bounds)
      : _canvas = _CountingCanvas(Canvas(ui.PictureRecorder(), bounds), cost),
        super(layer, bounds);

  final FrameCost cost;
  final _CountingCanvas _canvas;

  @override
  Canvas get canvas => _canvas;

  @override
  void paintChild(RenderObject child, Offset offset) {
    // ignore: invalid_use_of_protected_member
    child.paint(this, offset);
  }

  @override
  PaintingContext createChildContext(ContainerLayer childLayer, Rect bounds) =>
      _CountingContext(cost, childLayer, bounds);

  @override
  void pushLayer(
      ContainerLayer childLayer, PaintingContextCallback painter, Offset offset,
      {Rect? childPaintBounds}) {
    // An opacity or a shader mask over composited children is an offscreen
    // layer too.
    if ((childLayer is OpacityLayer && (childLayer.alpha ?? 255) < 255) ||
        childLayer is ShaderMaskLayer ||
        childLayer is BackdropFilterLayer ||
        childLayer is ColorFilterLayer ||
        childLayer is ImageFilterLayer) {
      cost.saveLayers++;
    }
    painter(this, offset);
  }
}

class _CountingCanvas implements Canvas {
  _CountingCanvas(this._inner, this._cost);
  final Canvas _inner;
  final FrameCost _cost;

  void _blur(Paint paint, {Path? path}) {
    if (paint.maskFilter == null) return;
    if (path == null) {
      _cost.analyticBlurs++;
    } else if (paint.shader == null && _convex(path)) {
      _cost.analyticBlurs++;
    } else {
      _cost.gaussianBlurs++;
    }
  }

  static bool _convex(Path path) {
    final metrics = path.computeMetrics().toList();
    if (metrics.length != 1) return false;
    final m = metrics.single;
    final points = [
      for (var i = 0; i < 96; i++)
        m.getTangentForOffset(m.length * i / 96)!.position,
    ];
    var sign = 0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i],
          b = points[(i + 1) % points.length],
          c = points[(i + 2) % points.length];
      final turn =
          (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (turn.abs() < 1e-6) continue;
      final s = turn > 0 ? 1 : -1;
      if (sign == 0) sign = s;
      if (s != sign) return false;
    }
    return true;
  }

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    _cost.saveLayers++;
    final clip = _inner.getLocalClipBounds();
    final area = bounds == null ? clip : bounds.intersect(clip);
    if (!area.isEmpty) _cost.saveLayerArea += area.width * area.height;
    _inner.saveLayer(bounds, paint);
  }

  @override
  void drawPath(Path path, Paint paint) {
    _blur(paint, path: path);
    _inner.drawPath(path, paint);
  }

  @override
  void drawDRRect(RRect outer, RRect inner, Paint paint) {
    _blur(paint,
        path: Path()
          ..fillType = PathFillType.evenOdd
          ..addRRect(outer)
          ..addRRect(inner));
    _inner.drawDRRect(outer, inner, paint);
  }

  @override
  void drawRect(Rect rect, Paint paint) {
    _blur(paint);
    _inner.drawRect(rect, paint);
  }

  @override
  void drawRRect(RRect rrect, Paint paint) {
    _blur(paint);
    _inner.drawRRect(rrect, paint);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    _blur(paint);
    _inner.drawCircle(c, radius, paint);
  }

  @override
  void drawOval(Rect rect, Paint paint) {
    _blur(paint);
    _inner.drawOval(rect, paint);
  }

  @override
  void drawImageRect(ui.Image image, Rect src, Rect dst, Paint paint) {
    _cost.images++;
    _inner.drawImageRect(image, src, dst, paint);
  }

  // Everything else is forwarded as it is.

  @override
  void clipPath(Path path, {bool doAntiAlias = true}) =>
      _inner.clipPath(path, doAntiAlias: doAntiAlias);
  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) =>
      _inner.clipRRect(rrect, doAntiAlias: doAntiAlias);
  @override
  void clipRSuperellipse(ui.RSuperellipse rse, {bool doAntiAlias = true}) =>
      _inner.clipRSuperellipse(rse, doAntiAlias: doAntiAlias);
  @override
  void clipRect(Rect rect,
          {ui.ClipOp clipOp = ui.ClipOp.intersect, bool doAntiAlias = true}) =>
      _inner.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);
  @override
  void drawArc(Rect rect, double startAngle, double sweepAngle, bool useCenter,
          Paint paint) =>
      _inner.drawArc(rect, startAngle, sweepAngle, useCenter, paint);
  @override
  void drawAtlas(
          ui.Image atlas,
          List<RSTransform> transforms,
          List<Rect> rects,
          List<Color>? colors,
          BlendMode? blendMode,
          Rect? cullRect,
          Paint paint) =>
      _inner.drawAtlas(
          atlas, transforms, rects, colors, blendMode, cullRect, paint);
  @override
  void drawColor(Color color, BlendMode blendMode) =>
      _inner.drawColor(color, blendMode);
  @override
  void drawImage(ui.Image image, Offset offset, Paint paint) =>
      _inner.drawImage(image, offset, paint);
  @override
  void drawImageNine(ui.Image image, Rect center, Rect dst, Paint paint) =>
      _inner.drawImageNine(image, center, dst, paint);
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      _inner.drawLine(p1, p2, paint);
  @override
  void drawPaint(Paint paint) => _inner.drawPaint(paint);
  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      _inner.drawParagraph(paragraph, offset);
  @override
  void drawPicture(ui.Picture picture) => _inner.drawPicture(picture);
  @override
  void drawPoints(ui.PointMode pointMode, List<Offset> points, Paint paint) =>
      _inner.drawPoints(pointMode, points, paint);
  @override
  void drawRSuperellipse(ui.RSuperellipse rse, Paint paint) =>
      _inner.drawRSuperellipse(rse, paint);
  @override
  void drawRawAtlas(
          ui.Image atlas,
          Float32List rstTransforms,
          Float32List rects,
          Int32List? colors,
          BlendMode? blendMode,
          Rect? cullRect,
          Paint paint) =>
      _inner.drawRawAtlas(
          atlas, rstTransforms, rects, colors, blendMode, cullRect, paint);
  @override
  void drawRawPoints(ui.PointMode pointMode, Float32List points, Paint paint) =>
      _inner.drawRawPoints(pointMode, points, paint);
  @override
  void drawShadow(
          Path path, Color color, double elevation, bool transparentOccluder) =>
      _inner.drawShadow(path, color, elevation, transparentOccluder);
  @override
  void drawVertices(ui.Vertices vertices, BlendMode blendMode, Paint paint) =>
      _inner.drawVertices(vertices, blendMode, paint);
  @override
  Rect getDestinationClipBounds() => _inner.getDestinationClipBounds();
  @override
  Rect getLocalClipBounds() => _inner.getLocalClipBounds();
  @override
  int getSaveCount() => _inner.getSaveCount();
  @override
  Float64List getTransform() => _inner.getTransform();
  @override
  void restore() => _inner.restore();
  @override
  void restoreToCount(int count) => _inner.restoreToCount(count);
  @override
  void rotate(double radians) => _inner.rotate(radians);
  @override
  void save() => _inner.save();
  @override
  void scale(double sx, [double? sy]) => _inner.scale(sx, sy);
  @override
  void skew(double sx, double sy) => _inner.skew(sx, sy);
  @override
  void transform(Float64List matrix4) => _inner.transform(matrix4);
  @override
  void translate(double dx, double dy) => _inner.translate(dx, dy);
}
