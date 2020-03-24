library matrix_gesture_detector;

import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:vector_math/vector_math_64.dart';

typedef MatrixGestureDetectorCallback = void Function(
    Matrix4 matrix, Matrix4 translationDeltaMatrix, Matrix4 scaleDeltaMatrix, Matrix4 rotationDeltaMatrix);

/// [MatrixGestureDetector] detects translation, scale and rotation gestures
/// and combines them into [Matrix4] object that can be used by [Transform] widget
/// or by low level [CustomPainter] code. You can customize types of reported
/// gestures by passing [shouldTranslate], [shouldScale] and [shouldRotate]
/// parameters.
///
class MatrixGestureDetector extends StatefulWidget {
  /// [Matrix4] change notification callback
  ///
  final MatrixGestureDetectorCallback onMatrixUpdate;

  // Callback for the end of the gesture, as in [GestureDetector]'s [onScaleEnd]
  final Function onMatrixEnd;

  /// The [child] contained by this detector.
  ///
  /// {@macro flutter.widgets.child}
  ///
  final Widget child;

  /// Whether to detect translation gestures during the event processing.
  ///
  /// Defaults to true.
  ///
  final bool shouldTranslate;

  /// Whether to detect scale gestures during the event processing.
  ///
  /// Defaults to true.
  ///
  final bool shouldScale;

  /// Whether to detect rotation gestures during the event processing.
  ///
  /// Defaults to true.
  ///
  final bool shouldRotate;

  /// Whether [ClipRect] widget should clip [child] widget.
  ///
  /// Defaults to true.
  ///
  final bool clipChild;

  /// When set, it will be used for computing a "fixed" focal point
  /// aligned relative to the size of this widget.
  final Alignment focalPointAlignment;

  final WidgetController controller;

  final double maxScale;
  final double minScale;

  double childWidth;
  double childHeight;
  double childPadding;

  final GlobalKey targetKey;

  final bool disableGesture;

  MatrixGestureDetector({
    Key key,
    @required this.onMatrixUpdate,
    this.onMatrixEnd,
    @required this.child,
    this.shouldTranslate = true,
    this.shouldScale = true,
    this.shouldRotate = true,
    this.clipChild = true,
    this.focalPointAlignment,
    this.controller,
    this.targetKey,
    this.maxScale = 5,
    this.minScale = 0.2,
    this.childWidth,
    this.childHeight,
    this.childPadding,
    this.disableGesture = false,
  })  : assert(onMatrixUpdate != null),
        assert(child != null),
        super(key: key);

  @override
  _MatrixGestureDetectorState createState() => _MatrixGestureDetectorState();

  ///
  /// Compose the matrix from translation, scale and rotation matrices - you can
  /// pass a null to skip any matrix from composition.
  ///
  /// If [matrix] is not null the result of the composing will be concatenated
  /// to that [matrix], otherwise the identity matrix will be used.
  ///
  static Matrix4 compose(Matrix4 matrix, Matrix4 translationMatrix, Matrix4 scaleMatrix, Matrix4 rotationMatrix) {
    if (matrix == null) matrix = Matrix4.identity();
    if (translationMatrix != null) matrix = translationMatrix * matrix;
    if (scaleMatrix != null) matrix = scaleMatrix * matrix;
    if (rotationMatrix != null) matrix = rotationMatrix * matrix;
    return matrix;
  }

  ///
  /// Decomposes [matrix] into [MatrixDecomposedValues.translation],
  /// [MatrixDecomposedValues.scale] and [MatrixDecomposedValues.rotation] components.
  ///
  static MatrixDecomposedValues decomposeToValues(Matrix4 matrix) {
    var array = matrix.applyToVector3Array([0, 0, 0, 1, 0, 0]);
    Offset translation = Offset(array[0], array[1]);
    Offset delta = Offset(array[3] - array[0], array[4] - array[1]);
    double scale = delta.distance;
    double rotation = delta.direction;
    return MatrixDecomposedValues(translation, scale, rotation);
  }
}

class _MatrixGestureDetectorState extends State<MatrixGestureDetector> {
  Matrix4 matrix;
  MatrixDecomposedValues decomposedValues;

  void reset() {
    matrix = Matrix4.identity();
    decomposedValues = MatrixGestureDetector.decomposeToValues(matrix);
    // translationUpdater.value = Alignment.center.alongSize(context.size);
    // translationUpdater.value = Offset(0,0);
    rotationUpdater.value = double.nan;
    scaleUpdater.value = 1.0;
    widget.onMatrixUpdate(Matrix4.identity(), Matrix4.identity(), Matrix4.identity(), Matrix4.identity());
  }

  @override
  void initState() {
    super.initState();
    widget.controller?.setState(this);
    reset();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = widget.clipChild ? ClipRect(child: widget.child) : widget.child;
    if(widget.disableGesture){
      return child;
    } else {
      return GestureDetector(
        onScaleStart: onScaleStart,
        onScaleUpdate: (detail) {
          onScaleUpdate(
            focalPoint: detail.focalPoint,
            scale: detail.scale,
            rotation: detail.rotation,
          );
        },
        onScaleEnd: onScaleEnd,
        child: child,
      );
    }
  }

  _ValueUpdater<Offset> translationUpdater = _ValueUpdater(
    onUpdate: (oldVal, newVal) => newVal - oldVal,
  );
  _ValueUpdater<double> rotationUpdater = _ValueUpdater(
    onUpdate: (oldVal, newVal) => newVal - oldVal,
  );
  _ValueUpdater<double> scaleUpdater = _ValueUpdater(
    onUpdate: (oldVal, newVal) => newVal / oldVal,
  );

  void onScaleStart(ScaleStartDetails details) {
    translationUpdater.value = details.focalPoint;
    rotationUpdater.value = double.nan;
    scaleUpdater.value = 1.0;
  }

  void onScaleEnd(ScaleEndDetails details) {
    if (this.widget.onMatrixEnd != null) {
      this.widget.onMatrixEnd();
    }
  }

  void onScaleUpdate({Offset focalPoint, double scale, double rotation}) {
    Matrix4 _translationDeltaMatrix = Matrix4.identity();
    Matrix4 _scaleDeltaMatrix = Matrix4.identity();
    Matrix4 _rotationDeltaMatrix = Matrix4.identity();
    bool _useScale = false;

    // handle matrix translating
    if (focalPoint != null) {
      if (widget.shouldTranslate) {
        // if (translationUpdater.value == null) {
        //   translationUpdater.value = Offset(0,0);
        //   rotationUpdater.value = double.nan;
        //   scaleUpdater.value = 1.0;
        //   _useScale = true;
        // }
        Offset translationDelta = translationUpdater.update(focalPoint);
        _translationDeltaMatrix = _translate(translationDelta);
        matrix = _translationDeltaMatrix * matrix;

        double _imageWidth = widget.childWidth;
        double _imageScaledWidth = _imageWidth * matrix[0];
        double _imageHeight = widget.childHeight;
        double _imageScaledHeight = _imageHeight * matrix[5];

        // if(_useScale){
        //   _imageScaledWidth = _imageWidth * scale;
        //   _imageScaledHeight = _imageHeight * scale;
        // }

        if (matrix[12] < 0) {
          if (_imageScaledWidth < -matrix[12] + _imageWidth) {
            matrix[12] = -_imageScaledWidth + _imageWidth;
          } 
        } else {
          matrix[12] = 0.0;
        }

        print(matrix[13]);
        print(_imageScaledHeight);
        print(_imageHeight);
        if(matrix[13] < 0){
          if (_imageScaledHeight < -matrix[13] + _imageHeight) {
            matrix[13] = -_imageScaledHeight + _imageHeight;
          } 
        } else {
          matrix[13] = 0.0;
        }
        print(matrix[13]);
      }
    } else {
      final targetContext = widget.targetKey.currentContext ?? context;
      RenderBox renderBox = targetContext.findRenderObject();
      focalPoint = renderBox.localToGlobal(Alignment.center.alongSize(targetContext.size));
    }

    Offset focalPointLocal;
    if (widget.focalPointAlignment != null) {
      focalPointLocal = widget.focalPointAlignment.alongSize(context.size);
    } else {
      RenderBox renderBox = context.findRenderObject();
      focalPointLocal = renderBox.globalToLocal(focalPoint);
    }

    // handle matrix scaling
    if (widget.shouldScale && scale != null && scale != 1.0) {
      double scaleDelta = scaleUpdater.update(scale);
      _scaleDeltaMatrix = _scale(scaleDelta, focalPointLocal);
      final matrixScale = _scaleDeltaMatrix * matrix;
      final scaleUpdate = MatrixGestureDetector.decomposeToValues(matrixScale).scale;
      if (scaleUpdate <= widget.maxScale && scaleUpdate >= widget.minScale) {
        matrix = matrixScale;
      }
    }

    // handle matrix rotating
    if (widget.shouldRotate && rotation != null && rotation != 0.0) {
      if (rotationUpdater.value.isNaN) {
        rotationUpdater.value = rotation;
      } else {
        double rotationDelta = rotationUpdater.update(rotation);
        _rotationDeltaMatrix = _rotate(rotationDelta, focalPointLocal);
        matrix = _rotationDeltaMatrix * matrix;
      }
    }

    decomposedValues = MatrixGestureDetector.decomposeToValues(matrix);
    widget.onMatrixUpdate(matrix, _translationDeltaMatrix, _scaleDeltaMatrix, _rotationDeltaMatrix);
  }

  Matrix4 _translate(Offset translation) {
    var dx = translation.dx;
    var dy = translation.dy;

    //  ..[0]  = 1       # x scale
    //  ..[5]  = 1       # y scale
    //  ..[10] = 1       # diagonal "one"
    //  ..[12] = dx      # x translation
    //  ..[13] = dy      # y translation
    //  ..[15] = 1       # diagonal "one"
    return Matrix4(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);
  }

  Matrix4 _scale(double scale, Offset focalPoint) {
    var dx = (1 - scale) * focalPoint.dx;
    var dy = (1 - scale) * focalPoint.dy;

    //  ..[0]  = scale   # x scale
    //  ..[5]  = scale   # y scale
    //  ..[10] = 1       # diagonal "one"
    //  ..[12] = dx      # x translation
    //  ..[13] = dy      # y translation
    //  ..[15] = 1       # diagonal "one"
    return Matrix4(scale, 0, 0, 0, 0, scale, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);
  }

  Matrix4 _rotate(double angle, Offset focalPoint) {
    var c = cos(angle);
    var s = sin(angle);
    var dx = (1 - c) * focalPoint.dx + s * focalPoint.dy;
    var dy = (1 - c) * focalPoint.dy - s * focalPoint.dx;

    //  ..[0]  = c       # x scale
    //  ..[1]  = s       # y skew
    //  ..[4]  = -s      # x skew
    //  ..[5]  = c       # y scale
    //  ..[10] = 1       # diagonal "one"
    //  ..[12] = dx      # x translation
    //  ..[13] = dy      # y translation
    //  ..[15] = 1       # diagonal "one"
    return Matrix4(c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, dx, dy, 0, 1);
  }
}

typedef _OnUpdate<T> = T Function(T oldValue, T newValue);

class _ValueUpdater<T> {
  final _OnUpdate<T> onUpdate;
  T value;

  _ValueUpdater({this.onUpdate});

  T update(T newValue) {
    T updated = onUpdate(value, newValue);
    value = newValue;
    return updated;
  }
}

class MatrixDecomposedValues {
  /// Translation, in most cases useful only for matrices that are nothing but
  /// a translation (no scale and no rotation).
  final Offset translation;

  /// Scaling factor.
  final double scale;

  /// Rotation in radians, (-pi..pi) range.
  final double rotation;

  MatrixDecomposedValues(this.translation, this.scale, this.rotation);

  @override
  String toString() {
    return 'MatrixDecomposedValues(translation: $translation, scale: ${scale.toStringAsFixed(3)}, rotation: ${rotation.toStringAsFixed(3)})';
  }
}

class WidgetController {
  _MatrixGestureDetectorState _state;

  WidgetController();

  void setState(_MatrixGestureDetectorState s) => _state = s;

  double get scale => _state.decomposedValues.scale;

  set scale(double val) {
    _state.onScaleUpdate(scale: val);
  }

  double get rotation {
    return _state.decomposedValues.rotation;
  }

  set rotation(double val) {
    _state.onScaleUpdate(rotation: val);
  }

  void reset() {
    _state.reset();
  }
}
