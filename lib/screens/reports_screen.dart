import 'package:flutter/material.dart';

import '../models.dart';
import '../services/report.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Admin-only: download a PDF for one festival day, or the final report.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.session});
  final Session session;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late String _day = widget.session.festival.initialDay();
  String? _busy; // which report is being made

  Future<void> _run(String which, Future<void> Function() make) async {
    setState(() => _busy = which);
    try {
      await make();
    } catch (e) {
      if (mounted) toast(context, 'Could not create report: $e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _spinner() => const SizedBox(
      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white));

  @override
  Widget build(BuildContext context) {
    final f = widget.session.festival;
    final n = f.dayNumber(_day);
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Day report', style: display(20)),
                  const SizedBox(height: 4),
                  const Text(
                    'Expenses, contributions, pooja names and activities for one day.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DayStrip(festival: f, selected: _day, onPick: (d) => setState(() => _day = d)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(
              onPressed: _busy != null ? null : () => _run('day', () => shareDayReport(f, _day)),
              icon: _busy == 'day' ? _spinner() : const Icon(Icons.picture_as_pdf_outlined),
              label: Text('Download Day $n report (${shortDay(_day)})'),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Final report', style: display(20)),
                  const SizedBox(height: 4),
                  const Text(
                    'Whole festival: collected vs spent, balance, day-wise totals, expenses by category, '
                    'and every expense and contribution.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _busy != null ? null : () => _run('final', () => shareFinalReport(f)),
                    icon: _busy == 'final' ? _spinner() : const Icon(Icons.summarize_outlined),
                    label: const Text('Download final report'),
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Text(
              'The PDF opens in the share menu: save it to Files / Drive or send it on WhatsApp.',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
