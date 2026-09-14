import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/time/league_time.dart';

class DateScroller extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const DateScroller({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  State<DateScroller> createState() => _DateScrollerState();
}

class _DateScrollerState extends State<DateScroller> {
  late final ScrollController _scrollController;
  late final List<DateTime> _dates;

  static const double _pillWidth = 56.0;
  static const double _pillSpacing = 8.0;
  static const int _daysBefore = 15;
  static const int _daysAfter = 15;

  @override
  void initState() {
    super.initState();
    final today = LeagueTime.jamaicaDate(DateTime.now());
    final startDate = today.subtract(const Duration(days: _daysBefore));
    _dates = List.generate(
      _daysBefore + 1 + _daysAfter,
      (i) => startDate.add(Duration(days: i)),
    );

    // Calculate initial scroll offset to center the selected date
    final selectedIndex = _indexOfDate(widget.selectedDate);
    final initialOffset = _offsetForIndex(selectedIndex);
    _scrollController = ScrollController(initialScrollOffset: initialOffset);
  }

  int _indexOfDate(DateTime date) {
    final norm = DateTime.utc(date.year, date.month, date.day);
    for (int i = 0; i < _dates.length; i++) {
      if (_dates[i].year == norm.year &&
          _dates[i].month == norm.month &&
          _dates[i].day == norm.day) {
        return i;
      }
    }
    return _daysBefore; // fallback to today's index
  }

  double _offsetForIndex(int index) {
    // Try to center the pill in the viewport
    // We estimate a viewport width of ~360 and center accordingly
    final pillOffset = index * (_pillWidth + _pillSpacing);
    final centering = 160.0; // approximate half viewport minus half pill
    return (pillOffset - centering).clamp(0.0, double.infinity);
  }

  @override
  void didUpdateWidget(DateScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedDate != widget.selectedDate) {
      final index = _indexOfDate(widget.selectedDate);
      final offset = _offsetForIndex(index);
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final today = LeagueTime.jamaicaDate(DateTime.now());

    return SizedBox(
      height: 72,
      child: ListView.separated(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.paddingMd,
          vertical: AppSizes.paddingSm,
        ),
        itemCount: _dates.length,
        separatorBuilder: (_, _) => const SizedBox(width: _pillSpacing),
        itemBuilder: (context, index) {
          final date = _dates[index];
          final isSelected = _isSameDay(date, widget.selectedDate);
          final isToday = _isSameDay(date, today);

          return GestureDetector(
            onTap: () => widget.onDateSelected(date),
            child: Container(
              width: _pillWidth,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : isToday
                    ? AppColors.primaryLight
                    : Colors.white,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : isToday
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : AppColors.border,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('E').format(date).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.8)
                          : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Colors.white
                          : isToday
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
