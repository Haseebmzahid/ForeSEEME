Uri? httpsApiUrl(String configured) {
  final uri = Uri.tryParse(configured);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.port < 1 ||
      uri.port > 65535 ||
      uri.authority.contains('@') ||
      uri.hasQuery ||
      uri.hasFragment ||
      RegExp(r'[\s\\]').hasMatch(configured)) {
    return null;
  }
  return uri;
}
