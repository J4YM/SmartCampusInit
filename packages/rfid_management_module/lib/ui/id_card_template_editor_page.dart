// packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart
import 'package:dashboard_layout/dashboard_layout.dart';
import 'package:file_picker/file_picker.dart';
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
  }) onPrint;
}

String _studentFieldValue(IdDataFieldKey? key, RfidStudentRow student) {
  switch (key) {
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
    this.printContext,
  });

  final String templateName;
  final List<IdCardTemplateElement> initialFrontLayout;
  final List<IdCardTemplateElement> initialBackLayout;

  final Future<void> Function(
    List<IdCardTemplateElement> frontLayout,
    List<IdCardTemplateElement> backLayout,
  ) onSave;

  /// Uploads a static image (e.g. a school logo) for an Image-type
  /// element and returns its Storage object path. This page has no
  /// Supabase access of its own.
  final Future<String> Function(Uint8List bytes, String fileName) onUploadImage;

  /// Persists an inline rename of the header title (the template's own
  /// name). This page has no Supabase access of its own.
  final Future<void> Function(String newName) onRename;

  final IdCardPrintContext? printContext;

  @override
  State<IdCardTemplateEditorPage> createState() =>
      _IdCardTemplateEditorPageState();
}

class _IdCardTemplateEditorPageState extends State<IdCardTemplateEditorPage> {
  static const double _zoom = 3.0;
  static const List<(IdCardElementType, String, IconData)> _toolboxItems = [
    (IdCardElementType.staticText, 'Text', Icons.text_fields),
    (IdCardElementType.image, 'Image', Icons.image_outlined),
    (IdCardElementType.idData, 'ID Data', Icons.badge_outlined),
    (IdCardElementType.idPicture, 'ID Picture', Icons.account_box_outlined),
    (IdCardElementType.signature, 'Signature', Icons.draw_outlined),
    (IdCardElementType.rectangle, 'Rectangle', Icons.crop_square),
    (IdCardElementType.roundedRect, 'RoundedRect', Icons.rounded_corner),
    (IdCardElementType.ellipse, 'Ellipse', Icons.circle_outlined),
    (IdCardElementType.line, 'Line', Icons.horizontal_rule),
  ];

  late List<IdCardTemplateElement> _frontElements =
      List.of(widget.initialFrontLayout);
  late List<IdCardTemplateElement> _backElements =
      List.of(widget.initialBackLayout);
  bool _showingFront = true;
  Set<String> _selectedIds = {};
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
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _nameFocusNode.removeListener(_handleNameFocusChange);
    _nameFocusNode.dispose();
    _nameController.dispose();
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
          height: defaultHeight,
          fieldKey: IdDataFieldKey.firstName,
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
          fillColor: 0x00000000,
          strokeColor: 0xFF000000,
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
          fillColor: 0x00000000,
          strokeColor: 0xFF000000,
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
          fillColor: 0x00000000,
          strokeColor: 0xFF000000,
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
    final pasted = _clipboard
        .map((e) => e.copyWith(
              id: '${_nextElementId()}-paste',
              x: e.x + 10,
              y: e.y + 10,
            ))
        .toList();
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

    var adjustedDeltaX = _dragCumulativeDelta.dx;
    var adjustedDeltaY = _dragCumulativeDelta.dy;
    final guideX = <double>[];
    final guideY = <double>[];

    for (final moving in movingElements) {
      final start = _dragStartPositions[moving.id] ?? Offset(moving.x, moving.y);
      final newX = start.dx + _dragCumulativeDelta.dx;
      final newY = start.dy + _dragCumulativeDelta.dy;
      final candidatesX = [
        0.0,
        idCardWidthPt / 2 - moving.width / 2,
        idCardWidthPt - moving.width,
        for (final other in others) other.x,
        for (final other in others)
          other.x + other.width / 2 - moving.width / 2,
        for (final other in others) other.x + other.width - moving.width,
      ];
      final candidatesY = [
        0.0,
        idCardHeightPt / 2 - moving.height / 2,
        idCardHeightPt - moving.height,
        for (final other in others) other.y,
        for (final other in others)
          other.y + other.height / 2 - moving.height / 2,
        for (final other in others) other.y + other.height - moving.height,
      ];
      for (final cx in candidatesX) {
        if ((newX - cx).abs() < snapThreshold) {
          adjustedDeltaX = cx - start.dx;
          guideX.add((cx + moving.width / 2) * _zoom);
        }
      }
      for (final cy in candidatesY) {
        if ((newY - cy).abs() < snapThreshold) {
          adjustedDeltaY = cy - start.dy;
          guideY.add((cy + moving.height / 2) * _zoom);
        }
      }
    }

    final elements = _currentElements.map((e) {
      if (!_selectedIds.contains(e.id)) return e;
      final start = _dragStartPositions[e.id] ?? Offset(e.x, e.y);
      return e.copyWith(
        x: (start.dx + adjustedDeltaX).clamp(0, idCardWidthPt - e.width),
        y: (start.dy + adjustedDeltaY).clamp(0, idCardHeightPt - e.height),
      );
    }).toList();

    setState(() {
      _guideLinesX = guideX;
      _guideLinesY = guideY;
    });
    _setCurrentElements(elements);
  }

  void _resizeElement(String id, Offset screenDelta) {
    final deltaX = screenDelta.dx / _zoom;
    final deltaY = screenDelta.dy / _zoom;
    final elements = _currentElements.map((e) {
      if (e.id != id) return e;
      return e.copyWith(
        width: (e.width + deltaX).clamp(8, idCardWidthPt - e.x),
        height: (e.height + deltaY).clamp(8, idCardHeightPt - e.y),
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_frontElements, _backElements);
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
        _frontElements = List.of(detail.frontLayout);
        _backElements = List.of(detail.backLayout);
        _selectedIds = {};
        _dirty = false;
        _undoStack.clear();
        _redoStack.clear();
      });
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
                textStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
          OutlinedButton.icon(
            onPressed: _printing ? null : _capturePhoto,
            icon: const Icon(Icons.camera_alt_outlined, size: 16),
            label: Text(
              _photoBytes == null ? 'Capture Photo' : 'Retake Photo',
              style: _buttonTextStyle(),
            ),
          ),
          if (_needsSignature) ...[
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _printing ? null : _captureSignature,
              icon: const Icon(Icons.draw_outlined, size: 16),
              label: Text(
                _signatureBytes == null
                    ? 'Capture Signature'
                    : 'Retake Signature',
                style: _buttonTextStyle(),
              ),
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
              backgroundColor: ItTechnicianColors.azureBlue,
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
    return _bentoCard(
      context,
      child: DragTarget<IdCardElementType>(
        onAcceptWithDetails: (details) => _addElement(details.data),
        builder: (context, candidateData, rejectedData) => Center(
          child: Container(
            width: idCardWidthPt * _zoom,
            height: idCardHeightPt * _zoom,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: ItTechnicianColors.cardBorder(context)),
              // Lifts the card being edited off the surrounding toolbox panel
              // so it's unambiguous which surface is the live editing area,
              // distinct from the panel's own (lighter) Bento shadow.
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
              onTap: () => setState(() => _selectedIds = {}),
              onPanStart: (details) => setState(() {
                _marqueeStart = details.localPosition;
                _marqueeCurrent = details.localPosition;
              }),
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
                  for (final element in _currentElements)
                    _buildElementWidget(element),
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
                          color: ItTechnicianColors.azureBlue.withOpacity(0.1),
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
    );
  }

  Widget _buildElementWidget(IdCardTemplateElement element) {
    final isSelected = _selectedIds.contains(element.id);
    return Positioned(
      left: element.x * _zoom,
      top: element.y * _zoom,
      width: element.width * _zoom,
      height: element.height * _zoom,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _handleElementTap(element.id),
        onPanStart: (_) {
          if (!_selectedIds.contains(element.id)) _selectOnly(element.id);
          _pushHistory();
          _dragCumulativeDelta = Offset.zero;
          _dragStartPositions = {
            for (final e in _currentElements)
              if (_selectedIds.contains(e.id)) e.id: Offset(e.x, e.y),
          };
        },
        onPanUpdate: (details) => _moveSelection(details.delta),
        onPanEnd: (_) => setState(() {
          _guideLinesX = [];
          _guideLinesY = [];
          _dragStartPositions = {};
          _dragCumulativeDelta = Offset.zero;
        }),
        child: Container(
          decoration: isSelected
              ? BoxDecoration(
                  border:
                      Border.all(color: ItTechnicianColors.azureBlue, width: 2))
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: _elementContent(element)),
              if (isSelected && _selectedIds.length == 1)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: GestureDetector(
                    onPanStart: (_) => _pushHistory(),
                    onPanUpdate: (details) =>
                        _resizeElement(element.id, details.delta),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: ItTechnicianColors.azureBlue,
                        border: Border.all(color: Colors.white, width: 1.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _elementContent(IdCardTemplateElement element) {
    final student = widget.printContext?.student;
    switch (element.type) {
      case IdCardElementType.staticText:
        return Text(
          element.textContent ?? '',
          style: TextStyle(
            fontSize: (element.fontSize ?? 10) * _zoom,
            color: Color(element.color ?? 0xFF000000),
          ),
        );
      case IdCardElementType.idData:
        return Text(
          student == null
              ? '{${element.fieldKey?.name ?? 'field'}}'
              : _studentFieldValue(element.fieldKey, student),
          style: TextStyle(
            fontSize: (element.fontSize ?? 10) * _zoom,
            color: Color(element.color ?? 0xFF000000),
            fontStyle: student == null ? FontStyle.italic : FontStyle.normal,
          ),
        );
      case IdCardElementType.image:
        return Container(
          color: const Color(0xFFE5E7EB),
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined, size: 16),
        );
      case IdCardElementType.idPicture:
        if (_photoBytes != null) {
          return Image.memory(_photoBytes!, fit: BoxFit.cover);
        }
        return Container(
          color: const Color(0xFFE5E7EB),
          alignment: Alignment.center,
          child: const Text('PHOTO', style: TextStyle(fontSize: 9)),
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
        return Container(
          decoration: BoxDecoration(
            color: Color(element.fillColor ?? 0x00000000),
            border: Border.all(
              color: Color(element.strokeColor ?? 0xFF000000),
              width: element.strokeWidth ?? 1,
            ),
          ),
        );
      case IdCardElementType.roundedRect:
        return Container(
          decoration: BoxDecoration(
            color: Color(element.fillColor ?? 0x00000000),
            border: Border.all(
              color: Color(element.strokeColor ?? 0xFF000000),
              width: element.strokeWidth ?? 1,
            ),
            borderRadius:
                BorderRadius.circular((element.cornerRadius ?? 0) * _zoom),
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
                      (e) => e.copyWith(x: v.clamp(0, idCardWidthPt - 8)))),
              _numberField(
                  context,
                  'Y',
                  element.y,
                  (v) => _updateSelected(
                      (e) => e.copyWith(y: v.clamp(0, idCardHeightPt - 8)))),
              _numberField(
                  context,
                  'W',
                  element.width,
                  (v) => _updateSelected(
                      (e) => e.copyWith(width: v.clamp(8, idCardWidthPt)))),
              _numberField(
                  context,
                  'H',
                  element.height,
                  (v) => _updateSelected(
                      (e) => e.copyWith(height: v.clamp(8, idCardHeightPt)))),
              const SizedBox(height: 16),
              ..._typeSpecificFields(context, element),
              const SizedBox(height: 4),
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

  Widget _colorSwatchRow(int? current, ValueChanged<int> onPick) {
    return Wrap(
      spacing: 6,
      children: [
        for (final c in _colorPresets)
          GestureDetector(
            onTap: () => onPick(c),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      current == c ? ItTechnicianColors.azureBlue : Colors.grey,
                  width: current == c ? 2 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _typeSpecificFields(
      BuildContext context, IdCardTemplateElement element) {
    switch (element.type) {
      case IdCardElementType.staticText:
        return [
          _propFieldLabel(context, 'Content'),
          TextFormField(
            key: ValueKey('${element.id}_content'),
            initialValue: element.textContent ?? '',
            style: _propFieldStyle(context),
            decoration: _propFieldDecoration(context),
            onFieldSubmitted: (text) =>
                _updateSelected((e) => e.copyWith(textContent: text)),
          ),
          const SizedBox(height: 14),
          _numberField(
            context,
            'Font Size',
            element.fontSize ?? 10,
            (v) => _updateSelected((e) => e.copyWith(fontSize: v)),
          ),
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
            value: element.fieldKey ?? IdDataFieldKey.firstName,
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
          ),
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
        ];
      case IdCardElementType.idPicture:
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
          if (element.type == IdCardElementType.roundedRect)
            _numberField(
              context,
              'Radius',
              element.cornerRadius ?? 0,
              (v) => _updateSelected((e) => e.copyWith(cornerRadius: v)),
            ),
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
      _pushHistory();
      _updateSelected((e) => e.copyWith(imagePath: path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not upload image: $e')));
      }
    }
  }

  Widget _numberField(
    BuildContext context,
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    // Label sits above the field rather than beside it — a fixed-width
    // side label (previously 20px) wrapped onto two lines for anything
    // longer than "X"/"Y"/"W"/"H" (e.g. "Width", "Radius").
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _propFieldLabel(context, label),
          TextFormField(
            key: ValueKey('${_selectedIds.first}_$label'),
            initialValue: value.toStringAsFixed(0),
            style: _propFieldStyle(context),
            decoration: _propFieldDecoration(context),
            onFieldSubmitted: (text) {
              final parsed = double.tryParse(text);
              if (parsed != null) onChanged(parsed);
            },
          ),
        ],
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
