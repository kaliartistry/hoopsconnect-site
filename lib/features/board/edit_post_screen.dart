import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../models/post_model.dart';
import '../../providers/auth_providers.dart';
import '../../providers/post_providers.dart';

class EditPostScreen extends ConsumerStatefulWidget {
  final String postId;
  const EditPostScreen({super.key, required this.postId});

  @override
  ConsumerState<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends ConsumerState<EditPostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _pinned = false;
  bool _urgent = false;
  bool _isSubmitting = false;
  bool _initialized = false;

  void _initFromPost(PostModel post) {
    if (_initialized) return;
    _titleController.text = post.title;
    _bodyController.text = post.body;
    _pinned = post.pinned;
    _urgent = post.urgent;
    _initialized = true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final assocId = ref.read(currentAssociationIdProvider);
    if (assocId == null) return;

    setState(() => _isSubmitting = true);

    try {
      await ref.read(postRepositoryProvider).updatePost(
        assocId,
        widget.postId,
        {
          'title': _titleController.text.trim(),
          'body': _bodyController.text.trim(),
          'pinned': _pinned,
          'urgent': _urgent,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post updated')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final postAsync = ref.watch(postDetailProvider(widget.postId));
    final user = ref.watch(currentUserProvider).value;
    final canPinUrgentAck = user?.canPinUrgentAck ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Edit Post'),
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
      body: postAsync.when(
        data: (post) {
          if (post == null) {
            return const Center(child: Text('Post not found'));
          }

          _initFromPost(post);

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(AppSizes.paddingMd),
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'Enter post title...',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Title is required'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bodyController,
                  decoration: const InputDecoration(
                    labelText: 'Body',
                    hintText: 'Enter post details...',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Body is required'
                      : null,
                ),
                if (canPinUrgentAck) ...[
                  const SizedBox(height: 24),
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
                    value: _pinned,
                    onChanged: (v) => setState(() => _pinned = v),
                    activeThumbColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('Mark as urgent'),
                    value: _urgent,
                    onChanged: (v) => setState(() => _urgent = v),
                    activeThumbColor: AppColors.urgent,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
