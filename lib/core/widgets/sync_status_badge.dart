import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// A small badge that shows whether data has been synced to the server
/// or is only saved locally (pending writes).
///
/// Pass the [SnapshotMetadata] from any Firestore snapshot to determine state.
class SyncStatusBadge extends StatelessWidget {
  final SnapshotMetadata metadata;

  const SyncStatusBadge({super.key, required this.metadata});

  @override
  Widget build(BuildContext context) {
    final pending = metadata.hasPendingWrites;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          pending ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
          size: 14,
          color: pending ? AppColors.ack : AppColors.success,
        ),
        const SizedBox(width: 4),
        Text(
          pending ? 'Saved locally' : 'Synced',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: pending ? AppColors.ack : AppColors.success,
          ),
        ),
      ],
    );
  }
}
