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

/// A committee event type with its defaults (Navaratri, Vinayaka Chavithi, ...).
class EventDef {
  const EventDef(this.id, this.title, this.days, this.slots, this.sevaLabel, this.icon);
  final String id;
  final String title;
  final int days;
  final List<String> slots;
  final String sevaLabel; // name of the sign-up tile: "Pooja Seva" or "Volunteers"
  final String icon; // durga | ganesha | party | event
}

const defaultEvents = [
  EventDef('navaratri', 'Vijaya Dasami – Navaratri', 10, ['Morning Pooja', 'Evening Aarti'], 'Pooja Seva', 'durga'),
  EventDef('vinayaka', 'Vinayaka Chavithi', 5, ['Morning Pooja', 'Evening Aarti'], 'Pooja Seva', 'ganesha'),
  EventDef('newyear', '31st Night Celebration', 1, ['Decoration', 'Food', 'Cultural programme'], 'Volunteers', 'party'),
  EventDef('general', 'General Events', 1, ['Volunteers'], 'Volunteers', 'event'),
];

EventDef eventDefFor(String id, {String? title}) => defaultEvents.firstWhere(
      (e) => e.id == id,
      orElse: () => EventDef(id, title ?? 'Event', 1, const ['Volunteers'], 'Volunteers', 'event'),
    );

/// Each event's settings live in `settings/<doc>`. Vinayaka keeps the
/// original `settings/festival` doc so existing data stays as it is.
String settingsDocId(String eventId) => eventId == 'vinayaka' ? 'festival' : 'event_$eventId';

/// Records created before events existed belong to Vinayaka Chavithi.
String eventOf(Map<String, dynamic> m) => '${m['eventId'] ?? 'vinayaka'}';
bool inEvent(Map<String, dynamic> m, String eventId) => eventOf(m) == eventId;

/// One event's settings (title, dates, slots, UPI), edited by admins.
class Festival {
  const Festival({
    this.id = 'vinayaka',
    this.sevaLabel = 'Pooja Seva',
    this.icon = 'ganesha',
    required this.title,
    required this.start,
    required this.days,
    required this.slots,
    required this.upiId,
    required this.configured,
  });

  static const defaultSlots = ['Morning Pooja', 'Evening Aarti'];

  final String id;
  final String sevaLabel;
  final String icon;
  final String title;
  final DateTime start;
  final int days;
  final List<String> slots;
  final String upiId;
  final bool configured;

  factory Festival.fromMap(Map<String, dynamic>? m, {String id = 'vinayaka', String? title}) {
    final def = eventDefFor(id, title: title);
    final now = DateTime.now();
    final ts = m?['startDate'];
    final s = ts is Timestamp ? ts.toDate() : now;
    final rawDays = m?['days'];
    final days = rawDays is num ? rawDays.toInt().clamp(1, 31).toInt() : def.days;
    final rawSlots = m?['poojaSlots'];
    final slots = rawSlots is List
        ? rawSlots.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    return Festival(
      id: id,
      sevaLabel: '${m?['sevaLabel'] ?? def.sevaLabel}',
      icon: def.icon,
      title: '${m?['title'] ?? def.title}',
      start: DateTime(s.year, s.month, s.day),
      days: days,
      slots: slots.isEmpty ? def.slots : slots,
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

/// Apartment blocks members can belong to.
const residentBlocks = ['A', 'B', 'C'];

/// "A-101" style label for a contribution (empty for old entries).
String flatLabel(Map<String, dynamic> c) {
  final b = '${c['block'] ?? ''}';
  final f = '${c['flat'] ?? ''}';
  if (b.isEmpty && f.isEmpty) return '';
  return '$b-$f';
}
