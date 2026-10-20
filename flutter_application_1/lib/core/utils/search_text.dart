String searchText(String value) {
  var result = value.toLowerCase().replaceAll('i\u0307', 'i');
  const letters = {
    'ı': 'i',
    'İ': 'i',
    'ş': 's',
    'ğ': 'g',
    'ü': 'u',
    'ö': 'o',
    'ç': 'c',
  };
  for (final entry in letters.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result;
}
