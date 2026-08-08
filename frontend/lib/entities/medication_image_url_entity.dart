// File Name: medication_image_url_entity.dart
// Role: Defines the client trust policy for remotely loaded medication images.

const Set<String> _trustedMedicationImageHosts = {'nedrug.mfds.go.kr'};

// Function Name: safeMedicationImageUrl
// Description:
// - Returns a medication image URL only when it uses HTTPS and an approved
//   public-data host.
// - Rejects credentials, alternate ports, local endpoints, and arbitrary
//   third-party tracking hosts before Flutter can open a network connection.
// Parameters:
// - value: The untrusted URL value received from an API or persisted record.
// Returns:
// - The trimmed trusted URL, or an empty string when validation fails.
String safeMedicationImageUrl(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text.length > 3000) {
    return '';
  }

  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return '';
  }

  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (!_trustedMedicationImageHosts.contains(host)) {
    return '';
  }
  return text;
}
