# Storage authorization migration gate

The scoped Storage rules are a deployment candidate, not a declaration that live objects have been migrated.

Before any Storage rules deployment:

1. Run `scripts/audit_storage_migration.js` in explicit read-only mode with the exact project and bucket confirmations. Preserve only its aggregate JSON; do not save object names or download tokens.
2. Stop if it reports any legacy, unclassified, or URL-referenced objects. Attribute each object to an association and source record offline; quarantine anything that cannot be attributed.
3. Copy approved objects into `associations/{associationId}/...`, attach the required immutable metadata, replace Firestore download URLs with authenticated SDK object paths, and verify public/internal behavior for every role.
4. Revoke old download tokens and deny the legacy roots. Storage Rules cannot invalidate an already-issued token URL by themselves.
5. Preserve a count/hash migration manifest and rollback map. Re-run the read-only audit and require every blocker count to be zero.
6. Run `node scripts/run_security_emulators.js`, the repository safety preflight, Flutter tests/analyze, and the production web build before requesting deployment approval.

Invite Functions also require the immutable-version `INVITE_TOKEN_HMAC_KEY_V1` secret of at least 32 bytes. Future rotation must add a new versioned secret while preserving V1 for exact-operation retries. Creating/binding that live secret and deploying Functions or rules are separate, explicitly approved operations.
