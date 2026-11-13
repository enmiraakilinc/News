/// Derlemede verilen genel sunucu adresini okur.
String? neuralPublicUrl() {
  const raw = String.fromEnvironment('NEURAL_PUBLIC_URL');
  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri.origin;
}
