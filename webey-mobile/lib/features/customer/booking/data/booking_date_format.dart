/// Booking API date/time formatting (Europe/Istanbul wall times).
class BookingDateFormat {
  const BookingDateFormat._();

  static String dateOnly(DateTime date) {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String dateTime(DateTime date) {
    final base = dateOnly(date);
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    final s = date.second.toString().padLeft(2, '0');
    return '$base $h:$min:$s';
  }

  /// Builds `YYYY-MM-DD HH:MM:SS` from a calendar date and `HH:MM` slot label.
  static String slotStartsAt(DateTime date, String timeHm) {
    final day = dateOnly(date);
    final parts = timeHm.split(':');
    final h = (parts.isNotEmpty ? parts[0] : '00').padLeft(2, '0');
    final m = (parts.length > 1 ? parts[1] : '00').padLeft(2, '0');
    return '$day $h:$m:00';
  }

  /// Yalnızca mock fallback katalog için (ör. sv1 → 1).
  static int? parseMockFallbackId(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'any') return null;
    final direct = int.tryParse(raw);
    if (direct != null) return direct;
    final digits = RegExp(r'\d+').firstMatch(raw)?.group(0);
    return digits != null ? int.tryParse(digits) : null;
  }
}
