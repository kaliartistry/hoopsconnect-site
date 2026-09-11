import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_constants.dart';
import '../../core/time/league_time.dart';
import '../../models/event_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';
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
  bool _isSubmitting = false;

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
    if (date != null) setState(() => _date = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: _time);
    if (time != null) setState(() => _time = time);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_homeTeamId == null || _awayTeamId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select both teams')));
      return;
    }
    if (_homeTeamId == _awayTeamId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Home and away teams must be different')),
      );
      return;
    }

    final user = ref.read(currentUserProvider).value;
    final assocId = ref.read(currentAssociationIdProvider);
    if (user == null || assocId == null) return;

    setState(() => _isSubmitting = true);

    try {
      final startTime = LeagueTime.jamaicaWallClockToUtc(
        date: _date,
        hour: _time.hour,
        minute: _time.minute,
      );

      // Get team names for the title
      final teams = ref.read(teamsStreamProvider).valueOrNull ?? [];
      final homeTeam = teams.firstWhere((t) => t.id == _homeTeamId);
      final awayTeam = teams.firstWhere((t) => t.id == _awayTeamId);

      final event = EventModel(
        id: '', // auto-generate
        title: '${homeTeam.name} vs ${awayTeam.name}',
        type: AppDefaults.eventTypeGame,
        startTime: startTime,
        endTime: startTime.add(AppDefaults.defaultGameDuration),
        location: _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        divisionId: _divisionId,
        teamIds: [_homeTeamId!, _awayTeamId!],
        createdBy: user.id,
        statsStatus: StatsStatus.pending,
      );

      await ref.read(eventRepositoryProvider).createEvent(assocId, event);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Game scheduled successfully')),
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
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync = ref.watch(teamsStreamProvider);

    final divisions = ref.watch(activeDivisionsProvider);
    final teams = teamsAsync.valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Schedule Game'),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.paddingMd),
          children: [
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
              decoration: const InputDecoration(
                labelText: 'Location',
                hintText: 'e.g. National Arena',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 16),

            // Division
            DropdownButtonFormField<String?>(
              initialValue: _divisionId,
              decoration: const InputDecoration(
                labelText: 'Division',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('No division')),
                ...divisions.map(
                  (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
                ),
              ],
              onChanged: (v) => setState(() => _divisionId = v),
            ),
            const SizedBox(height: 16),

            // Home team
            DropdownButtonFormField<String?>(
              initialValue: _homeTeamId,
              decoration: const InputDecoration(
                labelText: 'Home Team',
                prefixIcon: Icon(Icons.home_outlined),
              ),
              items: teams
                  .map(
                    (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _homeTeamId = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Away team
            DropdownButtonFormField<String?>(
              initialValue: _awayTeamId,
              decoration: const InputDecoration(
                labelText: 'Away Team',
                prefixIcon: Icon(Icons.flight_outlined),
              ),
              items: teams
                  .map(
                    (t) => DropdownMenuItem(value: t.id, child: Text(t.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _awayTeamId = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
          ],
        ),
      ),
    );
  }
}
