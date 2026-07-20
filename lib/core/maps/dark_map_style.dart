/// Shared dark Google Map style so every map in the app matches the v2
/// deep-space shell in dark mode. Single source of truth — the Geospatial
/// Risk Map and the Nearby Hospitals map both apply this, rather than each
/// carrying its own copy.
const String kDarkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#0b1120"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8b96b1"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b1120"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#2a3247"}]},
  {"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#a4aecb"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#172033"}]},
  {"featureType":"road","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#05070f"}]}
]
''';
