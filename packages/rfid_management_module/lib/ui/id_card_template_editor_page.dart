// packages/rfid_management_module/lib/ui/id_card_template_editor_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../id_card_template.dart';
import 'it_technician_dashboard_page.dart' show ItTechnicianColors;

/// Full-screen ID card template editor — toolbox (drag elements onto the
/// canvas), canvas (front/back toggle above it), properties panel. The
/// constructor's shape is fixed as of Task 4: later tasks only change
/// what's inside build()/state (Task 7 adds one more constructor
/// parameter, `onUploadImage`).
class IdCardTemplateEditorPage extends StatefulWidget {
  const IdCardTemplateEditorPage({
    super.key,
    required this.templateName,
    required this.initialFrontLayout,
    required this.initialBackLayout,
    required this.onSave,
  });

  final String templateName;
  final List<IdCardTemplateElement> initialFrontLayout;
  final List<IdCardTemplateElement> initialBackLayout;

  final Future<void> Function(
    List<IdCardTemplateElement> frontLayout,
    List<IdCardTemplateElement> backLayout,
  ) onSave;

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

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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

  void _moveSelection(Offset screenDelta) {
    final deltaX = screenDelta.dx / _zoom;
    final deltaY = screenDelta.dy / _zoom;
    const snapThreshold = 4.0;

    final others =
        _currentElements.where((e) => !_selectedIds.contains(e.id)).toList();
    final movingElements =
        _currentElements.where((e) => _selectedIds.contains(e.id)).toList();
    if (movingElements.isEmpty) return;

    var adjustedDeltaX = deltaX;
    var adjustedDeltaY = deltaY;
    final guideX = <double>[];
    final guideY = <double>[];

    for (final moving in movingElements) {
      final newX = moving.x + deltaX;
      final newY = moving.y + deltaY;
      final candidatesX = [
        0.0,
        idCardWidthPt / 2 - moving.width / 2,
        idCardWidthPt - moving.width,
        for (final other in others) other.x,
        for (final other in others) other.x + other.width / 2 - moving.width / 2,
        for (final other in others) other.x + other.width - moving.width,
      ];
      final candidatesY = [
        0.0,
        idCardHeightPt / 2 - moving.height / 2,
        idCardHeightPt - moving.height,
        for (final other in others) other.y,
        for (final other in others) other.y + other.height / 2 - moving.height / 2,
        for (final other in others) other.y + other.height - moving.height,
      ];
      for (final cx in candidatesX) {
        if ((newX - cx).abs() < snapThreshold) {
          adjustedDeltaX = cx - moving.x;
          guideX.add((cx + moving.width / 2) * _zoom);
        }
      }
      for (final cy in candidatesY) {
        if ((newY - cy).abs() < snapThreshold) {
          adjustedDeltaY = cy - moving.y;
          guideY.add((cy + moving.height / 2) * _zoom);
        }
      }
    }

    final elements = _currentElements.map((e) {
      if (!_selectedIds.contains(e.id)) return e;
      return e.copyWith(
        x: (e.x + adjustedDeltaX).clamp(0, idCardWidthPt - e.width),
        y: (e.y + adjustedDeltaY).clamp(0, idCardHeightPt - e.height),
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
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'You have unsaved changes to this template. Leave without saving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
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
        appBar: AppBar(
          title: Text('Editing ${widget.templateName}'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _saving
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : FilledButton(
                      onPressed: _dirty ? _save : null,
                      child: const Text('Save'),
                    ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Front'),
                    selected: _showingFront,
                    onSelected: (_) => setState(() {
                      _showingFront = true;
                      _selectedIds = {};
                    }),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Back'),
                    selected: !_showingFront,
                    onSelected: (_) => setState(() {
                      _showingFront = false;
                      _selectedIds = {};
                    }),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildToolbox(context),
                  Expanded(child: _buildCanvasArea(context)),
                  _buildPropertiesPanel(context),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildToolbox(BuildContext context) {
    return SizedBox(
      width: 110,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final (type, label, icon) in _toolboxItems)
            Draggable<IdCardElementType>(
              data: type,
              feedback: Material(
                color: Colors.transparent,
                child: Icon(icon, size: 28, color: ItTechnicianColors.azureBlue),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Icon(icon, size: 22),
                    const SizedBox(height: 4),
                    Text(label,
                        style: const TextStyle(fontSize: 10),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCanvasArea(BuildContext context) {
    return DragTarget<IdCardElementType>(
      onAcceptWithDetails: (details) => _addElement(details.data),
      builder: (context, candidateData, rejectedData) => Center(
        child: Container(
          width: idCardWidthPt * _zoom,
          height: idCardHeightPt * _zoom,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: ItTechnicianColors.cardBorder(context)),
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
        },
        onPanUpdate: (details) => _moveSelection(details.delta),
        onPanEnd: (_) => setState(() {
          _guideLinesX = [];
          _guideLinesY = [];
        }),
        child: Container(
          decoration: isSelected
              ? BoxDecoration(
                  border: Border.all(
                      color: ItTechnicianColors.azureBlue, width: 2))
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
    switch (element.type) {
      case IdCardElementType.staticText:
        return Text(
          element.textContent ?? '',
          style: TextStyle(
            fontSize: (element.fontSize ?? 10) * _zoom / 2,
            color: Color(element.color ?? 0xFF000000),
          ),
        );
      case IdCardElementType.idData:
        return Text(
          '{${element.fieldKey?.name ?? 'field'}}',
          style: TextStyle(
            fontSize: (element.fontSize ?? 10) * _zoom / 2,
            color: Color(element.color ?? 0xFF000000),
            fontStyle: FontStyle.italic,
          ),
        );
      case IdCardElementType.image:
        return Container(
          color: const Color(0xFFE5E7EB),
          alignment: Alignment.center,
          child: const Icon(Icons.image_outlined, size: 16),
        );
      case IdCardElementType.idPicture:
        return Container(
          color: const Color(0xFFE5E7EB),
          alignment: Alignment.center,
          child: const Text('PHOTO', style: TextStyle(fontSize: 9)),
        );
      case IdCardElementType.signature:
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

  Widget _buildPropertiesPanel(BuildContext context) {
    if (_selectedIds.length != 1) {
      return const SizedBox(
        width: 160,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Select an element to edit its properties.',
            style: TextStyle(fontSize: 11),
          ),
        ),
      );
    }
    final id = _selectedIds.first;
    final element = _currentElements.firstWhere((e) => e.id == id);
    return SizedBox(
      width: 160,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Position & Size',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _numberField(
                'X', element.x, (v) => _updateSelected((e) => e.copyWith(x: v))),
            _numberField(
                'Y', element.y, (v) => _updateSelected((e) => e.copyWith(y: v))),
            _numberField('W', element.width,
                (v) => _updateSelected((e) => e.copyWith(width: v))),
            _numberField('H', element.height,
                (v) => _updateSelected((e) => e.copyWith(height: v))),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _deleteSelectedElements,
              child: const Text('Delete Element'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 20, child: Text(label, style: const TextStyle(fontSize: 11))),
          Expanded(
            child: TextFormField(
              key: ValueKey('${_selectedIds.first}_$label'),
              initialValue: value.toStringAsFixed(0),
              style: const TextStyle(fontSize: 11),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              ),
              onFieldSubmitted: (text) {
                final parsed = double.tryParse(text);
                if (parsed != null) onChanged(parsed);
              },
            ),
          ),
        ],
      ),
    );
  }
}
