// packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart
import 'dart:math' as math;

import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../id_card_template.dart';
import '../rfid_student_row.dart';
import 'it_technician_dashboard_page.dart' show ItTechnicianColors;
import 'shared_form_widgets.dart' show PillButton;
import 'signature_capture_dialog.dart';
import 'webcam_capture_dialog.dart';

/// Present when this editor is opened to print a specific student's ID card
/// (from Student Records' "Print Student ID" action) rather than just to
/// author a template. Turns on the print-only controls (template switcher,
/// photo/signature capture, Print) and makes the canvas render this
/// student's real photo/signature/field values in place of the generic
/// placeholders authoring mode shows — the canvas becomes the one live
/// preview, so what's on screen is exactly what gets printed.
class IdCardPrintContext {
  const IdCardPrintContext({
    required this.student,
    required this.initialTemplateId,
    required this.availableTemplates,
    required this.onLoadTemplate,
    required this.onPrint,
    this.initialPhotoBytes,
    this.initialSignatureBytes,
  });

  final RfidStudentRow student;

  /// The id of the template this editor was opened with — needed so the
  /// template-switcher dropdown can show it selected.
  final String initialTemplateId;

  /// The student's existing photo, downloaded by the host app before
  /// opening this page — null when they don't have one on file yet.
  final Uint8List? initialPhotoBytes;

  /// The student's existing signature, downloaded by the host app before
  /// opening this page — null when they don't have one on file yet.
  final Uint8List? initialSignatureBytes;

  /// Saved templates, for the switcher dropdown.
  final List<IdCardTemplateSummary> availableTemplates;

  /// Fetches a different template's full layout when the switcher
  /// selection changes — this page has no Supabase access of its own.
  final Future<IdCardTemplateDetail> Function(String templateId)
      onLoadTemplate;

  /// Uploads whatever changed (photo, and signature if captured) and sends
  /// the card to the printer, rendering from the layout passed in (the
  /// editor's current in-memory state at the moment Print was pressed, not
  /// necessarily what's saved). Rethrows on failure so this page can show
  /// the error inline.
  final Future<void> Function({
    required Uint8List photoBytes,
    required Uint8List? signatureBytes,
    required List<IdCardTemplateElement> frontLayout,
    required List<IdCardTemplateElement> backLayout,
    required IdCardOrientation orientation,
    required int backgroundColor,
  }) onPrint;
}

/// Lastname / First name, M.I. / Course — omits the trailing ", M.I."
/// when the student has no middle initial on file, rather than showing a
/// bare comma.
String _fullNameBlock({
  required String firstName,
  required String middleInitial,
  required String lastName,
  required String course,
}) {
  final mi = middleInitial.trim();
  final firstLine = mi.isEmpty ? firstName : '$firstName, $mi.';
  return '$lastName\n$firstLine\n$course';
}

String _studentFieldValue(IdDataFieldKey? key, RfidStudentRow student) {
  switch (key) {
    case IdDataFieldKey.fullName:
      return _fullNameBlock(
        firstName: student.firstName,
        middleInitial: student.middleInitial,
        lastName: student.lastName,
        course: student.course,
      );
    case IdDataFieldKey.firstName:
      return student.firstName;
    case IdDataFieldKey.middleInitial:
      return student.middleInitial;
    case IdDataFieldKey.lastName:
      return student.lastName;
    case IdDataFieldKey.studentNumber:
      return student.studentNumber;
    case IdDataFieldKey.course:
      return student.course;
    case IdDataFieldKey.section:
      return student.section;
    case IdDataFieldKey.yearLevel:
      return student.yearLevel;
    case IdDataFieldKey.guardianName:
      return student.guardianName;
    case IdDataFieldKey.guardianContactNo:
      return student.guardianContactNo;
    case null:
      return '';
  }
}

/// Full-screen ID card template editor — toolbox (drag elements onto the
/// canvas), canvas (front/back toggle above it), properties panel. Styled to
/// match the rest of the IT Technician dashboard's Bento UI. When
/// [printContext] is given, also doubles as the "Print Student ID" screen —
/// see [IdCardPrintContext]'s doc comment.
class IdCardTemplateEditorPage extends StatefulWidget {
  const IdCardTemplateEditorPage({
    super.key,
    required this.templateName,
    required this.initialFrontLayout,
    required this.initialBackLayout,
    required this.onSave,
    required this.onUploadImage,
    required this.onRename,
    this.initialOrientation = IdCardOrientation.landscape,
    this.initialBackgroundColor = 0xFFFFFFFF,
    this.onFetchImageBytes,
    this.printContext,
  });

  final String templateName;
  final List<IdCardTemplateElement> initialFrontLayout;
  final List<IdCardTemplateElement> initialBackLayout;

  /// Both sides of one physical card, so they always share one
  /// orientation — see [IdCardTemplateDetail.orientation].
  final IdCardOrientation initialOrientation;

  /// ARGB int — see [IdCardTemplateDetail.backgroundColor].
  final int initialBackgroundColor;

  final Future<void> Function(
    List<IdCardTemplateElement> frontLayout,
    List<IdCardTemplateElement> backLayout,
    IdCardOrientation orientation,
    int backgroundColor,
  ) onSave;

  /// Uploads a static image (e.g. a school logo) for an Image-type
  /// element and returns its Storage object path. This page has no
  /// Supabase access of its own.
  final Future<String> Function(Uint8List bytes, String fileName) onUploadImage;

  /// Resolves an Image-type element's already-saved [imagePath] (from
  /// `initialFrontLayout`/`initialBackLayout`, or from switching templates
  /// via [IdCardPrintContext.onLoadTemplate]) to its actual bytes, so the
  /// canvas can show the real picture instead of the generic placeholder
  /// icon. Null (the default) means the canvas always shows the
  /// placeholder for a pre-existing image — a freshly-picked-and-uploaded
  /// image still renders immediately either way, since this page already
  /// has its bytes in memory from the file picker.
  final Future<Uint8List?> Function(String imagePath)? onFetchImageBytes;

  /// Persists an inline rename of the header title (the template's own
  /// name). This page has no Supabase access of its own.
  final Future<void> Function(String newName) onRename;

  final IdCardPrintContext? printContext;

  @override
  State<IdCardTemplateEditorPage> createState() =>
      _IdCardTemplateEditorPageState();
}

/// The eight resize handles around a selected element: four corners (resize
/// both ways) and four sides (stretch one way).
enum _ResizeHandle {
  nw,
  n,
  ne,
  e,
  se,
  s,
  sw,
  w;

  bool get movesLeft => this == nw || this == w || this == sw;
  bool get movesRight => this == ne || this == e || this == se;
  bool get movesTop => this == nw || this == n || this == ne;
  bool get movesBottom => this == sw || this == s || this == se;

  /// Where the handle sits on the element's box, as a fraction of its
  /// width/height.
  Offset get anchor => Offset(
        movesLeft ? 0 : (movesRight ? 1 : 0.5),
        movesTop ? 0 : (movesBottom ? 1 : 0.5),
      );

  MouseCursor get cursor => switch (this) {
        nw || se => SystemMouseCursors.resizeUpLeftDownRight,
        ne || sw => SystemMouseCursors.resizeUpRightDownLeft,
        n || s => SystemMouseCursors.resizeUpDown,
        e || w => SystemMouseCursors.resizeLeftRight,
      };
}

class _IdCardTemplateEditorPageState extends State<IdCardTemplateEditorPage> {
  /// Screen pixels per card point. [_defaultZoom] is "100%" (the size the old
  /// 90% setting had — the original 100% was too large); the slider, the +/-
  /// buttons, the percentage dropdown and Ctrl + mouse wheel all move it
  /// within [_minZoom]-[_maxZoom], 25%-300% of it.
  static const double _defaultZoom = 2.7;
  static const double _minZoom = _defaultZoom * 0.25;
  static const double _maxZoom = _defaultZoom * 3;
  static const double _zoomStep = _defaultZoom * 0.1; // 10 percentage points
  static const List<int> _zoomPresets = [25, 50, 75, 100, 125, 150, 200, 300];
  double _zoom = _defaultZoom;

  // The canvas scrolls (both ways) once the zoomed card outgrows its area.
  final _canvasHScroll = ScrollController();
  final _canvasVScroll = ScrollController();

  void _setZoom(double zoom) =>
      setState(() => _zoom = zoom.clamp(_minZoom, _maxZoom).toDouble());

  /// Ctrl (or Cmd) + mouse wheel zooms the canvas instead of scrolling it.
  /// Also takes the platform's own "pinch" signals — a [PointerScaleEvent]
  /// (what a browser or a touchpad pinch reports for Ctrl + wheel) and the
  /// touchpad pan-zoom events below — so the zoom works however the OS
  /// delivers the gesture.
  void _handleCanvasPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final keyboard = HardwareKeyboard.instance;
      if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return;
      // Registering with the resolver is what stops the surrounding scroll
      // view from also scrolling for this same wheel tick.
      GestureBinding.instance.pointerSignalResolver.register(event, (e) {
        final dy = (e as PointerScrollEvent).scrollDelta.dy;
        if (dy == 0) return;
        // Proportional to how far the wheel turned, so a smooth/high-res
        // wheel isn't faster than a notched one: ~16% per 100px notch.
        _setZoom(_zoom * math.exp(-dy / 700));
      });
    } else if (event is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (e) {
        _setZoom(_zoom * (e as PointerScaleEvent).scale);
      });
    }
  }

  double _panZoomStartZoom = _defaultZoom;
  static const List<(IdCardElementType, String, IconData)> _toolboxItems = [
    (IdCardElementType.staticText, 'Text', Icons.text_fields),
    (IdCardElementType.image, 'Image', Icons.image_outlined),
    (IdCardElementType.idData, 'ID Data', Icons.badge_outlined),
    (IdCardElementType.idPicture, 'ID Picture', Icons.account_box_outlined),
    (IdCardElementType.signature, 'Signature', Icons.draw_outlined),
    (IdCardElementType.rectangle, 'Rectangle', Icons.crop_square),
    (IdCardElementType.ellipse, 'Ellipse', Icons.circle_outlined),
    (IdCardElementType.line, 'Line', Icons.horizontal_rule),
  ];

  late List<IdCardTemplateElement> _frontElements =
      _fitAll(widget.initialFrontLayout);
  late List<IdCardTemplateElement> _backElements =
      _fitAll(widget.initialBackLayout);
  late IdCardOrientation _orientation = widget.initialOrientation;
  late int _backgroundColor = widget.initialBackgroundColor;
  bool _showingFront = true;

  /// Cache of already-resolved Image-type element bytes, keyed by
  /// `imagePath` — populated immediately for a just-picked-and-uploaded
  /// image (no network round-trip needed), and lazily via
  /// [widget.onFetchImageBytes] for a pre-existing `imagePath` loaded from
  /// a template. See [_elementContent]'s `IdCardElementType.image` case.
  final Map<String, Uint8List> _imageBytesByPath = {};

  double get _cardWidthPt => cardWidthPtFor(_orientation);
  double get _cardHeightPt => cardHeightPtFor(_orientation);
  Set<String> _selectedIdsValue = {};

  /// True while the card itself (rather than an element on it) is the
  /// selection: the card gets a highlighted border and the properties panel
  /// offers its background color. Selecting any element clears it.
  bool _cardSelected = false;

  Set<String> get _selectedIds => _selectedIdsValue;
  set _selectedIds(Set<String> ids) {
    _selectedIdsValue = ids;
    if (ids.isNotEmpty) _cardSelected = false;
  }

  /// Hands the keyboard back to the canvas, so Delete/Backspace and the other
  /// canvas shortcuts act on the selection again. Without it, a properties
  /// field that was last focused keeps the keyboard even after you click an
  /// element on the canvas — and Delete then edits that field instead.
  void _focusCanvas() {
    if (FocusManager.instance.primaryFocus != _focusNode) {
      _focusNode.requestFocus();
    }
  }

  void _selectCard() {
    _focusCanvas();
    setState(() {
      _selectedIds = {};
      _cardSelected = true;
    });
  }

  void _clearSelection() {
    _focusCanvas();
    setState(() {
      _selectedIds = {};
      _cardSelected = false;
    });
  }
  bool _saving = false;
  bool _dirty = false;
  int _idCounter = 0;

  final List<(List<IdCardTemplateElement>, List<IdCardTemplateElement>)>
      _undoStack = [];
  final List<(List<IdCardTemplateElement>, List<IdCardTemplateElement>)>
      _redoStack = [];
  static const _maxHistory = 50;
  List<IdCardTemplateElement> _clipboard = [];
  List<double> _guideLinesX = [];
  List<double> _guideLinesY = [];
  final _focusNode = FocusNode();

  Offset? _marqueeStart;
  Offset? _marqueeCurrent;

  // Snap-to-guide drag tracking: keyed by element id, each moving element's
  // position at the start of the current drag gesture, plus how far the
  // pointer has actually travelled since then (in card points, unaffected
  // by snapping). See _moveSelection's own doc comment for why this can't
  // just accumulate onto the element's current (possibly already-snapped)
  // stored x/y.
  Map<String, Offset> _dragStartPositions = {};
  Offset _dragCumulativeDelta = Offset.zero;

  // --- Header title (rename) -----------------------------------------------

  late String _currentName = widget.templateName;
  bool _editingName = false;
  late final _nameController = TextEditingController(text: _currentName);
  final _nameFocusNode = FocusNode();

  // --- Print mode (only meaningful when widget.printContext != null) -----

  late Uint8List? _photoBytes = widget.printContext?.initialPhotoBytes;
  late Uint8List? _signatureBytes = widget.printContext?.initialSignatureBytes;
  late String? _currentTemplateId = widget.printContext?.initialTemplateId;
  bool _printing = false;
  String? _printError;

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(_handleNameFocusChange);
    _ensureImageBytesLoaded();
  }

  /// Fetches bytes for every Image-type element's `imagePath` not already
  /// cached (a pre-existing image loaded from a saved template) so the
  /// canvas can render the real picture instead of the placeholder icon.
  /// A no-op per path once cached, and entirely a no-op when
  /// [IdCardTemplateEditorPage.onFetchImageBytes] isn't provided.
  void _ensureImageBytesLoaded() {
    final onFetchImageBytes = widget.onFetchImageBytes;
    if (onFetchImageBytes == null) return;
    final paths = {
      for (final e in [..._frontElements, ..._backElements])
        if (e.type == IdCardElementType.image && e.imagePath != null)
          e.imagePath!,
    }..removeWhere(_imageBytesByPath.containsKey);
    for (final path in paths) {
      onFetchImageBytes(path).then((bytes) {
        if (bytes != null && mounted) {
          setState(() => _imageBytesByPath[path] = bytes);
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _nameFocusNode.removeListener(_handleNameFocusChange);
    _nameFocusNode.dispose();
    _nameController.dispose();
    _textEditController.dispose();
    _textEditFocus.dispose();
    _canvasHScroll.dispose();
    _canvasVScroll.dispose();
    super.dispose();
  }

  void _handleNameFocusChange() {
    if (!_nameFocusNode.hasFocus && _editingName) {
      _commitNameEdit(_nameController.text);
    }
  }

  void _beginNameEdit() {
    _nameController.text = _currentName;
    setState(() => _editingName = true);
  }

  void _cancelNameEdit() {
    _nameController.text = _currentName;
    setState(() => _editingName = false);
  }

  Future<void> _commitNameEdit(String newName) async {
    final trimmed = newName.trim();
    setState(() => _editingName = false);
    if (trimmed.isEmpty || trimmed == _currentName) {
      _nameController.text = _currentName;
      return;
    }
    final previous = _currentName;
    setState(() => _currentName = trimmed); // optimistic
    try {
      await widget.onRename(trimmed);
    } catch (e) {
      if (!mounted) return;
      setState(() => _currentName = previous);
      _nameController.text = previous;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not rename: $e')));
    }
  }

  List<IdCardTemplateElement> get _currentElements =>
      _showingFront ? _frontElements : _backElements;

  void _setCurrentElements(List<IdCardTemplateElement> elements) {
    elements = _fitAll(elements);
    setState(() {
      if (_showingFront) {
        _frontElements = elements;
      } else {
        _backElements = elements;
      }
      _dirty = true;
    });
  }

  String _nextElementId() {
    _idCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_idCounter';
  }

  IdCardTemplateElement _defaultElementFor(
    IdCardElementType type,
    String id,
  ) {
    const defaultWidth = 80.0;
    const defaultHeight = 20.0;
    switch (type) {
      case IdCardElementType.staticText:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: defaultWidth,
          height: defaultHeight,
          textContent: 'Static Text',
          fontFamily: 'Poppins',
          fontSize: 10,
          color: 0xFF000000,
          textAlign: 'left',
        );
      case IdCardElementType.idData:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: defaultWidth,
          // Taller than defaultHeight (20) since the default field
          // (fullName) is a 3-line block, not a single line.
          height: 40,
          fieldKey: IdDataFieldKey.fullName,
          fontFamily: 'Poppins',
          fontSize: 10,
          color: 0xFF000000,
          textAlign: 'left',
        );
      case IdCardElementType.image:
        return IdCardTemplateElement(
            id: id, type: type, x: 10, y: 10, width: 60, height: 60);
      case IdCardElementType.idPicture:
        return IdCardTemplateElement(
            id: id, type: type, x: 10, y: 10, width: 60, height: 70);
      case IdCardElementType.signature:
        return IdCardTemplateElement(
            id: id, type: type, x: 10, y: 10, width: 100, height: 30);
      case IdCardElementType.rectangle:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: 100,
          height: 40,
          fillColor: 0xFF345892,
          strokeColor: 0x00000000,
          strokeWidth: 1,
        );
      case IdCardElementType.roundedRect:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: 100,
          height: 40,
          fillColor: 0xFF345892,
          strokeColor: 0x00000000,
          strokeWidth: 1,
          cornerRadius: 8,
        );
      case IdCardElementType.ellipse:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: 40,
          height: 40,
          fillColor: 0xFF345892,
          strokeColor: 0x00000000,
          strokeWidth: 1,
        );
      case IdCardElementType.line:
        return IdCardTemplateElement(
          id: id,
          type: type,
          x: 10,
          y: 10,
          width: 80,
          height: 1,
          strokeColor: 0xFF000000,
          strokeWidth: 1,
        );
    }
  }

  void _pushHistory() {
    _undoStack.add((List.of(_frontElements), List.of(_backElements)));
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add((List.of(_frontElements), List.of(_backElements)));
    final (front, back) = _undoStack.removeLast();
    setState(() {
      _frontElements = front;
      _backElements = back;
      _selectedIds = {};
      _dirty = true;
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add((List.of(_frontElements), List.of(_backElements)));
    final (front, back) = _redoStack.removeLast();
    setState(() {
      _frontElements = front;
      _backElements = back;
      _selectedIds = {};
      _dirty = true;
    });
  }

  void _addElement(IdCardElementType type) {
    _focusCanvas();
    _pushHistory();
    final id = _nextElementId();
    _setCurrentElements([..._currentElements, _defaultElementFor(type, id)]);
    setState(() => _selectedIds = {id});
  }

  void _selectOnly(String id) => setState(() => _selectedIds = {id});

  void _handleElementTap(String id) {
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    setState(() {
      if (isShift) {
        _selectedIds = _selectedIds.contains(id)
            ? ({..._selectedIds}..remove(id))
            : {..._selectedIds, id};
      } else {
        _selectedIds = {id};
      }
    });
  }

  void _copySelection() {
    _clipboard =
        _currentElements.where((e) => _selectedIds.contains(e.id)).toList();
  }

  void _pasteClipboard() {
    if (_clipboard.isEmpty) return;
    _pushHistory();
    final pasted = _fitAll(_clipboard
        .map((e) => e.copyWith(
              id: '${_nextElementId()}-paste',
              x: e.x + 10,
              y: e.y + 10,
            ))
        .toList());
    setState(() {
      if (_showingFront) {
        _frontElements = [..._frontElements, ...pasted];
      } else {
        _backElements = [..._backElements, ...pasted];
      }
      _selectedIds = pasted.map((e) => e.id).toSet();
      _dirty = true;
    });
  }

  // The whole selection moves together by one shared delta (so a
  // multi-element selection stays rigid, not each member snapping off to
  // its own nearest candidate independently) — snapping compares each
  // moving element's proposed position against nearby alignment candidates
  // (card edges/center, other elements' edges) and, within snapThreshold,
  // overrides that shared delta so every selected element lands exactly on
  // the candidate together.
  //
  // The shared delta MUST be computed relative to each element's position
  // at drag START (_dragStartPositions), accumulated via
  // _dragCumulativeDelta — never relative to the element's current stored
  // x/y. Once snapped, an element's stored x/y equals the candidate
  // exactly, so computing "proposed = stored + this frame's tiny
  // incremental delta" would immediately re-land inside the same threshold
  // on the very next frame, re-triggering the same snap and cancelling the
  // movement. That made dragging feel like it kept "locking" onto guide
  // lines and refusing to move away from them under small, smooth pointer
  // deltas (the common case for an actual mouse/trackpad drag).
  void _moveSelection(Offset screenDelta) {
    _dragCumulativeDelta += Offset(
      screenDelta.dx / _zoom,
      screenDelta.dy / _zoom,
    );
    const snapThreshold = 4.0;

    final others =
        _currentElements.where((e) => !_selectedIds.contains(e.id)).toList();
    final movingElements =
        _currentElements.where((e) => _selectedIds.contains(e.id)).toList();
    if (movingElements.isEmpty) return;

    // Per axis the selection snaps to the ONE nearest alignment candidate
    // (across every moving element), never to several at once — otherwise two
    // nearby candidates (say the card's center and another element's edge)
    // would each draw a guide while the element can only sit on one of them.
    // Once snapped, a guide is drawn for each line the selection genuinely
    // sits on (e.g. centered on the card AND on another element's center),
    // at the edge or center that lines up.
    var adjustedDeltaX = _dragCumulativeDelta.dx;
    var adjustedDeltaY = _dragCumulativeDelta.dy;
    var bestDistX = snapThreshold;
    var bestDistY = snapThreshold;

    for (final moving in movingElements) {
      final start = _dragStartPositions[moving.id] ?? Offset(moving.x, moving.y);
      final newX = start.dx + _dragCumulativeDelta.dx;
      final newY = start.dy + _dragCumulativeDelta.dy;
      for (final c in _alignCandidates(moving, others, horizontal: true)) {
        final dist = (newX - c.position).abs();
        if (dist < bestDistX) {
          bestDistX = dist;
          adjustedDeltaX = c.position - start.dx;
        }
      }
      for (final c in _alignCandidates(moving, others, horizontal: false)) {
        final dist = (newY - c.position).abs();
        if (dist < bestDistY) {
          bestDistY = dist;
          adjustedDeltaY = c.position - start.dy;
        }
      }
    }

    final guideX = <double>[];
    final guideY = <double>[];
    void addGuide(List<double> guides, double line) {
      final screen = line * _zoom;
      if (!guides.any((g) => (g - screen).abs() < 0.01)) guides.add(screen);
    }

    for (final moving in movingElements) {
      final start = _dragStartPositions[moving.id] ?? Offset(moving.x, moving.y);
      if (bestDistX < snapThreshold) {
        final x = start.dx + adjustedDeltaX;
        for (final c in _alignCandidates(moving, others, horizontal: true)) {
          if ((x - c.position).abs() < 0.01) addGuide(guideX, c.line);
        }
      }
      if (bestDistY < snapThreshold) {
        final y = start.dy + adjustedDeltaY;
        for (final c in _alignCandidates(moving, others, horizontal: false)) {
          if ((y - c.position).abs() < 0.01) addGuide(guideY, c.line);
        }
      }
    }

    final elements = _currentElements.map((e) {
      if (!_selectedIds.contains(e.id)) return e;
      final start = _dragStartPositions[e.id] ?? Offset(e.x, e.y);
      return e.copyWith(
        x: _clampX(start.dx + adjustedDeltaX, e.width),
        y: _clampY(start.dy + adjustedDeltaY, e.height),
      );
    }).toList();

    setState(() {
      _guideLinesX = guideX;
      _guideLinesY = guideY;
    });
    _setCurrentElements(elements);
  }

  /// An element may be dragged (or typed) partly off the card — e.g. to bleed
  /// a background past the edge — but never so far that it can't be grabbed
  /// again: at least this much of it stays on the card. Dragging still snaps
  /// to the card's edges first (see [_alignCandidates]); it takes a deliberate
  /// pull past the snap to leave.
  static const double _minInside = 8.0;

  double _clampX(double x, double width) {
    final inside = math.min(_minInside, width);
    return x.clamp(inside - width, _cardWidthPt - inside).toDouble();
  }

  double _clampY(double y, double height) {
    final inside = math.min(_minInside, height);
    return y.clamp(inside - height, _cardHeightPt - inside).toDouble();
  }

  /// Every place [moving] could snap to along one axis: its leading edge,
  /// center or trailing edge lined up with the card's, or with another
  /// element's. `position` is where [moving]'s x (or y) lands, `line` the
  /// coordinate of the edge/center that lines up — where the guide is drawn.
  List<({double position, double line})> _alignCandidates(
    IdCardTemplateElement moving,
    List<IdCardTemplateElement> others, {
    required bool horizontal,
  }) {
    final size = horizontal ? moving.width : moving.height;
    final card = horizontal ? _cardWidthPt : _cardHeightPt;
    ({double position, double line}) leading(double line) =>
        (position: line, line: line);
    ({double position, double line}) center(double line) =>
        (position: line - size / 2, line: line);
    ({double position, double line}) trailing(double line) =>
        (position: line - size, line: line);
    final candidates = [leading(0), center(card / 2), trailing(card)];
    for (final other in others) {
      final start = horizontal ? other.x : other.y;
      final length = horizontal ? other.width : other.height;
      candidates
        ..add(leading(start))
        ..add(center(start + length / 2))
        ..add(trailing(start + length));
    }
    return candidates;
  }

  // --- Text hugging ------------------------------------------------------

  /// How a static text element is drawn, in the editor and when measuring it
  /// (the two must agree, or the selection box wouldn't hug the glyphs).
  TextStyle _staticTextStyle(IdCardTemplateElement e, double scale) =>
      GoogleFonts.poppins(
        fontSize: (e.fontSize ?? 10) * scale,
        fontWeight: _fontWeightOf(e),
        color: Color(e.color ?? 0xFF000000),
      );

  /// A static text element's box always equals its text: whenever the text,
  /// font size or color changes — or the element is created, pasted, loaded —
  /// width/height are re-measured, so the selection border hugs the content
  /// (and stays correct as it is edited or scaled). The box is anchored by
  /// the element's alignment (left edge, center or right edge stays put), so
  /// text a template centered in a wide box keeps its printed position.
  /// ID Data elements are NOT fitted: their text depends on the student, so
  /// their box is a reserved area the user sizes.
  IdCardTemplateElement _fitText(IdCardTemplateElement e) {
    if (e.type != IdCardElementType.staticText) return e;
    final content = e.textContent ?? '';
    final painter = TextPainter(
      text: TextSpan(
        text: content.isEmpty ? ' ' : content,
        style: _staticTextStyle(e, 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = math.max(painter.width, 4.0);
    final height = math.max(painter.height, 4.0);
    painter.dispose();
    if ((width - e.width).abs() < 0.01 && (height - e.height).abs() < 0.01) {
      return e;
    }
    final x = switch (e.textAlign) {
      'center' => e.x + (e.width - width) / 2,
      'right' => e.x + e.width - width,
      _ => e.x,
    };
    return e.copyWith(
      x: _clampX(x, width),
      width: width,
      height: height,
    );
  }

  List<IdCardTemplateElement> _fitAll(List<IdCardTemplateElement> elements) =>
      [for (final e in elements) _fitText(e)];

  // --- Resizing ----------------------------------------------------------

  /// Drags one of the eight handles by [screenDelta]. Corners resize both
  /// ways, sides stretch one way; the edge opposite the handle stays put.
  /// Text elements can't be stretched out of shape (their box hugs the
  /// glyphs), so every handle scales the font size instead.
  void _resizeElement(String id, _ResizeHandle handle, Offset screenDelta) {
    final dx = screenDelta.dx / _zoom;
    final dy = screenDelta.dy / _zoom;
    final elements = _currentElements.map((e) {
      if (e.id != id) return e;

      final movesLeft = handle.movesLeft;
      final movesRight = handle.movesRight;
      final movesTop = handle.movesTop;
      final movesBottom = handle.movesBottom;

      if (e.type == IdCardElementType.staticText) {
        final widthRatio = movesRight
            ? (e.width + dx) / e.width
            : movesLeft
                ? (e.width - dx) / e.width
                : null;
        final heightRatio = movesBottom
            ? (e.height + dy) / e.height
            : movesTop
                ? (e.height - dy) / e.height
                : null;
        final ratios = [widthRatio, heightRatio].whereType<double>().toList();
        final ratio = ratios.reduce((a, b) => a + b) / ratios.length;
        final fontSize =
            ((e.fontSize ?? 10) * ratio).clamp(4.0, 200.0).toDouble();
        final scaled = _fitText(e.copyWith(fontSize: fontSize));
        // Keep the edge opposite the handle where it was.
        final x = movesLeft ? e.x + e.width - scaled.width : e.x;
        final y = movesTop ? e.y + e.height - scaled.height : e.y;
        return scaled.copyWith(
          x: _clampX(x, scaled.width),
          y: _clampY(y, scaled.height),
        );
      }

      const minSize = 8.0;
      var left = e.x;
      var top = e.y;
      var right = e.x + e.width;
      var bottom = e.y + e.height;
      // Resizing stops at the card's edges, but an edge already past them (a
      // dragged-out element) stays where it is instead of snapping back in.
      final minLeft = math.min(0.0, e.x);
      final maxRight = math.max(_cardWidthPt, e.x + e.width);
      final minTop = math.min(0.0, e.y);
      final maxBottom = math.max(_cardHeightPt, e.y + e.height);
      if (movesLeft) {
        left = (left + dx).clamp(minLeft, right - minSize).toDouble();
      }
      if (movesRight) {
        right = (right + dx).clamp(left + minSize, maxRight).toDouble();
      }
      if (movesTop) top = (top + dy).clamp(minTop, bottom - minSize).toDouble();
      if (movesBottom) {
        bottom = (bottom + dy).clamp(top + minSize, maxBottom).toDouble();
      }
      return e.copyWith(
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
      );
    }).toList();
    _setCurrentElements(elements);
  }
  void _deleteSelectedElements() {
    if (_selectedIds.isEmpty) return;
    _pushHistory();
    _setCurrentElements(
      _currentElements.where((e) => !_selectedIds.contains(e.id)).toList(),
    );
    setState(() => _selectedIds = {});
  }

  // --- Layering (z-order) ---------------------------------------------
  //
  // The canvas Stack and the PDF renderer both just paint _currentElements
  // in LIST order — later entries land on top — so "layering" here is
  // moving the selected element to a different position in that same
  // list, not maintaining a separate z-index number nothing else reads.
  // Previously there was no way to change this at all: an element's stack
  // position was permanently whatever order it happened to be added in.

  void _reorderSelectedElement(int Function(int currentIndex, int lastIndex) computeNewIndex) {
    if (_selectedIds.length != 1) return;
    final id = _selectedIds.first;
    final elements = List<IdCardTemplateElement>.of(_currentElements);
    final currentIndex = elements.indexWhere((e) => e.id == id);
    if (currentIndex == -1) return;
    final newIndex =
        computeNewIndex(currentIndex, elements.length - 1).clamp(0, elements.length - 1);
    if (newIndex == currentIndex) return;
    _pushHistory();
    final moved = elements.removeAt(currentIndex);
    elements.insert(newIndex, moved);
    _setCurrentElements(elements);
  }

  void _bringToFront() => _reorderSelectedElement((_, last) => last);
  void _sendToBack() => _reorderSelectedElement((_, __) => 0);
  void _bringForward() => _reorderSelectedElement((current, _) => current + 1);
  void _sendBackward() => _reorderSelectedElement((current, _) => current - 1);

  void _updateSelected(
    IdCardTemplateElement Function(IdCardTemplateElement) update,
  ) {
    if (_selectedIds.length != 1) return;
    _pushHistory();
    final id = _selectedIds.first;
    final elements =
        _currentElements.map((e) => e.id == id ? update(e) : e).toList();
    _setCurrentElements(elements);
  }

  /// Like [_updateSelected] but without an undo step of its own, for a
  /// control (a slider) that records one step when the drag starts.
  void _setSelectedWithoutHistory(
    IdCardTemplateElement Function(IdCardTemplateElement) update,
  ) {
    if (_selectedIds.length != 1) return;
    final id = _selectedIds.first;
    _setCurrentElements(
        _currentElements.map((e) => e.id == id ? update(e) : e).toList());
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_frontElements, _backElements, _orientation, _backgroundColor);
      if (mounted) setState(() => _dirty = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_dirty) return true;
    // Colors are resolved from this method's own context — still inside
    // this page's local Theme — before crossing into the dialog's Overlay
    // subtree (see student_records_tab.dart's _openRegisterDialog for the
    // full explanation of why `dialogContext` can't be trusted here).
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BentoFormDialog(
        title: 'Unsaved changes',
        content: Text(
          'You have unsaved changes to this template. Leave without saving?',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: ItTechnicianColors.mutedText(context),
          ),
        ),
        backgroundColor: ItTechnicianColors.card(context),
        borderColor: ItTechnicianColors.cardBorder(context),
        titleColor: ItTechnicianColors.rowText(context),
        cancelFillColor: ItTechnicianColors.fieldFill(context),
        cancelLabel: 'Stay',
        onCancel: () => Navigator.of(dialogContext).pop(false),
        confirmLabel: 'Discard',
        confirmColor: ItTechnicianColors.dangerRed,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    return discard ?? false;
  }

  // --- Print mode ----------------------------------------------------------

  bool get _needsSignature => [..._frontElements, ..._backElements]
      .any((e) => e.type == IdCardElementType.signature);

  bool get _canPrint =>
      !_printing &&
      _photoBytes != null &&
      (!_needsSignature || _signatureBytes != null);

  Future<void> _capturePhoto() async {
    final theme = Theme.of(context);
    final bytes = await showDialog<Uint8List>(
      context: context,
      builder: (_) => Theme(data: theme, child: const WebcamCaptureDialog()),
    );
    if (bytes != null && mounted) setState(() => _photoBytes = bytes);
  }

  Future<void> _captureSignature() async {
    final theme = Theme.of(context);
    final bytes = await showDialog<Uint8List>(
      context: context,
      builder: (_) =>
          Theme(data: theme, child: const SignatureCaptureDialog()),
    );
    if (bytes != null && mounted) setState(() => _signatureBytes = bytes);
  }

  Future<void> _switchTemplate(String templateId) async {
    final printContext = widget.printContext;
    if (printContext == null || templateId == _currentTemplateId) return;
    if (!await _confirmDiscardIfDirty()) return;
    if (!mounted) return;
    try {
      final detail = await printContext.onLoadTemplate(templateId);
      if (!mounted) return;
      setState(() {
        _currentTemplateId = templateId;
        _frontElements = _fitAll(detail.frontLayout);
        _backElements = _fitAll(detail.backLayout);
        _orientation = detail.orientation;
        _backgroundColor = detail.backgroundColor;
        _selectedIds = {};
        _dirty = false;
        _undoStack.clear();
        _redoStack.clear();
      });
      _ensureImageBytesLoaded();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load template: $e')));
      }
    }
  }

  Future<void> _handlePrint() async {
    final printContext = widget.printContext;
    final photoBytes = _photoBytes;
    if (printContext == null || photoBytes == null || !_canPrint) return;
    setState(() {
      _printing = true;
      _printError = null;
    });
    try {
      await printContext.onPrint(
        photoBytes: photoBytes,
        signatureBytes: _signatureBytes,
        frontLayout: _frontElements,
        backLayout: _backElements,
        orientation: _orientation,
        backgroundColor: _backgroundColor,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _printError = '$e');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // A properties-panel TextFormField (e.g. the static-text Content field)
    // has its own focus node further down the tree. When one of those is
    // focused, keys like Ctrl+C/V/Z or Backspace/Delete are meant for that
    // field's own text editing, not the canvas — let the field handle them
    // and don't also treat them as canvas shortcuts.
    if (FocusManager.instance.primaryFocus != _focusNode) {
      return KeyEventResult.ignored;
    }
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isCtrl &&
        HardwareKeyboard.instance.isShiftPressed &&
        event.logicalKey == LogicalKeyboardKey.keyZ) {
      _redo();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      _undo();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
      _copySelection();
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyV) {
      _pasteClipboard();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      _deleteSelectedElements();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Cropping ends as soon as the picture being cropped stops being the one
    // selected, so it is off again when it is next selected.
    if (_cropId != null && !_isCropping(_cropId!)) _cropId = null;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardIfDirty() && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKey,
        child: Scaffold(
          backgroundColor: ItTechnicianColors.background(context),
          body: Column(
            children: [
              _buildHeader(context),
              if (widget.printContext != null) _buildPrintBar(context),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildToolbox(context),
                      const SizedBox(width: 16),
                      Expanded(child: _buildCanvasArea(context)),
                      const SizedBox(width: 16),
                      _buildPropertiesPanel(context),
                    ],
                  ),
                ),
              ),
              _buildZoomBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ItTechnicianColors.card(context),
        border: Border(
          bottom: BorderSide(color: ItTechnicianColors.cardBorder(context)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded,
                color: ItTechnicianColors.rowText(context)),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Expanded(child: _buildTitle(context)),
          const SizedBox(width: 16),
          _FrontBackToggle(
            isFront: _showingFront,
            onChanged: (front) => setState(() {
              _showingFront = front;
              _selectedIds = {};
              _cardSelected = false;
            }),
          ),
          const SizedBox(width: 12),
          _OrientationToggle(
            orientation: _orientation,
            onChanged: (orientation) => setState(() {
              _orientation = orientation;
              _dirty = true;
            }),
          ),
          const SizedBox(width: 16),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            FilledButton(
              onPressed: _dirty ? _save : null,
              style: FilledButton.styleFrom(
                backgroundColor: ItTechnicianColors.azureBlue,
                foregroundColor: Colors.white,
                textStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: const Size(0, kDashboardControlHeight),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.standard,
              ),
              child: const Text('Save'),
            ),
        ],
      ),
    );
  }

  /// Print-mode-only toolbar: which student this is for, a template
  /// switcher, photo/signature capture, and Print. Only built when
  /// [IdCardTemplateEditorPage.printContext] is set.
  Widget _buildPrintBar(BuildContext context) {
    final printContext = widget.printContext!;
    return Container(
      decoration: BoxDecoration(
        color: ItTechnicianColors.card(context),
        border: Border(
          bottom: BorderSide(color: ItTechnicianColors.cardBorder(context)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Printing for ${printContext.student.fullName}',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ItTechnicianColors.rowText(context),
              ),
            ),
          ),
          if (printContext.availableTemplates.isNotEmpty) ...[
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                value: _currentTemplateId,
                isExpanded: true,
                isDense: true,
                decoration: _propFieldDecoration(context),
                style: _propFieldStyle(context),
                items: [
                  for (final t in printContext.availableTemplates)
                    DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                onChanged: (id) {
                  if (id != null) _switchTemplate(id);
                },
              ),
            ),
            const SizedBox(width: 10),
          ],
          SecondaryPillButton(
            label: _photoBytes == null ? 'Capture Photo' : 'Retake Photo',
            icon: Icons.camera_alt_outlined,
            onTap: _printing ? null : _capturePhoto,
          ),
          if (_needsSignature) ...[
            const SizedBox(width: 10),
            SecondaryPillButton(
              label: _signatureBytes == null
                  ? 'Capture Signature'
                  : 'Retake Signature',
              icon: Icons.draw_outlined,
              onTap: _printing ? null : _captureSignature,
            ),
          ],
          const SizedBox(width: 10),
          if (_printError != null) ...[
            Flexible(
              child: Text(
                _printError!,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: ItTechnicianColors.dangerRed,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          FilledButton.icon(
            onPressed: _canPrint ? _handlePrint : null,
            icon: _printing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.print_outlined, size: 16),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, kDashboardControlHeight),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.standard,
              backgroundColor: ItTechnicianColors.azureBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            label: Text('Print', style: _buttonTextStyle()),
          ),
        ],
      ),
    );
  }

  static TextStyle _buttonTextStyle() =>
      GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600);

  Widget _buildTitle(BuildContext context) {
    final titleStyle = GoogleFonts.poppins(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: ItTechnicianColors.rowText(context),
    );

    if (!_editingName) {
      return InkWell(
        onTap: _beginNameEdit,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _currentName,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.edit_outlined,
                  size: 15, color: ItTechnicianColors.mutedText(context)),
            ],
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            _cancelNameEdit();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          controller: _nameController,
          focusNode: _nameFocusNode,
          autofocus: true,
          style: titleStyle,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: ItTechnicianColors.fieldFill(context),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: _commitNameEdit,
        ),
      ),
    );
  }

  /// Shared top-level Bento UI panel shell for the toolbox/canvas/properties
  /// panels below — matches the rest of the IT Technician dashboard's card
  /// convention ([ItTechnicianColors.card]/[ItTechnicianColors.cardBorder],
  /// default 20px radius + shadow). `Clip.antiAlias` keeps each panel's own
  /// scrolling content from drawing past the rounded corners.
  Widget _bentoCard(BuildContext context, {required Widget child}) {
    return BentoCard(
      backgroundColor: ItTechnicianColors.card(context),
      borderColor: ItTechnicianColors.cardBorder(context),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildToolbox(BuildContext context) {
    return SizedBox(
      width: 110,
      child: _bentoCard(
        context,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final (type, label, icon) in _toolboxItems)
              Draggable<IdCardElementType>(
                data: type,
                feedback: Material(
                  color: Colors.transparent,
                  child:
                      Icon(icon, size: 28, color: ItTechnicianColors.azureBlue),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      Icon(icon, size: 22),
                      const SizedBox(height: 4),
                      Text(label,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: ItTechnicianColors.rowText(context),
                          ),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvasArea(BuildContext context) {
    // No panel around the canvas: the card being edited is the only surface
    // in the middle, sitting directly on the page background. The ClipRect
    // keeps a zoomed-in card from drawing over the toolbox/properties panels.
    return ClipRect(
      // Clicking the empty space around the card deselects everything.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _clearSelection,
        child: DragTarget<IdCardElementType>(
          onAcceptWithDetails: (details) => _addElement(details.data),
          builder: (context, candidateData, rejectedData) => _zoomViewport(
            overlay: (origin) => [
              ..._cardSelectionRing(origin),
              ..._resizeHandles(origin),
            ],
            card: Container(
              width: _cardWidthPt * _zoom,
              height: _cardHeightPt * _zoom,
              decoration: BoxDecoration(
                color: Color(_backgroundColor),
                // Lifts the card being edited off the page background so it's
                // unambiguous which surface is the live editing area.
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withOpacity(context.isDarkMode ? 0.45 : 0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _selectCard,
                onPanStart: (details) {
                  _focusCanvas();
                  setState(() {
                    _marqueeStart = details.localPosition;
                    _marqueeCurrent = details.localPosition;
                  });
                },
                onPanUpdate: (details) {
                  if (_marqueeStart == null) return;
                  setState(() => _marqueeCurrent = details.localPosition);
                },
                onPanEnd: (_) {
                  final start = _marqueeStart;
                  final end = _marqueeCurrent;
                  if (start != null && end != null) {
                    final rect = Rect.fromPoints(start, end);
                    final hits = _currentElements
                        .where((e) => rect.overlaps(Rect.fromLTWH(
                              e.x * _zoom,
                              e.y * _zoom,
                              e.width * _zoom,
                              e.height * _zoom,
                            )))
                        .map((e) => e.id)
                        .toSet();
                    setState(() => _selectedIds = hits);
                  }
                  setState(() {
                    _marqueeStart = null;
                    _marqueeCurrent = null;
                  });
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Whatever part of an element hangs off the card is cut
                    // away, as it is on the printed card.
                    Positioned.fill(
                      child: ClipRect(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final element in _currentElements)
                              _buildElementWidget(element),
                          ],
                        ),
                      ),
                    ),
                    // Selection outlines sit above the clip, so the whole
                    // outline of a partly off-card element stays visible.
                    for (final element in _currentElements)
                      if (_selectedIds.contains(element.id) ||
                          _editingTextId == element.id)
                        Positioned(
                          left: element.x * _zoom,
                          top: element.y * _zoom,
                          width: element.width * _zoom,
                          height: element.height * _zoom,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [_selectionRing()],
                          ),
                        ),
                    for (final x in _guideLinesX)
                      Positioned(
                        left: x,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 1, color: Colors.redAccent),
                      ),
                    for (final y in _guideLinesY)
                      Positioned(
                        top: y,
                        left: 0,
                        right: 0,
                        child: Container(height: 1, color: Colors.redAccent),
                      ),
                    if (_marqueeStart != null && _marqueeCurrent != null)
                      Positioned.fromRect(
                        rect: Rect.fromPoints(_marqueeStart!, _marqueeCurrent!),
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                ItTechnicianColors.azureBlue.withOpacity(0.1),
                            border:
                                Border.all(color: ItTechnicianColors.azureBlue),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Centers [card] in the canvas area while it fits, and lets the area
  /// scroll in both directions once the zoomed card outgrows it. Ctrl + wheel
  /// over it zooms (see [_handleCanvasPointerSignal]); a plain wheel scrolls.
  Widget _zoomViewport({
    required Widget card,
    List<Widget> Function(Offset cardOrigin)? overlay,
  }) {
    const margin = 24.0;
    return LayoutBuilder(
      builder: (context, viewport) {
        final contentWidth =
            math.max(viewport.maxWidth, _cardWidthPt * _zoom + margin * 2);
        final contentHeight =
            math.max(viewport.maxHeight, _cardHeightPt * _zoom + margin * 2);
        return SingleChildScrollView(
          controller: _canvasHScroll,
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            controller: _canvasVScroll,
            // The Listener sits INSIDE the scroll views so it is the first
            // to see a wheel tick and can claim it for zooming.
            child: Listener(
              // Opaque, so the blank area around the card counts too: a plain
              // Listener only receives events over its child's own painted
              // widgets, and the wheel would then work over the card only.
              behavior: HitTestBehavior.opaque,
              onPointerSignal: _handleCanvasPointerSignal,
              onPointerPanZoomStart: (_) => _panZoomStartZoom = _zoom,
              onPointerPanZoomUpdate: (e) =>
                  _setZoom(_panZoomStartZoom * e.scale),
              child: SizedBox(
                width: contentWidth,
                height: contentHeight,
                child: Stack(
                  children: [
                    Positioned.fill(child: Center(child: card)),
                    // Drawn over the card, in the same coordinates, where the
                    // card sits centered in this area.
                    if (overlay != null)
                      ...overlay(Offset(
                        (contentWidth - _cardWidthPt * _zoom) / 2,
                        (contentHeight - _cardHeightPt * _zoom) / 2,
                      )),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The bar along the bottom of the screen: zoom out / slider / zoom in and
  /// the current zoom as a percentage.
  Widget _buildZoomBar(BuildContext context) {
    final percent = (_zoom / _defaultZoom * 100).round();
    return Container(
      decoration: BoxDecoration(
        color: ItTechnicianColors.card(context),
        border: Border(
          top: BorderSide(color: ItTechnicianColors.cardBorder(context)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Zoom out',
            icon: const Icon(Icons.remove_rounded, size: 20),
            color: ItTechnicianColors.rowText(context),
            onPressed: _zoom > _minZoom ? () => _setZoom(_zoom - _zoomStep) : null,
          ),
          SizedBox(
            width: 260,
            child: Slider(
              value: _zoom.clamp(_minZoom, _maxZoom).toDouble(),
              min: _minZoom,
              max: _maxZoom,
              activeColor: ItTechnicianColors.azureBlue,
              onChanged: _setZoom,
            ),
          ),
          IconButton(
            tooltip: 'Zoom in',
            icon: const Icon(Icons.add_rounded, size: 20),
            color: ItTechnicianColors.rowText(context),
            onPressed: _zoom < _maxZoom ? () => _setZoom(_zoom + _zoomStep) : null,
          ),
          const SizedBox(width: 8),
          _buildZoomPercentMenu(context, percent),
        ],
      ),
    );
  }

  /// The zoom percentage as a dropdown: pick a preset from [_zoomPresets].
  Widget _buildZoomPercentMenu(BuildContext context, int percent) {
    final textColor = ItTechnicianColors.rowText(context);
    final style = GoogleFonts.poppins(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: textColor,
    );
    return PopupMenuButton<int>(
      tooltip: 'Zoom level',
      position: PopupMenuPosition.over,
      color: ItTechnicianColors.card(context),
      onSelected: (value) => _setZoom(_defaultZoom * value / 100),
      itemBuilder: (context) => [
        for (final preset in _zoomPresets)
          PopupMenuItem<int>(
            value: preset,
            height: 36,
            child: Text(
              '$preset%',
              style: style.copyWith(
                color: preset == percent
                    ? ItTechnicianColors.azureBlue
                    : textColor,
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 38,
              child: Text('$percent%', textAlign: TextAlign.right, style: style),
            ),
            Icon(Icons.arrow_drop_down_rounded, size: 20, color: textColor),
          ],
        ),
      ),
    );
  }

  /// The selection outline, drawn just OUTSIDE the element's box so it never
  /// overlaps the content (for text, the last glyph) it hugs: a 2px blue ring
  /// with a 2px white halo around it. The halo is what keeps the selection
  /// visible when the card's background is itself blue (or any dark color);
  /// on a light background the halo simply disappears into it.
  Widget _selectionRing() => Positioned(
        left: -_ringWidth * 2,
        top: -_ringWidth * 2,
        right: -_ringWidth * 2,
        bottom: -_ringWidth * 2,
        child: IgnorePointer(
          child: Stack(
            children: [
              // Halo: the outer 2px.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: _ringWidth),
                  ),
                ),
              ),
              // Ring: the inner 2px, hugging the element.
              Positioned(
                left: _ringWidth,
                top: _ringWidth,
                right: _ringWidth,
                bottom: _ringWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: ItTechnicianColors.azureBlue, width: _ringWidth),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  static const double _ringWidth = 2;

  Widget _buildElementWidget(IdCardTemplateElement element) {
    // Double-clicked static text: typed into in place, no gestures on top.
    if (_editingTextId == element.id) {
      final boxWidth = element.width * _zoom;
      return Positioned(
        left: element.x * _zoom,
        top: element.y * _zoom,
        width: boxWidth,
        height: element.height * _zoom,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Far wider than the text on purpose: the field must never wrap or
            // scroll sideways as it is typed into (a field only a few pixels
            // wider than its text — room for the caret — wraps "Static Text"
            // onto two lines). Only the part inside the element's own box
            // can be hit, so the extra width is invisible and inert.
            // A faint tint over the box marks it as "being edited" even while
            // nothing is selected and the caret is mid-blink.
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: _editingTint),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: math.max(boxWidth + 8, 4000),
              child: _inlineTextEditor(element),
            ),
          ],
        ),
      );
    }

    return Positioned(
      left: element.x * _zoom,
      top: element.y * _zoom,
      width: element.width * _zoom,
      height: element.height * _zoom,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleElementTapOrDoubleTap(element),
        onPanStart: (_) {
          _focusCanvas();
          if (!_selectedIds.contains(element.id)) _selectOnly(element.id);
          _pushHistory();
          _dragCumulativeDelta = Offset.zero;
          _dragStartPositions = {
            for (final e in _currentElements)
              if (_selectedIds.contains(e.id)) e.id: Offset(e.x, e.y),
          };
        },
        onPanUpdate: (details) => _isCropping(element.id)
            ? _panCrop(element.id, details.delta)
            : _moveSelection(details.delta),
        onPanEnd: (_) => setState(() {
          _guideLinesX = [];
          _guideLinesY = [];
          _dragStartPositions = {};
          _dragCumulativeDelta = Offset.zero;
        }),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: _elementContent(element)),
          ],
        ),
      ),
    );
  }

  // --- Inline text editing -----------------------------------------------

  // A double-click is recognised by hand (two taps on the same text element
  // in quick succession) rather than with onDoubleTap, because a widget
  // listening for double-taps holds back its plain taps until it is sure
  // there is no second one — which would delay every selection by ~300ms.
  static const _doubleClickWindow = Duration(milliseconds: 350);
  String? _lastTappedElementId;
  DateTime? _lastElementTapAt;

  void _handleElementTapOrDoubleTap(IdCardTemplateElement element) {
    _focusCanvas();
    final now = DateTime.now();
    final isDoubleClick = element.type == IdCardElementType.staticText &&
        _lastTappedElementId == element.id &&
        _lastElementTapAt != null &&
        now.difference(_lastElementTapAt!) < _doubleClickWindow;
    if (isDoubleClick) {
      _lastTappedElementId = null;
      _lastElementTapAt = null;
      _startTextEdit(element.id);
      return;
    }
    _lastTappedElementId = element.id;
    _lastElementTapAt = now;
    _handleElementTap(element.id);
  }


  /// The static text element being typed into on the canvas, if any.
  String? _editingTextId;
  String _editingOriginalText = '';
  final _textEditController = TextEditingController();
  final _textEditFocus = FocusNode();

  void _startTextEdit(String id) {
    final element = _currentElements.where((e) => e.id == id).firstOrNull;
    if (element == null || element.type != IdCardElementType.staticText) return;
    _pushHistory(); // the whole typing session is one undo step
    _editingOriginalText = element.textContent ?? '';
    _textEditController.value = TextEditingValue(
      text: _editingOriginalText,
      selection: TextSelection(
          baseOffset: 0, extentOffset: _editingOriginalText.length),
    );
    setState(() {
      _selectedIds = {id};
      _editingTextId = id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editingTextId == id) _textEditFocus.requestFocus();
    });
  }

  void _onTextEditChanged(String text) {
    final id = _editingTextId;
    if (id == null) return;
    // The element's box re-fits to the new text (see _setCurrentElements).
    _setCurrentElements([
      for (final e in _currentElements)
        e.id == id ? e.copyWith(textContent: text) : e,
    ]);
  }

  /// Leaves edit mode keeping what was typed (Enter, or clicking away).
  void _commitTextEdit() {
    if (_editingTextId == null) return;
    setState(() => _editingTextId = null);
    _focusNode.requestFocus();
  }

  /// Escape: puts the original text back.
  void _cancelTextEdit() {
    final id = _editingTextId;
    if (id == null) return;
    _setCurrentElements([
      for (final e in _currentElements)
        e.id == id ? e.copyWith(textContent: _editingOriginalText) : e,
    ]);
    // Nothing changed overall, so drop the undo step _startTextEdit added.
    if (_undoStack.isNotEmpty) _undoStack.removeLast();
    setState(() => _editingTextId = null);
    _focusNode.requestFocus();
  }

  // Colors for typing into a text element in place. They are picked against
  // the CARD's color — the editor's own accent blue is invisible on a blue
  // card — so the selection, the caret and the "editing" tint always show:
  // white on a dark card, the accent blue on a light one.
  bool get _cardIsDark => Color(_backgroundColor).computeLuminance() < 0.5;

  Color get _editingSelectionColor => _cardIsDark
      ? Colors.white.withOpacity(0.38)
      : ItTechnicianColors.azureBlue.withOpacity(0.30);

  Color get _editingCaretColor =>
      _cardIsDark ? Colors.white : ItTechnicianColors.azureBlue;

  Color get _editingTint => _cardIsDark
      ? Colors.white.withOpacity(0.14)
      : ItTechnicianColors.azureBlue.withOpacity(0.08);

  Widget _inlineTextEditor(IdCardTemplateElement element) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelTextEdit();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextSelectionTheme(
        // The default selection color is the same blue as this editor's
        // accent, so on a blue card the highlighted (and the caret) text was
        // impossible to see. These follow the card's own color instead.
        data: TextSelectionThemeData(
          selectionColor: _editingSelectionColor,
          cursorColor: _editingCaretColor,
        ),
        child: TextField(
          controller: _textEditController,
          focusNode: _textEditFocus,
          // Static text is a single line (so is the panel's Content field):
          // Enter finishes the edit instead of adding a line break.
          maxLines: 1,
          textInputAction: TextInputAction.done,
          style: _staticTextStyle(element, _zoom),
          cursorColor: _editingCaretColor,
          decoration: const InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: _onTextEditChanged,
          onSubmitted: (_) => _commitTextEdit(),
          onTapOutside: (_) => _commitTextEdit(),
        ),
      ),
    );
  }

  /// The highlight of the selected card: a 3px blue border drawn just OUTSIDE
  /// it, over the canvas background — so it stays visible whatever color the
  /// card itself is (inside the card, a blue border vanished on a blue card).
  /// Nothing is drawn while the card isn't selected.
  List<Widget> _cardSelectionRing(Offset cardOrigin) {
    if (!_cardSelected) return const [];
    const width = 3.0;
    return [
      Positioned(
        key: const ValueKey('card-selection-ring'),
        left: cardOrigin.dx - width,
        top: cardOrigin.dy - width,
        width: _cardWidthPt * _zoom + width * 2,
        height: _cardHeightPt * _zoom + width * 2,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                  color: ItTechnicianColors.azureBlue, width: width),
            ),
          ),
        ),
      ),
    ];
  }

  /// The eight resize handles of the single selected element, as one overlay
  /// over the whole canvas area (not inside the element) so the half of each
  /// handle that sticks out past the element is still clickable.
  /// [cardOrigin] is where the card's top-left sits in that area.
  List<Widget> _resizeHandles(Offset cardOrigin) {
    if (_selectedIds.length != 1 || _editingTextId != null) return const [];
    final id = _selectedIds.first;
    final element = _currentElements.where((e) => e.id == id).firstOrNull;
    if (element == null) return const [];

    const hit = 24.0; // tap target
    const dot = 12.0; // what you see
    final rect = Rect.fromLTWH(
      cardOrigin.dx + element.x * _zoom,
      cardOrigin.dy + element.y * _zoom,
      element.width * _zoom,
      element.height * _zoom,
    );
    return [
      // Sides first, corners last, so a corner wins where they overlap on a
      // very small element.
      for (final handle in [
        _ResizeHandle.n,
        _ResizeHandle.e,
        _ResizeHandle.s,
        _ResizeHandle.w,
        _ResizeHandle.nw,
        _ResizeHandle.ne,
        _ResizeHandle.se,
        _ResizeHandle.sw,
      ])
        Positioned(
          left: rect.left + rect.width * handle.anchor.dx - hit / 2,
          top: rect.top + rect.height * handle.anchor.dy - hit / 2,
          width: hit,
          height: hit,
          child: MouseRegion(
            cursor: handle.cursor,
            child: GestureDetector(
              key: ValueKey('resize-${handle.name}'),
              behavior: HitTestBehavior.opaque,
              // A plain click on a handle must not fall through to the
              // canvas and deselect the element.
              onTap: _focusCanvas,
              onPanStart: (_) {
                _focusCanvas();
                _pushHistory();
              },
              onPanUpdate: (details) =>
                  _resizeElement(id, handle, details.delta),
              child: Center(
                child: Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    // White fill with a blue edge: shows on a blue card (the
                    // white) as well as on a light one (the blue edge).
                    color: Colors.white,
                    border: Border.all(
                        color: ItTechnicianColors.azureBlue, width: 2),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _elementContent(IdCardTemplateElement element) {
    final student = widget.printContext?.student;
    switch (element.type) {
      case IdCardElementType.staticText:
        return Text(
          element.textContent ?? '',
          // Never wraps: the element's box is measured from this one-line
          // layout (see _fitText).
          softWrap: false,
          overflow: TextOverflow.visible,
          style: _staticTextStyle(element, _zoom),
        );
      case IdCardElementType.idData:
        return Text(
          student == null
              ? '{${element.fieldKey?.name ?? 'field'}}'
              : _studentFieldValue(element.fieldKey, student),
          style: TextStyle(
            fontSize: (element.fontSize ?? 10) * _zoom,
            fontWeight: _fontWeightOf(element),
            color: Color(element.color ?? 0xFF000000),
            fontStyle: student == null ? FontStyle.italic : FontStyle.normal,
          ),
        );
      case IdCardElementType.image:
        final bytes =
            element.imagePath == null ? null : _imageBytesByPath[element.imagePath];
        return _withOpacity(
          element,
          ClipRRect(
            borderRadius:
                BorderRadius.circular(_cornerRadiusOf(element) * _zoom),
            child: bytes != null
                ? _croppedPicture(element, bytes)
                : Container(
                    color: const Color(0xFFE5E7EB),
                    alignment: Alignment.center,
                    child: const Icon(Icons.image_outlined, size: 16),
                  ),
          ),
        );
      case IdCardElementType.idPicture:
        // Rounded like the printed card (see _cornerRadiusOf).
        return _withOpacity(
          element,
          ClipRRect(
            borderRadius:
                BorderRadius.circular(_cornerRadiusOf(element) * _zoom),
            child: _photoBytes != null
                ? _croppedPicture(element, _photoBytes!)
                : Container(
                    color: const Color(0xFFE5E7EB),
                    alignment: Alignment.center,
                    child: const Text('PHOTO', style: TextStyle(fontSize: 9)),
                  ),
          ),
        );
      case IdCardElementType.signature:
        if (_signatureBytes != null) {
          return Image.memory(_signatureBytes!, fit: BoxFit.contain);
        }
        return Container(
          color: const Color(0xFFF3F4F6),
          alignment: Alignment.center,
          child: const Text('SIGNATURE', style: TextStyle(fontSize: 8)),
        );
      case IdCardElementType.rectangle:
      case IdCardElementType.roundedRect:
        return Container(
          decoration: BoxDecoration(
            color: Color(element.fillColor ?? 0x00000000),
            border: Border.all(
              color: Color(element.strokeColor ?? 0xFF000000),
              width: element.strokeWidth ?? 1,
            ),
            borderRadius:
                BorderRadius.circular(_cornerRadiusOf(element) * _zoom),
          ),
        );
      case IdCardElementType.ellipse:
        return Container(
          decoration: BoxDecoration(
            color: Color(element.fillColor ?? 0x00000000),
            border: Border.all(
              color: Color(element.strokeColor ?? 0xFF000000),
              width: element.strokeWidth ?? 1,
            ),
            shape: BoxShape.circle,
          ),
        );
      case IdCardElementType.line:
        return Container(color: Color(element.strokeColor ?? 0xFF000000));
    }
  }

  /// Section-label style for every property group in this panel ("Position
  /// & Size", "Content", "Fill", …) — Poppins/w600, matching every other
  /// panel label in the dashboard instead of the theme's default font. Sized
  /// up from the original 11px so the panel reads clearly at a glance.
  TextStyle _propLabelStyle(BuildContext context) => GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ItTechnicianColors.rowText(context),
      );

  /// Field/value text style for this panel's number fields, text fields, and
  /// dropdown items.
  TextStyle _propFieldStyle(BuildContext context) => GoogleFonts.poppins(
        fontSize: 13,
        color: ItTechnicianColors.rowText(context),
      );

  /// The weights the Font Weight property offers: CSS-style value → name.
  /// Only these two, because the printed card (Helvetica Regular/Bold, see
  /// `student_id_card_pdf.dart`) can't show any other weight — offering more
  /// would promise a look that never prints.
  static const List<(int, String)> _fontWeightOptions = [
    (400, 'Regular'),
    (700, 'Bold'),
  ];

  /// How [e]'s text is drawn: bold when saved at Semi Bold (600) or heavier —
  /// exactly where the printed card turns bold — else regular. That also
  /// covers templates saved with any other weight.
  static FontWeight _fontWeightOf(IdCardTemplateElement e) =>
      (e.fontWeight ?? 400) >= 600 ? FontWeight.w700 : FontWeight.w400;

  /// The Font Weight property: a dropdown of [_fontWeightOptions], each name
  /// previewed in its own weight.
  Widget _fontWeightDropdown(
      BuildContext context, IdCardTemplateElement element) {
    return DropdownButton<int>(
      key: ValueKey('${element.id}_font_weight'),
      value: (element.fontWeight ?? 400) >= 600 ? 700 : 400,
      isExpanded: true,
      items: [
        for (final (weight, name) in _fontWeightOptions)
          DropdownMenuItem(
            value: weight,
            child: Text(
              name,
              style: _propFieldStyle(context).copyWith(
                fontWeight: FontWeight.values[weight ~/ 100 - 1],
              ),
            ),
          ),
      ],
      onChanged: (weight) {
        if (weight != null) {
          _updateSelected((e) => e.copyWith(fontWeight: weight));
        }
      },
    );
  }

  /// Small label placed directly above a single field ("X", "Content", …) —
  /// this panel's own sized-up equivalent of the shared `FieldLabel` widget
  /// (kept local rather than resizing `FieldLabel` itself, since that widget
  /// is also used by every other dialog/form in this dashboard).
  Widget _propFieldLabel(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: ItTechnicianColors.rowText(context),
          ),
        ),
      );

  /// Pale rounded-10 borderless field fill — same recipe as the rest of the
  /// dashboard's fields ([fieldDecoration]), sized up a bit from this panel's
  /// original cramped padding now that the panel itself is wider.
  InputDecoration _propFieldDecoration(BuildContext context) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: ItTechnicianColors.fieldFill(context),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              BorderSide(color: ItTechnicianColors.azureBlue, width: 1.5),
        ),
      );

  /// Properties panel width — widened from the original 160px so bigger
  /// text and pill buttons ("Delete Element") have room without wrapping.
  static const _propertiesPanelWidth = 260.0;

  Widget _buildPropertiesPanel(BuildContext context) {
    if (_selectedIds.isEmpty && _cardSelected) {
      return SizedBox(
        width: _propertiesPanelWidth,
        child: _bentoCard(
          context,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Card', style: _propLabelStyle(context)),
                const SizedBox(height: 14),
                _propFieldLabel(context, 'Background'),
                // Every preset color is laid out here — no picker to open.
                _colorSwatchRow(
                  _backgroundColor,
                  (c) => setState(() {
                    _backgroundColor = c;
                    _dirty = true;
                  }),
                  size: 28,
                  allowTransparent: false,
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_selectedIds.length != 1) {
      return SizedBox(
        width: _propertiesPanelWidth,
        child: _bentoCard(
          context,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Select an element to edit its properties.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: ItTechnicianColors.mutedText(context),
              ),
            ),
          ),
        ),
      );
    }
    final id = _selectedIds.first;
    final element = _currentElements.firstWhere((e) => e.id == id);
    return SizedBox(
      width: _propertiesPanelWidth,
      child: _bentoCard(
        context,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Position & Size', style: _propLabelStyle(context)),
              const SizedBox(height: 14),
              _numberField(
                  context,
                  'X',
                  element.x,
                  (v) => _updateSelected(
                      (e) => e.copyWith(x: _clampX(v, e.width)))),
              _numberField(
                  context,
                  'Y',
                  element.y,
                  (v) => _updateSelected(
                      (e) => e.copyWith(y: _clampY(v, e.height)))),
              _numberField(
                  context,
                  'W',
                  element.width,
                  (v) => _updateSelected(
                      (e) => e.copyWith(width: v.clamp(8, _cardWidthPt)))),
              _numberField(
                  context,
                  'H',
                  element.height,
                  (v) => _updateSelected(
                      (e) => e.copyWith(height: v.clamp(8, _cardHeightPt)))),
              const SizedBox(height: 16),
              ..._typeSpecificFields(context, element),
              _propFieldLabel(context, 'Layer'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'Bring to Front',
                    icon: const Icon(Icons.flip_to_front, size: 20),
                    onPressed: _bringToFront,
                  ),
                  IconButton(
                    tooltip: 'Bring Forward',
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    onPressed: _bringForward,
                  ),
                  IconButton(
                    tooltip: 'Send Backward',
                    icon: const Icon(Icons.arrow_downward, size: 20),
                    onPressed: _sendBackward,
                  ),
                  IconButton(
                    tooltip: 'Send to Back',
                    icon: const Icon(Icons.flip_to_back, size: 20),
                    onPressed: _sendToBack,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PillButton(
                label: 'Delete Element',
                icon: Icons.delete_outline_rounded,
                background: ItTechnicianColors.dangerRed,
                onTap: _deleteSelectedElements,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _colorPresets = [
    0x00000000,
    0xFF000000,
    0xFFFFFFFF,
    0xFF345892,
    0xFFCD4855,
    0xFF137333,
    0xFFF5C518,
  ];

  /// Outline of a swatch / of the unselected editable card — dark enough to
  /// show a white one against a white panel or canvas.
  Color _cardOutlineColor(BuildContext context) => context.isDarkMode
      ? const Color(0xFF8A8F9C)
      : const Color(0xFF64748B);

  /// All the preset colors laid out open, one tap each. The current one gets
  /// a blue ring and a check mark; every swatch has a strong grey outline so
  /// white stays visible on the white panel. [allowTransparent] adds the
  /// "none" swatch (an empty circle) for properties that can be unset — not
  /// for the card background, where transparent would be meaningless.
  Widget _colorSwatchRow(
    int? current,
    ValueChanged<int> onPick, {
    double size = 18,
    bool allowTransparent = true,
  }) {
    return Builder(builder: (context) {
      final outline = _cardOutlineColor(context);
      return Wrap(
        spacing: size >= 24 ? 10 : 6,
        runSpacing: size >= 24 ? 10 : 6,
        children: [
          for (final c in _colorPresets)
            if (allowTransparent || c != 0x00000000)
              Builder(builder: (context) {
                final selected = current == c;
                final fill = Color(c);
                final isLight = fill.computeLuminance() > 0.6;
                return Tooltip(
                  message: c == 0x00000000 ? 'None' : _colorName(c),
                  child: GestureDetector(
                    onTap: () => onPick(c),
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: fill,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? ItTechnicianColors.azureBlue
                              : outline,
                          width: selected ? 3 : 1.5,
                        ),
                      ),
                      child: selected && c != 0x00000000
                          ? Icon(
                              Icons.check_rounded,
                              size: size * 0.6,
                              color: isLight ? Colors.black87 : Colors.white,
                            )
                          : null,
                    ),
                  ),
                );
              }),
        ],
      );
    });
  }

  static String _colorName(int c) => switch (c) {
        0xFF000000 => 'Black',
        0xFFFFFFFF => 'White',
        0xFF345892 => 'Blue',
        0xFFCD4855 => 'Red',
        0xFF137333 => 'Green',
        0xFFF5C518 => 'Yellow',
        _ => 'Color',
      };

  List<Widget> _typeSpecificFields(
      BuildContext context, IdCardTemplateElement element) {
    switch (element.type) {
      case IdCardElementType.staticText:
        return [
          _propFieldLabel(context, 'Content'),
          // Follows the element live (e.g. while it is typed into on the
          // canvas), not only what it was when it was selected.
          _LiveTextField(
            key: ValueKey('${element.id}_content'),
            value: element.textContent ?? '',
            style: _propFieldStyle(context),
            decoration: _propFieldDecoration(context),
            onSubmitted: (text) =>
                _updateSelected((e) => e.copyWith(textContent: text)),
          ),
          const SizedBox(height: 14),
          _numberField(
            context,
            'Font Size',
            element.fontSize ?? 10,
            (v) => _updateSelected((e) => e.copyWith(fontSize: v)),
            decimals: 1,
          ),
          _propFieldLabel(context, 'Font Weight'),
          _fontWeightDropdown(context, element),
          const SizedBox(height: 14),
          _propFieldLabel(context, 'Color'),
          _colorSwatchRow(
            element.color,
            (c) => _updateSelected((e) => e.copyWith(color: c)),
          ),
          const SizedBox(height: 16),
        ];
      case IdCardElementType.idData:
        return [
          _propFieldLabel(context, 'Field'),
          DropdownButton<IdDataFieldKey>(
            value: element.fieldKey ?? IdDataFieldKey.fullName,
            isExpanded: true,
            items: [
              for (final key in IdDataFieldKey.values)
                DropdownMenuItem(
                    value: key,
                    child: Text(key.name, style: _propFieldStyle(context))),
            ],
            onChanged: (key) {
              if (key != null)
                _updateSelected((e) => e.copyWith(fieldKey: key));
            },
          ),
          const SizedBox(height: 14),
          _numberField(
            context,
            'Font Size',
            element.fontSize ?? 10,
            (v) => _updateSelected((e) => e.copyWith(fontSize: v)),
            decimals: 1,
          ),
          _propFieldLabel(context, 'Font Weight'),
          _fontWeightDropdown(context, element),
          const SizedBox(height: 14),
          _propFieldLabel(context, 'Color'),
          _colorSwatchRow(
            element.color,
            (c) => _updateSelected((e) => e.copyWith(color: c)),
          ),
          const SizedBox(height: 16),
        ];
      case IdCardElementType.image:
        return [
          PillButton(
            label: 'Replace Image',
            icon: Icons.image_outlined,
            onTap: () => _pickAndUploadImage(element.id),
          ),
          const SizedBox(height: 16),
          _borderRadiusField(context, element),
          _opacityField(context, element),
          _cropControls(context, element),
          const SizedBox(height: 16),
        ];
      case IdCardElementType.idPicture:
        return [
          _borderRadiusField(context, element),
          _opacityField(context, element),
          _cropControls(context, element),
          const SizedBox(height: 16),
        ];
      case IdCardElementType.signature:
        return const [];
      case IdCardElementType.rectangle:
      case IdCardElementType.roundedRect:
      case IdCardElementType.ellipse:
        return [
          _propFieldLabel(context, 'Fill'),
          _colorSwatchRow(
            element.fillColor,
            (c) => _updateSelected((e) => e.copyWith(fillColor: c)),
          ),
          const SizedBox(height: 12),
          _propFieldLabel(context, 'Stroke'),
          _colorSwatchRow(
            element.strokeColor,
            (c) => _updateSelected((e) => e.copyWith(strokeColor: c)),
          ),
          const SizedBox(height: 12),
          _numberField(
            context,
            'Width',
            element.strokeWidth ?? 1,
            (v) => _updateSelected((e) => e.copyWith(strokeWidth: v)),
          ),
          if (element.type != IdCardElementType.ellipse)
            _borderRadiusField(context, element),
          const SizedBox(height: 16),
        ];
      case IdCardElementType.line:
        return [
          _propFieldLabel(context, 'Stroke'),
          _colorSwatchRow(
            element.strokeColor,
            (c) => _updateSelected((e) => e.copyWith(strokeColor: c)),
          ),
          const SizedBox(height: 12),
          _numberField(
            context,
            'Width',
            element.strokeWidth ?? 1,
            (v) => _updateSelected((e) => e.copyWith(strokeWidth: v)),
          ),
          const SizedBox(height: 16),
        ];
    }
  }

  Future<void> _pickAndUploadImage(String elementId) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (bytes == null) return;
    try {
      final path = await widget.onUploadImage(bytes, file!.name);
      // Cache the bytes we already have in memory immediately — the canvas
      // can then show the real picture right away without waiting on (or
      // even needing) onFetchImageBytes to re-download what was just
      // uploaded.
      setState(() => _imageBytesByPath[path] = bytes);
      _pushHistory();
      _updateSelected((e) => e.copyWith(imagePath: path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not upload image: $e')));
      }
    }
  }

  // --- Picture crop & opacity ---------------------------------------------

  /// The alignment of an Image / ID Picture's crop window: -1 is the picture's
  /// left/top edge, 1 its right/bottom edge.
  static Alignment _cropAlignment(IdCardTemplateElement e) =>
      Alignment((e.cropX ?? 0).clamp(-1.0, 1.0).toDouble(),
          (e.cropY ?? 0).clamp(-1.0, 1.0).toDouble());

  static double _cropZoomOf(IdCardTemplateElement e) =>
      (e.cropZoom ?? 1).clamp(1.0, 4.0).toDouble();

  /// [bytes] drawn inside [element]'s frame with its crop applied: the picture
  /// fills a box [_cropZoomOf] times the frame, and the frame shows the part of
  /// it the crop alignment points at. With no crop it is just the picture
  /// filling the frame.
  Widget _croppedPicture(IdCardTemplateElement element, Uint8List bytes) {
    final zoom = _cropZoomOf(element);
    final alignment = _cropAlignment(element);
    final width = element.width * _zoom;
    final height = element.height * _zoom;
    return ClipRect(
      child: OverflowBox(
        alignment: alignment,
        minWidth: 0,
        minHeight: 0,
        maxWidth: width * zoom,
        maxHeight: height * zoom,
        child: SizedBox(
          width: width * zoom,
          height: height * zoom,
          child: Image.memory(bytes, fit: BoxFit.cover, alignment: alignment),
        ),
      ),
    );
  }

  Widget _withOpacity(IdCardTemplateElement element, Widget child) {
    final opacity = (element.opacity ?? 1).clamp(0.0, 1.0).toDouble();
    return opacity >= 1 ? child : Opacity(opacity: opacity, child: child);
  }

  /// The picture being cropped: while set (and still the only selected
  /// element), dragging it on the canvas moves the picture inside its frame
  /// instead of moving the frame.
  String? _cropId;

  bool _isCropping(String id) =>
      _cropId == id && _selectedIds.length == 1 && _selectedIds.first == id;

  /// Slides the picture inside [id]'s frame by [screenDelta]. The farther it
  /// is zoomed in, the more picture there is to slide through, so the same
  /// drag moves the crop less.
  void _panCrop(String id, Offset screenDelta) {
    final element = _currentElements.where((e) => e.id == id).firstOrNull;
    if (element == null) return;
    final reach = math.max(_cropZoomOf(element) - 1, 0.25);
    final dx = -2 * screenDelta.dx / (element.width * _zoom * reach);
    final dy = -2 * screenDelta.dy / (element.height * _zoom * reach);
    final alignment = _cropAlignment(element);
    _setCurrentElements([
      for (final e in _currentElements)
        if (e.id == id)
          e.copyWith(
            cropX: (alignment.x + dx).clamp(-1.0, 1.0).toDouble(),
            cropY: (alignment.y + dy).clamp(-1.0, 1.0).toDouble(),
          )
        else
          e,
    ]);
  }

  /// The corner radius of an Image, ID Picture or Rectangle, in the same card
  /// units as every other size here, never more than half its shorter side (a
  /// full circle/pill).
  static double _cornerRadiusOf(IdCardTemplateElement e) =>
      (e.cornerRadius ?? 0).clamp(0.0, math.min(e.width, e.height) / 2).toDouble();

  /// The Border Radius property (Image, ID Picture, Rectangle): a number field to type the
  /// radius into, and a slider to drag it, both ending at a fully round
  /// picture (half the shorter side).
  Widget _borderRadiusField(
      BuildContext context, IdCardTemplateElement element) {
    final max = math.max(1.0, (math.min(element.width, element.height) / 2));
    return _numberSliderField(
      context,
      label: 'Border Radius',
      sliderKey: '${element.id}_border_radius_slider',
      value: _cornerRadiusOf(element),
      max: max,
      update: (v) => (e) => e.copyWith(cornerRadius: v),
    );
  }

  /// The Opacity property of an Image / ID Picture, 0-100 %.
  Widget _opacityField(BuildContext context, IdCardTemplateElement element) =>
      _numberSliderField(
        context,
        label: 'Opacity (%)',
        sliderKey: '${element.id}_opacity_slider',
        value: ((element.opacity ?? 1) * 100).clamp(0.0, 100.0).toDouble(),
        max: 100,
        update: (v) => (e) => e.copyWith(opacity: v / 100),
      );

  /// A labelled number field with a slider under it, both editing the same
  /// value between 0 and [max]. [update] turns a value into the element
  /// change. Typing is clamped to the range; the slider records one undo step
  /// for a whole drag, not one per pixel.
  Widget _numberSliderField(
    BuildContext context, {
    required String label,
    required String sliderKey,
    required double value,
    required double max,
    required IdCardTemplateElement Function(IdCardTemplateElement) Function(
            double)
        update,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _numberField(
          context,
          label,
          value,
          (v) => _updateSelected(update(v.clamp(0.0, max).toDouble())),
        ),
        Slider(
          key: ValueKey(sliderKey),
          value: value.clamp(0.0, max).toDouble(),
          min: 0,
          max: max,
          activeColor: ItTechnicianColors.azureBlue,
          onChangeStart: (_) => _pushHistory(),
          onChanged: (v) =>
              _setSelectedWithoutHistory(update(v.roundToDouble())),
        ),
      ],
    );
  }

  /// The Crop property of an Image / ID Picture: a Crop button that makes
  /// dragging on the canvas slide the picture inside its frame, plus (while
  /// cropping) a zoom for the picture and a reset.
  Widget _cropControls(BuildContext context, IdCardTemplateElement element) {
    final cropping = _isCropping(element.id);
    final zoomPercent = (_cropZoomOf(element) * 100).roundToDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PillButton(
          label: cropping ? 'Done' : 'Crop',
          icon: cropping ? Icons.check_rounded : Icons.crop_rounded,
          onTap: () => setState(() => _cropId = cropping ? null : element.id),
        ),
        if (cropping) ...[
          const SizedBox(height: 10),
          Text(
            'Drag the picture to reposition it inside its frame.',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: ItTechnicianColors.rowText(context).withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 10),
          _propFieldLabel(context, 'Crop Zoom (%)'),
          Slider(
            key: ValueKey('${element.id}_crop_zoom_slider'),
            value: zoomPercent.clamp(100.0, 400.0).toDouble(),
            min: 100,
            max: 400,
            activeColor: ItTechnicianColors.azureBlue,
            onChangeStart: (_) => _pushHistory(),
            onChanged: (v) => _setSelectedWithoutHistory(
                (e) => e.copyWith(cropZoom: v.roundToDouble() / 100)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('${zoomPercent.toStringAsFixed(0)}%',
                style: _propFieldStyle(context)),
          ),
          const SizedBox(height: 8),
          SecondaryPillButton(
            label: 'Reset Crop',
            icon: Icons.restart_alt_rounded,
            onTap: () => _updateSelected(
                (e) => e.copyWith(cropZoom: 1, cropX: 0, cropY: 0)),
          ),
        ],
      ],
    );
  }

  Widget _numberField(
    BuildContext context,
    String label,
    double value,
    ValueChanged<double> onChanged, {
    int decimals = 0,
  }) {
    // Label sits above the field rather than beside it — a fixed-width
    // side label (previously 20px) wrapped onto two lines for anything
    // longer than "X"/"Y"/"W"/"H" (e.g. "Width", "Radius").
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _propFieldLabel(context, label),
          _LiveTextField(
            key: ValueKey('${_selectedIds.first}_$label'),
            // Follows the element live, e.g. while it is dragged or resized on
            // the canvas — not just what it was when it was selected.
            value: decimals > 0 && value != value.roundToDouble()
                ? value.toStringAsFixed(decimals)
                : value.toStringAsFixed(0),
            style: _propFieldStyle(context),
            decoration: _propFieldDecoration(context),
            onSubmitted: (text) {
              final parsed = double.tryParse(text);
              if (parsed != null) onChanged(parsed);
            },
          ),
        ],
      ),
    );
  }
}

/// Landscape/Portrait toggle shown in the editor header, next to
/// [_FrontBackToggle] — same compact segmented-pill convention, icon-only
/// to keep the header from getting crowded. Changing this only swaps which
/// of the CR-80 card's two physical edges is "width" vs "height" (see
/// cardWidthPtFor/cardHeightPtFor); it does not rescale or reposition any
/// existing element, so elements positioned near the old width's edge may
/// need to be moved back on screen after switching.
class _OrientationToggle extends StatelessWidget {
  const _OrientationToggle({required this.orientation, required this.onChanged});

  final IdCardOrientation orientation;
  final ValueChanged<IdCardOrientation> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ItTechnicianColors.fieldFill(context),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(
            context,
            icon: Icons.crop_landscape_outlined,
            tooltip: 'Landscape',
            selected: orientation == IdCardOrientation.landscape,
            onTap: () => onChanged(IdCardOrientation.landscape),
          ),
          _segment(
            context,
            icon: Icons.crop_portrait_outlined,
            tooltip: 'Portrait',
            selected: orientation == IdCardOrientation.portrait,
            onTap: () => onChanged(IdCardOrientation.portrait),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? ItTechnicianColors.azureBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : ItTechnicianColors.mutedText(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Front/Back page toggle shown in the editor header — a compact segmented
/// pill matching the rest of the app's selection-pill convention.
class _FrontBackToggle extends StatelessWidget {
  const _FrontBackToggle({required this.isFront, required this.onChanged});

  final bool isFront;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ItTechnicianColors.fieldFill(context),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context,
              label: 'Front', selected: isFront, onTap: () => onChanged(true)),
          _segment(context,
              label: 'Back', selected: !isFront, onTap: () => onChanged(false)),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? ItTechnicianColors.azureBlue : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : ItTechnicianColors.mutedText(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// A properties-panel text field that shows [value] and keeps following it as
/// the element changes underneath (dragged, resized, typed into on the
/// canvas, undone…). A plain `TextFormField(initialValue: …)` only reads its
/// value once, so the panel showed the state at selection time, not live.
/// While the field itself has focus its text is left alone (it is being
/// typed into); losing focus drops anything not submitted and shows [value]
/// again.
class _LiveTextField extends StatefulWidget {
  const _LiveTextField({
    super.key,
    required this.value,
    required this.style,
    required this.decoration,
    required this.onSubmitted,
  });

  final String value;
  final TextStyle style;
  final InputDecoration decoration;
  final ValueChanged<String> onSubmitted;

  @override
  State<_LiveTextField> createState() => _LiveTextFieldState();
}

class _LiveTextFieldState extends State<_LiveTextField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void didUpdateWidget(_LiveTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        !_focusNode.hasFocus &&
        _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      style: widget.style,
      decoration: widget.decoration,
      onSubmitted: widget.onSubmitted,
    );
  }
}
