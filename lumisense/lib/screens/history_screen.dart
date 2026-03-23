import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:lumisense/models/history_entry.dart';
import 'package:lumisense/providers/history_provider.dart';
import 'package:lumisense/services/tts_service.dart';
import 'package:lumisense/utils/theme.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final HistoryProvider history = context.watch<HistoryProvider>();

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('History'),
        actions: <Widget>[
          if (history.hasEntries)
            IconButton(
              tooltip: 'Clear history',
              onPressed: () => _confirmClear(context),
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: history.hasEntries
          ? ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: history.entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) {
                final HistoryEntry item = history.entries[index];
                return _HistoryCard(entry: item);
              },
            )
          : const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'No history yet. Use Read or Identify in camera mode to save entries.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Clear history?'),
          content: const Text('This removes all saved OCR and object entries.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    await context.read<HistoryProvider>().clearAll();
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final DateFormat format = DateFormat('dd MMM, hh:mm a');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  switch (entry.type) {
                    HistoryEntryType.ocr => Icons.text_fields,
                    HistoryEntryType.objectDetection => Icons.search,
                    HistoryEntryType.sceneDescription => Icons.auto_awesome,
                  },
                  color: AppTheme.accentBlue,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Text(
                  format.format(entry.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              entry.content,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await context.read<TtsService>().speak(entry.content);
                },
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('Replay'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
