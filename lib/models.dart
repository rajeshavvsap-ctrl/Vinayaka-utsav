import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// A committee member's profile (collection `users`, doc id = auth uid).
class Member {
  const Member({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.role,
    required this.status,
  });

  final String id;
  final String name;
  final String phone;
  final String email;
  final String role; // 'member' | 'admin'
  final String status; // 'pending' | 'approved' | 'rejected'

  bool get isApproved => status == 'approved';
  bool get isAdmin => isApproved && role == 'admin';

  factory Member.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return Member(
      id: d.id,
      name: '${m['name'] ?? ''}',
      phone: '${m['phone'] ?? ''}',
      email: '${m['email'] ?? ''}',
      role: '${m['role'] ?? 'member'}',
      status: '${m['status'] ?? 'pending'}',
    );
  }
}

/// Festival settings (doc `settings/festival`), edited by admins.
class Festival {
  const Festival({
    required this.title,
    required this.start,
    required this.days,
    required this.slots,
    required this.upiId,
    required this.configured,
  });

  static const defaultSlots = ['Morning Pooja', 'Evening Aarti'];

  final String title;
  final DateTime start;
  final int days;
  final List<String> slots;
  final String upiId;
  final bool configured;

  factory Festival.fromMap(Map<String, dynamic>? m) {
    final now = DateTime.now();
    final ts = m?['startDate'];
    final s = ts is Timestamp ? ts.toDate() : now;
    final rawDays = m?['days'];
    final days = rawDays is num ? rawDays.toInt().clamp(1, 21).toInt() : 10;
    final rawSlots = m?['poojaSlots'];
    final slots = rawSlots is List
        ? rawSlots.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    return Festival(
      title: '${m?['title'] ?? 'Vinayaka Chaturthi'}',
      start: DateTime(s.year, s.month, s.day),
      days: days,
      slots: slots.isEmpty ? defaultSlots : slots,
      upiId: '${m?['upiId'] ?? ''}',
      configured: m != null && ts is Timestamp,
    );
  }

  List<DateTime> get dates =>
      List.generate(days, (i) => DateTime(start.year, start.month, start.day + i));

  List<String> get dayKeys => dates.map(dayKey).toList();

  /// 1-based festival day for [key], or null when outside the festival.
  int? dayNumber(String key) {
    final i = dayKeys.indexOf(key);
    return i < 0 ? null : i + 1;
  }

  /// Today if the festival is on, otherwise day 1.
  String initialDay() {
    final today = dayKey(DateTime.now());
    return dayKeys.contains(today) ? today : dayKeys.first;
  }
}

/// Everything a signed-in, approved member needs.
class Session {
  const Session(this.me, this.festival);
  final Member me;
  final Festival festival;
  bool get isAdmin => me.isAdmin;

  /// Admins can change anything; members can change what they created.
  bool canChange(Map<String, dynamic> data) => isAdmin || data['createdBy'] == me.id;
}

// ---------- formatting helpers ----------

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _dayFmt = DateFormat('yyyy-MM-dd');

String rupees(num v) => _money.format(v);
String dayKey(DateTime d) => _dayFmt.format(d);
DateTime parseDay(String key) => _dayFmt.parse(key);
String prettyDay(String key) => DateFormat('EEE, d MMM yyyy').format(parseDay(key));
String shortDay(String key) => DateFormat('d MMM').format(parseDay(key));
num toNum(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

/// 'HH:mm' (24h, sortable) -> '7:00 PM'.
String prettyTime(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length != 2) return hhmm;
  final dt = DateTime(2000, 1, 1, int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
  return DateFormat('h:mm a').format(dt);
}

const expenseCategories = [
  'Idol',
  'Pandal',
  'Pooja items',
  'Flowers',
  'Prasadam / Food',
  'Sound & Lights',
  'Decoration',
  'Visarjan',
  'Other',
];

const paymentModes = ['UPI', 'Cash', 'Bank transfer'];
