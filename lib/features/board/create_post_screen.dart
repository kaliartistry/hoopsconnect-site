import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/time/league_time.dart';
import '../../core/widgets/app_form_controls.dart';
import '../../core/widgets/app_state_message.dart';
import '../../models/post_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';
import '../../providers/post_providers.dart';
import '../../core/utils/error_mapper.dart';

enum _AckDeadlinePolicy { deadline, noDeadline }

class CreatePostScreen extends ConsumerStatefulWidget {
  final bool initialPinned;
  final bool initialUrgent;
  final bool initialRequiresAck;

  const CreatePostScreen({
    super.key,
    this.initialPinned = false,
    this.initialUrgent = false,
    this.initialRequiresAck = false,
  });

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  PostType _type = PostType.announcement;
  String? _divisionFilter;
  late bool _pinned = widget.initialPinned;
  late bool _urgent = widget.initialUrgent;
  late bool _requiresAck = widget.initialRequiresAck;
  DateTime? _ackDeadline;
  _AckDeadlinePolicy _ackDeadlinePolicy = _AckDeadlinePolicy.deadline;
  PostVisibility _visibility = PostVisibility.public;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    if (_requiresAck) _ackDeadline = _defaultAckDeadline();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_requiresAck &&
        _ackDeadlinePolicy == _AckDeadlinePolicy.deadline &&
        (_ackDeadline == null ||
            !_ackDeadline!.isAfter(DateTime.now().toUtc()))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a future acknowledgment deadline.'),
        ),
      );
      return;
    }

    final user = ref.read(currentUserProvider).value;
    final assocId = ref.read(currentAssociationIdProvider);
    if (user == null || assocId == null) return;

    setState(() => _isSubmitting = true);

    try {
      final post = PostModel(
        id: '', // Firestore will auto-generate
        authorId: user.id,
        authorName: user.displayName,
        authorRole: user.role.name,
        teamId: user.teamId,
        teamName: null,
        type: _type,
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        divisionFilter: _divisionFilter,
        pinned: _pinned,
        urgent: _urgent,
        visibility: _visibility,
        createdAt: DateTime.now().toUtc(),
        requiresAck: _requiresAck,
        ackDeadline:
            _requiresAck && _ackDeadlinePolicy == _AckDeadlinePolicy.deadline
            ? _ackDeadline
            : null,
        ackTargetScope: _requiresAck ? AppDefaults.ackScopeAll : null,
      );

      await ref.read(postRepositoryProvider).createPost(assocId, post);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _requiresAck
                  ? 'Acknowledgment request published. Notification delivery is tracked separately.'
                  : 'Board post published.',
            ),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ErrorMapper.map(e))));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickAckDeadline() async {
    final currentCivil = LeagueTime.jamaicaCivilFromInstant(
      _ackDeadline ?? _defaultAckDeadline(),
    );
    final todayCivil = LeagueTime.nowJamaicaCivil();
    final date = await showDatePicker(
      context: context,
      initialDate: currentCivil,
      firstDate: DateTime(todayCivil.year, todayCivil.month, todayCivil.day),
      lastDate: DateTime(
        todayCivil.year,
        todayCivil.month,
        todayCivil.day + AppDefaults.ackPickerMaxFuture.inDays,
      ),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: currentCivil.hour,
        minute: currentCivil.minute,
      ),
    );

    if (time == null) return;

    setState(() {
      _ackDeadline = LeagueTime.jamaicaWallClockToUtc(
        date: date,
        hour: time.hour,
        minute: time.minute,
      );
    });
  }

  DateTime _defaultAckDeadline() {
    final nowCivil = LeagueTime.nowJamaicaCivil();
    final date = DateTime.utc(
      nowCivil.year,
      nowCivil.month,
      nowCivil.day + AppDefaults.ackDeadlineDefault.inDays,
    );
    return LeagueTime.jamaicaWallClockToUtc(
      date: date,
      hour: AppDefaults.defaultAckDeadlineTime.hour,
      minute: AppDefaults.defaultAckDeadlineTime.minute,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;
    final canPinUrgentAck = user?.canPinUrgentAck ?? false;
    final divisions = ref.watch(divisionsStreamProvider).valueOrNull ?? [];

    // Build division options dynamically
    final divisionOptions = <String?>[null];
    final divisionLabels = <String>['All Divisions'];
    for (final div in divisions) {
      divisionOptions.add(div.id);
      divisionLabels.add(div.name);
    }

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Create board post'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _isSubmitting
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                    ),
                    child: const Text(
                      'Publish',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
          ),
        ],
      ),
      body: AppFormFocusGroup(
        onCancel: _isSubmitting ? null : () => context.pop(),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSizes.paddingMd),
            children: [
              // Post type
              DropdownButtonFormField<PostType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Post Type'),
                items: PostType.values.map((t) {
                  final labels = {
                    PostType.announcement: 'Announcement',
                    PostType.refRequest: 'Ref Request',
                    PostType.gymAvailable: 'Gym Available',
                    PostType.general: 'General',
                  };
                  return DropdownMenuItem(value: t, child: Text(labels[t]!));
                }).toList(),
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 16),

              // Division filter
              DropdownButtonFormField<String?>(
                initialValue: _divisionFilter,
                decoration: const InputDecoration(labelText: 'Division'),
                items: List.generate(divisionOptions.length, (i) {
                  return DropdownMenuItem(
                    value: divisionOptions[i],
                    child: Text(divisionLabels[i]),
                  );
                }),
                onChanged: (v) => setState(() => _divisionFilter = v),
              ),
              const SizedBox(height: 16),

              // Title
              TextFormField(
                controller: _titleController,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'Enter post title...',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Title is required' : null,
              ),
              const SizedBox(height: 16),

              // Body
              TextFormField(
                controller: _bodyController,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Body',
                  hintText: 'Enter post details...',
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Body is required' : null,
              ),
              const SizedBox(height: 24),

              // Admin-only options
              if (canPinUrgentAck) ...[
                const Text(
                  'Admin Options',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Pin to top'),
                  subtitle: const Text(
                    'Pinned posts stay at the top of the feed',
                  ),
                  value: _pinned,
                  onChanged: (v) => setState(() => _pinned = v),
                  activeThumbColor: AppColors.primary,
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Mark as urgent'),
                  subtitle: const Text('Highlights post with red border'),
                  value: _urgent,
                  onChanged: (v) => setState(() => _urgent = v),
                  activeThumbColor: AppColors.urgent,
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Internal only'),
                  subtitle: const Text(
                    'Hide from fans — admin, reps, and media only',
                  ),
                  value: _visibility == PostVisibility.internal,
                  onChanged: (v) => setState(
                    () => _visibility = v
                        ? PostVisibility.internal
                        : PostVisibility.public,
                  ),
                  activeThumbColor: AppColors.info,
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Require acknowledgment'),
                  subtitle: const Text(
                    'Assigned team representatives must confirm they reviewed it',
                  ),
                  value: _requiresAck,
                  onChanged: (v) => setState(() {
                    _requiresAck = v;
                    if (v &&
                        _ackDeadlinePolicy == _AckDeadlinePolicy.deadline &&
                        _ackDeadline == null) {
                      _ackDeadline = _defaultAckDeadline();
                    }
                  }),
                  activeThumbColor: AppColors.ack,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_requiresAck) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Acknowledgment timing',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'A deadline is recommended so representatives know when action is due. Publishing without one must be a deliberate choice.',
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<_AckDeadlinePolicy>(
                    segments: const [
                      ButtonSegment(
                        value: _AckDeadlinePolicy.deadline,
                        icon: Icon(Icons.event_available_outlined),
                        label: Text('Deadline'),
                      ),
                      ButtonSegment(
                        value: _AckDeadlinePolicy.noDeadline,
                        icon: Icon(Icons.event_busy_outlined),
                        label: Text('No deadline'),
                      ),
                    ],
                    selected: {_ackDeadlinePolicy},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _ackDeadlinePolicy = selection.single;
                        if (_ackDeadlinePolicy == _AckDeadlinePolicy.deadline &&
                            _ackDeadline == null) {
                          _ackDeadline = _defaultAckDeadline();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  if (_ackDeadlinePolicy == _AckDeadlinePolicy.deadline)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Acknowledgment deadline'),
                      subtitle: Text(
                        _ackDeadline != null
                            ? '${LeagueTime.formatJamaicaDate(_ackDeadline!, pattern: 'MMM d, yyyy')} at ${LeagueTime.formatJamaicaTime(_ackDeadline!)}'
                            : 'Choose a future deadline in Jamaica time',
                        style: TextStyle(
                          color: _ackDeadline != null
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: _pickAckDeadline,
                        child: Text(_ackDeadline != null ? 'Change' : 'Set'),
                      ),
                    )
                  else
                    const AppStateMessage(
                      title: 'No acknowledgment deadline',
                      message:
                          'The request will stay open until every assigned representative responds or an administrator changes it.',
                      tone: AppStateTone.warning,
                      compact: true,
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
