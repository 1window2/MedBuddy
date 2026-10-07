// File Name: medication_thumbnail.dart
// Role: Provides the shared small medication photo used by schedule, caregiver and saved-list rows.

import 'dart:io';

import 'package:flutter/material.dart';

import '../entities/medication_image_url_entity.dart';
import '../theme/medbuddy_theme.dart';

// Class Name: MedicationThumbnail
// Role: Shows a medication photo, or a calm pill placeholder when no photo can be shown.
// Responsibilities:
// - Prefers an existing on-device photo, then a validated network photo.
// - Shows the same pill placeholder for a missing photo and for a load failure.
// - Becomes tappable only when a photo exists and the caller supplies an action.
// Attributes:
// - imageUrl (String?): Raw image URL; unsafe or blank values are treated as absent.
// - localImagePath (String): Optional on-device photo path.
// - size (double): Square edge length.
// - onTap (VoidCallback?): Opens the photo; ignored when there is no photo.
// - tapKey (Key?): Key for the tappable area, used by tests and accessibility tools.
// - tooltip (String?): Optional long-press description.
// - missingImageTooltip (String?): Description used instead when no photo can be shown.
class MedicationThumbnail extends StatelessWidget {
  final String? imageUrl;
  final String localImagePath;
  final double size;
  final VoidCallback? onTap;
  final Key? tapKey;
  final String? tooltip;
  final String? missingImageTooltip;

  // Function Name: MedicationThumbnail
  // Description: Stores the photo sources, size and optional open action.
  // Parameters:
  // - key (Key?): Identity of the thumbnail frame.
  // - imageUrl, localImagePath: Photo sources.
  // - size (double): Square edge length.
  // - onTap (VoidCallback?): Opens the photo when one exists.
  // - tapKey (Key?): Key for the tappable area.
  // - tooltip (String?): Optional long-press description.
  // - missingImageTooltip (String?): Description used when no photo can be shown.
  // Returns: A configured MedicationThumbnail.
  const MedicationThumbnail({
    super.key,
    this.imageUrl,
    this.localImagePath = '',
    this.size = 48,
    this.onTap,
    this.tapKey,
    this.tooltip,
    this.missingImageTooltip,
  });

  // Function Name: build
  // Description: Renders the photo or the pill placeholder inside a rounded square.
  // Parameters:
  // - context (BuildContext): Widget tree location.
  // Returns: The thumbnail, wrapped in a tap target and tooltip when configured.
  @override
  Widget build(BuildContext context) {
    final path = localImagePath.trim();
    final localFile = path.isEmpty ? null : File(path);
    final hasLocalImage = localFile?.existsSync() ?? false;
    final networkUrl = hasLocalImage ? '' : safeMedicationImageUrl(imageUrl);
    final hasImage = hasLocalImage || networkUrl.isNotEmpty;
    final cacheWidth = (size * 4).round();
    final placeholder = _MedicationPlaceholder(size: size);

    Widget frame = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: hasImage ? MedBuddyColors.surfaceSubtle : MedBuddyColors.mint,
        borderRadius: MedBuddyRadii.control,
        border: hasImage ? Border.all(color: MedBuddyColors.cardBorder) : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: !hasImage
          ? placeholder
          : hasLocalImage
          ? Image.file(
              localFile!,
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              errorBuilder: (_, _, _) => placeholder,
            )
          : Image.network(
              networkUrl,
              fit: BoxFit.contain,
              cacheWidth: cacheWidth,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
    if (hasImage && onTap != null) {
      frame = InkWell(
        key: tapKey,
        onTap: onTap,
        borderRadius: MedBuddyRadii.control,
        child: frame,
      );
    }
    final message = hasImage ? tooltip : missingImageTooltip ?? tooltip;
    return message == null || message.isEmpty
        ? frame
        : Tooltip(message: message, child: frame);
  }
}

// Class Name: _MedicationPlaceholder
// Role: Draws the pill icon shown when no medication photo is available.
// Attributes:
// - size (double): Thumbnail edge length used to scale the icon.
class _MedicationPlaceholder extends StatelessWidget {
  final double size;

  // Function Name: _MedicationPlaceholder
  // Description: Stores the thumbnail size.
  // Parameters:
  // - size (double): Thumbnail edge length.
  // Returns: A configured _MedicationPlaceholder.
  const _MedicationPlaceholder({required this.size});

  // Function Name: build
  // Description: Centers a pill icon scaled to half the thumbnail.
  // Parameters:
  // - context (BuildContext): Widget tree location.
  // Returns: The placeholder icon.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.medication_outlined,
        color: MedBuddyColors.primary,
        size: size * 0.5,
      ),
    );
  }
}
