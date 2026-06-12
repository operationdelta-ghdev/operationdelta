class Article {
  final String id;
  final String title;
  final String url;
  final int publishedAt;
  final List<IngressEvent> events;

  Article({
    required this.id,
    required this.title,
    required this.url,
    required this.publishedAt,
    required this.events,
  });

  factory Article.fromJson(Map<String, dynamic> json) {
    var list = json['events'] as List? ?? [];
    List<IngressEvent> parsedEvents = list.map((e) => IngressEvent.fromJson(e)).toList();

    return Article(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      publishedAt: json['published_at'] as int? ?? 0,
      events: parsedEvents,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'published_at': publishedAt,
      'events': events.map((e) => e.toJson()).toList(),
    };
  }
}

class IngressEvent {
  final String name;
  final DateTime startTime; // Parsed as UTC from ISO string
  final DateTime endTime;   // Parsed as UTC from ISO string
  final String timingType;  // 'global' or 'local'
  final List<String> changes;

  IngressEvent({
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.timingType,
    required this.changes,
  });

  factory IngressEvent.fromJson(Map<String, dynamic> json) {
    return IngressEvent(
      name: json['name'] as String? ?? 'Unknown Anomaly',
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      timingType: json['timing_type'] as String? ?? 'global',
      changes: List<String>.from(json['changes'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'timing_type': timingType,
      'changes': changes,
    };
  }

  // Returns event status: 'active', 'upcoming', or 'past'
  String getStatus(DateTime now) {
    DateTime start = getAdjustedStart(now);
    DateTime end = getAdjustedEnd(now);
    
    if (!now.isBefore(start) && now.isBefore(end)) {
      return 'active';
    } else if (now.isBefore(start)) {
      return 'upcoming';
    } else {
      return 'past';
    }
  }

  // Adjust time relative to user context:
  // - Global: Time represents exact instant, convert UTC to user local.
  // - Local: Time represents wall-clock time. E.g. 18:00 UTC in DB is interpreted as 18:00 local time.
  DateTime getAdjustedStart(DateTime now) {
    if (timingType == 'local') {
      return _toLocalWallClock(startTime);
    } else {
      return startTime.toLocal(); // Convert absolute UTC moment to user device local time
    }
  }

  DateTime getAdjustedEnd(DateTime now) {
    if (timingType == 'local') {
      return _toLocalWallClock(endTime);
    } else {
      return endTime.toLocal();
    }
  }

  // Converts a UTC date (e.g. 2026-06-12 18:00:00.000Z) to local timezone wall clock date (e.g. 2026-06-12 18:00:00.000 local)
  DateTime _toLocalWallClock(DateTime utcDate) {
    return DateTime(
      utcDate.year,
      utcDate.month,
      utcDate.day,
      utcDate.hour,
      utcDate.minute,
      utcDate.second,
      utcDate.millisecond,
    );
  }
}
