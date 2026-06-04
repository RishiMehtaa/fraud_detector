import 'package:intl/intl.dart';

class FormatUtils {
  static final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  static final _compactCurrency = NumberFormat.compactCurrency(locale: 'en_IN', symbol: '₹');
  static final _date = DateFormat('MMM d, yyyy');
  static final _time = DateFormat('hh:mm a');

  static String amount(double val) => _currency.format(val);
  static String compactAmount(double val) => _compactCurrency.format(val);
  static String date(DateTime val) => _date.format(val);
  static String time(DateTime val) => _time.format(val);
  
  static String relativeTime(DateTime val) {
    final diff = DateTime.now().difference(val);
    if (diff.isNegative) return 'Just now';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}