import 'package:docx_creator/docx_creator.dart';

/// Shared STI College Baliuag header block, prepended to every generated
/// document (Good Moral Certificate, Reports & Exports, ...) so they read as
/// one consistent system rather than each feature inventing its own header.
/// Returns [builder] for further chaining.
DocxDocumentBuilder addLetterhead(
  DocxDocumentBuilder builder, {
  required String documentTitle,
}) {
  return builder
      .add(
        const DocxParagraph(
          align: DocxAlign.center,
          children: [
            DocxText(
              'STI COLLEGE BALIUAG',
              fontWeight: DocxFontWeight.bold,
              fontSize: 20,
            ),
          ],
        ),
      )
      .add(
        const DocxParagraph(
          align: DocxAlign.center,
          spacingAfter: 120,
          children: [
            DocxText(
              'Baliuag, Bulacan, Philippines',
              fontSize: 11,
              color: DocxColor.gray,
            ),
          ],
        ),
      )
      .hr()
      .add(
        DocxParagraph(
          align: DocxAlign.center,
          spacingBefore: 240,
          spacingAfter: 240,
          children: [
            DocxText(
              documentTitle,
              fontWeight: DocxFontWeight.bold,
              fontSize: 16,
            ),
          ],
        ),
      );
}
