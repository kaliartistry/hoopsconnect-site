import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../models/post_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/division_providers.dart';
import '../../providers/post_providers.dart';
import '../../core/utils/error_mapper.dart';

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
  PostVisibility _visibility = PostVisibility.public;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

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
        createdAt: DateTime.now(),
        requiresAck: _requiresAck,
        ackDeadline: _ackDeadline,
        ackTargetScope: _requiresAck ? AppDefaults.ackScopeAll : null,
      );

      await ref.read(postRepositoryProvider).createPost(assocId, post);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post created successfully')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ErrorMapper.map(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickAckDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(AppDefaults.ackDeadlineDefault),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(AppDefaults.ackPickerMaxFuture),
    );
    if (date == null) return;

    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: AppDefaults.defaultAckDeadlineTime,
    );

    setState(() {
      _ackDeadline = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? AppDefaults.defaultAckDeadlineTime.hour,
        time?.minute ?? AppDefaults.defaultAckDeadlineTime.minute,
      );
    });
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
      divisionOptions.add(div.name);
      divisionLabels.add(div.name);
    }

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Create Post'),
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
                      'Post',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
                return DropdownMenuItem(
                  value: t,
                  child: Text(labels[t]!),
                );
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
                subtitle:
                    const Text('Pinned posts stay at the top of the feed'),
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
                onChanged: (v) => setState(() => _visibility =
                    v ? PostVisibility.internal : PostVisibility.public),
                activeThumbColor: AppColors.info,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Require acknowledgment'),
                subtitle: const Text('Team reps must acknowledge this post'),
                value: _requiresAck,
                onChanged: (v) => setState(() => _requiresAck = v),
                activeThumbColor: AppColors.ack,
                contentPadding: EdgeInsets.zero,
              ),
              if (_requiresAck) ...[
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Acknowledgment Deadline'),
                  subtitle: Text(
                    _ackDeadline != null
                        ? '${_ackDeadline!.month}/${_ackDeadline!.day}/${_ackDeadline!.year} at ${_ackDeadline!.hour}:${_ackDeadline!.minute.toString().padLeft(2, '0')}'
                        : 'No deadline set',
                    style: TextStyle(
                      color: _ackDeadline != null
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: _pickAckDeadline,
                    child: Text(_ackDeadline != null ? 'Change' : 'Set'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
