import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/db.dart';
import '../theme.dart';

/// White rounded card with the app's warm border.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color == null ? AppColors.line : Colors.transparent),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Horizontal picker of festival days.
class DayStrip extends StatelessWidget {
  const DayStrip({super.key, required this.festival, required this.selected, required this.onPick});
  final Festival festival;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final dates = festival.dates;
    return SizedBox(
      height: 76,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final key = dayKey(dates[i]);
          final sel = key == selected;
          return Material(
            color: sel ? AppColors.maroon : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: sel ? AppColors.maroon : AppColors.line),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onPick(key),
              child: SizedBox(
                width: 62,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('DAY ${i + 1}',
                        style: TextStyle(fontSize: 11, color: sel ? AppColors.gold : AppColors.muted)),
                    Text(DateFormat('d').format(dates[i]),
                        style: display(22, color: sel ? Colors.white : AppColors.ink)),
                    Text(DateFormat('MMM').format(dates[i]),
                        style: TextStyle(fontSize: 11, color: sel ? Colors.white : AppColors.muted)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;

  factory StatusPill.forStatus(String status) {
    switch (status) {
      case 'verified':
      case 'approved':
        return StatusPill(status == 'verified' ? 'Verified' : 'Approved', bg: AppColors.greenBg, fg: AppColors.green);
      case 'rejected':
        return const StatusPill('Rejected', bg: AppColors.redBg, fg: AppColors.red);
      default:
        return const StatusPill('Pending', bg: AppColors.amberBg, fg: AppColors.amber);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 12, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
        ],
      ),
    );
  }
}

class LoadErrorView extends StatelessWidget {
  const LoadErrorView(this.error, {super.key});
  final Object? error;

  @override
  Widget build(BuildContext context) => EmptyHint(
        icon: Icons.cloud_off_outlined,
        text: 'Could not load data. Check your internet connection.\n($error)',
      );
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.maroon)));
}

/// Small rounded square with an icon, used on tiles and list rows.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.bg, required this.fg, this.size = 44});
  final IconData icon;
  final Color bg;
  final Color fg;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, color: fg, size: size * 0.5),
    );
  }
}

/// Loads a stored screenshot and shows it; tap opens full screen.
class ProofImage extends StatelessWidget {
  const ProofImage({super.key, required this.proofId, this.height = 220});
  final String proofId;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: Db.loadProof(proofId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SizedBox(height: height, child: const Center(child: CircularProgressIndicator()));
        }
        final bytes = snap.data;
        if (bytes == null) {
          return const Text('Screenshot not available', style: TextStyle(color: AppColors.muted));
        }
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
              body: Center(child: InteractiveViewer(maxScale: 5, child: Image.memory(bytes))),
            ),
          )),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, height: height, fit: BoxFit.cover, width: double.infinity),
          ),
        );
      },
    );
  }
}

/// Attach-screenshot control used in the add forms.
class ProofField extends StatelessWidget {
  const ProofField({super.key, required this.bytes, required this.onPick, required this.onClear, this.label = 'Attach payment screenshot'});
  final Uint8List? bytes;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (bytes == null) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text(label),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes!, height: 200, width: double.infinity, fit: BoxFit.cover),
        ),
        Positioned(
          right: 8,
          top: 8,
          child: IconButton.filled(
            tooltip: 'Remove screenshot',
            onPressed: onClear,
            style: IconButton.styleFrom(backgroundColor: Colors.black54),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

Future<bool> confirmDialog(BuildContext context, String title, String message, {String ok = 'Yes'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Labelled value row for detail sheets.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: AppColors.muted))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

/// Date field that opens a date picker.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.first, this.last});
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? first;
  final DateTime? last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: first ?? DateTime(2020),
          lastDate: last ?? DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today_outlined)),
        child: Text(DateFormat('EEE, d MMM yyyy').format(value)),
      ),
    );
  }
}

String? amountValidator(String? v) {
  final n = num.tryParse((v ?? '').trim());
  if (n == null || n <= 0) return 'Enter a valid amount';
  if (n >= 10000000) return 'Amount looks too large';
  return null;
}

/// Dropdown limited to the festival days the admin configured.
class FestivalDayField extends StatelessWidget {
  const FestivalDayField({
    super.key,
    required this.festival,
    required this.value,
    required this.onChanged,
    this.label = 'Festival day',
  });
  final Festival festival;
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final keys = festival.dayKeys;
    return DropdownButtonFormField<String>(
      value: keys.contains(value) ? value : keys.first,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final k in keys)
          DropdownMenuItem(value: k, child: Text('Day ${festival.dayNumber(k)} · ${prettyDay(k)}')),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
