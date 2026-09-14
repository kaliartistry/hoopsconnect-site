import 'package:flutter/material.dart';

import '../../../core/utils/error_mapper.dart';
import '../../../core/widgets/app_form_controls.dart';
import '../../../core/widgets/app_state_message.dart';

/// Runs one idempotent acknowledgment with explicit pending, confirmed, and
/// retryable failure states. The surrounding post stream remains the source of
/// truth for whether the user is acknowledged.
class AcknowledgmentAction extends StatefulWidget {
  const AcknowledgmentAction({
    super.key,
    required this.onAcknowledge,
    this.compact = false,
  });

  final Future<void> Function() onAcknowledge;
  final bool compact;

  @override
  State<AcknowledgmentAction> createState() => _AcknowledgmentActionState();
}

class _AcknowledgmentActionState extends State<AcknowledgmentAction> {
  bool _isSubmitting = false;
  bool _recorded = false;
  String? _error;

  Future<void> _submit() async {
    if (_isSubmitting || _recorded) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.onAcknowledge();
      if (!mounted) return;
      setState(() => _recorded = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ErrorMapper.map(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_recorded) {
      return const AppStateMessage(
        title: 'Acknowledgment recorded',
        message: 'This post will update when the confirmed record syncs.',
        tone: AppStateTone.success,
        compact: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          AppStateMessage(
            title: 'Acknowledgment not recorded',
            message: _error!,
            tone: AppStateTone.error,
            compact: true,
          ),
          const SizedBox(height: 8),
        ],
        AppAsyncActionButton(
          label: _error == null
              ? widget.compact
                    ? 'Acknowledge'
                    : 'Acknowledge This Post'
              : 'Retry acknowledgment',
          busyLabel: 'Recording acknowledgment',
          isBusy: _isSubmitting,
          icon: Icons.check_circle_outline,
          onPressed: _submit,
        ),
      ],
    );
  }
}
