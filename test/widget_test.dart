import 'package:flutter_test/flutter_test.dart';
import 'package:vinayaka_utsav/models.dart';

void main() {
  test('festival defaults to 10 days with two pooja slots', () {
    final f = Festival.fromMap(null);
    expect(f.days, 10);
    expect(f.dates.length, 10);
    expect(f.slots, Festival.defaultSlots);
    expect(f.configured, isFalse);
  });

  test('time and money formatting', () {
    expect(prettyTime('19:05'), '7:05 PM');
    expect(rupees(150000), '₹1,50,000');
  });
}
