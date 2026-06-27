import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/firestore_paths.dart';
import '../../models/event_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';
import '../../providers/team_providers.dart';

// ── Round-robin helpers ──────────────────────────────────────────────

/// Circle-method round-robin.  Returns (homeId, awayId) pairs.
List<(String, String)> generateRoundRobin(List<String> teamIds, int rounds) {
  final ids = List<String>.from(teamIds);
  final hasBye = ids.length.isOdd;
  if (hasBye) ids.add(AppDefaults.byeTeamId);

  final n = ids.length;
  final matchups = <(String, String)>[];

  for (var r = 0; r < rounds; r++) {
    final circle = List<String>.from(ids);
    for (var round = 0; round < n - 1; round++) {
      for (var i = 0; i < n ~/ 2; i++) {
        final home = circle[i];
        final away = circle[n - 1 - i];
        if (home == AppDefaults.byeTeamId || away == AppDefaults.byeTeamId) {
          continue;
        }
        // Alternate home/away on even/odd repetitions
        if (r.isEven) {
          matchups.add((home, away));
        } else {
          matchups.add((away, home));
        }
      }
      // Rotate: fix circle[0], move last to index 1
      final last = circle.removeLast();
      circle.insert(1, last);
    }
  }
  return matchups;
}

/// Assigns matchups to date+time slots.
List<_ScheduledGame> _assignSlots({
  required List<(String, String)> matchups,
  required Map<String, String> teamNames,
  required DateTime startDate,
  required DateTime endDate,
  required Set<int> gameDays, // 1=Mon..7=Sun
  required List<TimeOfDay> timeSlots,
  required String venue,
}) {
  final results = <_ScheduledGame>[];
  var matchIdx = 0;
  var date = startDate;

  while (matchIdx < matchups.length && !date.isAfter(endDate)) {
    if (gameDays.contains(date.weekday)) {
      for (final slot in timeSlots) {
        if (matchIdx >= matchups.length) break;
        final (homeId, awayId) = matchups[matchIdx];
        final homeName = teamNames[homeId] ?? homeId;
        final awayName = teamNames[awayId] ?? awayId;
        results.add(
          _ScheduledGame(
            homeId: homeId,
            awayId: awayId,
            homeName: homeName,
            awayName: awayName,
            dateTime: DateTime(
              date.year,
              date.month,
              date.day,
              slot.hour,
              slot.minute,
            ),
            venue: venue,
          ),
        );
        matchIdx++;
      }
    }
    date = date.add(const Duration(days: 1));
  }
  return results;
}

class _ScheduledGame {
  final String homeId, awayId, homeName, awayName, venue;
  final DateTime dateTime;
  const _ScheduledGame({
    required this.homeId,
    required this.awayId,
    required this.homeName,
    required this.awayName,
    required this.dateTime,
    required this.venue,
  });
}

// ── Screen ───────────────────────────────────────────────────────────

class ScheduleGeneratorScreen extends ConsumerStatefulWidget {
  const ScheduleGeneratorScreen({super.key});

  @override
  ConsumerState<ScheduleGeneratorScreen> createState() =>
      _ScheduleGeneratorScreenState();
}

class _ScheduleGeneratorScreenState
    extends ConsumerState<ScheduleGeneratorScreen> {
  int _currentStep = 0;

  // Step 1: Division & Teams
  String? _divisionId;
  Set<String> _selectedTeamIds = {};

  // Step 2: Format
  int _rounds = AppDefaults.defaultRounds; // default double RR
  String _formatLabel = 'double';
  final _customRoundsController = TextEditingController(
    text: '${AppDefaults.defaultRounds}',
  );

  // Step 3: Dates & Times
  DateTime _startDate = DateTime.now().add(AppDefaults.scheduleStartOffset);
  DateTime _endDate = DateTime.now().add(AppDefaults.scheduleEndOffset);
  final Set<int> _gameDays = Set<int>.from(AppDefaults.defaultGameDays);
  final List<TimeOfDay> _timeSlots = [AppDefaults.defaultGameTime];

  // Step 4: Venue
  final _venueController = TextEditingController();

  // Step 5: Preview
  List<_ScheduledGame> _preview = [];
  bool _isCreating = false;
  double _createProgress = 0;

  @override
  void dispose() {
    _customRoundsController.dispose();
    _venueController.dispose();
    super.dispose();
  }

  // ── computed ──

  int get _gameCount {
    final n = _selectedTeamIds.length;
    if (n < 2) return 0;
    return (n * (n - 1) ~/ 2) * _rounds;
  }

  int get _availableSlots {
    var count = 0;
    var date = _startDate;
    while (!date.isAfter(_endDate)) {
      if (_gameDays.contains(date.weekday)) count += _timeSlots.length;
      date = date.add(const Duration(days: 1));
    }
    return count;
  }

  // ── generate preview ──

  void _generatePreview() {
    final teams = ref.read(teamsStreamProvider).valueOrNull ?? [];
    final teamNames = <String, String>{};
    for (final t in teams) {
      teamNames[t.id] = t.name;
    }

    final matchups = generateRoundRobin(_selectedTeamIds.toList(), _rounds);

    final scheduled = _assignSlots(
      matchups: matchups,
      teamNames: teamNames,
      startDate: _startDate,
      endDate: _endDate,
      gameDays: _gameDays,
      timeSlots: _timeSlots,
      venue: _venueController.text.trim().isEmpty
          ? 'TBD'
          : _venueController.text.trim(),
    );

    setState(() => _preview = scheduled);
  }

  // ── bulk create ──

  Future<void> _createSchedule() async {
    final user = ref.read(currentUserProvider).value;
    final assocId = ref.read(currentAssociationIdProvider);
    if (user == null || assocId == null) return;

    setState(() {
      _isCreating = true;
      _createProgress = 0;
    });

    try {
      final db = FirebaseFirestore.instance;
      final eventsCol = db.collection(FirestorePaths.events(assocId));

      // Firestore batch limit is 500
      const batchSize = 500;
      for (var i = 0; i < _preview.length; i += batchSize) {
        final batch = db.batch();
        final end = (i + batchSize > _preview.length)
            ? _preview.length
            : i + batchSize;

        for (var j = i; j < end; j++) {
          final g = _preview[j];
          final event = EventModel(
            id: '',
            title: '${g.homeName} vs ${g.awayName}',
            type: AppDefaults.eventTypeGame,
            startTime: g.dateTime,
            endTime: g.dateTime.add(AppDefaults.defaultGameDuration),
            location: g.venue,
            divisionId: _divisionId,
            teamIds: [g.homeId, g.awayId],
            createdBy: user.id,
          );
          batch.set(eventsCol.doc(), event.toFirestore());
        }

        await batch.commit();
        setState(() {
          _createProgress = end / _preview.length;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_preview.length} games created successfully!'),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  // ── date/time pickers ──

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(AppDefaults.datePickerMaxFuture),
    );
    if (date != null) setState(() => _startDate = date);
  }

  Future<void> _pickEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: _startDate,
      lastDate: _startDate.add(AppDefaults.datePickerMaxFuture),
    );
    if (date != null) setState(() => _endDate = date);
  }

  Future<void> _addTimeSlot() async {
    final time = await showTimePicker(
      context: context,
      initialTime: AppDefaults.altGameTimeSlot,
    );
    if (time != null) {
      setState(() => _timeSlots.add(time));
    }
  }

  // ── step navigation ──

  void _onStepContinue() {
    if (_currentStep == 0 && _selectedTeamIds.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select at least 2 teams')));
      return;
    }
    if (_currentStep == 3) {
      // Moving to preview — generate it
      _generatePreview();
    }
    if (_currentStep < 4) {
      setState(() => _currentStep++);
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final divisionsAsync = ref.watch(divisionsStreamProvider);
    final teamsAsync = ref.watch(teamsStreamProvider);
    final divisions = divisionsAsync.valueOrNull ?? [];
    final allTeams = teamsAsync.valueOrNull ?? [];

    // Filter teams by selected division
    final filteredTeams = _divisionId == null
        ? allTeams
        : allTeams.where((t) => t.divisionId == _divisionId).toList();

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Generate Schedule'),
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: _currentStep == 4 ? null : _onStepContinue,
        onStepCancel: _onStepCancel,
        controlsBuilder: (context, details) {
          if (_currentStep == 4) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: details.onStepContinue,
                  child: Text(_currentStep == 3 ? 'Preview' : 'Next'),
                ),
                if (_currentStep > 0)
                  TextButton(
                    onPressed: details.onStepCancel,
                    child: const Text('Back'),
                  ),
              ],
            ),
          );
        },
        steps: [
          // ── Step 1: Division & Teams ──
          Step(
            title: const Text('Division & Teams'),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String?>(
                  initialValue: _divisionId,
                  decoration: const InputDecoration(labelText: 'Division'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All Divisions'),
                    ),
                    ...divisions.map(
                      (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
                    ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _divisionId = v;
                      // Auto-select all teams in division
                      final divTeams = v == null
                          ? allTeams
                          : allTeams.where((t) => t.divisionId == v).toList();
                      _selectedTeamIds = divTeams.map((t) => t.id).toSet();
                    });
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  '${_selectedTeamIds.length} team${_selectedTeamIds.length == 1 ? '' : 's'} selected',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: filteredTeams.map((t) {
                    final selected = _selectedTeamIds.contains(t.id);
                    return FilterChip(
                      label: Text(t.name),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedTeamIds.add(t.id);
                          } else {
                            _selectedTeamIds.remove(t.id);
                          }
                        });
                      },
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      showCheckmark: false,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // ── Step 2: Format ──
          Step(
            title: const Text('Format'),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _formatRadio('single', 'Single Round-Robin (1x)', 1),
                _formatRadio('double', 'Double Round-Robin (2x)', 2),
                _formatRadio('triple', 'Triple Round-Robin (3x)', 3),
                _formatRadio('custom', 'Custom', null),
                if (_formatLabel == 'custom')
                  Padding(
                    padding: const EdgeInsets.only(left: 48, top: 4),
                    child: SizedBox(
                      width: 120,
                      child: TextFormField(
                        controller: _customRoundsController,
                        decoration: const InputDecoration(
                          labelText: 'Rounds',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final n = int.tryParse(v);
                          if (n != null && n >= 1 && n <= 6) {
                            setState(() => _rounds = n);
                          }
                        },
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.sports_basketball,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_gameCount games will be generated',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Step 3: Dates & Times ──
          Step(
            title: const Text('Dates & Times'),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.indexed,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Date range
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start Date'),
                  subtitle: Text(DateFormat('MMM d, yyyy').format(_startDate)),
                  trailing: TextButton(
                    onPressed: _pickStartDate,
                    child: const Text('Change'),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('End Date'),
                  subtitle: Text(DateFormat('MMM d, yyyy').format(_endDate)),
                  trailing: TextButton(
                    onPressed: _pickEndDate,
                    child: const Text('Change'),
                  ),
                ),
                const Divider(),

                // Game days
                const Text(
                  'Game Days',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    _dayChip('Mon', 1),
                    _dayChip('Tue', 2),
                    _dayChip('Wed', 3),
                    _dayChip('Thu', 4),
                    _dayChip('Fri', 5),
                    _dayChip('Sat', 6),
                    _dayChip('Sun', 7),
                  ],
                ),
                const SizedBox(height: 16),

                // Time slots
                const Text(
                  'Time Slots',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ..._timeSlots.asMap().entries.map((e) {
                      return Chip(
                        label: Text(e.value.format(context)),
                        onDeleted: _timeSlots.length > 1
                            ? () {
                                setState(() => _timeSlots.removeAt(e.key));
                              }
                            : null,
                      );
                    }),
                    ActionChip(
                      label: const Text('+ Add'),
                      onPressed: _addTimeSlot,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Slot summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _availableSlots >= _gameCount
                        ? AppColors.primaryLight
                        : AppColors.urgent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _availableSlots >= _gameCount
                            ? Icons.check_circle
                            : Icons.warning,
                        color: _availableSlots >= _gameCount
                            ? AppColors.success
                            : AppColors.urgent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$_gameCount games → $_availableSlots available slots',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _availableSlots >= _gameCount
                                ? AppColors.success
                                : AppColors.urgent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Step 4: Venue ──
          Step(
            title: const Text('Venue'),
            isActive: _currentStep >= 3,
            state: _currentStep > 3 ? StepState.complete : StepState.indexed,
            content: TextFormField(
              controller: _venueController,
              decoration: const InputDecoration(
                labelText: 'Default Venue',
                hintText: 'e.g. National Indoor Sports Centre',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
          ),

          // ── Step 5: Preview & Create ──
          Step(
            title: const Text('Preview & Create'),
            isActive: _currentStep >= 4,
            state: StepState.indexed,
            content: _buildPreview(),
          ),
        ],
      ),
    );
  }

  // ── helper widgets ──

  Widget _formatRadio(String label, String title, int? rounds) {
    final selected = _formatLabel == label;
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? AppColors.primary : AppColors.textMuted,
      ),
      title: Text(title),
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: () {
        setState(() {
          _formatLabel = label;
          if (rounds != null) {
            _rounds = rounds;
            _customRoundsController.text = rounds.toString();
          }
        });
      },
    );
  }

  Widget _dayChip(String label, int weekday) {
    final selected = _gameDays.contains(weekday);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (v) {
        setState(() {
          if (v) {
            _gameDays.add(weekday);
          } else {
            _gameDays.remove(weekday);
          }
        });
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textPrimary,
        fontSize: 12,
      ),
      showCheckmark: false,
    );
  }

  Widget _buildPreview() {
    if (_preview.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No games generated. Go back and check your settings.',
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    }

    // Group by week
    final grouped = <String, List<_ScheduledGame>>{};
    final weekFmt = DateFormat('MMM d');
    for (final g in _preview) {
      // Get Monday of the week
      final monday = g.dateTime.subtract(
        Duration(days: g.dateTime.weekday - 1),
      );
      final key = 'Week of ${weekFmt.format(monday)}';
      grouped.putIfAbsent(key, () => []).add(g);
    }

    final dateFmt = DateFormat('EEE, MMM d');
    final timeFmt = DateFormat('h:mm a');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_preview.length} games generated',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          'Scroll to review, then tap Create to save all games.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Grouped list
        ...grouped.entries.map((week) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                color: AppColors.surface,
                child: Text(
                  week.key,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              ...week.value.map((g) {
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    '${g.homeName} vs ${g.awayName}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    '${dateFmt.format(g.dateTime)} · ${timeFmt.format(g.dateTime)} · ${g.venue}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          );
        }),

        const SizedBox(height: 16),

        // Create button
        if (_isCreating) ...[
          LinearProgressIndicator(value: _createProgress),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${(_createProgress * _preview.length).round()} / ${_preview.length}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ] else ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _createSchedule,
              icon: const Icon(Icons.check),
              label: Text('Create ${_preview.length} Games'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => setState(() => _currentStep = 0),
              child: const Text('Start Over'),
            ),
          ),
        ],
      ],
    );
  }
}
