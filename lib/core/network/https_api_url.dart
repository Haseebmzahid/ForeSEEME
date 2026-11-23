Uri? httpsApiUrl(String configured) {
  final uri = Uri.tryParse(configured);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.authority.contains('@') ||
      uri.hasQuery ||
      uri.hasFragment ||
      RegExp(r'[\s\\]').hasMatch(configured)) {
    return null;
  }
  return uri;
}
