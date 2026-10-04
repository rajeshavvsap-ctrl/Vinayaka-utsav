import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../services/db.dart';
import '../services/report.dart';
import '../services/proof_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Member contributions (chanda). A member pays by UPI/cash/bank, uploads
/// the payment screenshot, and an admin verifies it before it counts in the
/// "Collected" total.
class ContributionsScreen extends StatefulWidget {
  const ContributionsScreen({super.key, required this.session});
  final Session session;

  @override
  State<ContributionsScreen> createState() => _ContributionsScreenState();
}

class _ContributionsScreenState extends State<ContributionsScreen> {
  String _filter = 'All';
  static const _filters = ['All', 'Pending', 'Verified', 'Mine'];

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contributions'),
        actions: [
          PdfAction(
            make: () => shareContributionsReport(s.festival, filter: _filter, myId: s.me.id),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddContributionScreen(session: s))),
        icon: const Icon(Icons.add),
        label: const Text('I have paid'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.contributions.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return LoadErrorView(snap.error);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!.docs.toList()
            ..sort((a, b) {
              // Pending first, then newest date.
              final pa = a.data()['status'] == 'pending' ? 0 : 1;
              final pb = b.data()['status'] == 'pending' ? 0 : 1;
              if (pa != pb) return pa - pb;
              return '${b.data()['date']}'.compareTo('${a.data()['date']}');
            });
          num verified = 0, pending = 0;
          for (final d in all) {
            final m = d.data();
            if (m['status'] == 'verified') verified += toNum(m['amount']);
            if (m['status'] == 'pending') pending += toNum(m['amount']);
          }
          final shown = all.where((d) {
            final m = d.data();
            switch (_filter) {
              case 'Pending':
                return m['status'] == 'pending';
              case 'Verified':
                return m['status'] == 'verified';
              case 'Mine':
                return m['createdBy'] == s.me.id;
              default:
                return true;
            }
          }).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              AppCard(
                color: AppColors.maroon,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Collected (verified)', style: TextStyle(color: AppColors.gold, fontSize: 13)),
                    Text(rupees(verified), style: display(28, color: Colors.white)),
                    if (pending > 0)
                      Text('${rupees(pending)} waiting for verification',
                          style: const TextStyle(color: Color(0xFFF3DCCB), fontSize: 13)),
                  ],
                ),
              ),
              if (s.festival.upiId.isNotEmpty) ...[
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  child: Row(
                    children: [
                      const IconBadge(
                          icon: Icons.qr_code_2, bg: AppColors.purpleBg, fg: AppColors.purple, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pay committee UPI', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                            Text(s.festival.upiId,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy UPI ID',
                        icon: const Icon(Icons.copy_outlined),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: s.festival.upiId));
                          toast(context, 'UPI ID copied. Pay in GPay / PhonePe / Paytm.');
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final f in _filters)
                    ChoiceChip(
                      label: Text(f),
                      selected: _filter == f,
                      showCheckmark: false,
                      labelStyle: TextStyle(color: _filter == f ? Colors.white : AppColors.ink),
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (shown.isEmpty)
                const EmptyHint(
                    icon: Icons.volunteer_activism_outlined,
                    text: 'No contributions here yet.\nAfter paying, tap "I have paid" and share the screenshot.'),
              for (final d in shown) ...[
                _row(context, d),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final c = doc.data();
    return AppCard(
      padding: const EdgeInsets.all(12),
      onTap: () => _detail(context, doc),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: AppColors.purpleBg,
            child: Text(
              '${c['name']}'.isNotEmpty ? '${c['name']}'[0].toUpperCase() : '?',
              style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text(
                    [if (flatLabel(c).isNotEmpty) flatLabel(c), shortDay('${c['date']}'), '${c['mode']}']
                        .join(' · '),
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(rupees(toNum(c['amount'])), style: display(17)),
              StatusPill.forStatus('${c['status']}'),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _detail(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final c = doc.data();
    final s = widget.session;
    final proofId = '${c['proofId'] ?? ''}';
    final pending = c['status'] == 'pending';
    final canDelete = s.isAdmin || (c['createdBy'] == s.me.id && pending);

    Future<void> setStatus(BuildContext sheet, String status) async {
      try {
        await doc.reference.update({
          'status': status,
          'verifiedBy': s.me.id,
          'verifiedByName': s.me.name,
          'verifiedAt': FieldValue.serverTimestamp(),
        });
        if (sheet.mounted) Navigator.pop(sheet);
      } catch (e) {
        if (sheet.mounted) toast(sheet, 'Could not update: $e');
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: proofId.isEmpty ? 0.55 : 0.85,
        maxChildSize: 0.95,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Expanded(child: Text('${c['name']}', style: display(22))),
                StatusPill.forStatus('${c['status']}'),
              ],
            ),
            Text(rupees(toNum(c['amount'])), style: display(28, color: AppColors.maroon)),
            const SizedBox(height: 10),
            DetailRow('Block / flat', flatLabel(c)),
            DetailRow('Date', prettyDay('${c['date']}')),
            DetailRow('Mode', '${c['mode']}'),
            DetailRow('UPI / Txn ref', '${c['txnRef'] ?? ''}'),
            DetailRow('Note', '${c['note'] ?? ''}'),
            if (c['status'] == 'verified')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  onPressed: () => shareContributionReceipt(s.festival, c, doc.id),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Download receipt (PDF)'),
                ),
              ),
            if (!pending) DetailRow(c['status'] == 'verified' ? 'Verified by' : 'Checked by', '${c['verifiedByName'] ?? ''}'),
            const SizedBox(height: 12),
            if (proofId.isNotEmpty)
              ProofImage(proofId: proofId, height: 340)
            else
              const Text('No screenshot attached.', style: TextStyle(color: AppColors.muted)),
            if (s.isAdmin && pending) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setStatus(sheet, 'rejected'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, minimumSize: const Size(0, 52)),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => setStatus(sheet, 'verified'),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Verify payment'),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                    ),
                  ),
                ],
              ),
            ],
            if (s.isAdmin && !pending) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => doc.reference.update({'status': 'pending'}).then((_) {
                  if (sheet.mounted) Navigator.pop(sheet);
                }),
                child: const Text('Move back to pending'),
              ),
            ],
            if (canDelete) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await confirmDialog(sheet, 'Delete entry?', 'This contribution entry will be removed.',
                      ok: 'Delete')) {
                    await doc.reference.delete();
                    await Db.deleteProof(proofId);
                    if (sheet.mounted) Navigator.pop(sheet);
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete entry'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AddContributionScreen extends StatefulWidget {
  const AddContributionScreen({super.key, required this.session});
  final Session session;

  @override
  State<AddContributionScreen> createState() => _AddContributionScreenState();
}

class _AddContributionScreenState extends State<AddContributionScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.session.me.name);
  final _flat = TextEditingController();
  final _amount = TextEditingController();
  final _txn = TextEditingController();
  final _note = TextEditingController();
  String? _block;
  String _mode = paymentModes.first;
  late String _day = widget.session.festival.initialDay();
  Uint8List? _proof;
  bool _busy = false;
  bool _submitted = false; // show errors on every field after the first tap on Submit

  @override
  void dispose() {
    _name.dispose();
    _flat.dispose();
    _amount.dispose();
    _txn.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _needsProof => _mode != 'Cash';
  bool get _needsRef => _mode != 'Cash';

  // ---------- validators ----------
  static final _nameRe = RegExp(r"^[A-Za-zऀ-ॿఀ-౿ .'-]+$");
  static final _flatRe = RegExp(r'^[A-Za-z0-9-]{1,6}$');
  static final _refRe = RegExp(r'^[A-Za-z0-9]{6,35}$');
  static final _amountRe = RegExp(r'^\d+(\.\d{1,2})?$');

  String? _vName(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Enter the contributor name';
    if (t.length < 2) return 'Name is too short';
    if (t.length > 60) return 'Name must be 60 characters or less';
    if (!_nameRe.hasMatch(t)) return 'Use letters and spaces only';
    return null;
  }

  String? _vFlat(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Enter your flat number';
    if (!_flatRe.hasMatch(t)) return 'Flat number: up to 6 letters/digits (e.g. 101, G2)';
    if (!RegExp(r'\d').hasMatch(t)) return 'Flat number must contain a number';
    return null;
  }

  String? _vAmount(String? v) {
    final t = (v ?? '').trim().replaceAll(',', '');
    if (t.isEmpty) return 'Enter the amount paid';
    if (!_amountRe.hasMatch(t)) return 'Enter numbers only (up to 2 decimals)';
    final n = num.parse(t);
    if (n <= 0) return 'Amount must be more than ₹0';
    if (n >= 10000000) return 'Amount looks too large';
    return null;
  }

  String? _vRef(String? v) {
    if (!_needsRef) return null;
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Enter the UPI / transaction reference number';
    if (!_refRe.hasMatch(t)) return '6–35 letters or digits, no spaces';
    return null;
  }

  String? _vNote(String? v) => (v ?? '').trim().length > 200 ? 'Note must be 200 characters or less' : null;

  Future<void> _save() async {
    setState(() => _submitted = true);
    final fieldsOk = _form.currentState!.validate(); // also validates the block check boxes
    final proofOk = !_needsProof || _proof != null;
    if (!fieldsOk || !proofOk) {
      toast(context, 'Please fix the fields marked in red.');
      return;
    }
    setState(() => _busy = true);
    try {
      final ref = _txn.text.trim();
      if (_needsRef) {
        // Stop the same payment being submitted twice.
        final dup = await Db.contributions.where('txnRef', isEqualTo: ref).limit(1).get();
        if (dup.docs.isNotEmpty) {
          if (mounted) {
            setState(() => _busy = false);
            toast(context, 'This transaction reference was already submitted.');
          }
          return;
        }
      }
      String? proofId;
      if (_proof != null) proofId = await Db.saveProof(_proof!);
      await Db.contributions.add({
        'name': _name.text.trim(),
        'block': _block,
        'flat': _flat.text.trim().toUpperCase(),
        'amount': num.parse(_amount.text.trim().replaceAll(',', '')),
        'mode': _mode,
        'txnRef': _needsRef ? ref : '',
        'note': _note.text.trim(),
        'date': _day,
        'proofId': proofId,
        'status': 'pending',
        ...Db.stamp(),
      });
      if (mounted) {
        toast(context, 'Thank you! An admin will verify your payment.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Could not save: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final upi = widget.session.festival.upiId;
    return Scaffold(
      appBar: AppBar(title: const Text('Share payment')),
      body: Form(
        key: _form,
        autovalidateMode: _submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (upi.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text('1. Pay to UPI ID $upi\n2. Fill all details and attach the screenshot below.',
                    style: const TextStyle(color: AppColors.muted)),
              ),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Contributor name (person or family) *', counterText: ''),
              validator: _vName,
            ),
            const SizedBox(height: 16),
            FormField<String>(
              initialValue: _block,
              validator: (v) => v == null ? 'Select your block (A, B or C)' : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Block *', style: TextStyle(fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      for (final b in residentBlocks)
                        Expanded(
                          child: CheckboxListTile(
                            value: field.value == b,
                            title: Text('$b Block'),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: AppColors.maroon,
                            onChanged: (checked) {
                              final v = checked == true ? b : null; // one block only
                              field.didChange(v);
                              setState(() => _block = v);
                            },
                          ),
                        ),
                    ],
                  ),
                  if (field.hasError)
                    Text(field.errorText!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _flat,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Flat number * (e.g. 101)', counterText: ''),
              validator: _vFlat,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount paid *', prefixText: '₹ '),
              validator: _vAmount,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _mode,
              decoration: const InputDecoration(labelText: 'Paid by *'),
              items: [for (final m in paymentModes) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => _mode = v ?? _mode),
              validator: (v) => v == null ? 'Select how you paid' : null,
            ),
            const SizedBox(height: 12),
            FestivalDayField(
              label: 'Payment date *',
              festival: widget.session.festival,
              value: _day,
              onChanged: (d) => setState(() => _day = d),
            ),
            const SizedBox(height: 12),
            if (_needsRef) ...[
              TextFormField(
                controller: _txn,
                maxLength: 35,
                decoration: const InputDecoration(
                  labelText: 'UPI ref / transaction ID *',
                  helperText: 'Shown in your UPI app under payment details (12 digits for UPI)',
                  counterText: '',
                ),
                validator: _vRef,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Note (optional)', counterText: ''),
              validator: _vNote,
            ),
            const SizedBox(height: 16),
            ProofField(
              label: _needsProof ? 'Attach payment screenshot *' : 'Attach receipt photo (optional)',
              bytes: _proof,
              onPick: () async {
                final b = await pickProof(context);
                if (b != null) setState(() => _proof = b);
              },
              onClear: () => setState(() => _proof = null),
            ),
            if (_submitted && _needsProof && _proof == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Payment screenshot is required for UPI / bank payments',
                    style: TextStyle(color: AppColors.red, fontSize: 12)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Submit for verification'),
            ),
            const SizedBox(height: 8),
            const Text('* required', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
