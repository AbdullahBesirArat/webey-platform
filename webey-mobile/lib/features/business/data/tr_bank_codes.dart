/// TR IBAN banka kodu → banka adı eşlemesi.
///
/// Türkiye IBAN formatı: TR + 2 kontrol + 5 banka kodu + 17 hane = 26 karakter.
/// Banka kodu IBAN'ın 5..9 (substring 4..9) indeksinde.
///
/// Kart tipi (Visa/Mastercard/Troy) IBAN'dan çıkarılamaz — bunlar BIN tabanlıdır.
/// Yalnızca banka adı tahmin edilebilir.
library;

const Map<String, String> kTrBankCodes = {
  '00010': 'Ziraat Bankası',
  '00012': 'Halkbank',
  '00015': 'VakıfBank',
  '00046': 'Akbank',
  '00059': 'Şekerbank',
  '00062': 'Garanti BBVA',
  '00064': 'Türkiye İş Bankası',
  '00067': 'Yapı Kredi',
  '00099': 'ING Bank',
  '00103': 'Fibabanka',
  '00109': 'ICBC Turkey Bank',
  '00111': 'QNB Finansbank',
  '00123': 'HSBC Bank',
  '00124': 'Alternatif Bank',
  '00125': 'Burgan Bank',
  '00134': 'DenizBank',
  '00135': 'Anadolubank',
  '00143': 'Aktif Bank',
  '00146': 'Odea Bank',
  '00203': 'Albaraka Türk',
  '00205': 'Kuveyt Türk',
  '00206': 'Türkiye Finans',
  '00209': 'Ziraat Katılım',
  '00210': 'Vakıf Katılım',
  '00211': 'Emlak Katılım',
  '00212': 'Hayat Finans Katılım',
};

String normalizeTrIban(String raw) =>
    raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();

bool isValidTrIbanFormat(String iban) {
  final normalized = normalizeTrIban(iban);
  return RegExp(r'^TR[0-9]{24}$').hasMatch(normalized);
}

/// IBAN'dan banka kodunu (5 hane) çıkarır. Geçersizse null döner.
String? trBankCodeFromIban(String iban) {
  final normalized = normalizeTrIban(iban);
  if (!isValidTrIbanFormat(normalized)) return null;
  return normalized.substring(4, 9);
}

/// IBAN'dan banka adı tahmini. Bilinmeyen banka için null döner.
String? trBankNameFromIban(String iban) {
  final code = trBankCodeFromIban(iban);
  if (code == null) return null;
  return kTrBankCodes[code];
}

/// 4'lü gruplar halinde IBAN gösterimi: "TR12 3456 7890 ..."
String formatTrIban(String iban) {
  final normalized = normalizeTrIban(iban);
  if (normalized.isEmpty) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < normalized.length; i++) {
    if (i > 0 && i % 4 == 0) buffer.write(' ');
    buffer.write(normalized[i]);
  }
  return buffer.toString();
}
