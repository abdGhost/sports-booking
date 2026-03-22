import 'package:flutter/material.dart';

import '../models/organizer_matchup.dart';

class MatchupDetailScreen extends StatefulWidget {
  const MatchupDetailScreen({super.key, required this.matchup});

  final OrganizerMatchup matchup;

  @override
  State<MatchupDetailScreen> createState() => _MatchupDetailScreenState();
}

class _MatchupDetailScreenState extends State<MatchupDetailScreen> {
  late final TextEditingController _aCtrl =
      TextEditingController(text: widget.matchup.scoreA.toString());
  late final TextEditingController _bCtrl =
      TextEditingController(text: widget.matchup.scoreB.toString());
  OrganizerMatchupStatus _status = OrganizerMatchupStatus.scheduled;

  @override
  void initState() {
    super.initState();
    _status = widget.matchup.status;
  }

  @override
  void dispose() {
    _aCtrl.dispose();
    _bCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Matchup details')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('${widget.matchup.teamAName} vs ${widget.matchup.teamBName}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _aCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Score A'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _bCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Score B'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<OrganizerMatchupStatus>(
              initialValue: _status,
              items: OrganizerMatchupStatus.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.name),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _status = v);
              },
              decoration: const InputDecoration(labelText: 'Status'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () {
                final a = int.tryParse(_aCtrl.text.trim()) ?? widget.matchup.scoreA;
                final b = int.tryParse(_bCtrl.text.trim()) ?? widget.matchup.scoreB;
                Navigator.of(context).pop(
                  widget.matchup.copyWith(scoreA: a, scoreB: b, status: _status),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
