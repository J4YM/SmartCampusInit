// packages/rfid_management_module/lib/id_card_template.dart
//
// The single shared data shape for an ID card template's front/back
// layout — used by the template editor (this package), by
// IdCardTemplatesRepository (lib/data, does the Supabase I/O), and by
// the PDF renderer (lib/documents). Deliberately pure Dart (no
// Flutter/Supabase imports) so it's usable from every layer without
// pulling in dependencies those layers don't need.

/// One element's kind — matches IDAssist's own Design ID Layout toolbox,
/// minus Fingerprint (out of scope — no fingerprint hardware exists
/// anywhere in this app).
enum IdCardElementType {
  staticText,
  image,
  idData,
  idPicture,
  signature,
  rectangle,
  roundedRect,
  ellipse,
  line,
}

/// Which student field an `idData` element displays.
enum IdDataFieldKey {
  /// The standard 3-line ID name block:
  /// ```
  /// Lastname
  /// First name, M.I.
  /// Course
  /// ```
  /// The default for a freshly-dropped "ID Data" element — previously
  /// defaulted to [firstName] alone, which read as "the element only
  /// shows the first name" (a real bug report, even though [firstName]
  /// itself works exactly as its name says).
  fullName,
  firstName,
  middleInitial,
  lastName,
  studentNumber,
  course,
  section,
  yearLevel,
  guardianName,
  guardianContactNo,
}

/// One positioned element on a template's front or back. `x`/`y`/`width`/
/// `height` are always in PDF point units (72pt/inch) against the CR-80
/// card's real physical size ([idCardWidthPt] x [idCardHeightPt]) — the
/// single canonical coordinate space this whole feature stores and edits
/// in. Every field below `zIndex` is optional and only meaningful for
/// certain [type]s — see each field's doc comment.
class IdCardTemplateElement {
  const IdCardTemplateElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotation = 0,
    this.zIndex = 0,
    this.textContent,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.color,
    this.textAlign,
    this.imagePath,
    this.fieldKey,
    this.fillColor,
    this.strokeColor,
    this.strokeWidth,
    this.cornerRadius,
    this.cropZoom,
    this.cropX,
    this.cropY,
    this.opacity,
  });

  final String id;
  final IdCardElementType type;
  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
  final int zIndex;

  /// `staticText`/`idData` only.
  final String? textContent;
  final String? fontFamily;
  final double? fontSize;

  /// `staticText`/`idData` only: the CSS-style weight — 400 (regular) or 700
  /// (bold), the only two the printed card can show; anything 600 or heavier
  /// (older data) counts as bold. Null means regular, so templates saved before
  /// this property existed look the same as ever.
  final int? fontWeight;

  /// ARGB int (`Color.value`) — `staticText`/`idData`'s text color.
  final int? color;

  /// `staticText`/`idData` only: 'left' | 'center' | 'right'.
  final String? textAlign;

  /// `image` only — Storage object path in the `id-card-template-images`
  /// bucket.
  final String? imagePath;

  /// `idData` only — which student field this element displays.
  final IdDataFieldKey? fieldKey;

  /// `rectangle`/`roundedRect`/`ellipse` only. ARGB int.
  final int? fillColor;

  /// `rectangle`/`roundedRect`/`ellipse`/`line` only. ARGB int.
  final int? strokeColor;
  final double? strokeWidth;

  /// `roundedRect` and `idPicture` only (the picture's border radius).
  final double? cornerRadius;

  /// `image`/`idPicture` only: how far the picture is zoomed inside its frame
  /// (1 = fitted, up to 4) and which part of it the frame shows, as an
  /// alignment from -1 (left/top edge) to 1 (right/bottom edge). Null means the
  /// uncropped picture. Together they are the crop.
  final double? cropZoom;
  final double? cropX;
  final double? cropY;

  /// `image`/`idPicture` only: 0 (invisible) to 1 (solid). Null means solid.
  final double? opacity;

  IdCardTemplateElement copyWith({
    String? id,
    IdCardElementType? type,
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
    int? zIndex,
    String? textContent,
    String? fontFamily,
    double? fontSize,
    int? fontWeight,
    int? color,
    String? textAlign,
    String? imagePath,
    IdDataFieldKey? fieldKey,
    int? fillColor,
    int? strokeColor,
    double? strokeWidth,
    double? cornerRadius,
    double? cropZoom,
    double? cropX,
    double? cropY,
    double? opacity,
  }) {
    return IdCardTemplateElement(
      id: id ?? this.id,
      type: type ?? this.type,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      rotation: rotation ?? this.rotation,
      zIndex: zIndex ?? this.zIndex,
      textContent: textContent ?? this.textContent,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      color: color ?? this.color,
      textAlign: textAlign ?? this.textAlign,
      imagePath: imagePath ?? this.imagePath,
      fieldKey: fieldKey ?? this.fieldKey,
      fillColor: fillColor ?? this.fillColor,
      strokeColor: strokeColor ?? this.strokeColor,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      cropZoom: cropZoom ?? this.cropZoom,
      cropX: cropX ?? this.cropX,
      cropY: cropY ?? this.cropY,
      opacity: opacity ?? this.opacity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'rotation': rotation,
      'zIndex': zIndex,
      if (textContent != null) 'textContent': textContent,
      if (fontFamily != null) 'fontFamily': fontFamily,
      if (fontSize != null) 'fontSize': fontSize,
      if (fontWeight != null) 'fontWeight': fontWeight,
      if (color != null) 'color': color,
      if (textAlign != null) 'textAlign': textAlign,
      if (imagePath != null) 'imagePath': imagePath,
      if (fieldKey != null) 'fieldKey': fieldKey!.name,
      if (fillColor != null) 'fillColor': fillColor,
      if (strokeColor != null) 'strokeColor': strokeColor,
      if (strokeWidth != null) 'strokeWidth': strokeWidth,
      if (cornerRadius != null) 'cornerRadius': cornerRadius,
      if (cropZoom != null) 'cropZoom': cropZoom,
      if (cropX != null) 'cropX': cropX,
      if (cropY != null) 'cropY': cropY,
      if (opacity != null) 'opacity': opacity,
    };
  }

  factory IdCardTemplateElement.fromJson(Map<String, dynamic> json) {
    return IdCardTemplateElement(
      id: json['id'] as String,
      type: IdCardElementType.values.byName(json['type'] as String),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
      zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      textContent: json['textContent'] as String?,
      fontFamily: json['fontFamily'] as String?,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      fontWeight: (json['fontWeight'] as num?)?.toInt(),
      color: (json['color'] as num?)?.toInt(),
      textAlign: json['textAlign'] as String?,
      imagePath: json['imagePath'] as String?,
      fieldKey: json['fieldKey'] == null
          ? null
          : IdDataFieldKey.values.byName(json['fieldKey'] as String),
      fillColor: (json['fillColor'] as num?)?.toInt(),
      strokeColor: (json['strokeColor'] as num?)?.toInt(),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble(),
      cornerRadius: (json['cornerRadius'] as num?)?.toDouble(),
      cropZoom: (json['cropZoom'] as num?)?.toDouble(),
      cropX: (json['cropX'] as num?)?.toDouble(),
      cropY: (json['cropY'] as num?)?.toDouble(),
      opacity: (json['opacity'] as num?)?.toDouble(),
    );
  }
}

/// The CR-80 card's real physical size in PDF points (72pt/inch),
/// landscape (the long edge horizontal) — the canonical coordinate space
/// every element's x/y/width/height is stored and edited in, regardless of
/// [IdCardOrientation]. A portrait template just swaps which of these two
/// is the on-screen/on-page width vs height (see [cardWidthPtFor]/
/// [cardHeightPtFor]) — element coordinates are never transformed.
const double idCardWidthPt = 3.375 * 72;
const double idCardHeightPt = 2.125 * 72;

/// Whether a template's physical card is oriented with its long edge
/// horizontal (landscape, the CR-80 card's natural orientation) or
/// vertical (portrait).
enum IdCardOrientation { landscape, portrait }

/// The on-screen/on-page width for [orientation] — landscape uses the
/// CR-80's natural long-edge-horizontal width, portrait swaps in its
/// short edge.
double cardWidthPtFor(IdCardOrientation orientation) =>
    orientation == IdCardOrientation.portrait ? idCardHeightPt : idCardWidthPt;

/// The on-screen/on-page height for [orientation] — see [cardWidthPtFor].
double cardHeightPtFor(IdCardOrientation orientation) =>
    orientation == IdCardOrientation.portrait ? idCardWidthPt : idCardHeightPt;

/// One row of the template picker/list — no layout data, just enough to
/// display and sort (`fetchTemplates` orders by `updatedAt` descending).
class IdCardTemplateSummary {
  const IdCardTemplateSummary({
    required this.id,
    required this.name,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final DateTime updatedAt;
}

/// A template's full front/back layouts — what the editor loads and
/// saves, and what the print flow's renderer consumes.
class IdCardTemplateDetail {
  const IdCardTemplateDetail({
    required this.id,
    required this.name,
    required this.frontLayout,
    required this.backLayout,
    this.orientation = IdCardOrientation.landscape,
    this.backgroundColor = 0xFFFFFFFF,
  });

  final String id;
  final String name;
  final List<IdCardTemplateElement> frontLayout;
  final List<IdCardTemplateElement> backLayout;

  /// Both sides of one physical card, so they always share one orientation.
  final IdCardOrientation orientation;

  /// ARGB int (`Color.value`) — the card's background fill, behind every
  /// element. Both sides share one, same reasoning as [orientation].
  /// Defaults to opaque white, matching the hardcoded white this template
  /// editor always used before this was configurable.
  final int backgroundColor;
}
