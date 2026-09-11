import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/time/league_time.dart';
import '../../core/utils/error_mapper.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/event_model.dart';
import '../../models/team_model.dart';
import '../../providers/division_providers.dart';
import '../../providers/league_workflow_providers.dart';
import '../../providers/season_providers.dart';
import '../../providers/stats_providers.dart';
import '../../providers/team_providers.dart';

class AddGameScreen extends ConsumerStatefulWidget {
  const AddGameScreen({super.key});

  @override
  ConsumerState<AddGameScreen> createState() => _AddGameScreenState();
}

class _AddGameScreenState extends ConsumerState<AddGameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _locationController = TextEditingController();

  DateTime _date = LeagueTime.jamaicaDate(
    DateTime.now(),
  ).add(AppDefaults.addGameDateOffset);
  TimeOfDay _time = AppDefaults.defaultGameTime;
  String? _divisionId;
  String? _homeTeamId;
  String? _awayTeamId;
  late final String _operationId;
  String? _readinessMessage;
  bool _readinessIsError = false;
  ManualGameScheduleRequest? _preparedRequest;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _operationId = ref.read(eventRepositoryProvider).newScheduleOperationId();
  }

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = LeagueTime.jamaicaDate(DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today,
      lastDate: today.add(AppDefaults.datePickerMaxFuture),
    );
    if (date != null) {
      setState(() {
        _date = date;
        _readinessMessage = null;
        _preparedRequest = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: _time);
    if (time != null) {
      setState(() {
        _time = time;
        _readinessMessage = null;
        _preparedRequest = null;
      });
    }
  }

  void _reviewReadiness({
    required String? seasonId,
    required Set<String> activeDivisionIds,
    required Set<String> eligibleTeamIds,
    required List<EventModel>? existingEvents,
    required bool eventsLoading,
    required bool eventsFailed,
  }) {
    if (!_formKey.currentState!.validate()) return;
    try {
      if (seasonId == null || _divisionId == null) {
        throw StateError('An active season and active division are required.');
      }
      if (!activeDivisionIds.contains(_divisionId)) {
        throw StateError('Choose a division that is currently active.');
      }
      if (!eligibleTeamIds.contains(_homeTeamId) ||
          !eligibleTeamIds.contains(_awayTeamId)) {
        throw StateError(
          'Both teams must belong to the active season and selected division.',
        );
      }
      if (eventsLoading || eventsFailed || existingEvents == null) {
        throw StateError(
          'Existing games must load before duplicate and team conflicts can be checked.',
        );
      }
      final startTime = LeagueTime.jamaicaWallClockToUtc(
        date: _date,
        hour: _time.hour,
        minute: _time.minute,
      );
      final request = ManualGameScheduleRequest(
        operationId: _operationId,
        seasonId: seasonId,
        divisionId: _divisionId!,
        homeTeamId: _homeTeamId!,
        awayTeamId: _awayTeamId!,
        startTimeUtc: startTime,
        endTimeUtc: startTime.add(AppDefaults.defaultGameDuration),
        location: _locationController.text,
      );
      final conflicts = findManualScheduleConflicts(
        existingEvents: existingEvents,
        homeTeamId: request.homeTeamId,
        awayTeamId: request.awayTeamId,
        startTimeUtc: request.startTimeUtc,
        endTimeUtc: request.endTimeUtc,
      );
      if (conflicts.isNotEmpty) {
        final duplicate = conflicts.any(
          (conflict) => conflict.kind == ManualScheduleConflictKind.duplicate,
        );
        throw StateError(
          duplicate
              ? 'A duplicate game with these teams already exists at this Jamaica start time.'
              : 'A selected team already has an overlapping game: ${conflicts.first.eventTitle}.',
        );
      }
      setState(() {
        _readinessIsError = false;
        _readinessMessage =
            'Local checks passed. The server will repeat every scope and conflict check before saving.';
        _preparedRequest = request;
      });
    } catch (error) {
      setState(() {
        _readinessIsError = true;
        _preparedRequest = null;
        _readinessMessage = error is StateError
            ? error.message
            : 'The schedule details are not valid: $error';
      });
    }
  }

  Future<void> _save() async {
    final request = _preparedRequest;
    if (request == null || _saving) return;
    setState(() => _saving = true);
    try {
      final receipt = await ref
          .read(eventRepositoryProvider)
          .scheduleGame(request);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Game scheduled. Version ${receipt.scheduleVersion}.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _readinessIsError = true;
        _readinessMessage = ErrorMapper.map(error);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync = ref.watch(teamsStreamProvider);
    final seasonAsync = ref.watch(activeSeasonIdProvider);
    final seasonId = seasonAsync.valueOrNull;
    final workflow = ref.watch(leagueWorkflowCapabilityProvider).valueOrNull;
    final serverReady =
        workflow?.schedulingEnabled == true &&
        workflow?.activeSeasonId == seasonId;
    final canSave = serverReady && _preparedRequest != null && !_saving;
    final divisions = ref.watch(activeDivisionsProvider);
    final teams = seasonId == null || _divisionId == null
        ? const <TeamModel>[]
        : teamsEligibleForSchedule(
            teams: teamsAsync.valueOrNull ?? const [],
            seasonId: seasonId,
            divisionId: _divisionId!,
          );
    final activeDivisionIds = divisions.map((division) => division.id).toSet();
    final eligibleTeamIds = teams.map((team) => team.id).toSet();
    final dayStart = LeagueTime.startOfJamaicaDayUtc(
      _date,
    ).subtract(AppDefaults.defaultGameDuration);
    final dayEnd = LeagueTime.endExclusiveOfJamaicaDayUtc(
      _date,
    ).add(AppDefaults.defaultGameDuration);
    final existingEventsAsync = _divisionId == null
        ? const AsyncValue<List<EventModel>>.data([])
        : ref.watch(
            eventsStreamProvider((
              from: dayStart,
              to: dayEnd,
              divisionId: _divisionId,
            )),
          );

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Schedule Game'),
        actions: [
          Tooltip(
            message: serverReady
                ? 'Run local checks before saving.'
                : 'Saving requires the verified server scheduling workflow.',
            child: TextButton(
              onPressed: canSave ? _save : null,
              child: Text(
                _saving
                    ? 'Saving…'
                    : serverReady
                    ? 'Save game'
                    : 'Save unavailable',
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.paddingMd),
          children: [
            AppStateMessage(
              title: serverReady
                  ? 'Server scheduling is ready'
                  : 'Scheduling save is not available yet',
              message: serverReady
                  ? 'Review the game locally, then save it through the protected league scheduler.'
                  : 'You can prepare and check a game, but the app will not write it until the server capability confirms the callable and deny rules are active.',
              tone: AppStateTone.warning,
              compact: true,
            ),
            const SizedBox(height: 16),
            if (seasonAsync.isLoading)
              const AppLoadingState(
                label: 'Loading active season',
                compact: true,
              )
            else if (seasonId == null)
              const AppStateMessage(
                title: 'No active season',
                message: 'Activate a season before preparing a game.',
                tone: AppStateTone.error,
                compact: true,
              ),
            if (seasonId == null) const SizedBox(height: 16),
            // Date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Date'),
              subtitle: Text(
                '${DateFormat('EEEE, MMM d, yyyy').format(_date)} (Jamaica)',
              ),
              trailing: TextButton(
                onPressed: _pickDate,
                child: const Text('Change'),
              ),
            ),
            const Divider(),

            // Time
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: const Text('Time'),
              subtitle: Text('${_time.format(context)} Jamaica time'),
              trailing: TextButton(
                onPressed: _pickTime,
                child: const Text('Change'),
              ),
            ),
            const Divider(),
            const SizedBox(height: 16),

            // Location
            TextFormField(
              controller: _locationController,
              onChanged: (_) => setState(() {
                _readinessMessage = null;
                _preparedRequest = null;
              }),
              decoration: const InputDecoration(
                labelText: 'Location',
                hintText: 'e.g. National Arena',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 16),

            // Division
            DropdownButtonFormField<String>(
              initialValue: activeDivisionIds.contains(_divisionId)
                  ? _divisionId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Division',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: divisions
                  .map(
                    (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
                  )
                  .toList(),
              onChanged: seasonId == null
                  ? null
                  : (value) => setState(() {
                      _divisionId = value;
                      _homeTeamId = null;
                      _awayTeamId = null;
                      _readinessMessage = null;
                      _preparedRequest = null;
                    }),
              validator: (value) =>
                  value == null ? 'Choose an active division' : null,
            ),
            const SizedBox(height: 16),

            // Home team
            DropdownButtonFormField<String?>(
              initialValue: eligibleTeamIds.contains(_homeTeamId)
                  ? _homeTeamId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Home Team',
                prefixIcon: Icon(Icons.home_outlined),
              ),
              items: teams
                  .map(
                    (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                _homeTeamId = value;
                _readinessMessage = null;
                _preparedRequest = null;
              }),
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Away team
            DropdownButtonFormField<String?>(
              initialValue: eligibleTeamIds.contains(_awayTeamId)
                  ? _awayTeamId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Away Team',
                prefixIcon: Icon(Icons.flight_outlined),
              ),
              items: teams
                  .map(
                    (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                _awayTeamId = value;
                _readinessMessage = null;
                _preparedRequest = null;
              }),
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: seasonId == null || _divisionId == null
                  ? null
                  : () => _reviewReadiness(
                      seasonId: seasonId,
                      activeDivisionIds: activeDivisionIds,
                      eligibleTeamIds: eligibleTeamIds,
                      existingEvents: existingEventsAsync.valueOrNull,
                      eventsLoading: existingEventsAsync.isLoading,
                      eventsFailed: existingEventsAsync.hasError,
                    ),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Check schedule'),
            ),
            if (_readinessMessage != null) ...[
              const SizedBox(height: 12),
              AppStateMessage(
                title: _readinessIsError
                    ? 'Schedule needs attention'
                    : 'Schedule locally valid',
                message: _readinessMessage!,
                tone: _readinessIsError
                    ? AppStateTone.error
                    : AppStateTone.info,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
