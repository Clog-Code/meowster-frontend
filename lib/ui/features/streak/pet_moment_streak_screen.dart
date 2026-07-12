import 'package:flutter/material.dart';

import '../../../data/services/pet_streak_client.dart';
import '../../../domain/models/pet_streak_summary.dart';
import '../../core/pet_theme.dart';

String catMomentMarker(PetStreakDay? day) {
  if (day == null || !day.hasCapture) return '🐾';
  final emotion = day.dominantEmotion?.trim().toLowerCase();
  if (day.isHealthy) {
    if (emotion == 'happy' || emotion == 'playful') return '😸';
    if (emotion == 'surprised') return '🙀';
    return '😺';
  }
  if (emotion == 'angry' || emotion == 'watchful') return '😾';
  return '😿';
}

String _shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

String _longDate(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

class PetMomentStreakScreen extends StatefulWidget {
  const PetMomentStreakScreen({
    required this.streakClient,
    this.petId = 'pet-01',
    super.key,
  });

  final PetStreakClient streakClient;
  final String petId;

  @override
  State<PetMomentStreakScreen> createState() => _PetMomentStreakScreenState();
}

class _PetMomentStreakScreenState extends State<PetMomentStreakScreen> {
  late Future<PetStreakSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _loadSummary();
  }

  Future<PetStreakSummary> _loadSummary() {
    return widget.streakClient.fetchStreakSummary(petId: widget.petId);
  }

  void _retry() {
    setState(() {
      _summaryFuture = _loadSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pet moment streak')),
      body: SafeArea(
        child: FutureBuilder<PetStreakSummary>(
          future: _summaryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: PetTheme.aqua),
              );
            }

            if (snapshot.hasError) {
              return _StreakErrorState(onRetry: _retry);
            }

            final summary = snapshot.data ?? PetStreakSummary.empty();
            return _StreakContent(summary: summary);
          },
        ),
      ),
    );
  }
}

class _StreakContent extends StatefulWidget {
  const _StreakContent({required this.summary});

  final PetStreakSummary summary;

  @override
  State<_StreakContent> createState() => _StreakContentState();
}

class _StreakContentState extends State<_StreakContent> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(
      widget.summary.monthStart.year,
      widget.summary.monthStart.month,
    );
  }

  void _moveMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  void _showToday() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        const _UserProfileCard(),
        const SizedBox(height: 18),
        _HeroStreak(summary: summary),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Current',
                value: '${summary.currentStreak}',
                icon: Icons.local_fire_department,
                color: PetTheme.coral,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                label: 'Longest',
                value: '${summary.longestStreak}',
                icon: Icons.emoji_events_outlined,
                color: PetTheme.warning,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricTile(
                label: 'Moments',
                value: '${summary.momentsThisMonth}',
                icon: Icons.pets,
                color: PetTheme.aqua,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _MonthInsights(summary: summary, monthStart: _visibleMonth),
        const SizedBox(height: 24),
        _CalendarSection(
          summary: summary,
          monthStart: _visibleMonth,
          onPrevious: () => _moveMonth(-1),
          onToday: _showToday,
          onNext: () => _moveMonth(1),
        ),
        const SizedBox(height: 24),
        _MomentReel(summary: summary, monthStart: _visibleMonth),
      ],
    );
  }
}

class _UserProfileCard extends StatelessWidget {
  const _UserProfileCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PetTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profile', style: TextStyle(fontWeight: FontWeight.w800)),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ProfileDetail(
                    icon: Icons.person_outline,
                    value: 'Dickson Lai',
                  ),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: _ProfileDetail(
                    icon: Icons.phone_outlined,
                    value: '+65 8xxx 9460',
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            _ProfileDetail(
              icon: Icons.location_on_outlined,
              value: '14000 Bukit Mertajam, Pulau Pinang',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: PetTheme.aqua),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: PetTheme.muted),
          ),
        ),
      ],
    );
  }
}

class _HeroStreak extends StatelessWidget {
  const _HeroStreak({required this.summary});

  final PetStreakSummary summary;

  @override
  Widget build(BuildContext context) {
    final hasMoments = summary.momentsThisMonth > 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PetTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: PetTheme.coral.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.local_fire_department,
                color: PetTheme.coral,
                size: 34,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${summary.currentStreak} day streak',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasMoments
                        ? 'Tiny daily check-ins build a richer pet health story.'
                        : 'Capture a pet moment today to start the streak.',
                    style: const TextStyle(color: PetTheme.muted, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PetTheme.panelSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PetTheme.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthInsights extends StatelessWidget {
  const _MonthInsights({required this.summary, required this.monthStart});

  final PetStreakSummary summary;
  final DateTime monthStart;

  @override
  Widget build(BuildContext context) {
    final capturedDays = summary.capturedDaysInMonth(monthStart);
    final daysInMonth = DateUtils.getDaysInMonth(
      monthStart.year,
      monthStart.month,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: _UsageRing(
            capturedDays: capturedDays,
            daysInMonth: daysInMonth,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 5,
          child: _WeeklyBars(summary: summary, monthStart: monthStart),
        ),
      ],
    );
  }
}

class _UsageRing extends StatelessWidget {
  const _UsageRing({required this.capturedDays, required this.daysInMonth});

  final int capturedDays;
  final int daysInMonth;

  @override
  Widget build(BuildContext context) {
    final progress = daysInMonth == 0 ? 0.0 : capturedDays / daysInMonth;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PetTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            SizedBox(
              width: 104,
              height: 104,
              child: CustomPaint(
                painter: _UsageRingPainter(progress: progress.clamp(0, 1)),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$capturedDays/$daysInMonth',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'days',
                        style: TextStyle(color: PetTheme.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Using app',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: PetTheme.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageRingPainter extends CustomPainter {
  const _UsageRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 10) / 2;
    final track = Paint()
      ..color = const Color(0x26FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9;
    final progressPaint = Paint()
      ..shader = const SweepGradient(
        colors: [PetTheme.aqua, PetTheme.sage, PetTheme.coral],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      progress * 6.2832,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _UsageRingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _WeeklyBars extends StatelessWidget {
  const _WeeklyBars({required this.summary, required this.monthStart});

  final PetStreakSummary summary;
  final DateTime monthStart;

  @override
  Widget build(BuildContext context) {
    final days = _mondayThroughSaturday(monthStart);
    final maxCaptures = days
        .map((date) => summary.dayFor(date)?.captureCount ?? 0)
        .fold(1, (max, count) => count > max ? count : max);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: PetTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weekly view',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 112,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final date in days)
                    Expanded(
                      child: _WeeklyBar(
                        label: _weekdayLabel(date.weekday),
                        count: summary.dayFor(date)?.captureCount ?? 0,
                        maxCount: maxCaptures,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DateTime> _mondayThroughSaturday(DateTime monthStart) {
    final now = DateTime.now();
    final anchor = now.year == monthStart.year && now.month == monthStart.month
        ? DateTime(now.year, now.month, now.day)
        : DateTime(monthStart.year, monthStart.month, 15);
    final monday = anchor.subtract(Duration(days: anchor.weekday - 1));
    return [
      for (var index = 0; index < 6; index++) monday.add(Duration(days: index)),
    ];
  }

  String _weekdayLabel(int weekday) {
    return const {
          DateTime.monday: 'M',
          DateTime.tuesday: 'T',
          DateTime.wednesday: 'W',
          DateTime.thursday: 'T',
          DateTime.friday: 'F',
          DateTime.saturday: 'S',
        }[weekday] ??
        '';
  }
}

class _WeeklyBar extends StatelessWidget {
  const _WeeklyBar({
    required this.label,
    required this.count,
    required this.maxCount,
  });

  final String label;
  final int count;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    final height = count == 0 ? 8.0 : 18.0 + (count / maxCount) * 54;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            count == 0 ? '' : '$count',
            style: const TextStyle(fontSize: 10, color: PetTheme.muted),
          ),
          const SizedBox(height: 4),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 18,
            height: height,
            decoration: BoxDecoration(
              color: count == 0
                  ? const Color(0x24FFFFFF)
                  : PetTheme.aqua.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: PetTheme.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _CalendarSection extends StatelessWidget {
  const _CalendarSection({
    required this.summary,
    required this.monthStart,
    required this.onPrevious,
    required this.onToday,
    required this.onNext,
  });

  final PetStreakSummary summary;
  final DateTime monthStart;
  final VoidCallback onPrevious;
  final VoidCallback onToday;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(
      monthStart.year,
      monthStart.month,
    );
    final leadingBlanks = monthStart.weekday % DateTime.daysPerWeek;
    final totalCells = leadingBlanks + daysInMonth;
    final rowCount = (totalCells / DateTime.daysPerWeek).ceil();
    final monthLabel = _monthLabel(monthStart);
    final momentsThisMonth = summary.momentsInMonth(monthStart);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                monthLabel,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: 'Previous month',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left),
            ),
            TextButton(onPressed: onToday, child: const Text('Today')),
            IconButton(
              tooltip: 'Next month',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Expanded(
              child: Center(
                child: Text(
                  'S',
                  style: TextStyle(color: PetTheme.muted, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'M',
                  style: TextStyle(color: PetTheme.muted, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'T',
                  style: TextStyle(color: PetTheme.muted, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'W',
                  style: TextStyle(color: PetTheme.muted, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'T',
                  style: TextStyle(color: PetTheme.muted, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'F',
                  style: TextStyle(color: PetTheme.muted, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'S',
                  style: TextStyle(color: PetTheme.muted, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rowCount * DateTime.daysPerWeek,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: DateTime.daysPerWeek,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.86,
          ),
          itemBuilder: (context, index) {
            final dayNumber = index - leadingBlanks + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const SizedBox.shrink();
            }
            final date = DateTime(monthStart.year, monthStart.month, dayNumber);
            return _CalendarDayCell(
              date: date,
              dayNumber: dayNumber,
              day: summary.dayFor(date),
            );
          },
        ),
        if (momentsThisMonth == 0) ...[
          const SizedBox(height: 18),
          const _EmptyCalendarHint(),
        ],
      ],
    );
  }

  String _monthLabel(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.dayNumber,
    required this.day,
  });

  final DateTime date;
  final int dayNumber;
  final PetStreakDay? day;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final hasCapture = day?.hasCapture ?? false;
    final marker = _catMarker(day);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isToday ? PetTheme.aqua.withValues(alpha: 0.18) : PetTheme.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isToday
              ? PetTheme.aqua
              : hasCapture
              ? const Color(0x40FFFFFF)
              : const Color(0x18FFFFFF),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$dayNumber',
              style: TextStyle(
                fontSize: 12,
                height: 1,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: hasCapture ? PetTheme.ivory : PetTheme.muted,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: hasCapture ? 1 : 0.28,
              child: Text(
                marker,
                style: TextStyle(
                  fontSize: hasCapture ? 13 : 11,
                  height: 1,
                  color: hasCapture || marker != '🐾' ? null : PetTheme.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _catMarker(PetStreakDay? day) {
    return catMomentMarker(day);
  }
}

class _MomentReel extends StatelessWidget {
  const _MomentReel({required this.summary, required this.monthStart});

  final PetStreakSummary summary;
  final DateTime monthStart;

  @override
  Widget build(BuildContext context) {
    final days = summary.daysForMonth(monthStart)
      ..sort((a, b) => b.date.compareTo(a.date));
    final capturedDays = days.where((day) => day.hasCapture).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Moment reel',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            const Icon(Icons.auto_stories_outlined, color: PetTheme.aqua),
          ],
        ),
        const SizedBox(height: 10),
        if (capturedDays.isEmpty)
          const _EmptyMomentReel()
        else
          SizedBox(
            height: 134,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final day = capturedDays[index];
                return _MomentPreviewCard(
                  day: day,
                  onTap: () => _showMomentPreview(context, day),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemCount: capturedDays.length,
            ),
          ),
      ],
    );
  }

  void _showMomentPreview(BuildContext context, PetStreakDay day) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PetTheme.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) => _MomentPreviewSheet(day: day),
    );
  }
}

class _MomentPreviewCard extends StatelessWidget {
  const _MomentPreviewCard({required this.day, required this.onTap});

  final PetStreakDay day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final marker = catMomentMarker(day);
    return Semantics(
      button: true,
      label: 'Preview cat moment ${_shortDate(day.date)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 104,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: PetTheme.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x24FFFFFF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(marker, style: const TextStyle(fontSize: 24, height: 1)),
              const Spacer(),
              Text(
                _shortDate(day.date),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                day.dominantEmotion ?? 'moment',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PetTheme.muted,
                  fontSize: 11,
                  height: 1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${day.captureCount} snap${day.captureCount == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: PetTheme.aqua,
                  fontSize: 10,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MomentPreviewSheet extends StatelessWidget {
  const _MomentPreviewSheet({required this.day});

  final PetStreakDay day;

  @override
  Widget build(BuildContext context) {
    final marker = catMomentMarker(day);
    final healthLabel = day.isHealthy ? 'Healthy moment' : 'Needs attention';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: (day.isHealthy ? PetTheme.sage : PetTheme.coral)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(marker, style: const TextStyle(fontSize: 36)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _longDate(day.date),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        healthLabel,
                        style: TextStyle(
                          color: day.isHealthy ? PetTheme.sage : PetTheme.coral,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _PreviewFact(
              icon: Icons.camera_alt_outlined,
              label: 'Captured',
              value:
                  '${day.captureCount} pet moment${day.captureCount == 1 ? '' : 's'}',
            ),
            const SizedBox(height: 10),
            _PreviewFact(
              icon: Icons.psychology_alt_outlined,
              label: 'Mood',
              value: day.dominantEmotion ?? 'Unknown',
            ),
            const SizedBox(height: 10),
            _PreviewFact(
              icon: Icons.pets,
              label: 'Species',
              value: day.species ?? 'Pet',
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewFact extends StatelessWidget {
  const _PreviewFact({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: PetTheme.aqua, size: 20),
        const SizedBox(width: 10),
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(color: PetTheme.muted)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _EmptyMomentReel extends StatelessWidget {
  const _EmptyMomentReel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PetTheme.panelSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Captured cat moments for this month will appear here as a swipeable memory reel.',
          style: TextStyle(color: PetTheme.muted, height: 1.35),
        ),
      ),
    );
  }
}

class _EmptyCalendarHint extends StatelessWidget {
  const _EmptyCalendarHint();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PetTheme.panelSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, color: PetTheme.aqua),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No pet moments recorded for this month yet.',
                style: TextStyle(color: PetTheme.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakErrorState extends StatelessWidget {
  const _StreakErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final fallback = PetStreakSummary.empty();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        _HeroStreak(summary: fallback),
        const SizedBox(height: 18),
        DecoratedBox(
          decoration: BoxDecoration(
            color: PetTheme.panelSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Streak history is unavailable',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can still capture today\'s pet moment. Try loading the calendar again when the backend is reachable.',
                  style: TextStyle(color: PetTheme.muted, height: 1.35),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
