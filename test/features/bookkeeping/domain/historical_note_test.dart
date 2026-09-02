import 'package:anbookkeep/core/datetime/local_minute.dart';
import 'package:anbookkeep/features/bookkeeping/domain/historical_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final notes = [
    HistoricalNote(
      value: '常用旧备注',
      useCount: 10,
      lastUsedAt: LocalMinute.parse('2025-01-01 12:00'),
    ),
    HistoricalNote(
      value: '最近备注',
      useCount: 3,
      lastUsedAt: LocalMinute.parse('2026-09-01 12:00'),
    ),
  ];

  test('default ranking sorts by usage count', () {
    final ranked = rankHistoricalNotes(
      notes,
      smartSort: false,
      now: DateTime(2026, 9, 2),
    );

    expect(ranked.map((note) => note.value), ['常用旧备注', '最近备注']);
  });

  test('smart ranking balances frequency with recent usage', () {
    final ranked = rankHistoricalNotes(
      notes,
      smartSort: true,
      now: DateTime(2026, 9, 2),
    );

    expect(ranked.map((note) => note.value), ['最近备注', '常用旧备注']);
  });

  test('ranking respects the requested maximum result count', () {
    final ranked = rankHistoricalNotes(
      notes,
      smartSort: false,
      now: DateTime(2026, 9, 2),
      limit: 1,
    );

    expect(ranked, hasLength(1));
  });

  test('smart ranking uses every available bookkeeping context score', () {
    final contextualNotes = [
      HistoricalNote(
        value: '不匹配',
        useCount: 3,
        lastUsedAt: LocalMinute.parse('2026-09-01 12:00'),
        categoryAffinity: 0,
        amountSimilarity: 0.1,
        minuteSimilarity: 0.1,
      ),
      HistoricalNote(
        value: '匹配',
        useCount: 3,
        lastUsedAt: LocalMinute.parse('2026-09-01 12:00'),
        categoryAffinity: 1,
        amountSimilarity: 1,
        minuteSimilarity: 1,
      ),
    ];

    final ranked = rankHistoricalNotes(
      contextualNotes,
      smartSort: true,
      now: DateTime(2026, 9, 2),
    );

    expect(ranked.first.value, '匹配');
  });
}
