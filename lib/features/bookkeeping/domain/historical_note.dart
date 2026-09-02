import 'dart:math' as math;

import 'package:anbookkeep/core/datetime/local_minute.dart';

final class HistoricalNote {
  const HistoricalNote({
    required this.value,
    required this.useCount,
    required this.lastUsedAt,
    this.categoryAffinity,
    this.amountSimilarity,
    this.minuteSimilarity,
  });

  final String value;
  final int useCount;
  final LocalMinute lastUsedAt;
  final double? categoryAffinity;
  final double? amountSimilarity;
  final double? minuteSimilarity;
}

List<HistoricalNote> rankHistoricalNotes(
  Iterable<HistoricalNote> notes, {
  required bool smartSort,
  required DateTime now,
  int limit = 20,
}) {
  if (limit <= 0) return const [];
  final ranked = notes.toList(growable: false);
  if (ranked.isEmpty) return ranked;

  if (!smartSort) {
    ranked.sort(_compareByFrequency);
  } else {
    final maxUseCount = ranked
        .map((note) => note.useCount)
        .reduce((left, right) => left > right ? left : right);
    final scores = <HistoricalNote, double>{
      for (final note in ranked)
        note: _smartScore(note, maxUseCount: maxUseCount, now: now),
    };
    ranked.sort((left, right) {
      final scoreOrder = scores[right]!.compareTo(scores[left]!);
      return scoreOrder != 0 ? scoreOrder : _compareByFrequency(left, right);
    });
  }
  return ranked.take(limit).toList(growable: false);
}

int _compareByFrequency(HistoricalNote left, HistoricalNote right) {
  final countOrder = right.useCount.compareTo(left.useCount);
  if (countOrder != 0) return countOrder;
  final recentOrder = right.lastUsedAt.compareTo(left.lastUsedAt);
  if (recentOrder != 0) return recentOrder;
  return left.value.compareTo(right.value);
}

double _smartScore(
  HistoricalNote note, {
  required int maxUseCount,
  required DateTime now,
}) {
  final frequency = math.log(note.useCount + 1) / math.log(maxUseCount + 1);
  final ageHours = now.difference(note.lastUsedAt.toDateTime()).inHours;
  final ageDays = math.max(0, ageHours) / Duration.hoursPerDay;
  final recency = math.pow(0.5, ageDays / 30).toDouble();
  var score = frequency * 0.36 + recency * 0.24;
  var activeWeight = 0.6;
  if (note.categoryAffinity case final value?) {
    score += value * 0.18;
    activeWeight += 0.18;
  }
  if (note.amountSimilarity case final value?) {
    score += value * 0.14;
    activeWeight += 0.14;
  }
  if (note.minuteSimilarity case final value?) {
    score += value * 0.08;
    activeWeight += 0.08;
  }
  return score / activeWeight;
}
