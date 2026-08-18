# Repository Guidelines

## `lib` And `go` Structure Rules

- All hand-written code files under `lib`, `go`, `bridge`, and `macos/Runner` must stay under 500 lines.
- If a file approaches the limit, split it by feature or responsibility before adding more logic.
- Generated files are excluded from this rule:
  `.dart_tool`, `build`, `bin`, `macos/Flutter/ephemeral`.
- Every hand-written code file under `lib`, `go`, `bridge`, and `macos/Runner` must include at least one meaningful comment.
- Prefer file-level comments that explain the file responsibility, plus short section comments where logic is non-obvious.

## Flutter Frontend Organization

- Organize Flutter code by type first, then by feature:
  `lib/app`, `lib/pages`, `lib/widgets`, `lib/services`, `lib/state`, `lib/utils`, `lib/theme`, `lib/bridge`, `lib/models`.
- Keep entry files thin. They should wire modules together, not hold page logic inline.
- Large widget trees should be moved into page/widget modules instead of one oversized `build()` method.
- Keep bootstrap and configuration flows visually distinct from the eventual storage browser so first-run behavior stays obvious.

### Hover-aware clickable rows (binding rule)

Any clickable row, tile, card, or sidebar item that needs a hover visual response **must be a dedicated `StatefulWidget`** that owns a `bool _hovered` field. The field is toggled by `MouseRegion(onEnter/onExit)` to `setState`, and drives background color (and only when intentional, text/icon color) via an `AnimatedContainer`. This is the only reliable way to get hover to rebuild the widget subtree.

**Never** build hover items as inline `MouseRegion` + `Container` inside an `extension on State` or a plain builder — the extension/builder has no mutable field to store `_hovered`, so the `onEnter`/`onExit` callbacks have nowhere to write, hover never rebuilds, and you get a dead or stuck hover state. This bug has re-occurred multiple times (settings sidebar rail, file list tiles).

#### Hover visual style (binding — read every time you touch hover UI)

Hover is a **subtle state change**, not a different component skin. This is a hard product rule: if the pointer slides across a list of cards/buttons and they look like different designs while hovered, the hover is wrong.

**Allowed on hover (only):**
- Background wash via `ListInteractionColors.fromTheme` (`hover` = neutral `mutedForeground @ ~0.08`)
- Optionally a slightly stronger wash when already **selected**

**Forbidden on hover (unless the item is selected/disabled as its permanent state):**
- Changing **icon color** (muted → primary, gray → red, etc.)
- Changing **border color** or **border width**
- Changing **font weight / text color**
- Swapping in a different fill system (`colorScheme.secondary` blue, pink destructive fill, etc.)
- Showing/hiding trailing chrome (checkmarks) that reflows layout

**Checklist before shipping any hover control:**
1. Idle vs hover screenshot should differ mainly by a light background, not by “new theme”.
2. Icon/border/text at idle == icon/border/text at hover (same Color/width/weight).
3. Prefer `ListInteractionColors.rowBackground(selected:, hovered:, pressed:)` — do **not** invent per-feature hover palettes.
4. Use a dedicated `StatefulWidget` + `_hovered` + `MouseRegion` + `GestureDetector(behavior: opaque)` + `AnimatedContainer`.
5. Layout must not jump (fixed border width; reserve checkmark width; no 1→1.5 border).
6. Title-bar / chrome buttons (including modal close): **no Material ink splash**; hover = neutral wash only; **do not** turn the X red/pink on hover.

**Bad examples (regressions — do not reintroduce):**
- Protocol cards: hover → primary border + `secondary` fill + primary icon (`StorageProtocolCard`, fixed 2026-07-11).
- Modal shell close: hover → pink fill + red X (`DesktopModalShell`, fixed 2026-07-11). Correct = fixed muted X + neutral wash only.

Canonical implementations to copy:
- `lib/theme/list_interaction_colors.dart` — shared hover/selected washes.
- `lib/pages/main_layout_page.dart` `_SidebarNavItem` — sidebar nav items.
- `lib/widgets/file_list_tile.dart` — file-manager rows (`dimmed` disables hover).
- `lib/widgets/transfer_task_widgets.dart` — transfer queue rows.
- `lib/pages/settings_page_layout.dart` `_SettingsGroupTile` — settings left rail entries.
- `lib/widgets/cloud_storage_account_dialog_steps.dart` `StorageProtocolCard` — selectable cards (neutral hover; primary chrome only when selected).
- `lib/widgets/desktop_modal_shell.dart` `_ModalShellCloseButton` — modal title-bar close (no splash; neutral hover only).

Settings card visual consistency: every `Settings*Section` should follow the same structure — 12px muted intro text at the top, then secondary-container blocks (`colorScheme.secondary`, radius 10, padding 14/12), with optional `_SectionHeader` (14px w700 title + 11.5px muted description) between functional groups. Do not use `textTheme.h4` inside settings cards; it belongs to page-level headers only. See `lib/widgets/settings_p2p_section.dart` for the canonical card layout.

Cursor: dense list rows use idle `SystemMouseCursors.basic` and `click` only while hovered (or a constant `click` cursor for always-interactive cards if it never sticks). Never leave a pointing hand stuck after unhover/unmount.

## Go Bridge Organization

- Split Go files by responsibility within a package, for example:
  `dispatch_config.go`, `config_store.go`, `config_paths.go`.
- Keep bridge exports grouped by feature instead of one large bridge file.
- Shared parsing, normalization, and transport helpers should live in dedicated helper files.
- Prefer a narrow C ABI plus JSON payloads for Flutter FFI when it avoids duplicating backend structs in Dart.

## Build Outputs

- Do not write compiled binaries or build artifacts to the repository root.
- Route local Go and Flutter build outputs to `bin/`, `build/`, or tool-managed build directories.
- For ad-hoc Go smoke validation from the repository root, do not run bare `go build .`.
- Use `go build -o bin/...` for manual bridge smoke tests, and remove temporary one-off outputs if they were created.  
  On Windows this means `go build -buildmode=c-shared -o bin/bridge/remote_storage_bridge.dll ./bridge` with `CGO_ENABLED=1` and a MinGW toolchain (e.g. MSYS2 UCRT64) available via `BRIDGE_CC`/`BRIDGE_CXX`.
- The macOS app must be started through the Go binding workflow, not plain Flutter alone.
- `make run` is the canonical local launch command. It first runs `make bridge`, which builds `./bridge` as `bin/bridge/libremote_storage_bridge.dylib`, then launches Flutter with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter run -d macos`.
- When validating integrated app startup, prefer `make run` over a bare `flutter run -d macos` so the bridge binary and Xcode path are both set correctly.
- The Windows app must also be started through the Go binding workflow.  
  `scripts/run_windows.ps1` is the canonical Windows launch command. It resolves a Flutter binary and an MSYS2 MinGW toolchain, builds `./bridge` as `bin/bridge/remote_storage_bridge.dll`, then launches Flutter with `flutter run -d windows`.  
  `.\run_windows.ps1 -Build` builds the release bundle instead of running.  
  When validating integrated app startup on Windows, prefer `run_windows.ps1` over a bare `flutter run -d windows` so the bridge DLL and CGO toolchain are both set correctly.

## Adding a New Storage Backend

When the user asks to add a new storage type (e.g. FTP, SFTP, or any new remote storage provider), follow the step-by-step guide in [`docs/AddingStorageBackends.md`](docs/AddingStorageBackends.md). That document covers the full five-layer change set (Go config → Go backend → bridge → Dart model → Dart UI), with the exact files to modify and reference implementations to copy from.

## Git Workflow

- After completing the requested implementation and validation successfully, create a normal non-amended commit unless the user explicitly says not to commit.
- Do not include compiled binaries or other transient build artifacts in commits.
- Every time a new feature is added, update `README.md` in the same change set before committing.
- Maintain release note drafts in `CHANGELOG.md` under `## Unreleased` as work lands when the change is relevant to an upcoming release.

## Validation

- After each meaningful refactor batch, run the narrowest useful validation first.
- Before finishing, run `go test ./...` and `flutter analyze` unless the user explicitly asks for a different validation scope.
- Do not use screenshots as smoke-validation evidence.
- Do not run a local smoke test by default; after implementation, hand off app-level verification to the user unless they explicitly ask you to run it.


## Code Map (Cross-Session Knowledge)

> **Purpose:** This section captures the structure and responsibility of key features so new sessions do not have to re-explore the codebase. It must be kept up to date.
>
> **Explore rule (binding):** After any codebase exploration (including Explore-agent work), write the reusable findings into the relevant Code Map entry before ending the turn. Do not leave discoveries only in the conversation. This applies even when no implementation is made.
>
> **Maintenance rules (binding):**
>
> 1. **Feature work:** Every time a new feature is added or an existing feature's file set changes, update the relevant Code Map entry here in the same change set (before committing). List the files that participate in the feature, their responsibility, and the data flow between them.
> 2. **Exploration:** Any time the codebase is explored to answer a question, debug an issue, or understand a feature — even when no code change lands — record the discovered structure, file responsibilities, gotchas, and data flow into the relevant Code Map entry (or create a new one) before the turn ends. The goal is that the next session never has to re-read the same files to learn the same thing.
> 3. **Freshness:** Correct or remove entries that are no longer accurate. Do not leave this section stale — stale knowledge here is worse than no knowledge.

### Feature: Mount Operation Queues (挂载写回队列体系)

**Status (2026-08-18):** persistent inode metadata backs page/mount reads and metadata-enabled writes, and the unified `RemoteTask` projection is now the only remote-operation UI source. Mounts and profile-scoped page mutations share one journal-first namespace; callers without a durable `ProfileID` retain legacy execution compatibility only.

#### New persistent metadata core

- `go/mount/metadata/types.go` - durable contracts: `Inode`, `Dirent`, `Op`, `ListingState`, `ContentRef`, `Object/Page/Cursor`, `Namespace`, and the narrow provider `Backend` interface. `ContentRef` holds ordered SHA-256 chunk hashes, never a local path; a move freezes provider `MoveSource`/`MoveTarget` plus its target edge before the first side effect. `Namespace.CacheRoot` separates chunk data from the runtime metadata DB. Inode identity is local to each namespace; no symlinks/hardlinks.
- `go/mount/metadata/store.go` / `store_io.go` - bbolt schema v5 with `schema/inodes/dirents/journal/listing_state/content_refs/chunks/ready_ops/inode_ops/task_groups/task_members`; `schema.nextOpSeq` keeps journal sequences monotonic after history compaction. Root inode is fixed at 1; inodes are monotonically allocated and never reused. Every write is serialized; schema mismatch returns an error (reset/rebuild, no upgrade).
- `go/mount/metadata/service_read.go` - `MaterializeDirectory`, `ListPage`, `StatPath`, `StatInode`, `Resolve`, `Path`. Paging cursors are base64url `{v,inode,revision,lastNameKey}`; a changed directory revision returns `ErrStaleCursor` so the UI reloads rather than pretending snapshot consistency. Pending rename sources and tombstones suppress their stale remote keys. A renamed directory lists through its confirmed Remote edge until its move succeeds, retaining materialized child OIDs while its Desired name is already new.
- `go/mount/metadata/write.go` / `write_stage.go` - Desired-tree writes: `CreateDirectory`, `StageWrite` (fixed 4 MiB chunking, SHA-256, fsync plus atomic rename before bbolt ref commit), `Write`, `Rename`, `Delete`. A zero write generation is durably reserved before chunk staging so rapid path writes own distinct `ContentRef` keys. `write_stage.go` rolls back a new inode/ref when staging or journal append fails; startup recovery removes an `AwaitingJournal` ref that survived a crash without a journal owner. Root rename/delete is rejected. Rename changes exactly two dirent B+Trees plus one inode edge; descendant inodes and content files are untouched.
- `go/mount/metadata/service_write_path.go` - mount/page-facing path facade: `CreateDirectoryPath`, `WritePath`, `RenamePath`, and `DeletePath` resolve Desired paths before invoking inode APIs. The facade serializes its own path mutations and ties a staged generation to its matching write journal entry.
- `go/mount/metadata/chunk_store.go` / `chunk_protection.go` - pending data plane: chunks live at `<CacheDirectory>/metadata-chunks/<namespace>/chunks/<hash[:2]>/<hash>`; `chunks[hash]` has logical `nlink`, size, and last-access values. StageWrite writes/syncs chunks before bbolt, deduplicates equal blocks, and cumulatively publishes every prospective hash in atomic `protection.json` until refs commit, so concurrent cache cleanup cannot delete an earlier block in a multi-chunk write. Worker uploads splice a temporary full file; retirement/deletion decrements refs and removes zero-link blocks. Startup sweep removes uncommitted orphan chunks and interrupted splice files.
- `Op.ContentGeneration` binds write and local-only rename materialization to an exact `ContentRef`, so rapid successive writes retire their own generations rather than uploading the newest staged ref twice and leaving a stuck later op.
- The initial chunk root is persisted in `schema.chunkRoot`; changing the configured cache directory later does not strand pending data. Reopened services and RemoveNamespace use the persisted root until a future explicit migration.
- `go/mount/metadata/status.go` additionally counts `PendingContent`; status and the reset guard scan the journal so running ops remain protected after they leave `ready_ops`. Reset takes the Service operation barrier, rebuilds bbolt in place (rather than closing/swapping its handle), then sweeps the separated chunk root; forced reset waits for an in-flight worker before rebuilding.
- `go/mount/metadata/worker.go` / `worker_execute.go` / `worker_move.go` / `worker_reconcile.go` / `status.go` - scheduler/executor split for quiet-period journaling, retry backoff (15s→2m), pre-upload fingerprint checks, confirmation, conflict marking, namespace-qualified transfer snapshot IDs `metadata-op-<namespace>-<seq>`, and probe-based cancellation reconciliation. Verifying/cancel-requested/reconciling states are indexed and recovered on startup; a cancel only becomes terminal after provider absence or an explicit compensating move/delete is verified. A write executes against its immutable journal parent/name Remote edge, then a later rename moves it; move source/target and confirmation parent/name are frozen before the provider call, so a later Desired rename cannot redirect replay. Directory moves/deletes wait for earlier descendant work. `claimDue` also waits on the shared unsettled-state predicate for same-inode and prior parent work. `Drain` scans journal running entries absent from `ready_ops`; deletes purge confirmed subtrees. `remoteTarget` falls back to Desired only for never-synced deletes.
- `go/mount/metadata/chunk_recovery.go` - startup reconciliation removes chunk refs marked `AwaitingJournal` when no write/rename op owns them, deletes their new pending inode/dirent when safe, then sweeps orphan blocks and interrupted upload files. Raw low-level `StageWrite` refs are retained for callers that intentionally append their op separately.
- `go/mount/metadata/tasks.go` / `task_types.go` / `tasks_index.go` / `manager_tasks.go` - schema-v5 durable task projection uses stable `sync:<namespace>:<group>` IDs, adds sequence-qualified IDs for mixed lifecycle segments, folds pre-execution mkdir/rename chains, consecutive renames, and rapid same-inode writes, and retains raw journal events, dependency reasons, and all namespace-qualified physical snapshot IDs. `tasks_control.go` / `tasks_control_content.go` provide transactional cancel rollback, retry/trigger, `cancel_requested`/`reconciling` states, monotonic history compaction, and strict task-group lookup after compaction.
- `bridge/dispatch_remote_tasks.go` / `go/webapi/remote_tasks.go` - desktop and Web expose the same paged JSON task protocol. Metadata tasks join physical transfer monitor phases; profile/bucket/status filters, cursor pagination, freshness, and capability flags are applied before the response. Web ignores client profile widening and uses the authenticated active profile.
- `go/s3/transfer_monitor.go` / `go/sync/executor.go` - physical snapshots carry an owning profile identity so sync cards can use `RemoteTaskStore.tasksForProfile()` without parsing `sync-...` IDs. `lib/state/remote_task_store.dart` merges these snapshots with the explicit local adapter fed by `transfer_queue_remote_tasks.dart`; all visible task rows use the unified store. The old `TransferQueue` remains an execution/local compatibility producer, never a task display source.
- `go/mount/metadata/subtree.go` - `collectSubtreeInodes` walks `DesiredParentID` chains to find all descendants of a directory (visited marks nodes as examined; corrupt parent edges propagate errors instead of silently skipping). `purgeInodeRecords` deletes inode records, content refs, and the per-directory `dirents` sub buckets. Covered by `subtree_test.go` (subtree purge, dependency blocking, crash/replay, pending-child preservation).
- `go/mount/metadata/manager.go` - namespace registry (see above) plus `DrainAll`, which drains all namespace workers concurrently so app-exit drain time is one slowest-worker timeout, not a sum. `DefaultManager` is process-wide so page and future mount callers share a namespace lifecycle; production `Acquire` retains `storage.scopedBackend` for `RootPrefix`, keeping metadata paths view-relative. `Acquire` returns `ErrNoProfileID` (sentinel, not formatted error) for configs lacking the immutable identity; callers treat it as the direct-listing fallback.
- `go/config/cache_maintenance.go` / `metadata_chunk_cache.go` - cache stats expose `protectedBytes`/`protectedFiles`; cleanup exposes `skippedProtected` and never deletes chunks or active splice files listed in a valid protection manifest. Missing/corrupt manifests conservatively protect all chunks in that namespace. Dart cache models/settings display the protected pending-data state.

#### M2/M7: page read path via metadata (completed 2026-08-17)

- `bridge/dispatch_metadata.go` - routes `list_object_page` through the unified inode view and exposes the matching `headObjectFromMetadata` adapter. Both acquire the namespace via `metadata.DefaultManager().Acquire`, resolve the desired path, and fall back only on `ErrNoProfileID`; manager/acquire errors for a persistent identity fail closed rather than opening a second view. `objectInfosFromWire` lets legacy `list_objects` retain its output shape while reading the same metadata page. `forceRefresh` forces `MaterializeDirectory`; `ErrStaleCursor` restarts the page until Dart learns an explicit reload signal. Also exposes `metadata_namespace_status` returning `Service.Status()`.
- `bridge/dispatch_paging.go` - `listObjectPage` order is: metadata namespace for `ProfileID` configs; otherwise legacy `ListMountedObjectPage` then provider direct. A profile-scoped page never probes mount-session liveness or receives a process-local `m:<snapshot>` cursor.
- `bridge/dispatch.go` - registers `metadata_namespace_status`.
- `bridge/dispatch_metadata_test.go` + `dispatch_metadata_fake_backend_test.go` - pins: no-ProfileID fallback, wire adapter shape, stale-cursor unwrap, and forceRefresh rematerialization (cached view vs forced view vs remote change) via an in-memory `metadata.Backend` fake.
- `go/mount/metadata/manager.go` - `AcquireWithBackend` (injection/test variant) and `RemoveAllForTest` helper, in addition to the registry above.
- `lib/models/remote_storage_config.dart` / `remote_storage_config_copy.dart` - Flutter now retains Go's immutable `profileId` in JSON and `copyWith`, so desktop page requests send the identity back to bridge and activate the metadata path. The field is optional for unsaved/legacy in-memory configs, which still intentionally use the direct-listing fallback.
- **M7 acceptance:** `go/mount/metadata_shared_view_test.go` holds page and mount handles from one manager and proves pending mkdir/write/rename/delete share one Desired view. `mvp_recovery_test.go` pins reopen-before-worker and forced-reset rebuild behavior.
- **Known P2 (review 2026-08-17):** per-page Acquire/Release churns worker/db lifecycle (worker restarts between pages; `metadata_namespace_status` creates namespaces as a side effect); metadata `ListPage` returns direct children only, unlike the old S3 flat-prefix listing that included deep keys; a prefix pointing at a file errors instead of listing. Shared policy/transport synchronization and an end-to-end WebDAV `RootPrefix` provider-request assertion have landed; move handle lifetime to page-session scope later.
- **M3 lifecycle guard (2026-08-17):** `newBucketAccess` now retains `metadata.AcquireHandle` for any config with `ProfileID`, releasing it idempotently from both `close()` and `release()` so a page request cannot close a live mount's worker/DB. Missing `ProfileID` alone keeps legacy fallback; any other acquire error fails mount startup. A partial platform `Start` that leaves a live mount but rejects cleanup `Stop` is kept in the manager so its queue/namespace remains reachable for a later retry. `Service` quiet/read-only policy and scoped provider transport are synchronized and refreshed on either `Manager.Acquire` path; one worker operation captures that backend once and uses it for both mutation and confirmation, while the next operation uses refreshed credentials, token, or proxy settings. The pending read integration must still treat metadata as only the remote base: merge system overlay and tombstones before materialization, then local files/directories, restored or queued writeback, and `dirSync` entries. The mount backend is deliberately unscoped, so metadata materialization must use its scoped provider. Legacy-only writes still bypass Desired/journal until M6.

#### M3 mount read integration (completed 2026-08-17)

- `go/mount/metadata/service_directory.go` - path-level `ListDirectory` and `RefreshDirectory` APIs for mount adapters. They resolve/materialize the inode path internally and enumerate a full B+Tree directory without leaking root inode constants or UI pagination cursors. `service_read.go` plus `keys.go` reject deep provider keys during an allegedly one-level listing rather than flattening a basename into the wrong inode.
- `go/mount/metadata_read.go` - adapts metadata `Object` to `s3ops.ObjectInfo` while retaining inode/revision/state in `metadataMountObject` for M5 platform OID projection. `bucket_access_reads.go` routes normal list/stat/open authorization through it when a mount holds a metadata handle; `readRemoteRange` checks the metadata/tombstone view before byte transfer.
- `go/mount/bucket_cache.go` - `localEntry` separates local-first state from TTL-bound legacy remote cache. Metadata base entries are then merged with local files/directories and tombstones by normalized path, preventing simultaneous `name`/`name/` collisions. `writeback_restore.go` restores the local marker for every durable queued upload before reads resume.
- `go/mount/remote_poller.go`, `bucket_access_cloud_files.go`, and `cloud_files_refresh_windows.go` - poll re-materializes metadata then projects its remote-only base into Cloud Files. Placeholder refresh preserves local directory markers in addition to pending writes and tombstones. WebDAV, Linux FUSE, and WinFsp already flow through the common `bucketAccess` list/stat methods.

#### M5 stable OID projection (completed 2026-08-17)

- `go/mount/metadata/service_core.go` exposes only the namespace ID required for platform identity. `metadata_read.go` retains OID/revision/state with mount objects and only returns an OID when the visible entry is metadata-owned; legacy local drafts and system overlay remain intentionally unprojected until M6.
- `go/mount/linux_fuse_nodes.go` uses a metadata OID for lookup/readdir/getattr stable attrs, with its existing FNV path hash only as the legacy fallback. `linux_fuse_oid_test.go` pins rename-stable OID behavior.
- `go/mount/winfsp_metadata_windows.go`, `winfsp_fs_windows.go`, `winfsp_fs_helpers_windows.go`, and `backend_windows_winfsp_cgo.go` preserve OIDs through directory and open-file projections, publish `Stat_t.Ino`, and enable cgofuse `use_ino`.
- `go/mount/cloud_files_types_windows.go`, `cloud_files_hydrator_windows.go`, `cloud_files_refresh_windows.go`, and `backend_windows_cloud_files_cgo.go` pass metadata entries through projection callbacks. `FileIdentity` is namespace+OID while a separate remote fingerprint still detects content changes and dehydrates stale files; `cloud_files_identity_windows_test.go` pins that distinction.

#### M6b mount write integration (completed 2026-08-17)

- `go/mount/metadata_write.go` - the mount adapter routes metadata-enabled `createDirectory`, staged file close, rename, and delete to `metadata.Service` before returning success. It keeps local cached bytes readable, moves cache indexes before a rename and rolls them back if the Desired transaction rejects it, and does not announce a local intent through the legacy peer-broadcast path. Cloud Files completion uses its externally-moved variant, which only rebinds the marker to the callback's `newLocalPath` because Explorer has already moved the bytes.
- `go/mount/bucket_access_writes.go`, `bucket_cache_rename.go`, `overlay_bridge.go`, `webdav_file.go`, `linux_fuse_file.go`, `linux_fuse_nodes.go`, `winfsp_fs_windows.go`, and `cloud_files_watcher_windows.go` propagate staging errors at synchronous platform boundaries. `enqueueRenamePath` selects the external-move marker rebase for metadata sessions; pending metadata drafts now project their persistent OID, while legacy local-only drafts still use the fallback.
- **Known P2 (M6b review):** `winFspBucketFS.Release` clears `open.dirty` after a failed metadata `stageLocalWrite`, so that Windows close failure has no durable retry record yet. Keep this separate from successful journal admission; do not assume the local file was queued.

#### M6c page write integration (completed 2026-08-17)

- `bridge/dispatch_metadata_mutation.go` owns the profile-scoped page-to-journal adapter. It acquires `DefaultManager`, falls back only for `ErrNoProfileID`, and opens/stat's a file only before `Service.WritePath` stages it. `bridge/dispatch_page_mutations.go` owns page create/upload/rename/delete handlers; `dispatch_object_transfer.go` sends moves through the same adapter. `copyObject` and recursive `uploadDirectory` explicitly fail closed when `ProfileID` exists because they need a future durable copy/batch operation.
- `go/mount/metadata/manager.go` keeps an unreferenced namespace alive while `Status` reports pending/failed operations or pending content. This makes per-request page handles safe: the background worker remains available until work is drained, then a later acquire/release prunes the idle service. `Op.HardDelete` is durable and worker execution selects `DeleteObjectHard` for permanent page intent.
- `go/mount/metadata/service_projection.go` exposes `PathProjection` and a no-provider-I/O `ProjectionCurrent` check. `bridge/dispatch_metadata_mutation.go` captures the post-mutation inode/revision while the path lock is held; `go/mount/external_invalidation.go` and `bucket_access_reads.go` apply `ProjectMetadata*` only while that version remains current under `writebackMu`. A late page delete/upload/rename therefore cannot hide or clear a newer mount write marker. These helpers are distinct from `NotifyExternal*`, which remains the legacy remote-confirmed invalidation path.
- `go/mount/metadata/worker_move.go` persists the frozen move target before provider work and `Op.MoveApplied` after a provider accepts it but before confirmation. Replay re-confirms the frozen target; the pre-persist crash window probes even non-sentinel provider errors and accepts only a matching target fingerprint or explicit matching directory marker. `worker_move_test.go` covers chained renames, local-only replay, generic 404-style errors, missing directories, and marker-only directories.
- **Known P2/P3 (M6c review scope):** page task IDs do not yet map to worker transfer snapshot IDs, mount byte reads cannot yet serve unconfirmed page-upload chunks, and Web API/browser upload endpoints remain provider-direct even with `ProfileID`. Also reject `.`/`..` page create/rename segments in a later bridge-input validation pass. The WebDAV 404-to-`os.ErrNotExist` contract and worker reconciliation have unit coverage, but an HTTP-server end-to-end “MOVE applied then retry” fixture remains a P3 test gap. Do not present any of these as completed durability behavior.
- `go/mount/writeback_store.go` - a metadata-enabled mount constructs the legacy queue only as an inert compatibility/control surface: it deliberately does not restore old queue/mutation records and new mutations never enqueue there. This prevents two independent remote writers. Fallback mounts without a metadata namespace retain the old behavior.

- `go/mount/metadata/manager.go` - namespace registry rooted at `RuntimeDir()/metadata/v1/<namespace-hash>`; namespace = `ProfileID + storageType + endpoint + config bucket + rootPrefix + bucket`. Retains Service+Worker across mount sessions and exposes `DrainAll` for app exit.
- `go/config/config.go` + `go/config/config_db.go` + `profile_identity.go` - immutable `RemoteStorageConfig.ProfileID`, generated once per profile and preserved across saves/renames so metadata namespaces stay stable. `loadProfileFromDB` runs as a write transaction and lazily backfills `ProfileID` on read so legacy migrated profiles stop using unstable `unversioned-*` identities.
- `go/mount/metadata/metadata_test.go` - pins stable inode identity across listings, rename-without-descendant-rewrite, ancestor-cycle rejection, stale-cursor reload, read-only rejection, reset guard force semantics, and namespace determinism.

#### Legacy queues (fallback-only after M6b)


Mounted writes are asynchronous across four cooperating queues inside `go/mount`; file uploads, directory-marker creates, renames, and deletes have different durability and ordering guarantees.

#### Key files

- `go/mount/bucket_access.go` - `bucketAccess` owns all queues. `newBucketAccess` creates `dirSync` (`newDirSyncQueue`), `writeback` (`newWritebackQueue`), `deletes`. `writebackMu` orders every local path mutation (file staging, mkdir, delete, external invalidation, and rename); `mutationMu` serializes the corresponding provider move/delete after that local ordering has been fixed. `close()` shuts down queues; `drainWritebackContext` drains file writeback without discarding persisted entries when its caller times out. `release()` shuts down `dirSync` only.
- `go/mount/writeback_queue.go` / `writeback_queue_drain.go` - File upload queue. `stageLocalWrite` (from WebDAV close, FUSE/WinFsp publish, or Windows watcher) stores the local marker and calls `enqueue` under `writebackMu`; the queue delays by `WritebackQuietSeconds` and drains through a cancellation-safe dispatcher. If a cancellation hits queue backpressure, every not-yet-sent entry is re-armed for normal dispatch rather than stranded `queued=true`; `drainPath` forces only a rename source/subtree to settle before its synchronous remote move. `flushNow` stats the resolved local path, refreshes if size/mtime changed, `UploadFile`, then HEAD-verify, cache update, peer broadcast, store delete. Missing source = success-with-cleanup (`flush-missing`), so an upload whose cache file vanished is silently dropped.
- `go/mount/writeback_store.go` - Per-PID JSON store plus global registry keyed by store dir. Every writeback record has a hash scope of profile/view identity plus provider-specific principal: S3 access key, WebDAV username, FTP/SFTP username+port (or anonymous+port), or Baidu refresh token. Store merge keys are `scope + path`, so same virtual paths from different remotes survive compaction independently. An active in-process queue rejects attaching a changed scope.
- `go/mount/writeback_restore.go` - `restorePersistedEntries` restores only matching-scope records whose local source is a regular file inside `sessionRoot` or `cacheRoot`; mismatched or legacy-unscoped records stay dormant in the compacted store instead of being replayed or deleted. `restorePersistedMutations` applies the same scope check while retaining mismatches, rebuilds barriers/rebases, and replays matching rename records **without the `run` closure**.
- `go/mount/dir_sync_queue.go` - Directory marker create queue remains memory-only. `stageLocalDirectory` → `queueRemoteDirectory` → `enqueue`; 2 workers call `CreateDirectory`. The latest provider/pool failure is captured as a process-local `[dir-sync]` error, clears after a successful create of that path, and still closes the entry fence so it cannot block later writeback. `rebaseAndFence` is used by both queued Cloud Files renames and synchronous `renamePath` calls.
- `go/mount/bucket_access_writes.go` / `bucket_cache_rename.go` - `createDirectory` only stages locally + enqueues marker. `stageLocalWrite` protects the marker-to-queue handoff. Synchronous `renamePath` (macOS WebDAV, Linux FUSE, WinFsp) holds the common path gate, rebases/fences directory markers, drains matching queued/running uploads, waits/rebases in-flight delete intent, then moves the remote source; cache byte moves are preflighted and indexed only after success, with best-effort rollback on a multi-file failure. `enqueueRenamePath` (Windows Cloud Files only) captures a scoped persisted `mutationRecord` with barrier generation and a legacy `run` closure that creates the renamed directory remotely when the old path is absent.
- `go/mount/writeback_rename_queue.go` - Rename/mutation dispatcher. `enqueueMutation` persists record, creates barrier + source rebase, queues op. `executeQueuedRename` drains uploads at generations ≤ barrier, waits dir barrier, runs closure once, then state-driven reconciler retries. Unfinished barrier blocks **later-generation uploads** via `generationBlockedLocked` (50ms re-arm polling).
- `go/mount/mutation_reconcile.go` - `reconcileRemoteMove` state table: absent/present → complete; present/absent → Move; both → Copy+hard-delete; **absent/absent → `errMutationStateConflict`, retry forever** — it never creates the destination or uploads local content. `applyMutationSuccess` fixes caches/broadcast.
- `go/mount/delete_queue.go` - Separate delete queue with retries. It tracks claimed/running entries so a rename can rebase pending and not-yet-started remote delete targets only after the destination remote postcondition succeeds. The provider delete snapshots its path while holding `mutationMu`, preventing a stale or torn path from overtaking the move.
- `go/mount/types.go` + `lib/widgets/file_manager_bucket_browser_actions.dart` - Mount status combines session, rename-mutation, and dir-sync errors. The bucket action row shows a non-interactive alert icon with the full error in a tooltip while the mount remains active.
- `go/mount/webdav_fs.go` / `go/mount/webdav_file.go` - Finder path: MKCOL → `createDirectory` (local + dirSync), MOVE → `webDAVFS.Rename` → `renamePath`; PUT close → staged temp renamed into hashed cache path → `stageLocalWrite`.
- `go/mount/macos_mount_stop.go` - macOS `mountSession.stop` drains writeback before probing/unmounting the WebDAV volume. It uses `transferTimeout` as a bounded context; a drain failure or timeout keeps the mounted server and queue live, clears `stopping`, records an actionable `LastError`, and lets the user retry instead of silently closing pending work.
- `go/mount/manager.go` - Session replacement, global cleanup, and status probing all retain a session when its backend rejects Stop while keeping `mounted=true` and clearing `stopping`; this prevents another configuration from attaching to the still-live durable queue. `startMountSession` closes access/metadata queues on a `CleanupStale` or partial `Start` failure, except when that partial start left a live mount and cleanup Stop fails: that session is registered with its error so it remains retryable. A successful Stop removes the session normally.

#### Data flow (Finder: create dir → rename it → upload file)

1. MKCOL default name → cache local dir entry + `dirSync.enqueue("未命名文件夹")` marker create.
2. MOVE → `renamePath`: enter the common path gate, rebase/fence queued marker creates, drain matching writes, then move the remote source under the remote-mutation mutex. Only after the remote destination is confirmed are pending/not-yet-started delete targets rebased. A local-only directory whose source is absent verifies the rebased destination marker and completes without sending an invalid move. Windows Cloud Files uses `enqueueRenamePath`, which additionally persists the move.
3. PUT close → hashed cache file + `stageLocalWrite("正确名/文件")`, atomically publishing the local marker and `writeback.enqueue` record (visible as `mount-writeback-*` pending task, `sync_wait` → `upload_wait`).
4. Upload executes after quiet period and any rename barrier; per-backend parent behavior differs (SFTP/FTP auto-create parents; WebDAV `put` does not MKCOL parents; S3 keys are flat).

#### Gotchas / known risks

- **Directory creates are not persisted at all**; failures now surface as one process-local mount error, but no retry state survives a crash/remount. The rebase fix prevents legacy synchronous renames from creating the old marker name, but a crash before the marker completes still loses that memory-only create.
- **Scope mismatch is deliberately dormant:** changed-account/root-prefix records are retained locally but never auto-uploaded to the new remote. Legacy records with no scope are likewise not migrated; recovery requires returning to the original profile or manually handling the cached content.
- **Known P2 (rename cancellation):** `rebaseAndFence` changes a queued marker before `renamePath` waits. If that wait is canceled, the marker rebase is not rolled back, so a retry can observe a changed marker while the cache still shows the source path.
- **Known P2 (legacy writeback store):** queue JSON is still written with direct `os.WriteFile`, without temp-file rename or parent fsync; a power loss can make the entire queue unreadable. Also, restoring more than the 64 buffered rename mutations can block before the dispatcher starts. These need a dedicated persistence hardening batch rather than a partial semantic change here.
- **Known P2 (external mount disappearance):** a successful Stop invoked from `syncSessionLocked` does not currently stop the remote poller before status code removes the session. External unmount detection can therefore leave a poller briefly targeting released access state.
- **Stuck rename blocks the bucket:** an unfinished barrier (e.g. restored record with absent/absent remote state, no `run` closure) makes `generationBlockedLocked` defer every later upload indefinitely while the reconciler retries forever with `mutation state conflict`.
- **`renamePath` local-only shortcut** returns success without creating the renamed directory remotely; correctness then depends on later marker create/upload (backend-dependent).
- **First-stage MVP (2026-08-17):** the locked MVP is metadata refactor + unified page/mount read view only. Deliverables: immutable ProfileID and bbolt inode namespace; `inodes` + per-directory `dirents` B+Trees + `journal/listing_state/content_refs`; one `metadata.Service` read API (`ListPage/Stat/StatInode/Path`) with lazy remote-listing materialization; Flutter desktop listing/stat and macOS WebDAV/Linux FUSE/WinFsp/Cloud Files reads all served by that service (including while unmounted); single-transaction inode rename with explicit collision/cycle semantics; minimum write closure that updates Desired state + journal at existing write points and ingests Remote confirmation; status/reset-guard observability. inode/OID is internally owned by the metadata store; platform-visible file numbers only need a stable adapter-side resolution back to the same OID (Linux FUSE may set `Ino=OID`; WinFsp may use `FileIndex=OID` or a lookup; Cloud Files placeholder identity may encode OID or be resolved by the adapter; macOS WebDAV's external inode remains webdavfs-owned). Acceptance is page/mount view consistency, not equal inode numbers across platforms. Explicitly out of scope: journal-driven remote worker, cross-device change feed, legacy JSONL migration, full trash unification, conflict UI. Recommended implementation batches M1–M7 are in the plan.
- **Unified metadata architecture:** the app is being reworked toward one persistent inode B+Tree metadata view + operation journal shared by both the Flutter file manager and mount backends, with remote sync driven from the journal. Sequencing is binding: metadata store → unified read view → common write entry point → journal-driven remote worker → cross-device remote change feed. Local metadata is a rebuildable cache in this development phase: no migration of old writeback/mutation JSONL, no legacy queue feature flag, and schema mismatch/corruption means delete-and-rebuild from remote listing. Pending, not-yet-remote-synced content is the only data-class state and must be protected by the reset guard. Design, current-architecture coupling audit, risk list, and phased TODO live in `docs/MountMetadataJournalPlan.md`.
- **Page-vs-mount coupling details (M7):** Flutter desktop page `list_object_page`, `list_objects`, and `head_object` with `ProfileID` use the persistent namespace regardless of mount state; `ListMountedObjectPage` and its process-local snapshots survive only as the explicit no-identity legacy fallback. Page create/upload/rename/move/delete submit Desired+journal first and use revision-checked mount projection, rather than calling `NotifyExternal*`. `NotifyExternal*` remains only for legacy and provider-direct Web API paths; P2P/poll ingress still needs the later unified reconciliation entry point.
- **Cross-device remote freshness (2026-08-17 review):** current P2P sends only an optional parent-directory refresh hint after remote-confirmed changes; it is default-off and not durable. The fallback poller only scans recently opened directories (cap 12); SFTP explicitly disables it through `SupportsMountRemotePolling() == false`. Therefore a second mount cannot reliably observe an rsync overwrite on the first device. The planned inode B+Tree uses per-device-local OIDs only; cross-device synchronization must use a durable remote immutable event feed keyed by canonical remote paths + remote fingerprints + origin sequence, then verify via HEAD/list and invalidate/dehydrate old local content. Details and capability fallback are in `docs/MountMetadataJournalPlan.md`.
- Remote-operation UI is unified: `lib/models/remote_task.dart`, `lib/state/remote_task_store.dart`, `lib/pages/transfers_page*.dart`, `lib/widgets/remote_task_widgets.dart`, `lib/widgets/sidebar_transfer_status.dart`, and `lib/pages/file_sync_tasks_page.dart` render effective operations, dependencies, expandable raw events, physical phases, cancel/retry/trigger, and history. No page/sidebar/sync card falls back to `TransferQueue`.
- Bridge log: `~/.cloud-volume/runtime/logs/bridge.log` (`[mount/writeback]`, `[mount/dir-sync]`, `[webdav/mkdir]` lines); per-bucket queues: `~/.cloud-volume/runtime/mounts/<bucket>/{writeback,mutations}`.

### Feature: Account Disable (账号禁用)

An account can be disabled from the account-management page. A disabled account is kept (so the user can re-enable it) but skipped everywhere it would otherwise connect to its backend: it is not bucket-listed, does not appear as a load failure, does not participate in P2P, and is not contacted during quota prefetch.

#### Key files

- `go/config/config.go` — `RemoteStorageConfig.Disabled bool` (`json:"disabled" toml:"disabled"`). The zero value `false` means **enabled**, so no `UnmarshalJSON` shim is needed (contrast with `P2PEnabled`, which needed a shim because its default changed to false). `Normalized()` passes it through unchanged.
- `go/config/profile.go` — `ProfileInfo.Disabled bool` (`json:"disabled"`), populated in `go/config/config_db.go` `listProfilesFromDB` from `normalized.Disabled`.
- `bridge/dispatch_p2p.go:81` — the P2P manager gate now reads `cfg.P2PEnabled && cfg.IsConfigured() && secret != "" && !cfg.Disabled`. A disabled account never starts a P2P manager.
- `lib/models/remote_storage_config.dart` / `remote_storage_config_copy.dart` — `disabled` field (default false, fromJson, toJson omit-when-false, copyWith).
- `lib/models/bootstrap_state.dart` — `ProfileInfo.disabled` (`json['disabled'] == true`).
- `lib/services/bucket_source_service.dart` — `loadEntriesWithFailures` and `loadSources` filter `profiles.where((p) => !p.disabled)` **before** any `loadProfile`/`listBuckets` call. This is the single gate for file manager, global trash, and sync picker.
- `lib/widgets/cloud_storage_account_list.dart` — `_AccountActions` (list) and `_AccountCard` (grid) show a `ShadSwitch` (value = `!profile.disabled`); toggling calls `onToggleDisabled(profile, disabled)`. A disabled account's title gets a "（已禁用）" suffix. The account-management page does **not** filter disabled accounts (they must remain visible to re-enable). This file also owns `enum AccountStatus { checking, ok, error, disabled }` and `_AccountStatusChip` (dot + label + tooltip) used by the status column.
- `lib/pages/cloud_storage_page.dart` — `_toggleDisabled(profile, disabled)` mirrors `_delete`/`_saveEditedAccount`: `loadProfile` → `copyWith(disabled:)` → `saveProfile` → `onRefresh` + busy guard + toast. Also owns the status-column probe: `_refreshStatus()` marks disabled accounts `AccountStatus.disabled` without probing and fires `_probeAccount(name)` concurrently for each enabled account; `_probeAccount` calls `loadProfile` + `listBuckets` with a 12s Dart timeout, reusing the fast-fail path (3s dial, no SDK retry, 20s negative cache) so one unreachable account does not slow the page and seeds the shared negative cache for the file manager. Results are stored in `_status` / `_statusError` maps keyed by profile name and passed to `CloudStorageAccountList`.

#### Data flow

1. User toggles the switch on an account row → `_toggleDisabled(profile, disabled)` → `loadProfile` + `saveProfile(name, config.copyWith(disabled: disabled))`.
2. `onRefresh` reloads bootstrap → `listProfilesFromDB` returns the profile with `Disabled` populated → `ProfileInfo.disabled` flows to Flutter.
3. File manager / global trash / sync picker call `BucketSourceService.loadEntriesWithFailures` → disabled profiles filtered out before any backend call → disabled account's buckets never load, no connection is attempted, no failure is recorded.

#### Gotchas

- **`Disabled=false` means enabled.** The zero value is "enabled", so missing fields, old configs, and `DefaultConfig()` all produce enabled accounts. Disabling is always an explicit user action. Do not add an `UnmarshalJSON` shim that forces a default — unlike `P2PEnabled`, the natural zero value is already the desired default.
- **Filter in the service, not the page.** `BucketSourceService` is the shared entry point for file manager, global trash, and sync picker. Filtering there guarantees all consumers skip disabled accounts consistently. Do not filter in `FileManagerPage` (the profiles list is also needed for mount status and re-enable flows).
- **Account management page never filters.** Disabled accounts must stay visible there with a switch, or the user cannot re-enable them.
- Regression anchors: `go/config/config_disabled_test.go` (defaults-false, explicit true/false retained, DefaultConfig enabled, Normalized preserves), `test/bucket_source_service_test.dart` (`loadEntriesWithFailures skips a disabled account entirely`).

### Feature: Windows Local Development Workflow

Windows development now has two scripts: one for new-machine dependency bootstrap, and one for project run/build after dependencies exist.

#### Key files

- `scripts/setup_windows_dev.bat` - Double-click launcher for dependency bootstrap. It changes to the repo root, calls `scripts/setup_windows_dev.ps1` with `powershell -NoProfile -ExecutionPolicy Bypass`, forwards any command-line arguments, reports success/failure, and pauses at the end for double-click users. Set `CLOUD_VOLUME_NO_PAUSE=1` when invoking it from automation to avoid the final pause.
- `scripts/setup_windows_dev.ps1` - New-machine bootstrap script. Uses `winget` to install/verify Git, Go, Visual Studio 2022 Build Tools, and MSYS2; direct installers remain as fallbacks. It also installs the native MSVC Rust toolchain through official `rustup-init`, adds `$HOME\.cargo\bin` to user `PATH`, and ensures the matching Rust target exists. Architecture detection honors `PROCESSOR_ARCHITEW6432` so an emulated PowerShell still sees the native OS. x64 installs UCRT64 `mingw-w64-ucrt-x86_64-gcc`; ARM64 installs CLANGARM64 `mingw-w64-clang-aarch64-clang` and the Visual Studio `Microsoft.VisualStudio.Component.VC.Tools.ARM64` component (modifying an existing Build Tools installation when needed). The Go MSI fallback also uses the native `amd64`/`arm64` artifact. It sets `FLUTTER_ROOT`, architecture-matched `BRIDGE_CC`/`BRIDGE_CXX`, user `PATH`, and default `GOPROXY=https://goproxy.cn,direct` while preserving custom proxies. It treats unavailable Developer Mode as a warning, probes China Flutter mirrors before falling back to official sources, and checks native exit codes. Optional flags: `-FlutterRoot`, `-MsysRoot`, `-SkipWingetInstall`, `-SkipFlutterClone`, `-SkipMsysPackages`, `-SkipDoctor`, and `-ValidateProject`.
- `scripts/run_windows.ps1` - Canonical Windows local run/build helper. It detects native x64/ARM64 architecture, resolves Flutter, Go, and Rustup, selects UCRT64 GCC/G++ for x64 or CLANGARM64 Clang/Clang++ for ARM64, and validates each compiler's `-dumpmachine` output before enabling cgo. On ARM64, Rustup is required so CargoKit-backed plugins such as `super_native_extensions` build locally instead of downloading GitHub Release artifacts; CargoKit verbose logging exposes the underlying failure rather than only MSB8066. Stale `BRIDGE_CC` values for the wrong architecture are skipped; an explicitly passed incompatible compiler fails immediately with a focused error. It sets `GOOS=windows`, native `GOARCH`, `CGO_ENABLED`, `CC`/`CXX`, builds the bridge, and runs/builds Flutter. Release output uses `build/windows/x64/...` or `build/windows/arm64/...` dynamically and verifies `cloud-volume.exe`, `cloud-volume-app.exe`, the crash reporter, and updater before returning success. Developer Mode absence is warning-only. Build mode embeds `APP_VERSION_LABEL`; run mode defaults it to `dev`.
- `scripts/run_windows_debug.bat` - Double-click launcher for debug runs. It changes to the repo root and calls `scripts/run_windows.ps1` without `-Build`, so the bridge DLL is built first and then `flutter run -d windows` starts the app. Forwards extra command-line arguments and pauses unless `CLOUD_VOLUME_NO_PAUSE=1`.
- `scripts/build_windows.bat` - Double-click release-build launcher. It calls `scripts/run_windows.ps1 -Build`, detects x64 versus ARM64 (including an emulated shell), and opens the matching `build/windows/<x64|arm64>/runner/Release/` directory.
- `scripts/build_windows_installer.ps1` - Builds `yunjuan-windows-<x64|arm64>-installer.exe` from the architecture-matched Flutter release bundle via Inno Setup 6. It passes `x64compatible` or `arm64` to both Inno architecture directives and uses `git describe` unless `-Version` is provided.
- `scripts/build_windows_installer.bat` - Double-click launcher for `build_windows_installer.ps1`; it builds/packages the release and pauses on completion for interactive users.
- `README.md` - Windows development documentation covers bootstrap, architecture-specific toolchains, run/build launchers, Developer Mode behavior, and Go/Flutter mirrors.
- `AGENTS.md` Build Outputs section - Reinforces that Windows validation should prefer `scripts/run_windows.ps1` over bare `flutter run -d windows` so the bridge DLL and CGO toolchain are configured correctly.

#### Gotchas

- ARM64 cgo must use the CLANGARM64 compiler selected by the scripts. If `gcc_arm64.S` ever reports unknown `stp`/`ldp`/`blr` instructions again, inspect the printed compiler target: it must contain `aarch64`/`arm64`, not `x86_64`. User overrides passed with `-BridgeCc`/`-BridgeCxx` are intentionally rejected when their `-dumpmachine` target does not match the native architecture.
- Visual Studio readiness for Flutter Windows is more than a workload ID: ARM64 hosts need `Microsoft.VisualStudio.Component.VC.Tools.ARM64` and `MSBuild\\Microsoft\\VC\\*\\Platforms\\ARM64`. `setup_windows_dev.ps1` now verifies that platform folder and waits for VS setup modify to finish; `run_windows.ps1` fails early with the exact install command when it is missing.
- Cloud Files cgo sources under `go/mount/cloud_files_*_windows.go` must not hardcode `-D_AMD64_`. On ARM64 that forces x64 `windows.h` intrinsics (`+D`, `=@ccc`) and redefines `CONTEXT`. Use architecture-specific `#cgo amd64 CFLAGS` / `#cgo arm64 CFLAGS` instead.
- `Resolve-Executable` must not treat bare command names as filesystem paths. This repository has a top-level `go/` package directory, so resolving `go` via `Test-Path` would return that directory and later `& $go build` fails with “cannot recognize C:\\...\\cloud-volume\\go”. Bare names now go through `Get-Command` / explicit leaf candidates only.
- On some Windows ARM hosts, PowerShell's call operator (`& clang.exe -dumpmachine`) can return empty output even when the compiler works. `run_windows.ps1` therefore probes compilers through `System.Diagnostics.ProcessStartInfo`, prefers known `C:\\msys64\\clangarm64\\bin\\clang(.exe|++.exe)` paths over a stale user `BRIDGE_CC` pointing at UCRT64 gcc, and rewrites the user `BRIDGE_CC`/`BRIDGE_CXX` values after a successful match.
- `super_native_extensions` uses CargoKit. Without Rustup, CargoKit first downloads signed `aarch64-pc-windows-msvc` binaries from GitHub Releases; on this ARM64 host Dart's HTTP client timed out even while PowerShell could reach the same URL, and MSBuild surfaced only MSB8066. The setup script now installs Rustup, and the run script adds `$HOME\.cargo\bin` before Flutter starts, which makes CargoKit choose its built-in local-build path.
- `scripts/run_windows.ps1` fails fast with clear errors if Flutter or `gcc`/`g++` is missing; it does not download or install them.
- `scripts/setup_windows_dev.ps1` prefers `winget` but can install VS Build Tools and MSYS2 without it. Git and Go still require either `winget` or preinstallation before the script reaches later steps.
- Direct downloads use retrying `Invoke-WebRequest`, then `curl.exe -L --ssl-no-revoke`; the latter handles Windows machines whose certificate revocation check fails because the revocation server is offline.
- VS Build Tools installer exit code `3010` means installation succeeded but a reboot is requested; the script accepts it and continues.
- Flutter first bootstrap can leave `bin/cache/dart-sdk` incomplete with no `dart.exe`; the script detects that state and downloads `dart-sdk-windows-x64.zip` for the current engine version from `FLUTTER_STORAGE_BASE_URL` before invoking `flutter.bat`.
- If Flutter was cloned/installed from an elevated process, Git may reject it with `detected dubious ownership` because the directory is owned by `BUILTIN/Administrators`; both setup and run scripts add the resolved Flutter root (for example `C:/Users/3000y/dev/flutter`) to the current user's global Git `safe.directory` before invoking Flutter.
- Flutter Windows plugins may require symlink support. Both setup and run scripts check `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense`; when running as administrator they try to set it to `1`, otherwise they show the Developer Mode path as a warning without blocking setup/build preflight.
- `scripts/setup_windows_dev.ps1` does not run a full app build by default; pass `-ValidateProject` to call `scripts/run_windows.ps1 -Build` after dependency setup.
- After setup writes user environment variables and `PATH`, open a new PowerShell window before using `scripts/run_windows.ps1` interactively.

### Feature: Windows Crash Watchdog / Startup Reports

Windows release bundles separate the public launcher from the Flutter process so failures before the first window exists are still observable.

#### Key files

- `windows/runner/crash_launcher.cpp` - Implements the public `cloud-volume.exe`. It resolves the sibling `cloud-volume-app.exe`, forwards the original command line, starts it with `CreateProcessW`, waits for its process handle, and launches the report helper after a non-zero exit or `CreateProcessW` failure. If the report helper itself is unavailable, it shows a minimal native error with the Windows error/exit code.
- `windows/CMakeLists.txt` / `windows/runner/CMakeLists.txt` / `windows/runner/Runner.rc` - The Flutter target is named `cloud-volume-app`; a small native `cloud_volume_launcher` target keeps the on-disk name `cloud-volume.exe`; the Go `cloud-volume-crash-reporter.exe` is built with `CGO_ENABLED=0` and installed beside both. The launcher target compiles as UTF-8 because its last-resort native error contains Chinese text, and statically links the MSVC runtime so missing `MSVCP140`/`VCRUNTIME140` cannot prevent the watchdog itself from starting.
- `cmd/cloud-volume-crash-reporter/main.go` / `report.go` / `notify_windows.go` - Parses launch/exit diagnostics, writes `~/.cloud-volume/runtime/crashes/crash-<timestamp>-<pid>.txt`, and offers to reveal it in Explorer. Reports include the Windows build, runtime architecture, signed/hex exit code, SHA-256/size/mtime for the launcher, Flutter app, `data/app.so`, and bridge, plus 64 KiB tails from `bridge.log` and the newest `%TEMP%\cloud-volume-updater-*.log`. The prompt warns that local paths may be present.
- `cmd/cloud-volume-crash-reporter/report_test.go` - Covers exit-code/artifact report content and bounded log-tail reads.
- `bridge/app_launcher_path.go` / `bridge/dispatch_app_install.go` - Windows ZIP updates pass the public launcher to `cloud-volume-updater.exe`, even though `os.Executable()` inside Flutter resolves to `cloud-volume-app.exe`.
- `go/mount/windows_process_cleanup_windows.go` / `lib/pages/settings_page_actions.dart` - Development cleanup now terminates both launcher and app processes and describes them generically in the UI.
- `scripts/run_windows.ps1` / `scripts/build_desktop_packages.sh` / `scripts/build_windows_installer.ps1` - Release packaging verifies that launcher, app, crash reporter, and updater are all present before producing an artifact.

#### Data flow

1. Installer shortcuts, post-install launch, ZIP users, and the updater start `cloud-volume.exe`.
2. The launcher starts `cloud-volume-app.exe` and remains hidden while waiting on its process handle. Flutter-created modal/preview sub-windows continue to spawn `cloud-volume-app.exe` directly and are not wrapped in extra watchdogs.
3. Exit code `0` is normal, including confirmed close and the bridge's intentional update-time `os.Exit(0)`; the launcher exits silently.
4. A non-zero exit or app creation failure starts the report helper. The helper fingerprints the installed runtime, appends bounded diagnostic tails, writes the report with user-only permissions, and prompts the user to inspect/submit it.
5. For a green-ZIP update, the updater waits for the Flutter PID. Once Flutter exits with `0`, the launcher also exits; the updater polls `cloud-volume.exe` until writable, replaces the whole bundle, and starts the new launcher.

#### Gotchas

- Do not point shortcuts or updater relaunch at `cloud-volume-app.exe`; doing so bypasses pre-window crash capture.
- Do not report exit code `0` as a crash. The in-app updater intentionally terminates the Flutter process with `os.Exit(0)` after handing work to the external updater.
- `cloud-volume.exe` remains running while the app is healthy, so updates must wait for both processes before overwriting the launcher image. Passing the launcher as updater `-exe-name` provides that writability gate.
- The launcher can diagnose a missing app, loader failure, Flutter engine failure, or later native crash. It cannot diagnose corruption that prevents the launcher itself from loading; its imports therefore stay limited to Windows system libraries and it has no Flutter/Go runtime dependency.
- Reports may contain local paths from logs. Keep the user review warning and the 64 KiB tail limit when extending diagnostics; do not collect credentials or full configuration files.

### Feature: Desktop Application Icons

Desktop platforms share the same cloud-and-drive brand artwork, while each platform packages it in the format and silhouette expected by its shell.

#### Key files

- `assets/brand/yunjuan_app_icon.svg` - Editable brand artwork shared by the app icon family. It does not contain the platform-specific Windows corner mask.
- `macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png` - Opaque 1024px raster used as the input for Windows icon generation; macOS applies its own displayed app-icon silhouette.
- `scripts/generate_windows_app_icon.ps1` - Applies a transparent rounded-square mask with a default 22.5% radius, downsamples the masked master with high-quality filtering, and writes PNG-backed ICO layers at 16, 20, 24, 32, 40, 48, 64, 128, and 256px.
- `windows/runner/resources/app_icon.ico` / `windows/runner/Runner.rc` - Generated Windows icon and the runner resource binding consumed by the launcher, Flutter app, taskbar, Start menu, and Explorer.

#### Data flow

1. Update the editable brand artwork and regenerate the macOS 1024px raster when the artwork itself changes.
2. Run `powershell -ExecutionPolicy Bypass -File .\scripts\generate_windows_app_icon.ps1` from the repository root.
3. Commit the regenerated `windows/runner/resources/app_icon.ico`; Windows resource compilation embeds it through `Runner.rc`.

#### Gotchas

- The macOS 1024px PNG has opaque white corner pixels. Do not copy it directly into an ICO and expect Windows to apply the macOS silhouette; Windows needs real alpha in the rounded corners.
- Keep the rounded mask in the generator rather than baking it into `yunjuan_app_icon.svg`, so macOS and other platforms retain control of their own presentation.
- Keep the small ICO layers. A single 256px PNG forces Windows to rescale at runtime and makes the rounded silhouette and brand details less predictable at taskbar sizes.

### Feature: Desktop Window Close / Tray Exit

The custom desktop chrome routes close actions through Flutter so Windows can offer "hide to tray" versus "exit" without losing OS-level close gestures.

#### Key files

- `lib/widgets/desktop_window_controls.dart` - App-owned minimize/maximize/close controls. The close button and native close requests call `_confirmClose`; confirmed exit first awaits `AppExitCleanup.cleanupMounts()`, then calls `WindowControls.exitApp()` rather than `WindowControls.close()`.
- `lib/services/app_exit_cleanup.dart` - Stores the bootstrapped desktop gateway and coalesces exit-time `cleanupMounts` calls. Cleanup has a 30-second timeout and failures are swallowed so an unavailable stale mount cannot leave an invisible process running forever.
- `go/mount/manager.go` / `bridge/dispatch_mount.go` - `ActiveMountCount` and `get_active_mount_count` expose the number of live in-process mount sessions for the close warning without probing every bucket.
- `lib/services/window_controls.dart` - Method-channel facade for desktop window actions. `close()` means "request close" and may be intercepted by Windows tray logic; `exitApp()` means the user already confirmed and the native host must bypass tray interception.
- `windows/runner/flutter_window.cpp` / `windows/runner/flutter_window.h` - Windows host channel implementation. Every `WM_CLOSE` is sent back to Flutter as `requestClose`; tray Exit sends `requestExit` to Flutter so mounts are cleaned first; the subsequent `exitApp` calls `ExitApplication()` and destroys the window directly.
- `windows/runner/win32_window.cpp` / `windows/runner/win32_window.h` - Base Win32 window lifecycle. `Close()` posts `WM_CLOSE`, while `Destroy()` performs the real teardown and posts quit when `quit_on_close_` is set.
- `linux/runner/my_application.cc` - Linux channel implementation. It has no tray interception; `exitApp` is equivalent to `close`, and `shouldConfirmClose` returns `false`.

#### Gotchas

- Do not use `WindowControls.close()` for a confirmed app exit on Windows. It posts `WM_CLOSE`, which is intentionally intercepted when the tray icon is active and will reopen the confirmation flow instead of quitting.
- Use `WindowControls.close()` only for unconfirmed close requests such as the app-owned close button pre-confirmation path, Alt+F4, or taskbar close handling.
- Use `WindowControls.exitApp()` for explicit "Exit" choices after confirmation, including tray menu exit actions on the native side.

### Feature: Windows Custom Chrome / Window Corners

The Windows host removes the native title bar and uses app-owned chrome, while still asking DWM for native rounded corners where the OS supports it.

#### Key files

- `windows/runner/win32_window.cpp` - Creates the main host with the Flutter-default `WS_OVERLAPPEDWINDOW` style, resizes the hosted Flutter child in `WM_SIZE`, and requests native rounded corners in `UpdateTheme`. It does not override non-client calculation, hit-testing, or standard minimize/maximize/drag commands; the registered `window_manager` plugin owns those behaviors.
- `windows/runner/flutter_window.cpp` - Hosts the Flutter view and owns project-specific tray/close/exit behavior. Its custom method channel no longer exposes minimize, maximize, drag, or maximized-state methods, and it leaves initial visibility to Dart so the frame is hidden before the first visible window frame.
- `lib/app/app_entry_io.dart` - Initializes `window_manager`, applies `TitleBarStyle.hidden` to the main Windows window before `runApp`, then shows/focuses the window after Flutter's first frame.
- `lib/widgets/desktop_window_controls.dart` / `lib/services/window_controls.dart` - Draw the app-owned controls. On Windows, normal minimize/maximize/drag/state operations route through `window_manager`, and `WindowListener` events keep the maximize icon synchronized; Linux retains the custom method channel.

#### Gotchas

- Native DWM rounded corners are a Windows 11-era shell feature. On Windows 10 / Windows Server 2022 build 20348, the `DWMWA_WINDOW_CORNER_PREFERENCE` call is ignored even though it compiles, so the main window stays square.
- Even on Windows 11, fully custom borderless windows can be less reliable than standard framed windows for OS-drawn corners. The current code requests rounded corners but does not implement a manual `SetWindowRgn` or transparent-window mask fallback.
- Keep one owner for Windows non-client behavior. `window_manager` already handles hidden-titlebar `WM_NCCALCSIZE`, maximum-size constraints, frame refresh, and native animated system commands. Duplicating those cases in `Win32Window::MessageHandler` causes ordering conflicts because plugin delegates run before the runner handler.
- Do not replace the main host style with `WS_POPUP` or reintroduce runner `ForceRedraw()` calls around maximize. Those attempts either lose the standard taskbar work area or merely recolor the unpainted transition instead of letting the plugin/DWM path retain the rendered surface.
- The window class must keep a real `hbrBackground` brush (`CreateSolidBrush(RGB(0xF8,0xFA,0xFF))`, matching the light app surface). With `hbrBackground = 0` the area exposed during maximize/restore flashes black until Flutter presents the resized frame. A layered/transparent window is not viable: the hosted Direct3D Flutter child cannot composite through it, so the surface-matching opaque brush is the reliable fix. If a dark theme ships, this brush color must follow the theme.
- An earlier diagnostic machine reported Windows Server 2022 build 20348, where missing rounded corners were expected. The 2026-07-17 static diagnosis ran on Windows 11 Pro build 26100 and identified the relevant code path independently of that older shell limitation.

### Feature: Windows Mount Presentation / Drive Letters

Windows has two distinct mount presentations. Cloud Files is always a sync-root directory, while WinFsp is the virtual-volume engine that gives a bucket a real drive letter and capacity reporting.

#### Key files

- `go/mount/backend_windows.go` - Selects `cloud_files_cached`, `cloud_files_direct`, or `webdav`; an empty/unknown setting normalizes to `cloud_files_cached`.
- `go/mount/backend_windows_webdav.go` / `go/mount/webdav_mount_windows.go` - WebDAV starts the local server, scans unused drive letters from `Z:` down through `D:`, and invokes `net use <drive> <url> /persistent:no`.
- `go/mount/backend_windows_cloud_files_cgo.go` / `go/mount/windows_cloud_files_paths.go` - Cloud Files registers the stable sync root at `~/Cloud Volume/<bucket>` and returns that directory as `mountPath`. If stale cleanup encounters an occupied cache file, it deregisters the root but retains the directory so the next start can reuse it safely.
- `go/mount/windows_drive_mapping_windows.go` / `go/mount/windows_drive_mapping_other.go` - Shared Windows drive-letter discovery, requested-letter validation, and `subst` lifecycle, plus the portable bridge stub. It lists free letters from `Z:` down through `D:`, verifies the chosen letter again at mount time, verifies the mapping after creation, compares the current target before removal, and cleans managed mappings whose targets are direct children of the Cloud Files root.
- `go/mount/windows_shell_namespace_windows.go` - When `windows_this_pc_entry_enabled` is true, Cloud Files can register a per-user Explorer namespace shortcut under “This PC”. This is a folder entry targeting the sync root, not an `X:`-style drive.
- `bridge/dispatch_mount.go` / `lib/services/remote_storage_api_desktop_storage.dart` / `lib/services/remote_storage_gateway.dart` - `list_available_drive_letters` exposes the Windows list through the optional `AvailableDriveLetterQuery` capability, so Web and test gateways do not need a meaningless Windows method.
- `lib/widgets/mount_bucket_dialog.dart` / `lib/pages/file_manager_page_mount.dart` - Read/write behavior is a `ShadSwitch`. Cloud Files is path-only so Explorer does not mistake its host-volume free space for bucket capacity; WinFsp alone presents the free-drive selector and reports the configured bucket capacity. Free letters are still queried before the dialog so a user switching to strict read-only WinFsp can install the driver and continue.
- `lib/services/remote_storage_gateway.dart` / `lib/models/bucket_mount_status.dart` / `go/mount/options.go` / `go/mount/types.go` - Carry the requested `driveLetter` into the session and return the actual `driveLetter` to Flutter. Opening a mounted bucket prefers that drive when present while the provider continues using the real sync-root path internally.
- `lib/widgets/windows_settings_sections.dart` / `lib/models/remote_storage_config.dart` - Settings exposes both Cloud Files variants and the legacy pure-WebDAV mapped-drive fallback. New/default configs select `cloud_files_cached` and disable the optional “This PC” namespace entry.
- `go/mount/mount_capacity.go` / `go/mount/backend_windows_winfsp_cgo.go` / `go/mount/winfsp_fs_windows.go` - WinFsp resolves capacity per bucket: a positive `BucketSettings.CustomQuotaBytes` wins, otherwise the account-wide `WindowsWinFspCapacityGB` value is used. `Statfs` reports that value to Explorer. Regression anchors are `go/mount/mount_capacity_test.go`, `go/mount/winfsp_statfs_windows_test.go`, and the Cloud Files path-only cases in `test/mount_bucket_dialog_test.dart`.
- `go/mount/cloud_files_hydrator_windows.go` / `go/mount/cloud_files_hydrator_placeholders_windows.go` / `go/mount/cloud_files_provider_windows.go` / `go/mount/cloud_files_provider_directories_windows.go` / `go/mount/cloud_files_windows.c` / `go/mount/cloud_files_windows.h` - A placeholder fetch maps the callback path back to a checked virtual prefix, lists that remote directory, and creates placeholders. Coalesced callers receive the leader's real error. When a retained cache entry already exists, directory placeholders are updated with `CF_UPDATE_FLAG_ENABLE_ON_DEMAND_POPULATION`; ordinary NTFS directories are converted with `CfConvertToPlaceholder` plus `CF_CONVERT_FLAG_ENABLE_ON_DEMAND_POPULATION`, so Explorer requests their children instead of treating them as permanently empty local folders.
- `go/mount/windows_hidden_command_windows.go` / `go/mount/windows_drive_mapping_windows.go` / `go/mount/webdav_mount_windows.go` / `go/mount/windows_process_cleanup_windows.go` - Every console utility used by Windows mount lifecycle (`subst`, `net use`, `sc`, PowerShell) goes through `hiddenWindowsCommand`, which combines `HideWindow` with `CREATE_NO_WINDOW`. This prevents console flashes during mount, unmount, cleanup, and confirmed app exit.

#### Gotchas

- Do not describe the Cloud Files “This PC” namespace item as a drive letter. `Win32_LogicalDisk` / `net use` will not contain it, and paths remain under the user profile.
- Do not reintroduce Cloud Files drive selection in the UI. A `subst` mapping is only a host-directory alias and shows the wrong capacity for multi-bucket mounts; use WinFsp when a capacity-bearing volume is required.
- The drive-letter `ShadSelect` sets `ensureSelectedVisible: false`. The package default calls `Scrollable.ensureVisible` for the selected option and can scroll the surrounding app modal to its final row when the popover opens.
- Removal must query the current `subst` target and refuse to delete a drive whose target differs from the session path. Per-bucket stale cleanup runs before deleting the sync root, and full cleanup only removes mappings targeting direct children of `~/Cloud Volume`.
- The current WebDAV allocator does not let users request a specific letter; it always chooses the highest free letter in `Z:` to `D:` order.
- An occupied Cloud Files cache is not an active mount after provider disconnect/deregister. `Stop` keeps the bucket unmounted and returns the cache-removal problem through `BucketMountStatus.lastError`; `cleanupManagedWindowsCloudFilesForBucket` retains an undeletable stable root so the next mount can register and reuse it. `CleanupStaleWindowsProcesses` only targets stale `cloud-volume.exe` / `cloud-volume-app.exe` processes under local build runner directories. It intentionally does not terminate Explorer, Office, or other user applications holding an open file.
- Do not simply skip existing directories in `CreatePlaceholders`. Retained directories may have lost placeholder/on-demand state after deregistration; they must be repaired in place so their children remain lazy and local files are not discarded. Regression anchors are `cloud_files_hydrator_placeholders_windows_test.go`, `cloud_files_types_windows_test.go`, and `windows_hidden_command_windows_test.go`; the native retained-directory conversion still requires an Explorer remount check.

### Feature: File Sync (文件同步)

The sync feature lets users bind a local directory to a remote bucket prefix and keep them in sync (upload / download / two-way) on a configurable schedule, with conflict policies and exclude rules. The Go side runs a scheduler that computes diffs and executes operations; the Flutter side manages config and shows live status.

**Migration (2026-06-26):** Sync config management has been fully migrated from Settings to the File Sync Tasks page. The settings page no longer has a "文件同步" tab. The tasks page is now the **sole** entry point for creating, editing, deleting, toggling, and triggering sync profiles — this resolves the original UX friction where creating a task required navigating to Settings.

#### Flutter (Dart) files

- `lib/pages/file_sync_tasks_page.dart` — File Sync Tasks page. **The sole management hub for sync config.** Summary cards + profile rows; full `sync_*` queue lives on **Transfers**; each profile card shows latest pending/running task via `file_sync_profile_active_task.dart`.
- `lib/pages/file_sync_tasks_page_actions.dart` — Part file containing the CRUD extension (`_FileSyncTasksActions`): `_addProfile`, `_editProfile`, `_saveProfile`, `_deleteProfile`, `_toggleEnabled`, `_triggerSync`. Extracted to keep the page under 500 lines.
- `lib/widgets/file_sync_profile_editor.dart` — Editor widget for creating or editing a single `SyncProfile`. **2-step wizard:** Step 1 同步两端 (optional name, local dir via `FilePicker`, remote dir via `RemoteDirectoryPickerDialog`), Step 2 同步策略 (direction, conflict policy, interval, quiet period, exclude rules, enabled toggle). Receives `api` + `List<FileManagerBucketEntry> buckets`. **`asDialog`:** `true` (default) wraps step content in `ShadDialog` for the **default in-app modal** path; `false` returns bare `_buildContent` only for the **debug-only** OS sub-window — **never nest ShadDialog inside the detached sub-window**. Sub-window layout uses `_buildSubWindowLayout`: fixed step indicator + scrollable step body + pinned nav buttons (avoids RenderFlex overflow on step 2). On save success: `onSaved` then `Navigator.pop` only when `asDialog` is true.

**Modal presentation policy (2026-07-11):** Default for sync / account / remote-directory editors is the **in-app app modal** (`showAppModal` + `asDialog: true`). OS sub-windows stay in the tree for development only (`preferModalSubWindows` = `kDebugMode && USE_MODAL_SUB_WINDOWS`). See **Feature: App Modal (统一拟态框)** and **Feature: Desktop Modal Sub-Window Shell**.

**Debug sub-window stack (retained, not default):**
- `lib/models/sync_editor_window_args.dart` — Args model with `profileNames` and optional `initialProfileJson`.
- `lib/app/sync_editor_window_app.dart` — Built on shared **`DesktopModalSubWindowApp`** (`scrollable: false`). Bootstrap loads bridge + bucket list; content is `FileSyncProfileEditor(asDialog: false)`.
- `lib/services/sync_editor_window_service.dart` (+ `_io.dart` / `_web.dart`) — Desktop `isSupported` follows `preferModalSubWindows`; when false, `openEditor` returns `false` and pages open `showAppModal` + `FileSyncProfileEditor(asDialog: true)`.
- `lib/app/app_entry_io.dart` — Still dispatches debug-spawned sub-windows: `SyncEditorWindowArgs.matches` → `configureDesktopModalSubWindow` + `SyncEditorWindowApp`.
- `lib/services/desktop_modal_overlay_controller.dart` / `lib/widgets/desktop_modal_scrim.dart` — Parent scrim only on the debug sub-window path.
- `lib/services/desktop_sub_window_modal.dart` — Shared acquire/release, chrome, center, resize helpers for debug sub-windows.
- `lib/services/desktop_overlay.dart` — **`showDesktopOverlayOrDialog`**: opens sub-window only when `preferModalSubWindows && service.isSupported`; else in-app dialog. **Current sole caller:** `showRemoteDirectoryPicker`.
- `lib/services/desktop_window_method_host.dart` — Method multiplex for debug sub-window results/overlay/bounds.
- `lib/models/remote_directory_picker_window_args.dart` / `lib/app/remote_directory_picker_window_app.dart` / `lib/services/remote_directory_picker_window_service.dart` — Debug remote-directory OS window (720×560); default path is in-app modal.
- `lib/widgets/remote_directory_picker_dialog.dart` — File-manager-style remote directory picker. **`showRemoteDirectoryPicker`** uses `showDesktopOverlayOrDialog` (in-app modal by default). Widget supports `asDialog`, `onConfirm`, `onCancel`. Returns `RemoteDirectoryResult(bucket, prefix, profileName, config)`.
- `lib/widgets/remote_directory_picker_list.dart` — Part file: directory list + **file rows for display only**. Directories and `..` are selectable; **files are not** (`dimmed: true` on `FileListTile`). Toggle **显示隐藏文件** filters dot-prefixed names. File icons use **grayscale `ColorFilter.matrix`** (not `srcATop` tint) so multi-color SVGs (e.g. zip) grey correctly; title/size use muted text via `FileListTile.dimmed`.
- `lib/widgets/file_list_tile.dart` — Shared list row; **`dimmed`** disables hover/press, uses arrow (not hand) cursor, and paints title/size in muted foreground for non-selectable rows.

**Hover/cursor fix (2026-07-07):** `FileListTile` must keep `SystemMouseCursors.basic` while idle and switch to `SystemMouseCursors.click` only when its own `_hovered` field is true. A regression had `cursor: click` for every non-dimmed row, so file-manager rows could leave the cursor looking like a stuck hand during preview/open interactions. `deleting` rows now also count as non-interactive for hover/press/cursor and title tap handling.
- `lib/widgets/remote_directory_picker_actions.dart` — Part file with `_loadObjects` and `_createDirectory` methods for the picker.
- `lib/widgets/file_sync_profile_editor_steps.dart` — Part file with top-level functions `stepPickEndpoints`, `stepSyncStrategy` and bucket tile/list helpers. Receives `_FileSyncProfileEditorState self` to access fields/controllers and calls `self.markDirty(...)` for setState.
- `lib/models/sync_profile.dart` — Data models: `SyncDirection` (upload/download/twoway), `SyncConflictPolicy` (newest/localWins/remoteWins/skip), `SyncProfileStatus` (idle/syncing/error/paused), `SyncProfile` (mirrors `go/sync/profile.go`), `SyncProfileRuntime` (profile + live status/lastSyncAt/lastError/pendingOps). All have `fromJson` / `toJson` / `copyWith`.
- `lib/state/sync_profile_notifier.dart` — Singleton `SyncProfileNotifier` (ChangeNotifier). Polls Go runtime state every 3s. Exposes `profiles`, `saveProfile`, `deleteProfile`, `triggerProfile`. The tasks page is now the only UI listener.
- `lib/widgets/settings_file_sync_section.dart` — **DELETED** (2026-06-26). Its functionality moved to `file_sync_tasks_page.dart` + `file_sync_tasks_page_actions.dart`.

#### Delete detection and sync (exploration)

**Remote scan depth (2026-06-27):** `go/sync/reconcile.go` `scanRemote` must list **all nested files** under `RemotePrefix`, not only the immediate listing page. File-manager `ListObjectsPage` uses delimiter/depth-1 for UI browsing; sync uses `storage.Backend.ListObjectsRecursive` (S3: paginator without delimiter; WebDAV: PROPFIND depth infinity; Baidu: BFS over directories). If sync only saw top-level files, empty local + remote tree with subfolders would produce **zero downloads** even under two-way sync.
**Local directory keys:** `scanLocal` only walks files, so `classify` calls `localDirSide` to detect existing folders. Without this, `ensure_local_dir` index entries made the next pass think the remote dir vanished and emitted `delete_local` on the folder path.
**Empty remote folders:** Sync also emits `OpEnsureLocalDir` (`sync_mkdir`) when the remote side has a directory marker (S3 `key/` placeholder, WebDAV/Baidu `IsDir`) and local is missing it. File-only reconcile never created folders when a remote dir had no files inside.

Each reconcile pass compares **three views** per relative path: local scan (`localSide`), remote list under prefix (`remoteSide`), and **persisted index** (`IndexEntry` in bbolt — last synced local/remote size+mtime). Keys are the union of all three sets (`go/sync/diff.go` `classify`).

**“Deletion” is inferred when one side is missing now but the index says that side used to exist:**

| Now | Index hint | Direction | Op |
|-----|------------|-----------|-----|
| local missing, remote has file | `idx.LocalSize` or `idx.LocalMTime` ≠ 0 | **twoway** | `delete_remote` (propagate local delete to bucket) |
| same | same | **upload only** | skip |
| same | same | **download only** | `download` (`local_deleted_redownload` — treat as local loss, restore from remote) |
| local has file, remote missing | `idx.RemoteSize` or `idx.RemoteMTime` ≠ 0 | **twoway** | `delete_local` |
| same | same | **download only** | `download` (`remote_deleted_reupload` naming in code is upload path for upload-only — see `diff.go` case `l.present && !r.present`) |
| same | same | **upload only** | `upload` (`remote_deleted_reupload`) |

If a path is absent on both sides but still in index → `skip` (`stale_index`). Brand-new file on one side only (index never had the other side) → normal `upload` / `download`, not delete.

**Rename vs delete:** After classify, `reconcile.aggregateRenames` pairs a pending delete with an add of **equal size** (twoway only) → `OpRename` instead of delete+upload (`go/sync/rename_detect.go`).

**Execution:** `OpDeleteRemote` → `backend.DeleteObject`; `OpDeleteLocal` → `os.Remove`. Queue kind `sync_delete`. On success, index entry for that rel path is **removed** (`executor.updateIndex`). Deletes involving local paths can be deferred by **quiet period** only for upload/rename/delete_local hot-file check in `runner.isHot` — remote-only delete ops are not gated by quiet period.

**Not real-time FS watch:** Periodic reconcile (`intervalSeconds`) + manual trigger; not inotify-style instant delete sync.

#### Go files

- `go/sync/profile.go` — `SyncProfile` struct, JSON tags, source of truth for the Dart model.
- `go/sync/store.go` — Persistence of sync profiles (load/save/list/delete).
- `go/sync/scheduler.go` — Periodic scheduler: triggers sync runs per profile based on `intervalSeconds` and `quietSeconds`.
- `go/sync/runner.go` — Orchestrates a single sync run end-to-end.
- `go/sync/diff.go` — Diffs local vs remote to compute the operation set.
- `go/sync/reconcile.go` — Conflict resolution using `SyncConflictPolicy`.
- `go/sync/executor.go` — Executes the planned operations (upload/download/delete/rename).
- `go/sync/rename_detect.go` — Detects renames/moves to avoid delete+upload churn.
- `go/sync/index.go` / `go/sync/helpers.go` — Indexing and shared utilities.

#### Data flow

1. User creates/edits a profile from **文件同步** page only (`_addProfile` / `_editProfile`): default → `showAppModal` + `FileSyncProfileEditor(asDialog: true)`; debug sub-window only when `SyncEditorWindowService.openEditor` is supported (`preferModalSubWindows`).
2. `_FileSyncTasksActions._saveProfile` → `SyncProfileNotifier.saveProfile` → Go `saveSyncProfile` → `go/sync/store.go`.
3. `SyncProfileNotifier` polls `listSyncProfiles` every 3s → Go runtime state from `scheduler.go`/`runner.go`.
4. On interval or manual "立即同步" trigger → Go `runner.go` runs `diff.go` → `reconcile.go` → `executor.go`, enqueueing `sync_*` work through the runtime adapter.
5. `FileSyncTasksPage` displays profile statuses (from `SyncProfileNotifier`) and live sync work from `RemoteTaskStore.tasksForProfile()`; `TransferQueue` remains only the producer/execution compatibility facade.

### Feature: First-run Config Setup (首次启动配置)

First-run / incomplete-config onboarding before the main shell. Content extends under the desktop title-bar chrome (no page-level top padding).

**Layout by step (current, 2026-07-14):**
- **Step 0「选择协议」:** split-panel — left brand (`ConfigLeftPanel`), right type chooser (`ConfigStorageTypeStep`).
- **Step 1「连接信息」:** full-screen form — left brand is **hidden** so the form can use the full window width; `ConfigRightFormPanel(fullWidth: true)`. On wide windows, S3 / WebDAV fields use a two-column layout to avoid single-column scrolling; Baidu OAuth stays single-column because the auth block is already wide.
- **Step transition:** Next / Back animate the left brand with `TweenAnimationBuilder` + `ClipRect/Align(widthFactor)` (slide-collapse) and fade the right pane with a non-stacking `AnimatedSwitcher` (~240ms). No intermediate spinner page — that was dropped because double rebuild + spinner animation felt janky.

#### Key files

- `lib/pages/config_setup_page.dart` — Wizard host. Step 0 choose type → step 1 account form. Owns controllers and default gateway constants. Conditionally mounts left brand only on step 0; passes `fullWidth: true` on step 1.
- `lib/widgets/config_storage_type_step.dart` — Step 0 type cards (S3 / WebDAV / 百度网盘) + Next.
- `lib/widgets/config_right_form.dart` — Step 1 connection form shell + Back / Save / advanced dialog. `fullWidth` widens the form (max ~720) and enables two-column field layout when viewport ≥ 700. Back uses `ShadButton.ghost`.
- `lib/widgets/config_right_form_fields.dart` — Part file: single-column / two-column field builders for the connection form.
- `lib/widgets/config_left_panel.dart` — Brand / tagline / accent picker (step 0 only on first-run).
- `lib/pages/app_bootstrap_page.dart` — Routes here when `!state.configured` or “重新配置认证信息”.
- `lib/pages/login_page.dart` — Web login still uses left brand + form split (independent of first-run step layout).

#### Default gateways (IHEP)

| Protocol | Default endpoint |
|----------|------------------|
| S3 | `https://fgws3-ocloud.ihep.ac.cn` |
| WebDAV | `https://webdav-ocloud.ihep.ac.cn` |
| 百度网盘 | `https://pan.baidu.com` (OAuth, not user-edited) |

Presets apply when the field is empty or still a known preset; user-typed custom URLs are not overwritten when switching protocol cards.

#### Gotchas

- Do **not** add Scaffold body top padding to clear `DesktopWindowControls` — that creates a full-width white band above both panels. Baidu step-1 Back was already usable with the original padding; avoid layout hacks here unless a real hit-test bug is reproduced.
- Step 1 intentionally drops the left brand so the long connection form does not need as much vertical scrolling; step 0 keeps the brand for first-run marketing / accent picker.
- Account-management modal wizard (`CloudStorageAccountDialog`) is a separate path and does not prefill IHEP defaults; only first-run setup does.
- Save still goes through `api.saveConfig` (legacy first-run profile `"default"`).

### Feature: Account Management (账号管理)

Lists configured storage accounts and lets users add, edit, or remove them. **Default:** add/edit opens as an **in-app app modal** (`showAppModal` + `CloudStorageAccountDialog(asDialog: true)`). **Debug only:** with `preferModalSubWindows`, desktop can still spawn the detached OS sub-window.

**Three-step wizard (current, 2026-07-20):** New accounts use a 3-step guided flow:
- **Step 0「选择协议」:** Large selectable cards for S3 / WebDAV / 百度网盘. Selecting a card updates `_storageType` without navigating.
- **Step 1「连接信息」:** Name field + protocol-specific connection fields + `AccountProxySection`.
- **Step 2「桶列表显示设置」:** Live provider buckets can be selected as an allowlist; each selected bucket can receive a display alias and remote root prefix. Empty selection is dynamic-all.
- **Edit mode** does **not** use the wizard; it renders a single-screen connection form (`_buildEditContent`) with Cancel/Save only.
- Step navigation is only `_next` / `_back` (no step tabs / `_goToStep` on account editor).

**Window sizing policy (current, supersedes earlier per-step resize docs):**
- Account editor **does not** call `resizeKeepingWindowCenter` anymore (removed in `a4197b1d`).
- Initial OS window size is fixed at spawn by `app_entry_io._accountEditorWindowSize`:
  - New account seed: `528×340` (step 0); final size is content-measured after first layout.
  - Edit mode by protocol: Baidu `520×520`, WebDAV `520×600`, S3/default `520×700`.
- Minimum size comes from `configureDesktopModalSubWindow` default `480×400`.
- Open services (`AccountEditorWindowService`) only create the window + pass creator frame; they do **not** set size.
- Shell `AccountEditorWindowApp` uses `DesktopModalSubWindowApp(scrollable: true)` only as overflow safety when content exceeds the screen clamp. Normal steps measure content and resize the OS window via `fitModalSubWindowToContentSize`.
- Dialog sub-window content returns `SizedBox(width: 480)` + `Column(mainAxisSize: min)` — it shrink-wraps height; the fixed OS window height is what creates bottom gap or forces scroll.
- Historical note: `4ce325f9` / `4483c276` used hand-tuned per-step `resizeKeepingWindowCenter` sizes (fragile). `a4197b1d` temporarily used fixed window + scroll. Current approach measures shrink-wrapped form content (`MeasureSize`) and resizes with `fitModalSubWindowToContentSize`. Sync editor still uses discrete step sizes + `resizeKeepingWindowCenter`.

**Default modal path:**
- `lib/services/account_editor_presenter.dart` — Single presentation entry for account add/edit: opens the debug sub-window only when `preferModalSubWindows` allows it; otherwise uses `showAppModal` + `CloudStorageAccountDialog(asDialog: true)`.
- `lib/pages/cloud_storage_page.dart` — Account management delegates add/edit presentation to `account_editor_presenter.dart`.
- `lib/pages/file_manager_page_sources.dart` / `file_manager_page_bucket_loading.dart` — Source failures carry their exact `profileName`; only the newest load generation may publish an error, preventing overlapping startup reloads from replacing the failed-account target with the active/first account.
- `lib/pages/file_manager_page.dart` — Bucket-list error view secondary action is now **「账号管理」** (label) wired to `onOpenAccountManagement`, which `main_layout_page.dart` resolves to `onSelectedItemChanged(SidebarItem.storage)`. This jumps the user to the account-management page (where they can edit/disable/re-enable) instead of opening a single-profile editor in place. The old `file_manager_page_account_editor.dart` part file and `_failedBucketProfileName` field have been removed; `file_manager_page_object_loading.dart` no longer records a failed-bucket profile name.
- `lib/widgets/cloud_storage_account_dialog.dart` — Wizard/edit UI; dual-mode `asDialog` (default true).
- `lib/widgets/cloud_storage_account_dialog_steps.dart` — `stepProtocolPicker` / `stepConnectionFields` + protocol field builders.
- `lib/widgets/cloud_storage_account_dialog_bucket_loading.dart` / `cloud_storage_account_dialog_bucket_visibility.dart` — Fetch live buckets and edit the third-step allowlist/alias/prefix settings.
- `lib/models/cloud_storage_account_draft.dart` / `lib/utils/account_config_builder.dart` / `lib/utils/account_profile_name.dart` — Draft, config build, profile key.

**Debug sub-window architecture (retained):**
- `lib/models/account_editor_window_args.dart` — Args model with `initialConfigJson`, `profileName`, `editing`, `creatorFrame*`.
- `lib/app/account_editor_window_app.dart` — `DesktopModalSubWindowApp(scrollable: true)` + `CloudStorageAccountDialog(asDialog: false)`.
- `lib/services/account_editor_window_service.dart` (+ `_io.dart` / `_web.dart`) — `isSupported => preferModalSubWindows`; otherwise returns `false`.
- `lib/app/app_entry_io.dart` / `desktop_modal_window_config.dart` / `desktop_sub_window_modal.dart` / `desktop_window_method_host.dart` — Spawn, size, chrome, `account_editor_saved` (debug path only).

#### Data flow
1. User clicks "新增账号" or row "编辑" in `CloudStoragePage`.
2. **Default:** `account_editor_presenter.dart` opens `showAppModal` + `CloudStorageAccountDialog(asDialog: true)`; save via page `_saveNewAccount` / `_saveEditedAccount` → `api.saveProfile` → `onRefresh`.
3. **Debug only:** if `AccountEditorWindowService.openEditor` is supported, spawn OS sub-window; save notifies creator via `account_editor_saved`, then closes the child.
4. File-manager recovery identifies either the failed bucket-list source or the exact clicked bucket whose object listing failed, then uses the same presenter in edit mode; it saves via `api.saveProfile` and refreshes the bootstrap session.
5. Baidu OAuth success retains the authorized draft for a new account and advances to bucket visibility; edit mode still reuses `_submit` immediately so recovery behavior remains unchanged.

**Credential recovery update (2026-07-23):** `buildAccountConfig` preserves a stored S3/WebDAV/FTP password when an edit field is blank; the editor never hydrates secrets into Flutter. When an edited S3 Access Key or Secret Key is changed, `cloud_storage_account_dialog_credentials.dart` exposes an explicit validation button that calls bridge method `validate_account_credentials`; `bridge/dispatch_config.go` validates S3 through `s3.CheckAccess` and other backends through `ListBuckets` without persisting anything. `BucketSourceService.loadEntriesWithFailures` now isolates profile load/list failures, while `FileManagerPage` still renders working accounts and gives the first failed profile a focused “重新配置” recovery action.

#### Go / bridge account storage (exploration 2026-07-11)

Accounts are multi-profile configs, not a separate "account" table. There is **no persisted custom sort order** for accounts or for buckets today.

**Key files**
- `go/config/config.go` — `RemoteStorageConfig` (full account connection JSON), `BucketSettings`, `BootstrapState`.
- `go/config/profile.go` — public profile API: `SaveProfile`, `LoadProfile`, `ListProfiles`, `DeleteProfile`, `SetActiveProfile`, `ResetAllProfiles`; summary DTO `ProfileInfo`.
- `go/config/config_db.go` — bbolt persistence in `~/.cloud-volume/config.db`:
  - bucket `profiles`: key = profile name, value = JSON `RemoteStorageConfig`
  - bucket `meta`: key `active_profile` (active name), plus global proxy via `global_proxy.go`
  - `listProfilesFromDB` sorts: active first, then name `"default"`, then alphabetical `Name`
- `go/config/store.go` — `SaveProfileWithValidation` (first-run completeness check) then `saveProfileToDB`.
- `go/config/global_proxy.go` — global proxy in `meta` (`global_proxy`), separate from account profiles.
- `bridge/dispatch_config.go` — bridge handlers for bootstrap/profile/cache.
- `bridge/dispatch.go` — method switch for config/profile/storage methods.
- `go/s3/buckets.go` — live `ListBuckets` → `[]BucketInfo{Name}`; S3 provider order, no local reorder.
- `go/storage/webdav_backend.go` / `go/storage/baidu_pan_backend.go` — single synthetic bucket (`MappedBucketLabel` / Baidu label).
- Flutter aggregation: `lib/pages/file_manager_page_sources.dart` filters non-empty `bucketViews` allowlists, builds effective per-entry configs, then applies persisted bucket order (fallback profile order + bucket label).

**JSON schemas (Go → Flutter)**
- Account/profile full config (`RemoteStorageConfig`): `endpoint`, `storageType`, `providerType`, `displayName`, `mappedBucketName`, `region`, `bucket`, `accessKeyId`, `secretAccessKey`, `hasSecretAccessKey`, `webdavUsername`, `webdavPassword`, `hasWebdavPassword`, `rootPrefix`, `defaultDownloadDirectory`, `cacheDirectory`, `resolvedCacheDirectory`, `hideDotFiles`, `fileOpenMode`, `trashDirectoryName`, `trashRetentionDays`, `bucketSettings` (map), `bucketViews` (allowlist map), mount/cache/proxy fields. **No inline order/sort field.**
- Per-bucket overrides (`BucketSettings`): `readOnly`, `trashEnabled?`, `trashDirectory`. Map key is bucket name; **map has no order**.
- Per-bucket view (`BucketViewSettings`): `displayName`, `rootPrefix`. Map key is the immutable provider bucket name; an empty parent map means dynamic-all.
- Profile summary (`ProfileInfo`): `name`, `displayName`, `storageType`, `providerType`, `endpoint`, `accessKeyId`, `active`. **No order field.**
- Bootstrap (`BootstrapState`): `configPath`, `configured`, `config`, `profiles[]`.
- Live bucket row (`BucketInfo`): only `name`.

**Bridge APIs (account/profile)**
- `load_bootstrap_state` / `migrate_default` → `BootstrapState`
- `save_config` → validates + saves profile `"default"` + set active (legacy first-run path)
- `list_profiles` → `[]ProfileInfo` (hardcoded sort above)
- `load_profile` `{name}` → `RemoteStorageConfig`
- `save_profile` `{name, config}` → `{ok:true}`
- `delete_profile` `{name}` → `{ok:true}`
- `set_active_profile` `{name}` → `BootstrapState`
- `reset_user_config` `{confirm}` → empty profiles `BootstrapState`
- `update_proxy_settings` → global proxy only
- `list_buckets` `{config}` → live remote buckets (not stored)

**Custom list order (implemented 2026-07-11)**
- Meta keys in `config.db`:
  - `profile_order` JSON `[]string` profile names
  - `bucket_order` JSON `[]string` entry ids (`profileName::bucketName`)
- Go helpers: `go/config/list_order.go` (`ReorderProfiles`, `ReorderBuckets`, `ListBucketOrder`, apply/append/remove helpers).
- `listProfilesFromDB` uses `profile_order` when present; otherwise legacy sort (active → `default` → name).
- Bridge/webapi methods: `reorder_profiles` `{names}`, `reorder_buckets` `{ids}`, `list_bucket_order`.
- Flutter gateway: `reorderProfiles` / `reorderBuckets` / `listBucketOrder`.
- Account list UI: `CloudStorageAccountList` list mode `ReorderableListView` + `CloudStoragePage._reorderAccounts` (optimistic local order).
- Bootstrap soft refresh: `lib/pages/app_bootstrap_page.dart` keeps `_session` mounted and reloads bootstrap state in place; reorder no longer triggers full-screen loading shell.
- Bucket list UI: `FileManagerBucketBrowser` list mode reorder + `file_manager_page_bucket_view._reorderBuckets`; load path `file_manager_page_sources._loadBucketEntries` applies `listBucketOrder` (fallback: profile order then bucket name).
- Grid view / search / trash home do not enable drag reorder.
- Save profile appends new names to existing `profile_order`; delete profile strips profile + its `profile::` bucket ids; reset clears both orders.

#### Account list UI (exploration 2026-07-11)

- `lib/pages/cloud_storage_page.dart` — Account management page. Passes `widget.state.profiles` into list; CRUD via `api.saveProfile` / `deleteProfile` / editor modal; `onRefresh` reloads bootstrap.
- `lib/widgets/cloud_storage_account_list.dart` — Presentational list/grid only. Renders `List<ProfileInfo>` in given order:
  - table: `ListView.builder` (~L77–96)
  - grid: `GridView.builder` (~L47–64)
  - row title: `displayName` else `name`; no client sort.
  - account glyph is always `cloud`; protocol remains explicit in the type label. The sidebar uses the separate `cloudCog` glyph to denote the account-management function rather than any individual protocol.
- `lib/models/bootstrap_state.dart` — Dart `ProfileInfo` + `BootstrapState.profiles`.
- `lib/pages/app_bootstrap_page.dart` — Loads `api.loadBootstrapState()`; `onRefresh` reloads session so account list order comes from bridge list sort.
- `lib/pages/main_layout_page.dart` — Sidebar `storage` → `CloudStoragePage(state.profiles)`.
- No dedicated account `ChangeNotifier`; account list state is bootstrap `profiles`.

#### Bucket list UI (exploration 2026-07-11)

- `lib/pages/file_manager_page.dart` — Owns `_buckets`; `_loadBuckets()` → `_loadBucketEntries()`.
- `lib/pages/file_manager_page_sources.dart` — Multi-account aggregation:
  1. for each `widget.profiles` → `loadProfile` + `listBuckets(config)`
  2. wrap as `FileManagerBucketEntry` (`id = profileName::bucket.name`)
  3. apply persisted `listBucketOrder()` when present; otherwise keep account/profile order and sort bucket names within each account
- `lib/pages/file_manager_page_bucket_view.dart` — Builds `FileManagerBucketBrowser` from `_filteredBuckets`.
- `lib/pages/file_manager_page_state.dart` — `_filteredBuckets` filters by search only; preserves load order.
- `lib/widgets/file_manager_bucket_browser.dart` — Presentational list/grid:
  - list: `ListView.builder` (~L189+)
  - grid: `GridView.count` (~L79+)
  - responsive list columns prioritize the action cell: the independent source column collapses below 720px (source remains in the name subtitle), quota collapses below 420px, and actions remain whenever `showActionColumn` is enabled
- `lib/models/file_manager_bucket_entry.dart` / `lib/models/s3_objects.dart` (`BucketInfo`) — UI row models; `BucketInfo` carries optional provider `quotaBytes` / `usedBytes` metadata plus `quotaKnown` (so a real zero-used account is distinguishable from an unsupported query) and has no order field.
- Same aggregation pattern also used by `file_sync_tasks_page_actions.dart` for remote picker buckets.

#### Storage account bucket visibility (implemented 2026-07-20)

- `RemoteStorageConfig.bucketViews` / Go `BucketViews` is a map keyed by provider bucket name. An empty map means dynamic-all and includes buckets created later; a non-empty map is the explicit allowlist. `BucketViewSettings` carries `displayName` and `rootPrefix`; normalization lives in `lib/models/bucket_view_settings.dart` and `go/config/config_bucket_views.go`.
- `lib/widgets/cloud_storage_account_dialog.dart` now runs protocol → connection/OAuth → bucket visibility. `cloud_storage_account_dialog_bucket_loading.dart` validates the draft and fetches live buckets, while `cloud_storage_account_dialog_bucket_visibility.dart` owns selection, alias input, and the shared `remote_directory_picker_dialog.dart` entry. Baidu OAuth retains the authorized draft and advances instead of saving immediately. `account_editor_presenter.dart` and `account_editor_window_app.dart` pass the same gateway in modal and debug sub-window modes.
- S3 returns real buckets; WebDAV and Baidu return their existing single synthetic bucket, so all providers use the same selection UI and persistence model. Clearing the final checkbox returns to dynamic-all mode.
- `lib/pages/file_manager_page_sources.dart` and `file_sync_tasks_page_actions.dart` filter provider results only when the map is non-empty. `FileManagerBucketEntry` keeps the provider bucket name as its stable operation/id value, exposes the alias through `label`, and builds an effective config whose account prefix and selected bucket prefix are joined. Bucket list, breadcrumb, remote picker, and mount messaging use the alias without changing backend identifiers.
- `go/storage/scoped_backend.go` is the shared object-path boundary. `storage.ForConfig` wraps S3/WebDAV/Baidu when `RootPrefix` is non-empty; list/head results are translated back to view-relative keys, and listing, mutations, transfers, trash, streaming, directory access, and partial uploads translate outgoing keys. Visibility (which buckets appear in the UI) is intentionally not enforced here — it lives in the higher-level loaders because `ListBuckets` must still return the real provider set for sync, mount, quota, and the directory picker. `ListTrashPage` allocates a fresh slice before filtering (provider trash pages may share backing memory) and only surfaces entries whose provider `OriginalKey` lives under the view root, rewriting it to a view-relative path; `RestoreTrashItem`/`DeleteTrashItem` delegate the original `trashID` directly because provider trash metadata already records the fully scoped `OriginalKey`. `storage.IsScoped` exposes whether a backend is wrapped so callers can assert ownership of prefix translation.
- Mount layer ownership: `go/mount/bucket_access.go` clears `RootPrefix` before calling `storage.ForConfig` and performs all prefix translation itself via `remotePrefix`/`remoteKey`/`virtualKey`. Any other path would double-prefix provider keys because both the mount layer and `scopedBackend` apply the root. `bucket_access_root_prefix_test.go` asserts the constructed backend is unscoped.
- Tests: `go/config/config_bucket_views_test.go`, `go/storage/scoped_backend_test.go`, `go/mount/bucket_access_root_prefix_test.go`, and `test/bucket_quota_test.dart` cover normalization, dynamic-all versus allowlist JSON, virtual path translation, scoped trash filtering without mutating provider state, and the mount unscoped-backend contract.

#### Bucket custom quota (implemented 2026-07-18)

- `go/config/config.go` adds `BucketSettings.CustomQuotaBytes` (`customQuotaBytes` JSON / `custom_quota_bytes` TOML). `go/config/config_bucket_settings.go` normalizes negative values to zero and returns the override through `BucketSettingsFor`; zero means unset. Bucket-specific normalization was split out of `config.go` to keep the main file below the hand-written 500-line limit.
- `lib/models/bucket_settings.dart` mirrors the optional field, accepts camelCase and snake_case JSON, omits zero from serialized output, and clamps legacy negative values to zero. `RemoteStorageConfig.bucketSettingsFor` carries it into resolved bucket settings; `lib/models/remote_storage_config_enums.dart` now owns the imported/re-exported persistence enums so the main config model stays below 500 lines.
- `lib/widgets/bucket_settings_dialog.dart` edits the quota in GB, accepts decimals, converts to bytes, and treats zero/blank as unset. The value is informational only and does not enforce an upload limit.
- `lib/widgets/file_manager_bucket_browser.dart` uses the existing `FileListTile` size column as a responsive “已用 / 配额” column in list mode; `lib/widgets/file_manager_bucket_quota.dart` owns total resolution and list formatting. Bucket cards intentionally omit capacity text/progress to keep the fixed Finder-style tile within its height; list mode prefers `CustomQuotaBytes` for the total and falls back to `BucketInfo.quotaBytes`: `quotaKnown` fills the track from real usage, total-only backends such as generic S3 show a neutral empty track labeled `用量未知 · total`, and buckets without any total show `未设置额度` plus the same empty track. `FileListTile.sizeWidget` allows the richer capacity cell without changing other list rows. `lib/utils/transfer_format.dart` formats TB values as well as smaller units.
- `go/mount/mount_capacity.go` resolves mounted capacity with bucket `CustomQuotaBytes` first, then optional provider quota, then a backend fallback. WinFsp passes its global `windowsWinFspCapacityGB` only as the final fallback; Linux FUSE has no fallback and preserves its previous zeroed Statfs when quota is unset.
- `go/mount/backend_windows_winfsp_cgo.go` snapshots resolved capacity and provider used bytes when a session starts; `winfsp_fs_windows.go` reports total/free/available blocks. `go/mount/linux_fuse_nodes.go` implements `NodeStatfser` and reports the same bucket quota. Both use 4096-byte blocks; WinFsp subtracts provider-used bytes when available, otherwise free mirrors total. Changing quota requires a remount.
- `go/config/config.go` / `go/config/config_bucket_settings.go` / `lib/models/bucket_settings.dart` / `lib/models/remote_storage_config.dart` / `lib/widgets/bucket_settings_dialog.dart` - BucketSettings.WinFspVolumeLabel persists the optional label across Go and Flutter JSON models. The dialog limits it to 32 characters; a saved override flows through BucketSettingsFor into winFspVolumeLabel for the next WinFsp mount.
- Cloud Files and WebDAV mounts do not use an app-owned Statfs callback, so their reported capacity is controlled by the host filesystem/client and is not changed by custom quota.
- `go/mount/mount_capacity.go` resolves mounted capacity with bucket `CustomQuotaBytes` first and a backend fallback second. WinFsp passes its global `windowsWinFspCapacityGB` as fallback; Linux FUSE has no fallback and preserves its previous zeroed Statfs when quota is unset.
- `go/mount/backend_windows_winfsp_cgo.go` snapshots the resolved capacity when a session starts; `winfsp_fs_windows.go` reports it as total/free/available blocks. `go/mount/linux_fuse_nodes.go` implements `NodeStatfser` and reports the same bucket quota. Both use 4096-byte blocks and mirror total into free/available because remote usage is unknown; changing quota requires a remount.
- Windows Cloud Files and Windows WebDAV mounts do not use an app-owned Statfs callback, so their reported capacity is controlled by the host filesystem/client. macOS loopback WebDAV is the exception: RFC 4331 dead properties from `go/mount/webdav_quota.go` let `webdavfs` project cached provider/custom quota into `df`.
- `test/bucket_quota_test.dart` covers legacy/current JSON, decimal input, invalid input, and list values. `go/config/config_bucket_settings_test.go`, `go/mount/mount_capacity_test.go`, `go/mount/winfsp_statfs_windows_test.go`, and the Linux Statfs test cover normalization, precedence, and filesystem block output.

#### Remote quota discovery (implemented 2026-07-18)

- Generic S3 `ListBuckets` does not provide quota or usage. A reliable S3 quota requires a provider-specific management API; recursively summing objects is expensive, incomplete under pagination/versioning, and is not a quota.
- `go/s3.BucketInfo` is the shared bridge payload and carries optional `quotaBytes` / `usedBytes`. Flutter `BucketInfo.fromJson` mirrors both values; the list only renders total quota today, while used bytes are retained for future capacity UI.
- `go/storage/webdav_quota.go` performs a depth-0 RFC 4331 PROPFIND against the mapped root, parses `DAV:quota-used-bytes` and `DAV:quota-available-bytes`, and reports total as used + available through the optional `BucketQuotaProvider` path. `ListBuckets` returns the synthetic root immediately; HTTP/XML/missing-property failures are recorded through central `logging.Errorf`.
- `bridge/dispatch.go` logs the portable `list_buckets` bridge entry before routing to `storage.ForConfig`; `bridge/dispatch_bucket_quota.go` exposes the second-stage `get_bucket_quota` bridge method. `go/storage/baidu_pan_quota.go` logs quota request start/success at INFO and failures through central `logging.Errorf`. It calls the pinned xpan client's account-level `Client.Quota()` with `checkfree=1` and `checkexpire=1`, maps `total` / `used` into `BucketInfo`, and returns quota errors without blocking the initial bucket list. Token refresh and per-account proxy behavior continue through `withBaiduPanClient`; `go/storage/baidu_pan_sdk.go` treats Baidu's quota-specific `用户未登录` response as an expired authentication state so the first quota request refreshes OAuth credentials and retries instead of depending on a later file-list request. Refreshed credentials are matched back to the actual stored Baidu profile (which may not be the active account) instead of only attempting to overwrite the active profile. Refresh failures, persistence failures, and failures from the retried provider call are logged separately at error level rather than being collapsed into the original authentication error.
- `lib/services/remote_storage_gateway.dart` requires `getBucketQuota` so the second-stage request cannot be skipped by a failed runtime capability check; desktop implements it in `remote_storage_api_desktop_storage.dart` and Web forwards it through `remote_storage_api_web_transfers.dart` / `go/webapi/invoke.go`. `file_manager_page.dart` owns a page-session quota cache; `file_manager_page_bucket_loading.dart` reapplies cached values and awaits `file_manager_page_quota.dart` provider requests before the single list `setState`, avoiding the old post-frame row rebuild that broke hover. Successful quota results are cached by profile/bucket for 5 minutes. `go/storage/quota_cache.go` mirrors successful `GetBucketQuota` results in a process-wide 5-minute cache keyed by a SHA-256 of quota-relevant connection identity plus bucket: protocol/provider, endpoint, region, credentials, FTP port/anonymous mode, path-style/JWan mode, and proxy settings. It deliberately excludes display, cache, RootPrefix, mount, writeback, and bucket-presentation settings, so the bucket-list config and mount config reuse the same quota while endpoint/credential changes remain isolated. Hit/miss logs expose only a short hash prefix. `go/storage/quota_cache_test.go` covers account/bucket isolation, presentation-setting reuse, endpoint isolation, and expiry; `go/mount/webdav_quota_test.go` proves a new access reuses the storage result without a second provider request; provider tests cover protocol mapping, and `test/widget_test.dart` verifies UI reuse.
- Future remote quota should remain optional and distinguish its source from the current custom display value. Unsupported providers must stay unknown rather than reporting zero, and quota failures must not fail bucket loading.

#### Reorder patterns

- Account/bucket **list** mode: Flutter `ReorderableListView.builder` + `ReorderableDragStartListener` (custom grip handle; no default trailing handles).
- Canonical: `lib/widgets/cloud_storage_account_list.dart`, `lib/widgets/file_manager_bucket_browser.dart`.
- Persistence via Go meta order APIs above; not local-only.
- Other drag uses remain unrelated: `file_manager_drag_selection.dart` (marquee), local file drop upload.



### Feature: Transfer Queue (通用传输队列兼容层)

`TransferQueue` is the execution and local-producer compatibility facade for manual uploads/downloads and Dart-only work. It mirrors lifecycle changes into `RemoteTaskStore`; no visible task page, sidebar, sync card, preview, batch dialog, or update status reads this queue as its display source. Go journal/runtime work is projected directly into the same `RemoteTask` model.

#### Key files

- `lib/state/transfer_queue.dart` — Core `TransferQueue` singleton. Polling (not streaming): `pollNow()` calls `api.listTransferJobs()`, `refreshFromSnapshots` merges `TransferSnapshot` fields into `TransferTask` (`bytesCompleted`/`totalBytes`/`itemsCompleted`/`totalItems`/`speedBytes`/…). `_ensurePolling` picks `_activePollInterval` = 700 ms while `hasRunning`, `_idlePollInterval` = 2 s otherwise.
- `lib/state/transfer_queue_lifecycle.dart` — API binding, task creation, and terminal success/failure/cancel transitions; successful completion normalizes both byte and item progress.
- `lib/state/transfer_task.dart` — `TransferTask` model; `TransferKind { upload, download, copy, move, delete, appUpdate }`; `progress` getter = `bytesCompleted/totalBytes`, or 0 when `totalBytes<=0`. `transfer_queue_lifecycle.dart` creates pending local tasks optimistically, while `refreshFromSnapshots` overwrites progress fields from Go snapshots — Go remains authoritative during active work.
- `lib/models/transfer_job.dart` — `TransferSnapshot.fromJson` mirror of Go JSON.
- `go/s3/transfer_monitor.go` — `TransferSnapshot` struct (:15) JSON: `id,type,bucket,key,localPath,targetPath,status,statusDetail,createdAt,bytesCompleted,totalBytes,itemsCompleted,totalItems,currentFileKey,currentFileBytesCompleted,currentFileTotalBytes,speedBytes,error`. `startTransfer` (:54) sets status running + TotalBytes (default StatusDetail "uploading"); `advanceTransfer` (:246) adds bytes + computes `speedBytes = completed/elapsed`; also `AddTransferTotal`/`AddTransferItems`/`AdvanceTransferItems`, `finishTransfer` (:263; when TotalBytes>0 sets completed=total). Exposed via bridge `list_transfer_jobs` (`bridge/dispatch.go:98`, handler :394 -> `s3ops.ListTransferSnapshots()` recent-first :330) and `go/webapi/invoke.go:316`.
- `lib/state/transfer_queue_*.dart` — Split concerns: metrics, sync, local progress, foreground, storage, directory children.
- `lib/pages/transfers_page.dart` / `lib/pages/transfers_page_remote.dart` — Transfers page showing effective `RemoteTask` operations grouped by active/waiting/attention/history; raw journal events and physical phases expand from `RemoteTaskRow`. The legacy `TransferTaskRow` implementation remains unreferenced compatibility code and is not a display path.
- `lib/widgets/batch_task_progress_dialog.dart` — Modal progress for foreground batches (upload/download/delete). Summary `LinearProgressIndicator(value: progress)` (:232-242) with `progress = completedBytes/totalBytes` when any task has `totalBytes>0`, else `1.0` when all finished, else `null` = indeterminate (:44-68). Per-row determinate bar only when `currentFileTotalBytes>0` (:366-382). `_modeForTasks` returns `BatchTaskProgressMode.delete` when all tasks are deletes (:152); copy/icon in `lib/widgets/batch_task_progress_mode.dart`.

#### Gotchas

- A task with `totalBytes==0` renders indeterminate (modal) or plain "删除中" text (transfers row); setting `totalBytes>0` via `startTransfer`/`AddTransferTotal` + `advanceTransfer` immediately turns the modal summary bar and transfers subtitle into real percentage/bytes — no UI change needed.
- Successful local completion must normalize both progress dimensions: Go `finishTransfer` already sets `BytesCompleted = TotalBytes` and `ItemsCompleted = TotalItems` before the bridge returns, and Flutter `TransferQueue.markTaskDone` mirrors that invariant immediately. Without the item normalization, the last-polled count (for example `10 / 20`) could remain visible after the status changed to `done` until idle polling refreshed the authoritative snapshot about 2 seconds later.

### Feature: macOS WebDAV Local-First Writes

macOS mounts the loopback WebDAV server through `webdavfs_agent`. File content is meant to land in a local staging/cache file first, then enter the shared delayed-writeback queue; the Finder-facing `PUT` must not wait for the upstream provider upload.

#### Key files and data flow

- `go/mount/webdav_http_handler.go` / `webdav_fs.go` - The loopback `x/net/webdav.Handler` delegates file opens to `webDAVFS`. Content-write flags select `newWritableWebDAVFile`; reads select the range-capable readable handle. An exact `os.O_RDWR` open is the `x/net/webdav` metadata probe used by `PROPPATCH` and is routed to the metadata-only handle.
- `go/mount/webdav_metadata_file.go` / `webdav_metadata_file_test.go` - The metadata-only handle supports `Stat` without staging or scheduling object content and deliberately omits `webdav.DeadPropsHolder`, preserving the previous forbidden-property response. Tests assert that metadata opens do not queue writeback while truncating `PUT`-style opens remain local-first.
- `go/mount/webdav_file.go` - A writable handle uses `<runtime>/mounts/<bucket>/staging/<hashed-key>` while the request body is arriving. `Close` moves that file into `<cache>/mounts/<bucket>/<hashed-key>`, calls `registerLocalWrite`, then `scheduleUpload`.
- `go/mount/webdav_quota.go` / `webdav_quota_test.go` / `bucket_access.go` / `go/storage/quota_cache.go` - Root read handles expose RFC 4331 `quota-available-bytes` and `quota-used-bytes` through `webdav.DeadPropsHolder`, while exact-`O_RDWR` metadata handles still omit that interface. `newBucketAccess` seeds the first response from `storage.CachedBucketQuotaForMount`; fresh and expired entries for the same account/bucket are both usable, but an expired entry is immediately refreshed in the background. It prefers `BucketSettings.CustomQuotaBytes`, retains provider used bytes, clamps used to total, and preserves the last known capacity through transient refresh failures. There is no synchronous quota request in macOS mount startup. A true cache miss stays non-blocking and starts the existing 30-second in-session background refresh. Tests cover fresh/stale cache reads, seeded first-request quota, failed/successful background refresh, non-blocking unknown quota, and custom-total precedence.
- `go/mount/macos_mount.go` / `macos_mount_test.go` / `macos_command.go` / `macos_command_test.go` / `system_mounts.go` - Default mounts use AppleScript and custom paths use `mount_webdav`. While either command is running, `runLoggedCommandUntilSuccess` polls the system WebDAV mount table and returns as soon as the requested path or URL-derived decoded volume name (including numeric suffixes) appears, canceling the still-running command instead of waiting for its 20-second timeout. Finder `open` is asynchronous and guarded by a per-path single-flight gate because a process blocked in a WebDAV filesystem call may ignore `CommandContext` cancellation for much longer than five seconds. Stop order is system unmount first, local WebDAV/access shutdown second; an unmount failure keeps the server and session alive for retry. Tests cover early mount confirmation, Finder-open coalescing, decoded/requested path matching, fallback order, and server survival after an unmount error.
- `go/mount/macos_mount.go` `runMacOSFinderOpen` - `openMountPath` no longer uses `runLoggedCommand`/`CombinedOutput`. macOS LaunchServices (launched by `open`) inherits the stdout/stderr pipes, and Finder holds them open for ~90s during the first `statfs` on a freshly mounted WebDAV volume; `CommandContext` + `WaitDelay` does not reliably reclaim them because the descendant is launched via XPC, not fork. The new implementation detaches the process (Stdout/Stderr → `os.DevNull`, `Setpgid: true`), calls `Start()` + a bounded `Wait()` goroutine with a 3s ceiling, and logs "dispatched" if `open` is still running. The per-path single-flight gate (`mountOpenGate`) still prevents duplicate opens. Never put `CombinedOutput` back on `open` for a mounted WebDAV path. Tests must replace the package-level `launchFinder` hook instead of passing `t.TempDir()` to the real `openMountPath`, otherwise running `go test ./go/mount` genuinely opens Finder on the macOS test temp directory.
- `go/mount/bucket_access_reads.go` / `bucket_cache.go` / `bucket_access_stat_cache_test.go` - `statPath` treats a fresh full directory listing as authoritative for both hits and misses, and treats an absent child of a mount-created local directory as locally missing. Finder probes every destination before `PUT`; these negative-cache paths prevent a many-small-file copy from performing one synchronous SFTP `HeadObject`/connection handshake per file. Expired or unknown directories still fall through to the provider so remote overwrites remain discoverable. `ensureLocalFile` additionally serves metadata pending files from staged chunks: it validates an inode+generation cache stamp, materializes chunks into the ordinary cache file under a path-keyed singleflight, and keeps an in-progress mount-local write marker authoritative over a newer page generation. `readRemoteRange` answers pending ranges from `ReadPendingRange` before any provider call.
- `go/mount/bucket_access_writes.go` / `writeback_queue.go` / `writeback_store.go` - `scheduleUpload` persists a pending record, publishes `sync_wait`, resets that file's configured quiet timer (default 10 seconds), then uploads in the background worker pool. Earlier files may upload while Finder continues writing later files; this is intentional asynchronous behavior, not a foreground dependency. A successful remote upload clears the local overlay marker and persisted record; the cache file itself remains available for reads.
- `go/storage/tracked_upload.go` / `ftp_backend_io.go` / `sftp_backend_io.go` / `webdav_backend_upload.go` - FTP, SFTP, and WebDAV provider uploads share one context-aware reader that starts the queued transfer, advances copied bytes, honors cancellation, and finishes success/failure. Protocol tests in `ftp_backend_test.go`, `sftp_backend_test.go`, and `webdav_upload_tracking_test.go` assert successful mount-style `UploadFile` calls finish at `14/14` instead of staying in `sync_wait`. SFTP still establishes a fresh SSH/SFTP connection per operation, and writeback performs a separate `HeadObject`, so handshake latency and server connection limits continue to affect many-small-file throughput without changing local-first foreground semantics.
- `go/storage/sftp_backend.go` implements both `MountPrefetchPolicy=false` and `MountRemotePollingPolicy=false`; `go/storage/scoped_backend.go` forwards both policies through RootPrefix wrapping. Finder root listing therefore does not launch speculative reads of up to eight child directories, and Finder/Spotlight recursive `PROPFIND` paths do not become a repeated P0 polling stream of up to 12 fresh SSH/SFTP connections every five seconds. Explicit directory navigation remains on-demand. TCP dial uses `DialContext`, the SSH handshake inherits the request deadline, and cancellation closes the socket, so reads cannot silently exceed the mount request timeout during connect/handshake.
- `go/s3/transfer_monitor.go` / `lib/state/transfer_task.dart` - Mount writeback first registers a `pending` task with `sync_wait`. Every current provider upload implementation consumes the task ID and advances/finalizes the shared monitor, so successful writeback leaves `sync_wait` immediately instead of waiting for the monitor's 10-minute pruning window.
- `go/mount/webdav_logging.go` - Successful `PUT`, `COPY`, and `PROPPATCH` requests are not currently logged; ordinary logs therefore cannot time the foreground write path. `writeback` enqueue/ready/flush lines and the staging/cache/writeback directories are the reliable current evidence.

#### Finder PROPPATCH handling (fixed 2026-07-30)

Finder sends `PROPPATCH` requests for creation dates and other dead properties. `golang.org/x/net/webdav` opens the target with exactly `os.O_RDWR` before checking whether the returned handle implements `DeadPropsHolder`. `webDAVFS.OpenFile` must keep this exact flag routed to `metadataWebDAVFile`; sending it through `newWritableWebDAVFile` would seed a cold target by downloading it and schedule redundant writeback on `Close` even when no `Write` occurred. Normal `PUT` opens include content-write flags such as `O_CREATE`/`O_TRUNC` and still use staging, cache registration, and delayed writeback.

The metadata handle intentionally does not implement `DeadPropsHolder`, so unsupported Finder properties retain their previous forbidden response without touching object content. Do not merge exact `O_RDWR` back into the generic writable branch; merely shortening `writeback_quiet_seconds` does not prevent redundant transfers, and increasing writeback concurrency can worsen SFTP handshake resets.

When diagnosing an SFTP row stuck in `sync_wait`, inspect both `<runtime>/mounts/<bucket>/writeback/queue-*.json` and the remote object. An empty persisted map means the writeback layer no longer has recoverable pending work. Provider upload implementations that accept a task ID must explicitly start, advance, and finish that shared transfer task; pruning a stale snapshot sooner only hides lifecycle bugs.

#### Provider impact matrix (audited 2026-07-30)

- The Finder `PROPPATCH` misrouting was above the storage-provider boundary in `webDAVFS`, so before the metadata-only handle fix it could trigger redundant content work for every macOS mount upstream: S3, WebDAV, Baidu Pan, FTP, and SFTP. The exact-`O_RDWR` routing fix applies to all of them.
- The active-directory P0 poller is provider-policy controlled. SFTP disables it because each refresh establishes a fresh SSH/SFTP session and recursive macOS metadata crawls are indistinguishable from user directory opens at the WebDAV layer. S3, FTP, WebDAV, and Baidu Pan retain the bounded poller for cross-client change discovery; if a provider shows the same amplification, add an explicit policy after auditing its connection/retry behavior rather than changing local-first writeback semantics.
- On macOS 15, an instrumented mount can return correct quota XML from the loopback Depth-0 `PROPFIND` in under 1 ms while the first `statfs`/`df` remains blocked or reports `0/0` for roughly 90 seconds; an immediate second query then reports the correct capacity. This is delayed state publication inside Apple's `webdavfs_agent`, not a synchronous upstream quota/list call. Waiting for `statfs`, pre-refreshing the root, disabling HTTP keep-alive, removing AppleScript `POSIX path` coercion, and leaving `osascript` running did not change it and were reverted. Do not put any of those waits back on the mount completion path.
- During local macOS validation, do not run `/Applications/云卷.app` and the `make run` debug build concurrently against the same SFTP account. The older process keeps its own mount/poller sessions alive and can roughly double connection pressure; in the 2026-07-30 reproduction, terminating the installed copy reduced an SFTP root list from about 90 seconds to 0.45–0.75 seconds. The current debug build mounted in 0.4–0.7 seconds and Finder `open` completed in about 0.2 seconds with no deep `[mount/poll]` refreshes.
- S3 `UploadFile` / `UploadReader` own the supplied task ID in `go/s3/upload_resume.go` and `go/s3/http_stream.go`; both start, advance, and finish the transfer monitor entry.
- Baidu Pan owns the task lifecycle in `baidu_pan_backend_io.go`, including byte progress and terminal status.
- FTP, SFTP, and WebDAV-upstream `UploadFile` / `UploadReader` use `runTrackedUpload` in `tracked_upload.go`; the wrapper owns start/advance/finish and provider closures own only the actual store/PUT call. Keep new backends on that contract instead of shortening snapshot retention.

#### macOS mount-success probe must match the source URL, not the path name (fixed 2026-08-01)

- `go/mount/system_mounts.go` parses macOS `mount -t webdav` rows via `parseMountEntry`, which preserves **both** the source URL (`http://127.0.0.1:<random-port>/<scope>/`) and the on-disk path into a `mountEntry`. `parseMountPoint`/`parseMountPaths` remain as path-only thin wrappers for the unmount/cleanup callers that do not care about the source.
- `go/mount/macos_mount.go` `findMountedWebDAVPath`/`probeMountedWebDAVPath`/`recoverMountedWebDAVPath` require the row's source URL to equal `serverURL` after `normalizeServerURL` (lowercased scheme/host, trailing slash on path). A row with the same display name but a different port — a stale volume, a different process's mount, or the directory created by the requested-path branch's `MkdirAll` — is rejected.
- **Do not** relax this back to path-name-only matching. The earlier `0126a09b` "finish startup promptly" optimization polled the mount table and returned as soon as any path matched; because `parseMountPoint` discarded the source URL, a residual same-name `/Volumes/云卷-<bucket>` (or the `MkdirAll`-created request directory itself) satisfied the probe, the live `mount_webdav` was canceled, and the UI reported "mounted" while Finder showed nothing. Clicking **open** then blocked indefinitely on a path that was never a real WebDAV volume. SFTP surfaced this first because its high first-access latency and disabled prefetch/polling made the name-collision shortcut win the race most often.
- The regression anchors live in `go/mount/macos_mount_test.go` (`TestFindMountedWebDAVPathRejectsSameNameDifferentPort`, `TestFindMountedWebDAVPathRejectsPathMatchWithoutURL`) and `go/mount/system_mounts_test.go` (`TestParseMountEntryExtractsSourceURLAndPath`). Keep them green.
- `prewarmWebDAVMount` runs `os.Stat`/`os.ReadDir` through `boundedStat`/`boundedReadDir` (30s ceiling via `prewarmStatTimeout`). Those syscalls have no context parameter and cannot be interrupted once blocked inside `webdavfs_agent`, so a truly wedged webdavfs leaves one leaked syscall goroutine behind; the bound guarantees `prewarmWebDAVMount` itself returns within the timeout and never blocks `start()`/`stop()`. Do not remove the bound or claim the underlying call is cancellable.

#### macOS mount must use synchronous mount_webdav, never osascript (fixed 2026-08-01)

- `go/mount/macos_mount.go` `mountWebDAV` now always mounts at an explicit resolved path via the synchronous `/sbin/mount_webdav` command. `session.start()` passes `s.mountPath` (already resolved by `macOSWebDAVBackend.Initialize` to either the caller's path or the default `/Volumes/云卷-<bucket>`), not the raw `s.requestedPath`.
- The `osascript "mount volume"` branch and `appleScriptStringLiteral` have been **removed entirely**. `osascript "mount volume"` is fire-and-forget: it registers the volume in the kernel and returns immediately, while `webdavfs_agent` finishes its ~90s handshake asynchronously. The previous code returned "mounted" from a stale mount-table entry before the volume was usable, and canceling the still-running osascript could interrupt the handshake — leaving Finder unable to see or open the volume and `os.Stat` blocking for 30s+.
- `/sbin/mount_webdav` is synchronous: when it returns (or when the probe confirms the volume in the mount table matching our exact source URL), the volume is actually usable. The `runLoggedCommandUntilSuccess` probe still short-circuits early once the volume is confirmed, but even without a probe hit the command's own synchronous return is reliable.
- **Do not** reintroduce an `osascript`/`mount volume` path or route an empty `requestedPath` to a fire-and-forget mount. If a caller needs a custom mount point it must be resolved to a concrete path before `mountWebDAV`. The regression anchor is `TestMountWebDAVRejectsEmptyMountPath` in `go/mount/macos_mount_test.go`.

### Feature: Multi-Account Bucket Loading Resilience (桶加载并发/超时/去重/负缓存)

桌面端加载存储桶列表必须并发、按账号隔离、带超时、去重、负缓存——一个不可达上游不能阻塞其它账号、不能重复拨号、不能让整页卡死。

#### Key files

- `lib/services/bucket_source_service.dart` — `BucketSourceService.loadEntriesWithFailures` now loads profiles and lists buckets **concurrently** via `Future.wait`, with per-account try/catch isolation (`_loadSource` / `_listBucketsForSource` helpers + `_SourceLoadOutcome` / `_BucketListingOutcome`). Each `loadProfile`/`listBuckets` is wrapped in `.timeout(_perAccountTimeout = 40s)`. A failing or stalled account surfaces in `failures` (driving the existing "重新配置" error bar) instead of blocking healthy accounts. Profile order is preserved for the deterministic fallback sort. `loadEntriesWithFailures`/`loadEntries` carry an optional `force` flag.
- `bridge/dispatch.go` — `listBuckets` wraps the call in `context.WithTimeout(context.Background(), bridgeListBucketsTimeout = 30s)` and routes it through `storageops.ListBucketsDedup` (singleflight + negative cache). `listBucketsArgs` carries an optional `force` flag.
- `go/storage/list_buckets_cache.go` — `ListBucketsDedup(ctx, cfg, listFn, force)`: singleflight collapses N concurrent callers for the same connection identity into one upstream dial; a 20s per-account negative cache (`listBucketsNegativeCacheTTL`) returns the previous failure immediately so a known-bad account does not re-dial on every page load; `force: true` bypasses the negative cache (used by the user's explicit refresh) and a success clears the stale entry. Keyed by `bucketListIdentityKey` (connection identity, account-scoped).
- `go/s3/buckets.go` — `bucketListTimeout = 8s` (down from 15s) so a single ListBuckets fails fast before the negative cache records it.
- `go/s3/failover_pool.go` — S3 client construction's JWanFS gateway detection (`IsJWanFSGateway`) runs under `jwanfsDetectionTimeout = 10s`.
- `go/jwanfs/detect.go` / `go/jwanfs/client.go` — `NewClient`'s initial `balancer.Refresh` runs under `gatewayRefreshTimeout = 10s`; failure falls back to direct connect as before.
- `lib/services/remote_storage_gateway.dart` / `remote_storage_api_desktop_storage.dart` / `remote_storage_api_web_transfers.dart` — `listBuckets(config, {force = false})`; desktop passes `force` through to bridge `list_buckets` args.
- `lib/pages/file_manager_page.dart` / `file_manager_page_bucket_loading.dart` / `file_manager_page_sources.dart` — `_loadBuckets({force})` / `_loadBucketEntries({force})`; the user's explicit "返回桶列表" navigation (`onOpenBucketList`) and the error-view "重试" button pass `force: true`. Automatic reloads (startup, post-mount, post-reorder) stay non-forced so they reuse the negative cache.

#### Gotchas (binding)

- **TCP dial timeout (binding — root cause of the 2026-08-01 "等超时" complaint).** Every HTTP transport in the app (`go/config/proxy.go` `ProxyTransport` via the process-wide `boundedDialer`, `go/s3/client.go` `newSingleEndpointClient` which now always uses `ProxyHTTPClient`, and `go/jwanfs/http_client.go` `DefaultHTTPClient`) applies a 3s `DialContext` timeout. Without it, an endpoint that **drops** packets (powered-off gateway, firewall DROP, unroutable IP — NOT a RST "connection refused") makes the OS retry SYN for ~75s on macOS, and only the per-request context (8s `bucketListTimeout`) can interrupt it. Measured 2026-08-01: default dialer = 75.011s, 3s dialer = 3.000s against a dropped endpoint. Do **not** remove the `DialContext` from any of these transports, and do not let the S3 client fall back to the AWS SDK default HTTP client (it has no dial timeout). A "connection refused" (RST) still returns instantly; the dial timeout only bounds the DROP case.
- The singleflight + negative cache live in **Go** (`ListBucketsDedup`), keyed on connection identity. The 3 concurrent `list_buckets s3 test` calls observed in the 2026-08-01 reproduction (file manager + global trash + quota prefetch) now share ONE upstream dial instead of each waiting 8s+ independently.
- A failure is cached for `listBucketsNegativeCacheTTL = 20s`. Within that window, non-forced reloads return the cached error instantly (no dial). The user's explicit refresh (`force: true`) **must** bypass this so a fixed account can be retried — keep `force` wired to the two user-initiated paths only, not to automatic reloads, or the negative cache becomes useless.
- jwanfs `IsJWanFSGateway` and `NewClient`'s `balancer.Refresh` run **during S3 client construction**, before any per-request context exists. They previously used `context.Background()`, so an unreachable endpoint stalled on the OS-level TCP timeout (~1-2 minutes). Always bound construction-phase probes explicitly; the bridge/req timeouts only bound what runs inside `ListBuckets` itself.
- `bridge list_buckets` uses `context.Background()` (no inbound HTTP request to inherit a deadline from), so it **must** establish its own timeout — without it a single unreachable S3 account hangs the bridge call indefinitely.
- Flutter `_perAccountTimeout` (40s) is intentionally longer than the Go `bucketListTimeout` (8s) + construction (10s) so the backend's descriptive error is preferred over a generic Dart `TimeoutException`.
- FTP/SFTP/WebDAV/Baidu `ListBuckets` all return a synthetic bucket immediately without contacting the server, so they cannot hang or be negatively cached in practice; only S3 (and its JWanFS gateway probe) actually dials out during bucket listing.
- The regression anchors are `go/storage/list_buckets_cache_test.go` (singleflight collapse, negative cache fast-fail, force bypass + clear, account isolation), `go/jwanfs/detect_test.go` (construction-phase timeout), and `test/bucket_source_service_test.dart` (Flutter isolation + stall-timeout). Keep them green.

#### Data flow

1. File manager / global-trash page → `BucketSourceService.loadEntriesWithFailures(api, profiles, fallbackConfig, force)`.
2. `loadProfile` for all profiles concurrently → `BucketSource` list + isolated `failures`.
3. `listBuckets` for all sources concurrently → bridge `list_buckets` → `ListBucketsDedup` (singleflight collapses duplicates; negative cache short-circuits recent failures unless `force`) → backend `ListBuckets` (8s S3 / instant synthetic for others).
4. Apply saved bucket order (fallback: profile order then label sort); `failures` drive the existing per-account "重新配置" error bar in the file-manager home view.

### Feature: Mount Cache Sync from External Mutations (挂载缓存外部失效)

文件管理界面的删除/重命名/移动/复制/建目录/上传通过 bridge/webapi 直接改远端对象，绕过 `go/mount`。为了让挂载点（Finder/WebDAV/FUSE）和文件管理列表不显示幽灵文件、不卡"删除中"，所有外部 mutation 在成功后必须同步失效挂载 session 的 `bucketCache`。

#### Key files

- `go/mount/external_invalidation.go` — 导出 API `NotifyExternalDelete`/`NotifyExternalUpload`/`NotifyExternalRename`，委托 `globalManager.notifyExternalMutation(cfg, bucket, callback)`。session 不存在或 cfg 不匹配时 callback 不执行，无挂载场景零开销。
- `go/mount/bucket_access_reads.go` — `bucketAccess.MarkExternalDelete`（`markDeleted` + `invalidatePath`，放 tombstone）、`InvalidateExternalUpload`（`removeLocalPath` + `invalidatePath` + 父目录，清 tombstone/staging）、`InvalidateExternalRename`（= delete old + upload new）。
- `bridge/dispatch.go` — `deleteObject`/`renameObject`/`createDirectory`/`uploadFile`/`uploadDirectory` 成功分支调 `bucketmount.NotifyExternal*`；`parentDirectoryOf`/`joinChildPath` 辅助计算路径。
- `bridge/dispatch_object_transfer.go` — `copyObject` 调 `NotifyExternalUpload(TargetKey)`；`moveObject` 调 `NotifyExternalRename(SourceKey, TargetKey)`。
- `go/webapi/invoke.go` — webapi 同名 mutation 同步接入（`delete_object`/`rename_object`/`copy_object`/`move_object`/`create_directory`），仅在 `err == nil` 时调用。
- `go/mount/external_invalidation_test.go` — 覆盖 delete/upload/rename 对 `listCache`/`objectCache`/`localEntries`/`deletedPaths` 的失效，以及 cfg 不匹配/无 session 时的 no-op。
- `bridge/dispatch_metadata.go` / `dispatch_paging.go` / `go/mount/object_page.go` / `go/mount/object_page_snapshots.go` — 有 `ProfileID` 的桌面页面分页、旧 `list_objects` 和 `head_object` 都走 metadata inode tree，游标是持久目录 revision + nameKey；不会探测挂载会话，也不会生成 `m:<snapshot-id>`。`ListMountedObjectPage` 与 2 分钟快照只为无身份 legacy mount 保留。Web API 仍是 provider-direct 的独立 P2 transport。
- `lib/pages/file_manager_page_object_deletes.dart` — 删除 API 成功后立即从 `_objects`、`_selectedObjectKeys` 和 `_deletingObjectKeys` 移除该 key；批次结束时把成功 key 传给写后刷新，失败 key 恢复成普通可操作行。
- `lib/pages/file_manager_page_object_loading.dart` — `_loadObjects(... suppressObjectKeys:)` 过滤本批次已确认删除、但提供方短暂重新返回的旧 key，并丢弃对应原始页缓存，让后续导航重新请求后端。
- `test/file_manager_delete_state_test.dart` — 回归覆盖“删除成功，但 force-refresh 仍返回旧目录”的场景，确保行和删除标记都收敛。

#### Gotchas

- `InvalidateListCacheForPrefix`（仅清 `listCache`）不足以反映外部变更——`mergeLocalFiles` 会用过期 `localEntries` 把幽灵重新塞回列表，`hiddenByDeleteLocked` 也会用过期 tombstone 隐藏本应显示的对象。外部 mutation 必须用 `NotifyExternal*` 这组完整语义（同时清 `objectCache`/`localFiles`/`localEntries`/`deletedPaths`）。
- 不要只依赖 `_deletingObjectKeys.removeWhere((key) => !visibleKeys.contains(key))` 收敛状态：S3/挂载刷新可能短暂返回旧目录，导致成功任务永久显示“删除中”。删除 API 成功必须主动清 key/移除行，随后的写后刷新再用成功 key 抑制一次陈旧响应。
- `uploadDirectory` 是 `go func()` 异步：启动时先 `NotifyExternalUpload(parentDirectoryOf(Key))` 让父目录可见，goroutine 完成后再 `NotifyExternalUpload(Key, isDir=true)` 刷新目录内容。

#### Data flow

1. 界面操作 → bridge `delete_object` 等 → `storageops.ForConfig(cfg).XxxObject(...)` 改远端。
2. 成功后 bridge 调 `bucketmount.NotifyExternal*(cfg, bucket, path, isDir)` → `globalManager.notifyExternalMutation` → 匹配 session → `bucketAccess.MarkExternalDelete/InvalidateExternalUpload/InvalidateExternalRename`。
3. Flutter 收到删除成功后立即移除行和“删除中”标记；批次 `list_object_page(forceRefresh)` 使用成功 key 过滤一次陈旧响应并丢弃该页缓存。挂载点下一次 `listDirectory` 重新 `fetchDirectory`，由 tombstone/远端结果共同隐藏已删 key。

### Feature: Mount Remote Polling P0

P0 是多客户端挂载变更发现的无服务兜底：它只刷新用户近期打开的目录，远端对象存储仍是唯一的字节和版本权威。

- `go/config/config.go` / `go/config/config_account.go` / `lib/models/remote_storage_config.dart` / `lib/models/remote_storage_config_copy.dart` - `mount_remote_poll_seconds` / `mountRemotePollSeconds` 是 P0 活跃轮询间隔（默认 5 秒，后端规范化到 1-300 秒）；账户辅助方法和 Dart 的不可变 `copyWith` 各自拆出，避免配置模型超过文件行数限制。
- `lib/pages/settings_page.dart` / `lib/pages/settings_page_poll_actions.dart` / `lib/pages/settings_page_sections.dart` / `lib/widgets/settings_sync_section.dart` / `lib/pages/config_setup_page.dart` - 「同步设置」保存 P0 远端目录轮询间隔；首次配置编辑会保留该值；保存后重新挂载，新的会话才会采用该间隔。
- `go/mount/remote_poller.go` - `directoryActivityTracker` 在 `bucketAccess.listDirectory` 和 Cloud Files 的 placeholder 回调中记录目录活动，最多保留 12 个目录，并在新目录活动时唤醒等待中的 poller。`remoteDirectoryPoller` 在活动 45 秒内按 `mount_remote_poll_seconds` 刷新，之后每 30 秒刷新；3 分钟没有活动目录时停止网络访问。它调用 `fetchDirectory`，刷新 `bucketCache`，不会用远端状态删除本地 overlay 或 writeback。
- `go/mount/manager.go` / `go/mount/types.go` - 每个成功启动的 `mountSession` 创建 poller；卸载时先停止轮询，再关闭平台后端，避免访问已释放的 `bucketAccess`。
- `go/mount/backend_windows_cloud_files_cgo.go` / `go/mount/cloud_files_hydrator_windows.go` / `go/mount/cloud_files_refresh_windows.go` - P0 轮询结果通过 `externalDirectoryRefresh` 进入 `RefreshPlaceholders`。它记录已投影目录的远端快照：新对象创建占位符，已存在对象经 `CfUpdatePlaceholder` 更新元数据并对变更文件脱水，远端删除仅移除之前投影且没有本地写回/tombstone 的项。对象 ETag 参与文件标识，保证同大小同秒覆盖也会失效 Explorer 缓存。
- `go/mount/remote_poller_test.go` / `go/mount/object_page_test.go` - 覆盖远端目录缓存刷新、占位符投影回调、活动/空闲退避窗口，以及目录写入期间的稳定快照分页。

**Metadata-cache independence (verified 2026-08-10):** disabling mount metadata caching persists `MountMetadataCacheSeconds = -1`; `newBucketAccess` converts that to a zero `bucketCache` TTL but decides `allowRemotePoll` independently from the backend capability. `pollRemoteDirectory` still calls `fetchDirectory` and then `externalDirectoryRefresh` even though `cache.storeList` becomes a no-op, so Windows Cloud Files placeholder refresh does not depend on metadata caching being enabled. Both metadata-cache and poll-interval changes apply to a newly created mount session; remount after changing either setting. There is a shared poller unit test and a Windows metadata-comparison test, but no automated real-CFAPI test for the cache-disabled combination.

**Gotchas:** P0 不是文件传输协议，也不是递归扫描器。它不保证即时投递，未主动刷新的文件管理器窗口仍可能需要一次目录读取；删除和覆盖投影只能作用于自己此前记录的远端占位符，并必须跳过 tombstone、排队写回和正在上传的路径，不能盲目删除本地项。

### Feature: File Actions and Linux Mount Ownership

File-manager copy/move chooses a destination directory rather than asking users to compose an object key, while mounts keep both cross-client metadata and local filesystem ownership coherent.

- `lib/widgets/object_action_dialogs.dart` / `lib/pages/file_manager_page_actions.dart` / `lib/pages/file_manager_page_selected_actions.dart` - Copy and move open the existing remote directory picker restricted to the active bucket, then append each source object's display name with `objectTargetPathInDirectory`; the UI never asks users to reconstruct a full target key.
- `lib/services/local_file_opener_io.dart` - Windows invokes `cmd /c start` with the path as a separate argv element, avoiding literal quote characters in Explorer's filename lookup.
- `go/s3/object_mutations.go` / `go/s3/object_move_cleanup_test.go` - Rename and move remove the exact source keys captured during the initial copy plan, avoiding delayed re-listing that leaves the old object beside its new name.
- `go/mount/linux_fuse_nodes.go` / `go/mount/linux_fuse_owner_test.go` - Root and entry attributes use the mounting process UID/GID so Linux FUSE `default_permissions` authorizes the desktop user instead of treating remote entries as root-owned.

Regression anchors: `test/object_action_dialogs_test.dart` verifies directory-to-target-key composition; `go/s3/object_move_cleanup_test.go` verifies directory rename performs one planning list and deletes every captured source key. The Windows external-open fix is currently code-reviewed through `lib/services/local_file_opener_io.dart` (`cmd /c start`, empty title, unquoted argv path) and still needs an app-level check for a cached path containing spaces or non-ASCII characters.

**Gotchas:** Cloud Files refresh code is built only for `windows && cgo`; macOS/Linux Go tests validate shared behavior but cannot exercise the Windows CFAPI call. Validate a changed hydrated file, a same-size ETag-only overwrite, a remote deletion, and an occupied-cache remount through `scripts/run_windows.ps1` on a Windows host.

### Feature: LAN P2P D1/D2

同账号设备以 mDNS 自动发现，P2P 只加速通知和读取；对象存储的 `size + LastModified` 始终是版本权威，任何失败都会退回普通远端下载。

**默认关闭的实验功能（2026-08-01）：** P2P 现在默认关闭（`RemoteStorageConfig.P2PEnabled` 在 `DefaultConfig()` 为 false，且 `UnmarshalJSON` 不再为缺字段强制设 true）。新账号/新配置不会启动 mDNS，因此不再在无组播路由的网卡上刷 `no route to host`。已显式保存 `p2pEnabled:true` 的配置保留开启（尊重已 opt-in 的用户）。用户可在「设置 → 局域网同步」手动打开（`SettingsP2PSection` 带「实验功能 · 默认关闭」标识）。启动门控无需改动：`dispatch_p2p.go:81` 的 `cfg.P2PEnabled && cfg.IsConfigured() && secret != ""` 已尊重该字段。回归锚点：`go/config/config_p2p_test.go`（缺字段→false、显式 true→保留、显式 false→保留、DefaultConfig→false）。

- `go/p2p/discovery.go` / `discovery_test.go` / `identity.go` / `events.go` / `manager.go` - `_cloudvolume._tcp` 在 `local.` mDNS 域中只广播账号指纹和设备 ID；注册时服务名和完整域名必须分别传给 `hashicorp/mdns.NewMDNSService`，查询复用相同值。账户凭证中的 secret 在本机派生 HMAC key，事件同时用 HMAC 和 Ed25519 认证。`PeerManager` 维护实际 running 状态，配置账号改变时由 bridge 停止并重建。查询遇到 `ENETUNREACH`/`EHOSTUNREACH` 时按接口共享 2 分钟退避，避免无组播路由的 en0/en1 在多账号轮询中刷屏；其他 mDNS 错误仍正常记录，退避到期后自动重试。
- `go/p2p/transport.go` / `protocol.go` / `content_client.go` - QUIC 流承载有长度上限的 JSON 控制帧和原始 chunk bytes。查询、范围请求、查询响应和 chunk metadata 都有 HMAC，原始 bytes 在传输时计算并校验绑定对象/版本/范围的 chunk HMAC；下载最多 4 路并发，chunk 大小限定为 1–64 MiB。
- `bridge/dispatch_p2p.go` / `bridge/dispatch_config.go` / `bridge/dispatch.go` / `bridge/dispatch_object_transfer.go` - 多账号并行发现：`ensureP2PManagers` 按档案名维护 `PeerManager` 表，为每个启用 P2P 的档案各注册一条 mDNS 服务（各自随机 QUIC 端口），profile 增删改（bootstrap/saveConfig/saveProfile/deleteProfile）后对账创建/替换/停止。两台设备只要共享任意一个账号即可互相发现，与活跃账号无关。`BroadcastPayload.Config` 与 `broadcastPeerMutation(cfg, ...)` 携带发起方配置，bridge 用指纹路由到对应账号的 manager；`p2pStatus()` 聚合所有 manager 的 peer 并按 `accounts[]` 标注共享账号。远端确认的 bridge/mount mutation 广播父目录刷新；bridge 上传和 mount writeback 的成功 `HeadObject` 会登记本地源供 D2 读取。
- `go/mount/peer_hook.go` / `peer_content.go` / `bucket_remote.go` / `peer_refresh.go` - mount 通过回调避免反向导入 `p2p`。读取顺序是本地完整 cache → P2P 临时 `.downloading` 文件 → 远端；P2P 完成后再次 `HeadObject` 检查版本，成功才按既有 stamp/rename 流程进入缓存。`LocalPeerContentPath` 只提供匹配版本的完整缓存或远端已确认的上传源。

**Gotchas:** mDNS 的账号指纹不是认证材料；不能把它当作 shared secret。不要向 JSON/base64 放大 1–64 MiB chunk，且不要为 P2P 增加强制全文件 hash 扫描。P2P 的可用性不应改变写回、删除或 bootstrap 的成功语义。

### Feature: Remote Configuration Backup

桌面端可把当前账号配置保存为加密的远端快照，便于在误改配置后从设置页还原；备份目标本身不属于普通账号列表时也可独立保存。

- `go/config/config_backup.go` — 在 bbolt `meta` 保存 `ConfigBackupSettings`；目标可引用 profile 或保存独立 `RemoteStorageConfig`。`ExportConfigBackup`/`RestoreConfigBackup` 只处理 profiles、活动账号、全局代理和显示顺序，刻意不打包本地缓存；还原时保留备份目标设置。
- `go/configbackup/backups.go` — 解析目标，用用户自设备份密码派生 AES-GCM 密钥（`cloud-volume/config-backup/v2` + password 的 SHA-256），上传/列举/下载 `*.cloud-volume-config.json.enc` 快照。恢复前校验前缀、后缀和最大 32 MiB 大小，再验证解密标签并导入。空密码走明文 JSON；加密但无密码时返回 `此备份已加密，请先设置加密密码`，密码错误时包装为 `无法解密配置备份：...`。
- `bridge/dispatch_config_backup.go` / `bridge/dispatch.go` — 提供加载/保存目标、立即备份、列出快照与还原方法；`restore_config_backup_with_target` 成功后把 inline target（含密码）固化为本地备份设置并默认开启自动备份。普通 profile、代理、排序变动后以 2 秒合并窗口异步自动备份，不因远端失败阻塞本地保存。
- `lib/models/config_backup.dart` / `lib/services/remote_storage_*` — Flutter bridge model/API；Web 明确不支持本地配置备份。
- `lib/utils/bridge_error_text.dart` / `test/config_backup_restore_test.dart` — `isConfigBackupDecryptionError` 只匹配 Go 稳定解密失败文案（`无法解密配置备份` / `此备份已加密` / `message authentication failed`），避免网络/解析错误误进密码重试。
- `lib/widgets/config_backup_restore.dart` — 共享密码输入弹窗 + 解密失败重试循环；`skipInitialAttempt` 用于「本地密码已经失败过」的路径，避免再跑一轮必然失败的下载；取消抛 `ConfigBackupRestoreCancelled`，调用方静默退出。
- `lib/widgets/settings_config_backup_section.dart` / `lib/widgets/settings_config_backup_cards.dart` / `lib/widgets/settings_config_backup_history_dialog.dart` / `lib/widgets/settings_config_backup_labels.dart` / `lib/pages/settings_page*.dart` / `lib/pages/config_setup_page.dart` — 「设置 → 账号 → 配置备份」配置已有或独立目标、自动备份与立即备份；页面只保留可点击的历史摘要卡片，完整快照列表在 `ConfigBackupHistoryDialog` 拟态框中滚动查看。还原流程统一为：点还原 → 立刻确认 → 用本地密码尝试 → 解密失败才弹密码框循环重试。历史弹窗打开时的后台刷新不再锁住行按钮，避免首点被吞。首次启动「从备份存储还原」复用同一套密码重试 helper。独立目标复用账号连接向导，但不会调用 `saveProfile`，因而不显示在账号页。

**Gotchas:** 加密密钥只从用户备份密码派生，与 endpoint / AK/SK 无关，换机器可解密；密码错误与未设密码是两类稳定错误，UI 只对它们弹密码框。自动备份只在已存在且启用的目标上运行，多个紧邻的本地配置写入会合并为一次快照。完整清除本地配置后，必须先重新提供备份目标连接才能读取远端快照，不能从加密备份中无凭证自举。设置页历史弹窗里 `busy` 只应包含 `_restoring/_deleting`，不要把后台 `_loading` 并进去，否则打开瞬间点还原会被静默吞掉。

**P1/D2 update (2026-07-27):** 已实现 mDNS/QUIC 自动发现和受账号 secret HMAC 认证的事件/内容流。对端事件只应触发受影响父目录的 `RefreshRemoteDirectory`，绝不能直接调用 `NotifyExternalDelete`，因为后者会取消本机 pending writeback 并写 tombstone。事件生产端仍只能放在 `writebackQueue.flushNow`、`deleteQueue.runDelete`、`bucketAccess.renamePath` 和 bridge 的远端 mutation 成功点；P0 继续是 P2P 不可用时的可靠性兜底。

**P2P safety update (2026-07-28):** D2 content transfer prefers a provider ETag. `go/s3.ObjectInfo` carries the ETag from Head/List responses, cache stamps persist it, and the requester re-checks it after transfer. Providers without ETag use the existing `LastModified + size` cache-version fallback, so same-second same-size overwrites retain that known cache limitation without forcing full-file hashing. `RemoteStorageConfig.UnmarshalJSON` supplies enabled/default P2P fields for pre-feature profiles. The settings toggle persists config before issuing the runtime toggle (runtime disable is tracked per profile in `p2pDisabledProfiles`), and disabling is idempotent after the manager has been released.

**Multi-account discovery (2026-07-28):** The previous singleton `ensureP2PManager(cfg)` only broadcast the *active* profile's fingerprint, so two devices restored from the same backup but showing different active profiles never discovered each other. Now `ensureP2PManagers(overlays)` reconciles a map of managers keyed by profile name. The lifecycle key is `p2pSecretsKey` = sha256 of storageType + endpoint + principal + secret **only** — never the full config JSON, because timestamps and other non-credential fields would change on backup/restore and break discovery. Each manager registers its own mDNS service instance on its own random QUIC port — hashicorp/mdns allows parallel servers, and per-port registration avoids cross-account port confusion. Never route a mutation through "the" manager: always resolve by `managerForConfig(cfg)` fingerprint match, otherwise account A events would leak to account-B-only peers and be silently dropped by the auth check.

**Shared mDNS socket (2026-07-28):** `go/p2p/discovery.go` uses a single `sharedMDNS` with a `multiServiceZone` to serve all account fingerprints on one UDP 5353 socket. Never create one `mdns.Server` per account — the port conflict silently drops broadcasts. IPv6 mDNS queries are disabled (`DisableIPv6: true`) because LANs without routable IPv6 multicast cause hashicorp/mdns to spam bind errors; both the client query and the shared server pass `Logger: log.New(io.Discard, ...)` so the library's INFO/ERR lines don't flood bridge.log.

**Multi-interface query (2026-07-28):** `queryPeers` must iterate `multicastIPv4Interfaces()` and query each one separately. hashicorp/mdns's default query only uses the primary interface, so on hosts with multiple NICs (e.g. Mac with VMware bridge on en1 while en0 is primary) the default query misses peers reachable through the secondary interface. Do not revert to a single default-interface query.

**Automatic-discovery option (2026-07-23):** 可以免配对，但组密钥只能在内存中由同一挂载范围的规范化 `storageType + endpoint + bucket + rootPrefix` 与实际凭证材料经 HKDF-SHA256 派生；mDNS TXT 仅广播截断 `HMAC(groupKey, "cloud-volume/p1/discovery/v1")` 标签和临时端口，绝不广播 endpoint、bucket、路径或凭证。标签匹配后才建立 QUIC，首个双向流以随机 nonce、组密钥 HMAC 和 event MAC 认证；事件路径放在该加密流内，接收端按父目录刷新。这样无需持久化新的组密钥，但凭证轮换会自然换组，匿名/无密钥账号不能启用，并且弱 WebDAV/FTP 密码会让广播标签成为离线猜测验证器；自动发现应默认关闭或至少明确告知该风险。不要依赖 HMAC `pathHash` 反查任意路径，它不可逆；需传加密路径或只发已知目录刷新提示。

### Feature: File Preview & Upload Cache Seeding (文件预览与上传缓存衔接)

点击/双击文件打开走的是 `FileAccessService._ensureCachedObjectRequest`：`headObject` 拿远端 size/mtime → `FileCacheStore.findUsableCachePath` 通过 `RemoteStorageGateway.findCacheIndexRecord` 调 Go bridge 查询 bbolt 缓存索引 → 命中则直接用缓存文件，未命中则建 `download` 任务拉到 `<cacheDir>/files/<bucket>/<key>` 并写缓存记录。缓存命中的硬约束：记录的 `localPath` 必须 `_isInsideRoot` 缓存目录内，且 size/mtime 与远端匹配（`_matchesRemoteObject`）。

**Windows SQLite removal (2026-07-07):** Windows Debug 真实回归中界面闪退，日志为 `Failed to load dynamic library 'sqlite3.dll'`，根因是 `sqflite_common_ffi` 需要系统/打包的 SQLite 动态库，而新 Windows 开发机没有。最终方案已移除 `sqflite_common_ffi` / `sqlite3` 依赖和 `platform_bootstrap_io.dart` 的 SQLite FFI 初始化，且不再由 Flutter 前端维护 JSON 索引；缓存索引通过 bridge 方法 `cache_index_find` / `cache_index_upsert` / `cache_index_remove` / `cache_index_remove_prefix` 存进 Go config bbolt DB 的 `preview_cache` bucket。bbolt key 为 `bucket + "\x00" + objectKey`，record 字段为 `bucket`、`objectKey`、`localPath`、`fileSize`、`lastModified`、`updatedAtEpochMs`。这样 Windows 前端启动不再依赖 `sqlite3.dll`，缓存索引 I/O 也留在 Go bridge 后台 isolate 调用链上。

**Preview latency logging (2026-07-07):** 点击预览卡顿排查使用 `AppLog.debug` 的 `preview` tag。`lib/pages/file_manager_page_preview.dart` 记录 open/source-load/dialog-close；`lib/services/file_access_service_io.dart` 记录 `ensure start`、`head done`、`cache find done`、`cache path done`、download task create/reuse、cache upsert、download complete、read bytes；`lib/services/file_cache_store.dart` 记录 `cache index find` 和 `cache validate`。日志写入 bridge log（macOS/Windows 桌面端通常在 `~/.cloud-volume/runtime/logs/bridge.log`），看 `phaseMs` / `totalMs` 即可判断卡在远端 head、bridge/bbolt index、本地文件 stat/read，还是下载链路。未手动设置日志等级时，Debug 构建默认 `Debug`，Release 构建默认 `Silent`；需要在 设置 → 通用 → 日志设置 切到“调试”后再复现 release 环境问题。

**问题（2026-06-30 修复）：** 上传走传输队列，成功后只 `markTaskDone` + 刷新列表，从不动缓存表。所以"刚上传完的文件双击还要重下"——上传与预览是两套独立记账。

**修复：** 上传成功后调 `FileAccessService.seedCacheFromUpload`（io 实现 / web 空操作）：`headObject` 拿远端元数据 → 把本地源（`localSourcePath` 或 `bytes`）copy/写入缓存目录 → `upsertCacheRecord`。以远端 size/mtime 为准（不能用本地 stat，否则比对失败）。整个 seed 包 try/catch 吞异常：只是缓存优化，绝不阻断"上传已成功"。`unawaited` 后台执行，不阻塞列表回显。

#### Key files
- `lib/services/file_access_service_io.dart` — `seedCacheFromUpload`（桌面实现）、`_ensureCachedObjectRequest`（预览/打开缓存命中逻辑）。
- `lib/services/file_access_service_downloads_io.dart` — part extension，承接下载另存为/默认目录选择相关方法，保持 `file_access_service_io.dart` 在线数规则内。
- `lib/services/file_access_service_web.dart` — `seedCacheFromUpload` 空操作（浏览器无本地缓存目录）。
- `lib/pages/file_manager_page_actions.dart` — `_runUploadTask`（本地路径上传，传 `localSourcePath`）、`_runBrowserUploadTask`（bytes 上传，传 `bytes`）成功分支调 seed。
- `lib/services/file_cache_store.dart` — 只负责缓存路径生成、安全校验、size/mtime 比对、本地缓存文件删除；索引持久化全部委托 `RemoteStorageGateway` bridge 方法。缓存文件本体仍放在 `<cacheDir>/files/<bucket>/<key>`。
- `lib/models/cached_file_record.dart` — Dart cache index record，JSON 使用 bridge camelCase 字段，并兼容旧 snake_case 读取。
- `lib/services/remote_storage_gateway.dart` / `lib/services/remote_storage_api_desktop_cache.dart` / `lib/services/remote_storage_api_web.dart` — gateway cache index API。Desktop 调 bridge；Web 本地缓存索引方法为 no-op/null，因为浏览器没有本地预览缓存目录。
- `go/config/cache_index.go` — Go bbolt cache index store，复用 `config.db`，bucket 为 `preview_cache`，支持 find/upsert/remove/remove-prefix；`go/config/cache_index_test.go` 覆盖读写和前缀删除。
- `bridge/dispatch_cache_index.go` / `bridge/dispatch.go` — bridge JSON 方法路由：`cache_index_find`、`cache_index_upsert`、`cache_index_remove`、`cache_index_remove_prefix`。
- `lib/pages/file_manager_page_preview.dart` — 双击预览入口 `_showObjectPreview`。

#### Data flow
1. 预览/打开：`FileAccessService._ensureCachedObjectRequest` → `api.headObject` → `FileCacheStore.findUsableCachePath(api, cacheDir, bucket, remoteObject)` → desktop gateway `cache_index_find` → Go `config.FindCacheIndexRecord` → Dart 校验路径在 cache root 内、文件存在、size/mtime 匹配。
2. 下载成功或上传 seed 成功：文件写入 `<cacheDir>/files/<bucket>/<objectKey>` → `FileCacheStore.upsertCacheRecord(api, ...)` → desktop gateway `cache_index_upsert` → Go bbolt `preview_cache`。
3. 删除/移动/重命名对象：`FileAccessService.evictCacheForObject(api, ...)` → 文件对象走 `cache_index_remove`；目录对象走 `cache_index_remove_prefix`，Go 返回被删记录，Dart 再清理对应本地缓存文件。

### Feature: Local File Paste / Drag Upload (本地粘贴/拖拽上传)

桌面端文件管理页接收本地文件输入（访达复制后 Cmd+V 粘贴、拖拽到列表）。**粘贴走 method channel（见下）**；拖拽走 `super_drag_and_drop` 的 `DropRegion`。二者共用 `DesktopFileTransferService` 把 file:// URI 解析成本地路径，再交给 `_uploadLocalPaths` 入队上传。

**根因与修复（2026-07-01）：** Flutter macOS 引擎的 `FlutterViewController.performKeyEquivalent` 在 `firstResponder == _flutterView` 时调 `[_flutterView keyDown:event]`。但 `FlutterView` 是普通 `NSView`，没有 override `keyDown:`——默认实现走 `interpretKeyEvents:`，把 Cmd+V 交给 TSM 输入上下文（日志表现为 `NSSoftLinking - _TSMMenuKeyTransWithModifiersBeginWithEvent`），TSM 静默吞掉 `paste:`/`copy:` selector，事件**永远到不了**引擎 keyboardManager 或 Flutter `Shortcuts`。

**解决方案：** 不再依赖 Flutter `Shortcuts` 处理 Cmd+V/C。改为在 `MainFlutterWindow.performKeyEquivalent`（NSWindow 层）截获 Cmd+V/C，`return true` 阻止 AppKit 菜单和 TSM 处理，通过 `cloud_volume/clipboard_shortcut` method channel 直接通知 Dart 侧。`FileTransferClipboardRegion` 里的 `Shortcuts`/`_PasteFilesIntent` 仍保留（理论上对非 macOS 或未来 engine 修复有用），但 macOS 上实际由 channel 驱动。

#### Key files

- `macos/Runner/ClipboardShortcutPlugin.swift` — `ClipboardShortcutPlugin`（FlutterPlugin，注册 method channel `cloud_volume/clipboard_shortcut`）+ `ClipboardShortcutCoordinator`（单例，持有 plugin 实例供 window 调用）。
- `macos/Runner/MainFlutterWindow.swift` — `performKeyEquivalent` override：截获 Cmd+V → `ClipboardShortcutCoordinator.shared.handlePaste()`、Cmd+C → `handleCopy()`，其余交 `super`。在 `awakeFromNib` 注册 plugin。
- `lib/services/clipboard_shortcut_channel.dart` — `ClipboardShortcutChannel` 单例：`start(onPaste, onCopy)` 设置 `MethodChannel` handler；`isSupported` 仅 macOS 非 Web。
- `lib/widgets/file_transfer_clipboard_region.dart` — `Shortcuts`+`Actions`+`DropRegion` 包装层（拖拽实际生效；粘贴的 `Shortcuts` 在 macOS 上被 channel 旁路）。
- `lib/services/desktop_file_transfer_service_io.dart` — `localFilePathsFromClipboard`（读 `SystemClipboard` 的 `Formats.fileUri`）、`localFilePathsFromDrop`、`writeLocalFilesToClipboard`、`localUploadEntries`。
- `lib/pages/file_manager_page_transfer_inputs.dart` — `_uploadLocalPaths`（入口，含 `_ensureCurrentDirectoryWritable` 兜底校验）、`_copySelectedObjectsToClipboard`、`_handleNativePaste` / `_handleNativeCopy`（channel 回调入口）。
- `lib/pages/file_manager_page_access.dart` — `_currentDirectoryWritable` / `_ensureCurrentDirectoryWritable` / `_refreshDirectoryAccess`（WebDAV 目录 PROPFIND 可写性检查）。

#### Data flow

1. 访达复制文件 → 系统 pasteboard 含 `public.file-url`。
2. macOS Cmd+V → `MainFlutterWindow.performKeyEquivalent` 截获 → `ClipboardShortcutCoordinator.handlePaste()` → method channel `paste`。
3. Dart `ClipboardShortcutChannel` → `_handleNativePaste` → `DesktopFileTransferService.localFilePathsFromClipboard` 解析路径 → `_uploadLocalPaths` → `_ensureCurrentDirectoryWritable` → `TransferQueue.startTask` 入队上传。

### Feature: macOS Window Lifecycle & Positioning

Controls how the main window is sized, centered, shown/hidden, and terminated on macOS.

#### Key files

- `macos/Runner/MainFlutterWindow.swift` — Main window class (`NSWindow` subclass). Owns `MenuBarController` (tray). In `awakeFromNib` it sets transparent titlebar, full-size content view, min size, then calls `applyDefaultWindowLayout()` on the next run loop tick. `applyDefaultWindowLayout` resolves a size via `resolvedInitialWindowSize()` (scales to fit smaller screens) then centers via `centeredWindowFrame(for:)` using `self.screen ?? NSScreen.main`. Overrides `close()` to intercept with a confirm dialog (退出 / 隐藏到托盘 / 取消) unless `allowsDirectClose` is set. `terminateWithoutConfirmation` bypasses the dialog.
- `macos/Runner/AppDelegate.swift` — `FlutterAppDelegate`. `applicationShouldTerminateAfterLastWindowClosed` returns `false` (keeps app alive when window hidden). `applicationShouldHandleReopen` calls `showYunjuanMainWindow()` (dock click reopens window). `applicationWillTerminate` calls bridge `cleanup_mounts` via dlopen to unmount buckets on exit.
- Top-level free functions: `yunjuanMainWindow()` finds the main `MainFlutterWindow`; `showYunjuanMainWindow()` / `hideYunjuanMainWindow()` show/hide via `orderOut` / `makeKeyAndOrderFront` + `NSApp.activate`.

#### Startup screen behavior

The window centers on `self.screen ?? NSScreen.main`. `NSScreen.main` is whatever macOS considers the primary display (the one with the menu bar in System Settings → Displays). If the app launches on the "wrong" screen, the fix is in macOS display settings, not in app code.

#### Constants

- Default size: 1160 x 740; minimum: 920 x 620; compact fallback: 840 x 560.
- Size resolution scales to 72% width / 66% height of the visible frame if the defaults don't fit.

### Navigation structure

- `lib/pages/main_layout_page.dart` — Root layout with sidebar navigation. Routes include 文件同步 (`FileSyncTasksPage`), 文件管理 (`FileManagerPage`), 传输 (`TransfersPage`), 回收站 (`GlobalTrashPage`), 分享管理 (`ShareManagementPage`), and 设置 (`SettingsPage`).
- `lib/pages/settings_page.dart` — Settings page. Groups (通用设置, Windows 设置, 关于) use a **left vertical sidebar rail** (not top tabs). Sync management was **removed** from Settings (2026-06-26) and now lives entirely in the File Sync Tasks page. The obsolete Windows “此电脑” entry card and anchor were removed on 2026-07-15.

### Feature: Settings Page Layout (设置页布局)

The settings page uses a **two-column anchor layout**: a left vertical anchor rail with section headers (通用 / Windows / 关于), and a right scrollable page that shows all settings cards in one continuous column. Clicking a left rail item scrolls the right page to that card. The rail has **no persistent active/selected highlight** — entries only change appearance on hover (2026-07-06 change: previously a click pinned a highlighted entry via `_activeTab`; that was removed so nothing stays selected after the click).

#### Key files
- `lib/pages/settings_page.dart` — `SettingsPage` + `_SettingsPageState`. `_SettingsTab` enum identifies one card/anchor per config block. State owns `_contentScrollController` and `_sectionKeys` (**no `_activeTab` field**). `build()` renders a `Row`: left `SizedBox(width: 180)` with title + `_buildGroupRail(theme)`; right `Expanded` + `SingleChildScrollView(controller: _contentScrollController)` with `_buildAllContent`.
- `lib/pages/settings_page_layout.dart` — part file. `_SettingsLayout` extension: `_railGroups()` builds `_SettingsRailGroup` list with section headers + anchors; `_buildGroupRail` renders headers + `_SettingsGroupTile` rows; `_tabLabel` maps enum to Chinese label; `_buildAllContent` renders every visible card as one page using `KeyedSubtree` + `_sectionKeys`; `_scrollToAnchor` uses `Scrollable.ensureVisible` and **only scrolls** — it no longer updates any `_activeTab` (2026-07-06). `_SettingsGroupTile` is the hover-aware StatefulWidget tile (must be StatefulWidget — see Hover rule above); it exposes **no `active` parameter** — appearance is hover-only.
- `lib/pages/settings_page_sections.dart` — part file. `_SettingsSections` extension with per-anchor card builders (`_buildUpdateSection`, `_buildProxySection`, `_buildAppearanceSection`, `_buildLogSection`, `_buildDownloadSection`, `_buildCacheSection`, `_buildVisibilitySection`, `_buildSyncSection`, `_buildTrashSection`, `_buildWebdavSection`, `_buildResetAccountSection`, `_buildConfigManageSection`, `_buildWindowsWritebackSection`, `_buildWindowsMountSection`, `_buildAboutSection`). Each returns `[_buildCard(...)]`. The removed Windows entry has no builder or page state/action; `windowsThisPcEntryEnabled` remains in the config model only for backward compatibility.
- `lib/widgets/settings_cache_section.dart` — Settings → 通用 → 缓存设置 card body. Layout is intentionally split into three visible groups: `缓存目录设置` (resolved path + choose/reset/open actions), `缓存占用` (stats block + refresh action + error text), and `缓存清理` (manual clean buttons + auto-clean rules editor). Keep these concerns visually separated; do not collapse them back into one mixed button row.
- `lib/pages/settings_page_actions.dart` — part file with `_SettingsPageActions` extension: all config save/refresh/cleanup actions.

#### Data flow
1. `_SettingsPageState.build()` wires the right-side `SingleChildScrollView` to `_contentScrollController` and calls `_buildAllContent(theme, config)`.
2. `_railGroups()` returns 通用 (including 日志设置; download anchor only when supported; WebDAV 凭据 anchor only on Web), Windows (if `isWindowsPlatform`, with 写回并发 and 挂载恢复 only), 关于 groups.
3. `_buildAllContent` loops through those same visible anchors, wrapping each section card with the matching `_sectionKeys[tab]`.
4. Tapping `_SettingsGroupTile` calls `_scrollToAnchor(tab)`, which runs `Scrollable.ensureVisible` to scroll the right page to the keyed card. It does **not** set any active/selected state — the rail tile only shows hover feedback while the pointer is over it.
5. Left rail scrolls independently when the anchor list is taller than the viewport.

### Feature: App Diagnostic Logging (应用诊断日志)

The app has four diagnostic levels: `Silent`, `Error`, `Info`, `Debug`. Settings labels are user-facing Chinese (`安静` / `仅错误` / `常规` / `调试`), while persisted/bridge values stay lowercase English (`silent` / `error` / `info` / `debug`). If the user has never chosen a level, Flutter sets the default by build mode: Debug builds use `Debug`, Release builds use `Silent`.

- `go/logging/logging.go` — Central Go logging package. Owns `Level`, process-wide atomic level, `ConfigureOutput`, filtering writer, and `Debugf` / `Infof` / `Errorf`. Existing backend `log.Printf` lines are treated as `Info`; obvious error-like legacy lines containing `error` / `failed` / `warn` are kept at `Error` level. New backend diagnostics should use this package instead of adding another logger or ad-hoc filter.
- `bridge/logging.go` — Configures the standard Go logger to write through `go/logging` into stderr + `BridgeLogPath()` (`~/.cloud-volume/runtime/logs/bridge.log`). The backend starts at `Silent`; Flutter syncs the effective level after API bootstrap.
- `bridge/dispatch_log.go` / `bridge/dispatch.go` — Bridge JSON methods: `set_log_level`, `get_log_level`, and `write_flutter_log`. `write_flutter_log` forwards Flutter-tagged lines into the same Go logging filter, so frontend and backend diagnostics share one level.
- `lib/utils/app_log.dart` — `AppLogLevel` + `AppLog.info/debug/error`; bound in `AppBootstrapPage` after API bootstrap. The current level is persisted in SharedPreferences key `app.log.level`; `loadLevel()` and `setLevel()` both call `RemoteStorageGateway.setLogLevel`, so settings apply to Go backend logs as well as Flutter-forwarded logs.
- `lib/widgets/settings_log_section.dart` — User-facing Settings UI for the four levels. Lives under Settings → 通用 → 日志设置 and avoids implementation terms such as Flutter/bridge in visible copy.
- `lib/pages/settings_page.dart` / `settings_page_layout.dart` / `settings_page_sections.dart` — Adds the `logging` anchor/card to the Settings page.
- `RemoteStorageGateway.setLogLevel` / `writeAppLog` — desktop FFI calls; web no-op because browser builds do not write the desktop bridge log file.

### Feature: In-App Auto Update (应用内自动更新)

Detects new GitHub releases and, on desktop, downloads + installs the correct platform package in-app — no manual uninstall or command-line steps needed.

**Mirror rule (2026-07-02 fix):** The GitHub Releases **API** call (`checkLatestRelease`) is **always direct** to `api.github.com` — public download mirrors like `gh-proxy.com` reject api.github.com URLs with HTTP 403. The configured mirror prefix (`UpdateNetworkConfig.wrapUrl`) is now applied **only** to the asset **download** URL in `downloadAndInstallAsset`.
**Architecture matching (2026-07-02 fix):** `matchPlatformAsset` previously hardcoded universal-first on macOS, so an arm64 app would download the larger universal DMG. It now prefers the **running build architecture**: the Go bridge exposes `get_build_info` returning `buildArch` (injected at compile time via `-ldflags -X main.buildArch=...` in Makefile / `build_desktop_packages.sh`); Flutter reads it via `widget.api.getBuildInfo()` and passes it to `matchPlatformAsset`. If the bridge is unavailable (web, old dev build), it falls back to `runtimeCpuArchitecture` (parsed from `Platform.version`). Universal is tried only after the arch-specific package, and as a fallback when the specific arch asset is absent.
**Download progress (2026-07-02 fix):** When the server does not report `Content-Length` and the asset metadata has no size, the progress bar previously stayed stuck at 0%. `_installProgress` is now initialized to `-1` (indeterminate); the `LinearProgressIndicator` uses `null` value (continuous animation) and the status text shows downloaded bytes via `_formatBytes`.
**Windows architecture matching (2026-07-13, supersedes the Windows portion above):** Both Dart and Go asset matchers prefer exact native `yunjuan-windows-<arch>.zip` / installer names. ARM64 may fall back to amd64 because Windows 11 ARM supports x64 emulation; amd64 never selects an ARM64 package. Exact filenames prevent desktop/CLI package collisions.
Participating files: `bridge/dispatch_platform_asset.go` / `dispatch_platform_asset_test.go` implement and test bridge-side exact matching; `lib/services/platform_asset_matcher.dart` / `test/platform_asset_matcher_test.dart` implement the same Dart-side ordering with a test-only platform override.
**Timeout hardening (2026-07-04 fix):** `checkLatestRelease` used a 10s single-shot timeout and often failed on slow GitHub/proxy paths; it now uses 30s per attempt with up to 3 attempts (2s/4s backoff) for `TimeoutException` and retryable socket errors. `install_app` download used `ProxyHTTPClient(..., 120)` which caps the **entire** HTTP request at 2 minutes — large DMG/exe downloads via mirrors frequently hit that; bumped to 7200s while still cancellable via `cancel_transfer` on the request context.
**Mirror probe + kind fix (2026-07-04 fix):** Two related issues when a mirror is configured: (1) `TransferTask._transferKindFromName` defaulted `app_update` to `upload`, so the transfers page showed an empty "upload" task — now explicitly mapped to `download`. (2) Some public mirrors silently return 403/HTML for large GitHub release downloads, so the progress bar sat at 0B forever; `install_app` now HEAD-probes the wrapped download URL with a 20s client before streaming and fails the task with a clear "镜像不可用" message. The mirror field (`SettingsUpdateMirrorField`) gained a "测试镜像可用性" button that fetches the latest release's first `browser_download_url`, wraps it with the selected prefix, and HEAD-probes it to show 2xx/3xx/4xx result inline so users can pick a working mirror before triggering an update.
**App-update task kind (2026-07-04 fix):** Go transfer snapshots use `type: "app_update"`. `TransferQueue._addRemoteTask` maps `snapshot.type` via `_kindFromWire`, which previously had no `app_update` case → `TransferKind.upload` and UI label "上传". Fix: `TransferKind.appUpdate`, map in both `_transferKindFromName` and `_kindFromWire`, `typeLabel` "应用更新", transfers filter + row icon (`refreshCw`). `displayName` uses `key` (asset file name from Go `StartQueuedTransfer` target).
**Installer cache + resume (2026-07-04):** `install_app` wrote to `os.TempDir()/app_updates` and always full re-download. Now `<ResolveCacheDir>/app_updates`, `UsableCachedInstaller` + `assetSize` from Dart skips network (`statusDetail` `cached`); `downloadInstaller` uses `Range: bytes=N-` resume (206 append, 200 without Range restarts file). `installApp` JSON adds `config` + `assetSize`.
**Windows green ZIP update (2026-07-08; headless since v1.2.0):** `matchPlatformAsset` prefers `yunjuan-windows-amd64.zip` for Windows and only falls back to `yunjuan-windows-amd64-installer.exe` when the ZIP is absent; the Go installer path supports both. `installWindowsZip` extracts `cloud-volume-updater.exe` from the downloaded zip to a temp directory (old versions do not need to pre-install it) and launches it with `-zip`, `-install-dir`, `-pid`, `-exe-name`. In watched builds, the PID is the running `cloud-volume-app.exe` but `-exe-name` is the public `cloud-volume.exe` launcher. The updater waits for the app PID, then polls until the launcher has also exited and become writable before replacing the staged bundle and starting the new launcher. Since commit `8f2d0ac3` / release `v1.2.0`, `updater_window_windows.go` runs this flow without a window or message pump; failures are visible only in `%TEMP%\cloud-volume-updater-<pid>.log`. Because the bridge intentionally exits the main app before the external updater replaces locked files, any headless updater failure is perceived by users as the app disappearing or failing to restart. The updater EXE is built by `run_windows.ps1 -Build` and `build_desktop_packages.sh build_windows`, and ships inside the release zip so it can be extracted on demand during updates.

**Release artifact regression (v1.2.0):** the GitHub release for `v1.2.0` contains Windows CLI archives but no desktop `yunjuan-windows-amd64.zip` or installer. The tagged `build_desktop_packages.sh` placed a shell comment inside the continued PowerShell command used to invoke Inno Setup; commit `616a3b0c` fixed that CI command after the tag. Do not use `v1.2.0` as evidence for a desktop-runtime regression because no official Windows desktop artifact was published for that tag. Static comparison of the official `v1.1.9` and `v1.2.1` desktop ZIPs found the same 639-file layout, identical Flutter engine/plugin dependency set, x86-64 EXE/DLL/AOT architectures, and identical imported runtime DLL names; only `data/app.so`, `remote_storage_bridge.dll`, and the updater payload changed in size. This rules out a generally missing DLL or wrong-architecture package, but not a partial in-place update or user-specific startup data failure.
**Relaunch + mirror-mode persistence (2026-07-04 fix):** (1) `relaunchApp` on macOS launched `/Applications/云卷.app/Contents/MacOS/云卷` (the raw executable) with `open -n`, which spawned a foreground shell-style process without normal LaunchServices window/activation lifecycle and left the old process un-cleaned. It now launches `/Applications/云卷.app` (the bundle) so LaunchServices owns the new app. (2) `SettingsUpdateMirrorField` initialized `_mode` from `widget.initialConfig.mirrorPrefix` in `initState`, but `_SettingsUpdateSectionState._loadMirrorConfig` is **async** — the first build passed an empty `UpdateNetworkConfig`, so `_mode` resolved to `direct` and never updated when the real `mirrorPrefix` arrived (SharedPreferences actually stored `flutter.update.mirror_prefix` correctly, visible via `defaults read com.example.remoteStorage`). Added `didUpdateWidget` to re-resolve `_mode` whenever the parent passes a changed `mirrorPrefix`, clearing probe state at the same time.
**Temp download path (2026-07-03 fix):** Historical Dart-side temp-dir issue; install path is now Go `bridge/dispatch_app_install.go` (`os.TempDir()/app_updates`, `MkdirAll` before download).
**Download integrity (2026-07-06 fix):** 一键更新报「macOS 安装失败：挂载 DMG 失败：映像数据已损坏」。根因：`downloadInstaller` 收到 HTTP 响应后只按 body 流写盘，下载完成不做任何校验；部分加速镜像用 HTTP 200 返回截断内容或 HTML 错误页，被原样写入 `.dmg`，到 `hdiutil attach` 时才暴露为映像损坏（GitHub 网页直接下载同样的 asset 正常）。修复：双重完整性校验。(1) `bridge/app_install_download.go` 新增 `verifyDownloadedSize(destPath, expectedSize)`：下载并显式 `f.Close()` flush 后 stat 落盘文件，与 GitHub asset `assetSize` 不一致时删除残留文件并报「下载文件大小不匹配……镜像可能返回了截断或错误内容」；`expectedSize <= 0` 时跳过。(2) 新增 `verifyDownloadedDigest(destPath, expectedDigest)`：用 GitHub asset 的 `digest`（`sha256:<hex>`）对落盘文件读盘算 SHA-256 全文校验，大小相同但内容被替换的情况也能挡住，不匹配删除文件并报「安装包校验和不匹配：下载内容已被损改，请尝试切换镜像或直连 GitHub 重新更新」；空/非 `sha256:`/非 32 字节 hex 视为不可用摘要，跳过不阻断。缓存命中路径也做大小+校验和校验，digest 不匹配时跳过缓存重新下载。(3) `bridge/dispatch_app_install.go` `appInstallArgs` 增加 `AssetDigest`；`probeDownloadURL` 增加 `expectedSize` 参数，镜像 HEAD 返回的 `Content-Length > 0` 且与 `assetSize` 不一致时直接报「镜像报称大小为 N 字节，与 GitHub Release 的 M 字节不一致」，下载前就拒绝坏镜像。(4) `downloadInstaller` 写文件由 `defer f.Close()` 改为显式 `f.Close()`，保证 stat 前数据已落盘。(5) Dart 侧 `ReleaseAsset` 增加 `digest` 字段，解析 GitHub asset 的 `digest`；`downloadAndInstallAsset`/网关 `installApp`（desktop runtime + web）增加 `assetDigest` 参数透传到 Go。测试 `bridge/app_install_download_test.go` 覆盖大小匹配/不匹配（且文件被删除）/无期望大小，以及 digest 匹配/不匹配（且文件被删除）/空与畸形 digest 五种情形。
**Windows file handle note (2026-07-06 fix):** `verifyDownloadedDigest` must close the opened installer file before removing it on mismatch. Unix allows unlinking an open file; Windows does not, so leaving `defer f.Close()` before `os.Remove(destPath)` made `TestVerifyDownloadedDigestMismatchRemovesFile` fail and would leave a bad cached installer behind.

**Bundled dylib load order (2026-07-03 fix):** macOS bundles may contain two copies of `libremote_storage_bridge.dylib` — `Contents/Frameworks/` (from `make build-macos`) and a stale `Contents/MacOS/` copy from older dev runs. `_findBundledLibraryPath` previously preferred `MacOS/` first, so Flutter FFI loaded the old dylib without `install_app` → `unsupported bridge method "install_app"`. Fix: probe `Frameworks/` before `MacOS/`; `Makefile` `build-macos` runs `rm -f` on `Contents/MacOS/$(dylib)` before `cp` to Frameworks.
**HTTP/2 stream reset + resume retry (2026-07-06 fix):** 一键更新报「下载失败：读取响应失败：stream error: stream ID 1; INTERNAL_ERROR; received from peer」。根因：部分 GitHub 加速镜像在 HTTP/2 上转发大文件时会在中段 reset 流，`downloadInstaller` 的单次 `resp.Body.Read` 直接把错误返回用户即终止。修复：`bridge/app_install_download.go` 把单次下载抽成 `fetchOnce`，`downloadInstaller` 外层重试编排：遇到 `stream error` / `INTERNAL_ERROR` / 连接重置 / 意外 EOF 等可重试错误时按已落盘字节数用 HTTP Range 续传重试，最多 5 次（每次退避 attempt 秒，且响应 ctx 取消）；HTTP 状态码、写盘失败等不可重试错误仍立即返回。新增 `isRetryableFetchError` 判定。测试 `bridge/app_install_download_test.go` 新增 `TestIsRetryableFetchError` 覆盖可重试（stream error / connection reset / EOF）与不可重试（HTTP 403 / 写盘失败）样本。**Reverted sub-fix:** 曾尝试在 `go/config/proxy.go` 新增 `InstallerDownloadHTTPClient` 并设置 `ForceAttemptHTTP2=false` 强制 HTTP/1.1，但 `gh-proxy.com` 在该路径下返回 HTTP/2 二进制帧，Go 按 HTTP/1.x 解析时报 `net/http: HTTP/1.x transport connection broken: malformed HTTP response "\x00\x00..."`；因此撤回协议强制，保留 Go 默认协议协商 + Range 续传重试。

#### Key files

- `lib/bridge/remote_storage_bridge.dart` — FFI loader: `connect()` / `openAtPath()`; `_findBundledLibraryPath()` macOS order Frameworks → MacOS.
- `lib/services/app_update_service.dart` — `AppUpdateService.checkLatestRelease`: fetches GitHub Releases API **directly** (never wrapped by mirror), parses `tag_name` + `assets` array into `AppUpdateCheckResult` with `List<ReleaseAsset>`. Each `ReleaseAsset` carries `name`, `downloadUrl`, `size`, `contentType`, and `digest` (GitHub asset `sha256:<hex>` for post-download integrity verification); `digest` is empty when the release has none. Also has `compareVersionLabels` for semver comparison.
- `lib/services/platform_asset_matcher.dart` — `matchPlatformAsset(assets, {runtimeArchitecture})`: picks the correct asset. macOS order: arch-specific DMG/zip → universal DMG/zip → other-arch DMG/zip; Windows prefers `.zip` → `installer.exe`; Linux prefers `.AppImage` → `.tar.gz`.
- `lib/services/app_installer.dart` — Conditional export: IO → `app_installer_io.dart`, Web → `app_installer_stub.dart`. Exports `kSupportsInAppInstall` and `downloadAndInstallAsset`.
- `lib/services/app_installer_io.dart` — Desktop: delegates to `api.installApp()` → bridge `install_app`; progress is projected into `RemoteTaskStore` through the local/runtime adapter (no Dart `Process.run` / download).
- `bridge/dispatch_app_install.go` — Go `install_app`: download (mirror/proxy), platform install (DMG/ZIP/exe/AppImage/tar), relaunch, `os.Exit(0)`; progress via `s3ops` transfer monitor. Windows installer EXE starts Inno Setup silently; Windows ZIP starts `cloud-volume-updater.exe` because the running app/launcher cannot overwrite their own EXE/DLLs. `probeDownloadURL` HEAD-probes wrapped mirror URL (with `expectedSize` Content-Length check) before download. Uses `storageconfig.ProxyHTTPClient` for installer downloads; do not force HTTP/1.1 because some mirrors return HTTP/2 frames and trigger malformed-response errors.
- `bridge/windows_process_attrs_windows.go` / `_other.go` — Small platform shim for starting the Windows ZIP updater hidden while keeping non-Windows bridge builds portable.
- `cmd/cloud-volume-updater/main.go` — Standalone Go updater entry point. Parses -zip, -install-dir, -pid, -exe-name; opens %TEMP%\cloud-volume-updater-<pid>.log at startup; runs performUpdate (wait old PID, poll writability, extract zip, copy payload skipping own exe, relaunch, then waitForNewApp to confirm the new process started).
- `cmd/cloud-volume-updater/updater_window_windows.go` — Windows headless wrapper around `performUpdate`. It logs status and exits with code 1 on failure; there is no updater UI, message pump, or visible error after `v1.2.0`.
- `cmd/cloud-volume-updater/updater_window_other.go` — Non-Windows stub so the updater cross-compiles for go vet.
- `cmd/cloud-volume-updater/process_windows.go` / `process_other.go` — waitForProcess (WaitForSingleObject), isFileWritable (exclusive CreateFile), waitForNewApp (polls tasklist for a new PID != old PID).
- `cmd/cloud-volume-updater/logger.go` — Process-wide timestamped logger writing to %TEMP%\cloud-volume-updater-<pid>.log; flushed on every logf call.
- `bridge/app_install_download.go` — Resumable installer download (`downloadInstaller`, HTTP Range), retry coordinator around `fetchOnce` (up to 5 attempts on HTTP/2 stream reset / connection reset via `isRetryableFetchError`), cache dir resolution, and post-download integrity checks: `verifyDownloadedSize` (byte count vs GitHub asset `size`) followed by `verifyDownloadedDigest` (SHA-256 vs GitHub asset `digest` `sha256:<hex>`); cache path also re-verifies digest before reuse.
- `go/config/proxy.go` — Proxy transport/client helpers. `ProxyHTTPClient` wraps `ProxyTransport`; installer downloads use this default protocol negotiation plus `downloadInstaller` Range retry, not a forced HTTP/1.1 transport.
- `lib/services/app_installer_stub.dart` / `app_installer_web.dart` — Web stub: returns error string (no local filesystem access).
- `lib/widgets/settings_update_section.dart` — Update UI in 设置 → 通用设置 → 应用更新. Calls `widget.api.getBuildInfo()` at init to load `_buildArch`, passes it to `matchPlatformAsset`. Shows version status, “检测更新”, “一键更新” (when matched asset exists), “取消更新” while an `app_update` task is active, indeterminate-or-percentage progress bar, and “GitHub 下载” fallback.
- `lib/widgets/settings_update_mirror_field.dart` — GitHub download mirror input (extracted from `settings_update_section.dart` to keep it under 500 lines). Persisted via `UpdateNetworkConfig`; affects only `downloadAndInstallAsset` download URLs.
- `bridge/build_info.go` — `buildArch` package var (set by ldflags) + `getBuildInfo()` returns `{buildArch, runtimeOS, runtimeArch}`. Falls back to `runtime.GOARCH` when `buildArch` is empty (local dev builds).
- `bridge/dispatch.go` — Routes `get_build_info` → `getBuildInfo()`.
- `lib/platform/platform_info_io.dart` / `_stub.dart` / `_web.dart` — `runtimeCpuArchitecture` heuristic (parses `Platform.version`), used as Dart-side fallback.

#### Data flow

1. User clicks “检测更新” → `AppUpdateService.checkLatestRelease` → GitHub API **direct** (no mirror).
2. If `updateAvailable` and `matchPlatformAsset(assets, runtimeArchitecture: _buildArch)` finds a matching asset → “一键更新” button appears.
3. User clicks “一键更新” → `lib/services/app_installer_io.dart` `downloadAndInstallAsset` → `api.installApp(...)` → bridge `install_app` → `bridge/dispatch_app_install.go` spawns background goroutine, returns `taskId`.
4. Go goroutine streams download (URL wrapped by mirror if configured) to `os.TempDir()/app_updates/`, reporting progress through `s3ops` transfer monitor; Flutter `_SettingsUpdateSectionState` renders the matching `RemoteTaskStore` task.
5. On download complete, goroutine performs platform install: macOS mounts DMG (`hdiutil attach -plist`) and replaces `/Applications/云卷.app`, Windows runs `.exe` `/SILENT`, Linux replaces AppImage / extracts tarball.
6. If the user clicks “取消更新” before completion, `SettingsUpdateSection._cancelInstall` calls `RemoteTaskStore.cancel(taskId)`; the local/runtime adapter reaches bridge `cancel_transfer` (or the provider context directly), and Go `CancelTransfer` aborts the HTTP download.
7. `relaunchApp()` starts the new binary, then `os.Exit(0)`.

### Feature: Global Proxy & Network Configuration (全局代理设置)

Three proxy modes: system (default), direct (no proxy), custom (user-specified URL). Affects all outbound traffic. **System mode note (2026-07-08):** Dart's `HttpClient.findProxyFromEnvironment` only reads `http_proxy`/`https_proxy` env vars and ignores the Windows Settings manual proxy. The desktop app now resolves the host-level system proxy via a new bridge method `resolve_system_proxy`, which reads `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings` (`ProxyEnable`/`ProxyServer`) on Windows. Flutter calls it before GitHub update checks and installer downloads so the "follow system" mode actually honors the Windows proxy. Go-side `ProxyTransport` still uses `http.ProxyFromEnvironment` for S3/WebDAV/Baidu traffic.

#### Key files

- `go/config/config.go` — `ProxyMode` / `ProxyURL` fields on `RemoteStorageConfig`; `normalizeProxyMode` validates to system/direct/custom.
- `go/config/proxy.go` — `ProxyTransport(mode, customURL)` returns an `http.RoundTripper` respecting the mode. `ProxyHTTPClient` wraps it with a timeout.
- `go/s3/client.go` — AWS S3 client uses `ProxyTransport` as its `http.Client.Transport`.
- `go/s3/minio_directory.go` — MinIO client gets `options.Transport` from `ProxyTransport`.
- `go/storage/webdav_backend.go` — WebDAV `http.Client` created via `ProxyHTTPClient`.
- `go/storage/baidu_pan_sdk.go` / `baidu_pan_retry_http.go` — Baidu Pan SDK client replaced via `ApplyBaiduPanProxy` on config save.
- `lib/services/proxy_http_client.dart` — Conditional export: IO → `proxy_http_client_io.dart` (dart:io `HttpClient` with proxy), Web → stub (browser handles proxy).
- `lib/services/update_settings.dart` — GitHub mirror config (separate from proxy): persisted in SharedPreferences, wraps github.com URLs with a mirror prefix.
- `lib/widgets/settings_proxy_section.dart` — Settings UI: proxy mode chips + custom URL input + GitHub mirror input with quick-pick buttons.
- `bridge/dispatch_config.go` — `saveConfig` applies `ApplyBaiduPanProxy` before saving. Also holds `updateProxySettings`, profile CRUD, and cache maintenance handlers (split from `dispatch.go`).

#### Data flow

1. User configures proxy in 设置 → 通用设置 → 网络代理.
2. `SettingsProxySection._save` → `_saveProxySettings` → `widget.api.saveConfig(config.copyWith(proxyMode, proxyUrl))` → Go `saveConfig` → `ApplyBaiduPanProxy` + `SaveProfile`.
3. On next S3/WebDAV/MinIO client creation, `ProxyTransport(cfg.ProxyMode, cfg.ProxyURL)` is applied.
4. Dart http calls (GitHub API, download) use `createProxyHttpClient(ProxyConfig(mode, customUrl))`. In system mode the update section first calls `api.resolveSystemProxy()` and converts a Windows registry proxy into a custom `ProxyConfig` because Dart cannot read the Windows system proxy directly.
5. GitHub mirror wraps **download** URLs only (via `UpdateNetworkConfig.wrapUrl` in `app_installer_io.dart`); the Release API call bypasses the mirror entirely.
- `go/config/proxy.go` 鈥?`ProxyTransport(mode, customURL)` returns an `http.RoundTripper` respecting the mode. `ProxyHTTPClient` wraps it with a timeout.
- `bridge/dispatch_system_proxy.go` + `dispatch_system_proxy_windows.go` / `_other.go` 鈥?`resolve_system_proxy` bridge method: reads Windows registry `ProxyEnable`/`ProxyServer` on Windows, returns empty on other platforms.
- `lib/models/system_proxy_info.dart` 鈥?Dart mirror of the Go `systemProxyResult`.
- `lib/widgets/settings_update_section.dart` 鈥?`_resolveEffectiveProxy()` queries `api.resolveSystemProxy()` in system mode before update check and install download, converting the result to a `ProxyConfig(mode: custom)`.

### Feature: App Modal (统一拟态框)

**Binding rule (2026-07-11):** User-facing modal UI defaults to **in-app app modals** (single Flutter engine). OS `desktop_multi_window` editors are **debug-only Experimental**. Business code must not call `showShadDialog` directly — only `lib/services/app_modal.dart` may wrap it.

#### Unified API

- `lib/services/app_modal.dart` — Sole business entry for in-app modals:
  - `showAppModal` — builder returning a `ShadDialog` / dual-mode editor.
  - `showAppModalDialog` — title / description / body / actions helper for simple forms.
  - `showAppConfirmModal` — yes/no confirmations (`cancel` + `confirm`, optional `destructive`).
  - Constants: `kAppModalDefaultMaxWidth = 480`, `kAppModalDefaultContentWidth = 420`.
  - The only allowed `showShadDialog` call lives here.
- `lib/services/modal_sub_window_debug.dart` — `preferModalSubWindows = kDebugMode && USE_MODAL_SUB_WINDOWS`.
- `lib/services/desktop_overlay.dart` — `showDesktopOverlayOrDialog`: debug OS sub-window only when gate + supported; otherwise in-app modal. **Current sole production caller:** `showRemoteDirectoryPicker`.

#### Inventory (all current in-app modals)

Catalogued 2026-07-14. Presentation is always in-app `showAppModal*` unless noted under dual-mode / debug sub-window.

##### Dual-mode large editors (default `asDialog: true`; optional debug OS sub-window)

| Modal | Entry / widget | Opened from | Notes |
|-------|----------------|-------------|-------|
| Account editor | `CloudStorageAccountDialog` | `account_editor_presenter.dart` from account management or file-manager recovery | Compact in-app max width **520**. Main form keeps connection fields only; path-style + proxy open nested **高级设置** modal (`showAppModal`, max **420**). Content-fit resize only in sub-window. |
| Sync profile editor | `FileSyncProfileEditor` | `file_sync_tasks_page_actions.dart` add/edit | Comfortable max width **600**. **3-step** wizard: 同步两端 → 同步策略 → 高级设置（排除规则 / 启用）. Nested remote picker. |
| Remote directory picker | `showRemoteDirectoryPicker` / `RemoteDirectoryPickerDialog` | Sync editor step 1 | Comfortable max width **640**, body height **480**. Via `showDesktopOverlayOrDialog`. |

Debug sub-window shells (only when `preferModalSubWindows`): `AccountEditorWindowApp`, `SyncEditorWindowApp`, `RemoteDirectoryPickerWindowApp` — see **Feature: Desktop Modal Sub-Window Shell**.

##### File manager / objects

| Modal | Entry | Opened from | Purpose |
|-------|-------|-------------|---------|
| Create directory | `CreateDirectoryDialog` | `file_manager_page_actions.dart` | Name input + create. |
| Rename object | `showRenameObjectDialog` | `file_manager_page_actions.dart` | Rename file/dir. |
| Copy / move target path | `showObjectTargetPathDialog` | file-manager actions / selection | Path form for copy or move. |
| Delete object | `showDeleteObjectDialog` | `file_manager_page_actions.dart` | Single delete confirm. |
| Batch delete objects | `showDeleteObjectsDialog` | `file_manager_page_selection.dart` | Multi-select delete confirm. |
| Bucket settings | `showBucketSettingsDialog` | `file_manager_page_bucket_policy.dart` | Per-bucket read-only + trash policy. |
| Mount bucket | `showMountBucketDialog` | `file_manager_page_mount.dart` | Mount path + read-only mode. |
| File preview | `FilePreviewDialog` via `showAppModal` | `file_manager_page_preview.dart` | In-app image/text preview; separate non-modal OS preview window also exists. |
| Batch task progress | `BatchTaskProgressDialog` via `showAppModal` | `file_manager_page_upload_feedback.dart` | Upload/download/copy/move progress; can background. |
| Breadcrumb overflow | inline `ShadDialog` via `showAppModal` | `file_manager_breadcrumb_bar.dart` | Jump to collapsed path segments. |
| Page error / message | inline `ShadDialog` via `showAppModal` | `file_manager_page_actions.dart` `_showPageMessage` | Generic failure / info. |

Object/trash dialog helpers live in `lib/widgets/object_action_dialogs.dart`. Create-directory UI is `lib/widgets/create_directory_dialog.dart`. Bucket/mount: `bucket_settings_dialog.dart`, `mount_bucket_dialog.dart`. Preview/progress: `file_preview_dialog.dart`, `batch_task_progress_dialog.dart`.

##### Trash

| Modal | Entry | Opened from | Purpose |
|-------|-------|-------------|---------|
| Permanent delete (one) | `showDeleteTrashItemDialog` | file-manager trash + `global_trash_page.dart` | Hard-delete one trash item. |
| Permanent delete (batch) | `showDeleteTrashItemsDialog` | `global_trash_page.dart` | Hard-delete multiple. |
| Empty trash | `showClearTrashDialog` | file-manager trash + global trash | Clear one bucket trash. |

##### Share

| Modal | Entry | Opened from | Purpose |
|-------|-------|-------------|---------|
| Share duration | `showShareDurationDialog` | file-manager actions, share management refresh | Hours input + presets (1h–7d). |
| Share created | `showShareLinkDialog` | after create share | Copy/open link. |
| Share details | `showShareRecordDetailsDialog` | `share_management_page.dart` | Detail + copy/open/refresh/delete actions. |
| Delete share (one) | `showDeleteShareRecordDialog` | share management | Confirm delete one record. |
| Delete share (batch) | `showDeleteShareRecordsDialog` | share management multi-select | Confirm delete many. |

All in `lib/widgets/share_dialogs.dart`.

##### Sync / accounts / settings / app chrome

| Modal | Entry | Opened from | Purpose |
|-------|-------|-------------|---------|
| Delete sync profile | `showAppConfirmModal` | `file_sync_tasks_page_actions.dart` | Confirm delete sync config. |
| Clear finished transfers | inline `ShadDialog` via `showAppModal` | `transfers_page.dart` | Remove finished/failed/cancelled queue rows. |
| Reset all accounts | inline `ShadDialog` via `showAppModal` | `settings_reset_user_config_section.dart` | Destructive clear of saved accounts. |
| Advanced S3 settings | inline `ShadDialog` via `showAppModal` | `config_right_form.dart` | Region + path-style (first-run / legacy form). |
| Close app | inline `ShadDialog` via `showAppModal` | `desktop_window_controls.dart` | Tray hide vs exit (or minimize vs exit). |
| Profile / gateway picker | `ProfilePickerDialog` | currently no live caller found | Switch remote storage gateway; keep for potential reuse. |

#### Not app modals

- `FilePreviewWindowApp` — detached non-modal preview window (no scrim / overlay release).
- Toasts (`showAppToast` / `showAppErrorToast`) — non-blocking, not modal routes.
- Context menus / overflow menus — not modal dialogs.

#### Gotchas

- Large editors with internal `Expanded` / fixed-height lists must not get an outer `SingleChildScrollView` on top. Prefer finite height inside `ShadDialog` (picker uses height 420) or `scrollable: true` only when the body is `mainAxisSize: min`.
- Hover / close chrome still follows global hover rules (`ListInteractionColors`; no ink splash; neutral wash only).
- Web always uses app modals (window services unsupported).
- Dual-mode editors must stay **smaller than the main window**: account/sync **~600–640**, remote picker **~640×480**. Prefer more steps / nested advanced modals over widening. Account path-style + proxy live in nested 高级设置; sync exclude/enable is step 3.
- Prefer `showAppConfirmModal` for simple yes/no; prefer dedicated widgets/helpers when the body has form fields, lists, or progress.
- When adding a new modal: enter only through `showAppModal*`, keep content under 500 lines (split by part/feature), and update this inventory.

### Feature: Desktop Modal Sub-Window Shell (通用子窗口壳)


Three **debug-only** modal sub-windows (account editor, sync editor, directory picker) share a common lifecycle when `preferModalSubWindows` is on: detached OS window with hidden title bar → custom 44px title bar → bootstrap bridge/data → loading/error/content body → modal scrim + overlay release on close. Previously each window re-implemented this from scratch (title bar widget × 3, close function × 3, `WindowLifecycle` × 2, `_configure*Window` × 4). A shared abstraction now handles all of it.

#### Shared components

- `lib/widgets/desktop_modal_shell.dart` — `DesktopModalShell` (StatelessWidget): 44px title bar with title + close button. Replaces `_AccountEditorTitleBar` / `_SyncEditorTitleBar` / `_PickerTitleBar`.
- `lib/app/desktop_modal_sub_window_app.dart` — `DesktopModalSubWindowApp<T>` (StatelessWidget): generic sub-window root. Encapsulates `ShadApp` + theme, `_ModalSubWindowLifecycle` (overlay release on dispose/close), `DesktopModalParentFocusRelay` (optional via `useParentFocusRelay`), `DesktopModalWindowFocusGate`, `DesktopModalScrim`, `DesktopModalShell`, and bootstrap-driven loading/error/content body. Features supply `bootstrap: Future<T> Function()` and `contentBuilder: Widget Function(BuildContext, T, Future<void> Function() close)`. The third `close` arg is the public close sequence `closeDesktopModalSubWindow(...)` (formerly private `_closeModalSubWindow`): optional `onClose` → unregister child → notify creator overlay release → clear chrome → `windowManager.close()`. **`scrollable` (default true):** when true, body is `Padding` + `SingleChildScrollView` (form-like content such as the account editor). When false, body is only `Padding` so content receives finite height from the shell `Expanded` — required for widgets that use `Expanded` / fill-height lists (`FileSyncProfileEditor`, `RemoteDirectoryPickerDialog`). Never wrap those fill-height editors in an outer scroll view.
- `lib/app/desktop_modal_window_config.dart` — `configureDesktopModalSubWindow()`: unified `WindowOptions` + `waitUntilReadyToShow` + `applyModalChildWindowChrome` + `setTitle` + `show` + `positionChildCenteredFromFrame` + `focus`. Replaces per-window `_configure*Window` functions.

#### Migrated windows

- `lib/app/account_editor_window_app.dart` — `DesktopModalSubWindowApp<RemoteStorageGateway>` with `scrollable: true` (overflow safety only when content exceeds screen clamp), `bootstrap` → `defaultRemoteStorageApiFactory()`, `contentBuilder` → `_AccountEditorContent` (save + Baidu OAuth). `onSaved` notifies parent then `close()`; `onCancel` calls `close()`. Content-fit resize lives in `CloudStorageAccountDialog` (`MeasureSize` + `fitModalSubWindowToContentSize`).
- `lib/widgets/measure_size.dart` — `MeasureSize` RenderObject reports child size changes (including descendant-only rebuilds such as proxy custom fields).
- `lib/services/desktop_sub_window_modal.dart` — `fitModalSubWindowToContentSize` converts measured body size + title bar (44) + content padding into a centered OS window size, clamped to fixed min/max only (never `FlutterView.physicalSize` — that is the child window in multi-window).
- `lib/app/sync_editor_window_app.dart` — `DesktopModalSubWindowApp<_SyncBootstrapResult>` with **`scrollable: false`** (editor owns step indicator + internal scroll + pinned nav via `Expanded`). `bootstrap` → load profiles + buckets; `contentBuilder` → `_SyncEditorContent`; `onSaved` → `close()`. Deleted: `_SyncEditorTitleBar`, `_closeSyncEditorWindow`, `SyncEditorWindowLifecycle`.
- `lib/app/remote_directory_picker_window_app.dart` — `DesktopModalSubWindowApp<RemoteStorageGateway>` with **`scrollable: false`**, `useParentFocusRelay: false`. `onConfirm` stashes result then `close()`; `onCancel` clears result then `close()`; title-bar X still runs shell `onClose` → `_sendResult` (null if no selection). Deleted: `_PickerTitleBar`, inline `_finish`, `_RemoteDirectoryPickerBody`.
- `lib/app/app_entry_io.dart` — All three modal windows now configured via `configureDesktopModalSubWindow()`. Deleted: `_configureSyncEditorWindow`, `_configureAccountEditorWindow`, `_configureRemoteDirectoryPickerWindow`. `_configurePreviewWindow` remains (non-modal, center:true, no chrome).

#### Initial window sizes (current)

- Account editor: `_accountEditorWindowSize` in `app_entry_io.dart` seeds only — new `640×360`; edit Baidu `640×480` / WebDAV `640×520` / S3 `640×560`, min `400×280`. Runtime size comes from content measure. In-app dialog max width is **640**. Nested advanced modal max width **480**.
- Sync editor: fixed initial `600×480` in `app_entry_io.dart`; step sizes `600×480` / `600×500` / `600×480`. In-app dialog max width is **640**. Three steps: endpoints, strategy, advanced.
- Remote directory picker: fixed `640×560` (min `480×400`); in-app dialog max width **640** / body height **480**; dialog fills height with `Expanded` list (`scrollable: false` shell).


#### Not migrated

- `FilePreviewWindowApp` — non-modal standalone window (no scrim, no overlay release, draggable title bar). Mode is fundamentally different; stays independent.

#### Open-path routing (policy 2026-07-11)

| Flow | Default (release / normal debug) | Debug OS sub-window |
|------|----------------------------------|---------------------|
| Account editor | `CloudStoragePage` → `showAppModal` + `CloudStorageAccountDialog(asDialog: true)` | Only when `preferModalSubWindows` → `AccountEditorWindowService.openEditor` |
| Sync editor | `file_sync_tasks_page_actions` → `showAppModal` + `FileSyncProfileEditor(asDialog: true)` | Only when `preferModalSubWindows` → `SyncEditorWindowService.openEditor` |
| Remote directory picker | `showRemoteDirectoryPicker` → in-app modal via `showDesktopOverlayOrDialog` → `showAppModal` | Only when `preferModalSubWindows` → `RemoteDirectoryPickerWindowService.openPicker` |
| Other dialogs | Always `showAppModal` / `showAppConfirmModal` | No sub-window |
| File preview | Independent non-modal window (unchanged) | Unchanged |

**Debug gate:** `lib/services/modal_sub_window_debug.dart` — `preferModalSubWindows = kDebugMode && bool.fromEnvironment('USE_MODAL_SUB_WINDOWS', defaultValue: false)`. Enable with `--dart-define=USE_MODAL_SUB_WINDOWS=true` in a debug build. Desktop window services set `isSupported => preferModalSubWindows` (web remains false). Never open multi-window modals just to look more “native” for users.

Near-500 dual-mode content widgets: `cloud_storage_account_dialog.dart` (~471), `file_sync_profile_editor.dart` (~480), `remote_directory_picker_dialog.dart` (~446). Shell/services are well under 500 except `desktop_sub_window_modal.dart` (~355).

#### Gotchas

- Never set `scrollable: true` for content that uses `Expanded`, `height: double.infinity`, or an internal scroll region (`FileSyncProfileEditor._buildSubWindowLayout`, `RemoteDirectoryPickerDialog`). The outer `SingleChildScrollView` makes height unbounded and crashes with `RenderFlex children have non-zero flex but incoming height constraints are unbounded`.
- Content must call the injected `close` from save/cancel/confirm paths. Title-bar X already calls shell `onClose` → `closeDesktopModalSubWindow`; empty `onCancel` / `onSaved` callbacks leave the window open after the migration.
- Do not nest `ShadDialog` in modal sub-windows (`asDialog: false`). File preview is not this shell — leave it alone.
- Account editor uses **content-measured** resize (`MeasureSize` + `fitModalSubWindowToContentSize`), not hand-tuned per-step heights. Only shrink-wrapped (`MainAxisSize.min`) form content may use it. Sync editor / directory picker keep discrete or fill-height layouts and must not call content-fit.
- Content-fit must add shell chrome: title bar 44px + content padding `LTRB(24,16,24,24)` (+ small height fudge). Measuring only the form body and applying that as the OS window size leaves chrome cut off or reintroduces scroll/whitespace.
- `MeasureSize` must report the **child's unconstrained height** (layout with `maxHeight: infinity`), not the short size forced by the parent `Expanded`/seed window. Reporting the clamped parent size under-measures and clips the button row.
- After content-fit resize, re-center with `positionChildCenteredFromFrame` using the creator frame from window args. Do not only call `resizeKeepingWindowCenter` on first show — the child may still be at a default OS origin and will jump/off-center.
- Never clamp content-fit with `FlutterView.physicalSize` / `platformDispatcher.views.first` inside a multi-window child engine — that reports the **current sub-window**, so `max = size * 0.9` shrinks the dialog on every next/back. Use fixed `maxSize` (or a real monitor API from the main process), never the child view size.

### Feature: Responsive Page Header Actions (页面头部响应式操作区)

All list-style pages (任务队列 / 分享管理 / 回收站 / 文件同步 / 账号管理) share the same header pattern: a left `Flexible(Column(title + subtitle))` and right-side action buttons. When many buttons are visible (e.g. bulk-selection mode), the title column was squeezed and the subtitle wrapped mid-sentence. A shared `PageHeaderActions` widget now collapses secondary actions into a `…` overflow menu (`ShadContextMenu`) when the available width drops below a threshold.

#### Key files

- `lib/widgets/page_header_actions.dart` — `PageHeaderActions` (StatelessWidget): takes `primary` (always laid out) and `secondary` (`List<SecondaryAction>`). Uses `LayoutBuilder` to compare `constraints.maxWidth` against `overflowThreshold` (default 520). When wide, renders all primary + secondary `.builder()` inline; when narrow, renders primary + an `_OverflowMenuButton` whose `ShadContextMenu` items come from `secondary` `.label` / `.onPressed`. `_OverflowMenuButton` mirrors the existing `_BucketOverflowMenuButton` pattern (`ShadContextMenuController` + `DesktopContextMenuRegistry` group `_pageHeaderOverflowGroup` + `ShadGlobalAnchor`). `SecondaryAction` carries `label`, `builder`, `onPressed`, `enabled`.
- `lib/widgets/transfer_task_widgets.dart` — `TransferTaskSelectionActions` now wraps `PageHeaderActions`. Primary: 已选 N 项 badge + 批量开始 + 批量取消. Secondary: 移除记录 / 清空选择 / 清空已完成 (new `onClearFinished` + `finishedCount` params moved from the page-level standalone button).
- `lib/pages/transfers_page.dart` — header `Row` simplified: `Flexible` title column + single `TransferTaskSelectionActions` (no separate 清空已完成 button). Subtitle gained `maxLines: 2`.
- `lib/pages/share_management_page.dart` — header rebuilt via `PageHeaderActions`. Selected: primary 已选 N 项 + 删除选中; secondary 取消选择. Unselected: primary 刷新.
- `lib/widgets/global_trash_controls.dart` — `GlobalTrashHeaderActions` wraps `PageHeaderActions`. Selected: only the 已选 N 项 badge + 批量恢复 + 批量彻底删除; there is no header-level 清空选择 action, and users deselect through the row/header checkboxes. Both states use a 42px minimum action-area height because Shad's regular outline button renders 2px taller than regular ghost/destructive variants; selected batch buttons also use regular size. Unselected: primary 刷新; secondary 清空回收站. `test/global_trash_header_actions_test.dart` locks the equal-height, single-row, and hidden-action behavior at the 360px header width.
- `lib/pages/global_trash_page_view.dart`, `lib/pages/file_sync_tasks_page.dart`, `lib/pages/cloud_storage_page.dart` — title column switched `Expanded` → `Flexible(fit: FlexFit.tight)`; subtitle gained `maxLines: 2, overflow: ellipsis` as a hard floor.

#### Gotchas

- The title column must be `Flexible(flex: 1, fit: FlexFit.tight)`, not `Expanded`, so the right-side `PageHeaderActions` `Wrap` is measured by `LayoutBuilder` against the real remaining width; with `Expanded` the title took all space and the actions never saw a width constraint.
- `_OverflowMenuButton` must be a `StatefulWidget` owning the `ShadContextMenuController` and `_menuAnchorOffset`; the `onPressed` of `ShadButton.outline` computes the anchor via the button's `GlobalKey` + `localToGlobal` before `_controller.show()`.
- Single-button headers (文件同步 新建配置, 账号管理 新增账号) intentionally do NOT use `PageHeaderActions` — they can't overflow, but the `Flexible` title column + subtitle `maxLines` floor still applies for consistency.


### Feature: Per-Account Proxy (账号独立代理)

Each storage account can choose its own outbound proxy policy. The default is `inherit` (跟随全局); explicit alternatives are `system`, `direct` (no proxy), or `custom` HTTP/SOCKS5 with optional authentication. The global proxy is persisted independently in the bbolt `meta` bucket and acts only as the fallback for inheriting accounts.

#### Key files

- `go/config/config.go` — Defines `ProxyModeInherit` and normalizes all four account modes. New account configs default to `inherit`.
- `go/config/global_proxy.go` — Persists the global proxy subset under bbolt `meta/global_proxy` via `LoadGlobalProxy` / `SaveGlobalProxy`. Global mode cannot itself be `inherit`; it normalizes that value to `system`.
- `go/config/proxy.go` — `ResolveProxyConfig(account, global)` copies global proxy fields only when the account mode is `inherit`; explicit system/direct/custom accounts are untouched.
- `go/storage/types.go` — `ForConfig` loads the global proxy, resolves inheritance, then constructs S3/WebDAV/Baidu backends from the effective config.
- `go/storage/baidu_pan_sdk.go` / `baidu_pan_retry_http.go` — Builds a per-account xpan HTTP client carrying both the effective proxy transport and per-account OAuth credentials. The global xpan client remains only as a fallback for legacy code paths.
- `bridge/dispatch_config.go` — `update_proxy_settings` writes only the independent global proxy record; it no longer overwrites every profile. Bootstrap returns global proxy fields to the Settings page.
- `lib/widgets/account_proxy_section.dart` — Account-editor proxy UI: 跟随全局 / 跟随系统 / 直连 / 自定义; custom expands HTTP/SOCKS5 host/port/auth fields.
- `lib/widgets/cloud_storage_account_dialog.dart` — Embeds `AccountProxySection` for S3/WebDAV/Baidu accounts and submits proxy values with the account draft.
- `lib/models/cloud_storage_account_draft.dart` / `lib/utils/account_config_builder.dart` / `lib/models/remote_storage_config.dart` — Carries and serializes per-account proxy values; new accounts default to `inherit`.
- `lib/widgets/settings_proxy_section.dart` — Global proxy UI; copy explains that accounts may override it.
- `github.com/lfhy/xpan v0.2.0` (local repo `../xpan`) — Adds per-call HTTP clients and per-`Client` credentials so concurrent Baidu accounts no longer race on global tokens. The SDK work is split into commits `6b64c93` (per-call client) and `4ab8c36` (multi-account credentials), tagged `v0.2.0`.

#### Data flow

1. Settings global proxy -> `update_proxy_settings` -> `config.SaveGlobalProxy` (`meta/global_proxy`).
2. Account editor saves `proxyMode` plus custom fields in that profile.
3. Storage operation -> `storage.ForConfig` -> `LoadGlobalProxy` -> `ResolveProxyConfig`.
4. Explicit account modes use their own transport; `inherit` accounts receive the global proxy fields.
5. Baidu operations create `xpanclient.NewWithClient` with a retry client that exposes the account credentials and uses the resolved proxy transport.

#### Gotchas

- Do not reintroduce the old behavior where `updateProxySettings` loops over profiles; that destroys per-account overrides.
- `direct` is a valid per-account override and means no proxy even when the global proxy is custom.
- The temporary local `replace github.com/lfhy/xpan => ../xpan` is only for validation before v0.2.0 is pushed. Remove it after the tag is published and run `go mod tidy`.

### Feature: Object Delete / App Trash (软删除与回收站)

Deleting an object from the file manager is a soft delete by default for S3 accounts: the object tree is moved (CopyObject per entry + DeleteObject per source) into a bucket-level trash prefix, then metadata is persisted. That is why a UI "delete" can surface S3 CopyObject errors.

#### Key files

- `lib/pages/file_manager_page_actions.dart` (`_runObjectAction`, delete branch) and `lib/pages/file_manager_page_selection.dart` (`_deleteSelectedObjects`) — confirm via `showDeleteObjectDialog` / `showDeleteObjectsDialog` (`lib/widgets/object_action_dialogs.dart`; both take `trashEnabled:` and return `Future<DeleteDialogChoice>` (`confirmed` + `permanent`), dismiss → confirmed:false). Dialog body is the shared `DeleteDialogBody` StatefulWidget: target label + `ShadSwitch` 永久删除 (only when `trashEnabled`, sublabel 不移入回收站，删除后无法恢复) + cancel/destructive actions; description switches between 移入回收站 and 此操作不可撤销 based on trash state. Then `_queueObjectDeletes(permanent:)` + `_showDeleteProgressDialogForTasks` (`lib/pages/file_manager_page_upload_feedback.dart:16` → `BatchTaskProgressDialog` with `BatchTaskProgressMode.delete`).
- `lib/pages/file_manager_page_object_deletes.dart` — `_queueObjectDeletes` (:8, `permanent` named param) starts `TransferKind.delete` tasks (`localPath: ''`) and runs `_runDeleteTask` (:73) -> `api.deleteObject(config, bucket, key, isDir, taskId, permanent: permanent)` + cache evict + `markTaskDone/markTaskFailed`; failures are collected and surfaced via `_showPageMessage(title: '删除失败', ...)` (raw `error.toString()`, which keeps the `RemoteStorageBridgeException:` prefix).
- `lib/services/remote_storage_api_desktop_storage.dart:69` / `lib/services/remote_storage_api_web_objects.dart:61` — gateway `deleteObject` -> bridge op `delete_object` with `{config, bucket, key, isDirectory, taskId, permanent}`. Gateway interface `lib/services/remote_storage_gateway.dart:135` declares `permanent = false` named param (test fakes must match).
- `bridge/dispatch.go:66` (`delete_object` case) and `:293` (handler) — `objectMutationArgs` carries `permanent`; handler picks `backend.DeleteObjectHard` when permanent, else `backend.DeleteObject` (trash-routed); on success calls `bucketmount.NotifyExternalDelete`. Web path: `go/webapi/invoke.go:222` (same permanent routing on `invokeEnvelope.Permanent`). Trash ops: `bridge/dispatch.go:68-77` + `bridge/dispatch_trash.go` (`list_trash`, `list_trash_page` in `bridge/dispatch_paging.go`, `restore_trash_item`, `delete_trash_item`, `clear_trash`).
- `go/storage/s3_backend.go:66` — `DeleteObject` routes by per-bucket trash flag: trash disabled -> `s3ops.DeleteObjectHardContextWithTask`; trash enabled -> `s3ops.DeleteObjectContextWithTask` (soft delete). `s3Backend.DeleteObjectHard` (:82) is reachable from the file manager via the `permanent` flag, and from the mount delete queue. `go/config/config.go:397` `BucketSettingsFor` defaults `TrashEnabled=true` for `StorageTypeS3`, overridable per bucket (`bucketSettings[bucket].trashEnabled`, `trashDirectory`); Dart mirror `lib/models/remote_storage_config.dart:418` + `lib/models/bucket_settings.dart`.
- `go/s3/object_mutations.go` — soft `DeleteObjectContext(WithTask)` (:30, `startTransfer(taskID,"delete",…,0,cancel)` :46) delegates to `MoveObjectToTrashContextWithTask` (`go/s3/trash_ops.go:39`, passes taskID through). Hard path: `DeleteObjectHardContextProgress` lists via `mutationEntriesWithProgress` (reports TotalItems up front) then `deleteEntriesHardWithTask` (per-key resilient delete + `AdvanceTransferItems` per key); `DeleteObjectHardContextWithTask` (:110) registers the task and forwards taskID so hard deletes show a determinate item bar. `DeleteObjectHardContext` keeps the zero-progress path for internal callers.
- `go/s3/trash_ops.go` + `go/s3/trash_helpers.go` + `go/s3/trash_index.go` — `MoveObjectToTrashContext(WithTask)`: trims key, skips trash keys, `mutationKeys` (count), generates UUID, target = `<trashDir>/objects/<uuid>/<originalKey>` (trashDir default `.trash`, config `trashDirectoryName`), calls `MoveObjectContextWithTask` (copy + delete-source, taskID forwarded), then `buildTrashMetadata` + `persistTrashMetadata` (index objects under `.trash/index/`; legacy `.trash/entries/<id>.trashinfo.json` fallback). Retention purge: `go/s3/trash_purge_scheduler.go` (10 min cooldown, `trashRetentionDays`, default 30 / -1 disables).
- `go/s3/object_moves.go:79` `MoveObjectContextWithTask` — when taskID set, pre-reports TotalItems via `mutationEntriesWithProgress` (single enumeration reused by `buildObjectTransferPlan`), then `executeObjectCopyPlan` (`object_transfer_run.go:51`: per-entry resilient CopyObject, placeholders become PutObject markers, `advanceTransferTaskProgress` bumps bytes + items per entry) and finally `deleteObjectKeysHardWithTask` on `plan.deleteKeys` (items keep advancing past copy total, so a trash-move bar runs to 200% of copy items = 100% overall). This copy phase is the CopyObject that appears in delete error messages. Byte progress still flows via `beginObjectTransferTask` (`startTransfer(…,plan.totalBytes,cancel)`). `plan.deleteKeys` is captured at plan build time (`object_transfer_plan.go` + `transferEntryKeys` in `object_entries.go`); `listMutationEntries` also calls `ensureDirectoryRootEntry` so a provider that omits the source `dir/` marker while listing children cannot leave an empty directory after restart. The cleanup must NOT re-list the source prefix, because a re-list can observe keys already deleted mid-sweep and silently skip them, leaving stale source objects behind. `go/s3/object_move_cleanup_test.go` covers both the captured key set and the omitted-root-marker response.
- `go/s3/object_transfer_progress.go` — `sumTransferEntrySizes` (byte totals) + `advanceTransferTaskProgress` (bytes + item per finished entry). `go/s3/object_delete_progress.go` — `deleteObjectKeysHardWithTask` / `deleteEntriesHardWithTask` (per-item delete progress). `go/s3/object_entries.go` `mutationEntriesWithProgress` — enumerates a prefix and reports TotalItems immediately. `go/s3/transfer_phases.go` + `PlanTransferPhaseItems`/`resetTransferPhaseItems`/`PlannedTransferItems` in `go/s3/transfer_monitor.go` — phase-aware item accounting so copy and delete phases of one sweep never double-count or overshoot. Item fields surface in Flutter via `TransferSnapshot.totalItems/itemsCompleted` → `TransferTask` → `BatchTaskProgressDialog` (determinate summary bar when `totalItems > 0`, `x / y 个对象` chips + per-row subtitle with `正在删除源对象` during the cleanup phase; transfers page `_subtitleFor` shows the same counts). Tests: `go/s3/transfer_phase_plan_test.go`.
- Flutter trash flag: `lib/models/remote_storage_config.dart` `bucketSettingsFor` (:416, `defaultTrashEnabled = storageType == StorageType.s3` :418) / `bucketTrashEnabled` (:429); `lib/models/bucket_settings.dart` `BucketSettings.isTrashEnabled` (:48). File manager: `lib/pages/file_manager_page_bucket_policy.dart` `_bucketTrashEnabled` (:14) + `_activeBucketTrashEnabled` (:20) — feeds the delete dialogs' switch visibility. Edit UI: `lib/widgets/bucket_settings_dialog.dart` (ShadSwitch inside ShadDialog via StatefulBuilder :24-63); the delete dialogs use the `DeleteDialogBody` StatefulWidget variant.
- `go/s3/client.go` — single `s3.New(opts)` client: static creds, `Region`, `BaseEndpoint=cfg.Endpoint`, `UsePathStyle`, proxy override only for direct/custom. Global client keeps the AWS SDK v2 default retry (3 attempts); sweep call sites opt into a bigger per-call budget.
- `go/s3/aws_retry.go` + `go/s3/object_copy_retry.go` — per-call retry layer for single-object sweep calls (CopyObject, HeadObject, DeleteObject, placeholder PutObject). `singleObjectCallOptions()` attaches a standard retryer with 5 attempts / 15s max backoff to individual API calls (not the client); on top of that, `runSingleObjectSweep` re-issues calls that fail with vendor-flaky non-retryable errors (`isSweepWorthyError`: InvalidArgument/InvalidRequest codes, non-retryable 5xx-ish codes, transport errors) up to 3 extra times with a 2s delay (test-shrunk via `singleObjectSweepRetryDelay`). Delete sweeps route through `go/s3/object_delete_sweep.go` `deleteObjectKeysHard`; copy sweeps through `copyObjectResilient`/`putDirectoryPlaceholderResilient` in `object_transfer_run.go`; plan sizing through `headObjectResilient` in `object_transfer_plan.go`. Tests: `object_copy_retry_test.go`.

#### Gotchas

- Soft-delete moves one object at a time; for a directory the whole tree is copied to trash before any source delete, so deleting large directories is N CopyObject + N DeleteObject calls and fails entirely if one copy fails. Per-call retries (`aws_retry.go` / `object_copy_retry.go`) absorb transient gateway errors (502 HTML pages, connection resets, vendor InvalidArgument glitches), but a persistent outage still aborts the whole delete with the raw SDK error shown in 删除失败 dialogs.
- Some S3-compatible services omit the exact directory marker from `ListObjectsV2` once children exist. Never use the raw recursive listing alone as a directory mutation plan: `ensureDirectoryRootEntry` deliberately adds `dir/`, making target placeholder creation and idempotent source-marker deletion part of copy/move/soft-delete/hard-delete operations.
- The 永久删除 dialog switch only appears when the bucket has trash enabled; it is enforced bridge-side (`permanent` → `DeleteObjectHard`), so the Dart flag is advisory, not authoritative. Buckets with trash disabled never show the switch (their deletes are already permanent).
- Delete task progress is item-based (TotalItems/AdvanceTransferItems), not byte-based: the summary bar in `BatchTaskProgressDialog` prefers `totalItems > 0` over bytes. Item accounting is phase-aware (`PlanTransferPhaseItems` in `go/s3/transfer_monitor.go`, phases in `go/s3/transfer_phases.go`): a trash move plans a "delete" phase from the source listing (worst case) and a "copy" phase from the target-tree enumeration; identical re-enumerations replace rather than double-count. Between copy and source cleanup, `MoveObjectContextWithTask` calls `resetTransferPhaseItems` + `SetTransferStatusDetail(taskID,"deleting")` so the bar restarts at 0/N for the deletion phase. `finishTransfer` settles ItemsCompleted=TotalItems so completed tasks never show overshoot like 206/103.
- `RestoreTrashItem` copies back from trash key to original key; `DeleteTrashItem`/`ClearTrash` hard-delete trash payloads (`trash_ops.go:344+`).
- File manager page has no persistent inline transfer tray: delete feedback is the modal `BatchTaskProgressDialog` only; in-row feedback is `deletingKeys` (`_deletingObjectKeys`, `file_manager_page.dart:130` → passed as `deletingKeys` :461 to `FileManagerObjectBrowser`); finished/failed status afterwards lives only on the Transfers page (`lib/pages/transfers_page.dart`).
- Mount delete queue (`go/mount/delete_queue.go`) also calls backend `DeleteObject`/`DeleteObjectHard` and treats `CopyObject`+`InvalidArgument` errors as non-retryable.
- Trash UI: file-manager header trash icon (`lib/widgets/file_manager_action_bar.dart:153-176`, gated by `_activeBucketTrashEnabled`), per-bucket trash browser `lib/widgets/file_manager_trash_browser.dart`, global page `lib/pages/global_trash_page.dart` + `lib/widgets/global_trash_browser.dart`, settings section `lib/widgets/settings_trash_section.dart`, sidebar entry `lib/pages/main_layout_page.dart:197`.

### Feature: Windows Cloud Files Remote Deletion Projection

`NotifyExternalDelete` now synchronizes both the Go-side `bucketCache` and the physical Windows Cloud Files sync root. `bucketAccess.MarkExternalDelete` cancels pending writeback before applying the tombstone, then invokes the Windows backend projection installed while the Cloud Files session is active. The projection removes the local file/directory under `Cloud Volume\\<bucket>` and records a short-lived provider-delete marker so both fsnotify and `NOTIFY_DELETE_COMPLETION` treat the removal as provider-owned instead of scheduling a duplicate remote delete.

`InvalidateExternalUpload` uses the matching upload projector for app-side directory creation, uploads, copies, and move/rename destinations. It refreshes remote metadata, recreates an overwritten placeholder when needed, and only creates a child when its parent directory is already present in the sync root; otherwise the next Cloud Files placeholder fetch creates the missing tree.

Relevant files and flow: `go/mount/bucket_access.go` owns the session-scoped `externalDelete`/`externalUpload` projectors; `go/mount/bucket_access_reads.go` cancels pending writeback and invokes them from external mutation invalidation; `go/mount/backend_windows_cloud_files_cgo.go` installs/clears the projectors and consumes provider-delete callback markers; `go/mount/cloud_files_external_delete_windows.go` validates paths, removes placeholders, reads remote metadata, and creates new/overwritten placeholders; `go/mount/cloud_files_watcher_state_windows.go` owns provider-delete and ordinary watcher state. Watcher lifecycle tests are split between `cloud_files_watcher_windows_test.go` and `cloud_files_watcher_lifecycle_windows_test.go` to keep both files below 500 lines. File-list delete is `delete_object` -> remote soft delete -> cancel writeback -> cache tombstone -> local placeholder removal. Directory create/upload/copy/move are `NotifyExternalUpload` or `NotifyExternalRename` -> cache invalidation -> remote metadata lookup -> local placeholder creation. Explorer delete remains CFAPI delete completion -> `handleDelete` -> `deletePath` -> async remote delete.

**Test-triage update (2026-07-23):** `restore_trash_item` now carries the `TrashItem` original key/directory flag from Flutter through `bridge/dispatch_trash.go`, then calls `NotifyExternalUpload` after the backend restore. This clears a mounted tombstone and reprojects the Cloud Files placeholder, so restore -> re-delete/rename does not depend on a remount. Cloud Files read-only mode is now rejected bridge-side because CFAPI receives post-operation callbacks and cannot veto Explorer writes; `mount_bucket_dialog.dart` routes strict read-only selections to WinFsp, whose filesystem methods return `EROFS`. The unmount confirmation offers to keep or clear only a managed default Cloud Files sync-root, warns about open files, and `backend_windows_cloud_files_cgo.go` reports an occupied cache cleanup without re-mounting the already disconnected volume.

**Release logging triage (verified 2026-08-10):** an absent `app.log.level` key in `%APPDATA%\\3000y\\Yunjuan\\shared_preferences.json` means a Release build keeps the bridge at `Silent`; `~/.cloud-volume/runtime/logs/bridge.log` may therefore remain a zero-byte file even after a reproduction. Before asking for Cloud Files writeback logs, confirm the Settings log level was explicitly changed to `Debug`, restart/remount if the affected session predates that change, and verify that the log timestamp/size advances before reproducing.

**Explorer upload-then-directory-rename fix (implemented 2026-08-11):** Cloud Files rename callbacks now enqueue an asynchronous writeback barrier through `backend_windows_cloud_files_cgo.go` and `bucket_access_writes.go`. `writeback_rename_queue.go` assigns upload generations: uploads before a directory rename are drained first, the rename retries until it succeeds, and uploads observed below the new path cannot start until that barrier completes. `writebackQueue` rebases queued and in-flight local source paths from the old directory to the new directory before opening them, while retaining their original remote keys so the backend order is upload old key -> rename -> upload new key. `MarkRenameSource` suppresses only stale old-path watcher events and does not leave the renamed tree permanently hydrating. The queue's stop signal is also used for both dispatchers so shutdown cannot send into a closed upload channel. Regression coverage lives in `writeback_rename_queue_test.go` and `cloud_files_watcher_windows_test.go`.

**Cross-client mutation diagnosis, restart-safe moves, and idle refresh (verified 2026-08-14):** `cloud_files_watcher_windows.go` handles Explorer create/rename callbacks synchronously only long enough to stage local state and enqueue work; `backend_windows_cloud_files_cgo.go` routes directory renames through `bucket_access_writes.go` and file moves through `enqueueRenamePath` so the CFAPI callback stays non-blocking. `overlay_bridge.go` sends staged directory markers to `dir_sync_queue.go`, while file uploads and remote moves share `writeback_rename_queue.go`.

**Directory ordering (Task 1, regression anchors live in `dir_sync_queue_test.go`, `bucket_access_remote_probe_test.go`, `writeback_rename_queue_test.go`):** `writeback_rename_queue.go` first drains upload generations captured before a directory rename, then waits the `dirSyncBarrier`, then runs the remote rename, and only then releases later uploads. `dir_sync_queue.go` `rebaseAndFence(old,new,isDir)` rekeys every queued old-prefix create to the new prefix, keeps already-running provider calls on their original path, resolves target collisions by retaining both entries in the barrier, and closes each entry only after its provider call finishes. For a rebased directory create whose old source is proven absent, `bucket_access_writes.go` probes the old path, calls idempotent `createRemoteDirectory(newClean)`, verifies the destination marker, and skips `MoveObject(old,new)` only after the new path exists. Only `os.ErrNotExist` means absence; authentication, network, and listing errors propagate and keep the rename retryable.

**Restart-safe remote moves (Task 2, regression anchors live in `mutation_record.go`, `mutation_store.go`, `mutation_reconcile.go`, `mutation_test_backend_test.go`, `mutation_store_test.go`, `writeback_mutation_recovery_test.go`, and the renamed dir-sync test names):** Every queued remote move is persisted as an append-only, fsync-per-event JSONL record under `<sessionRoot>/mutations/queue-<pid>.jsonl`. `mutation_record.go` `mutationRecordVersion` gates forward compatibility, and `mutationEventUpsert` / `mutationEventComplete` events are the only journal kinds. `mutation_store.go` tolerates exactly one unterminated final line per file (a crash mid-append); interior malformed data and unsupported versions are hard errors that must never silently resurrect or drop a move. Recovery replays every `queue-*.jsonl` log in file order, compacts live records into one uniquely named JSONL file, and finally removes stale process logs without renaming over an existing file on Windows. `bucket_access.go` carries `writebackQueue.mutations`, and `writeback_restore.go` rebuilds upload barriers plus local source rebases before either dispatcher starts while pushing the next queue generation past the maximum restored generation. `mutation_reconcile.go` drives a state-driven retry matrix: `source absent + destination present` mark complete without another provider mutation, `source present + destination absent` call `MoveObject`, `source present + destination present` merge via `CopyObject` + `DeleteObjectHard`, and `source absent + destination absent` retain as a state-conflict. A real provider success still needs a verified postcondition (source probed absent, destination probed present) before `Complete` is written; a crash between provider success and the tombstone stays recoverable because the next reconcile pass sees source-absent/destination-present and converges. Only `os.ErrNotExist` means absence; authentication, network, timeout, and listing errors propagate and keep the record retrying. `mountSession.status()` reads `writebackQueue.mutationLastError()` so durable failures surface without an in-memory callback.

**Bounded idle directory refresh (Task 3, regression anchors live in `remote_poller_test.go`):** `directoryActivityTracker` is a bounded observed-directory set capped at `remotePollDirectoryCap = 12`. Idle entries are no longer deleted by `remotePollWarmWindow`; instead the cap evicts the oldest entry when full, and `nextDelay` becomes a cadence selector (active within 45s, warm between 45s and 3min, idle two-minute refresh otherwise). `SupportsMountRemotePolling()` behavior is unchanged so SFTP remains opted out. Already-open but idle Windows directories therefore keep refreshing on the two-minute cadence, so files written from Linux (or any other client) appear without remounting.

### Feature: Windows WinFsp Virtual File System Engine

Windows mounts can now choose between the Cloud Files shell (default) and a WinFsp-backed virtual file system that reports a real volume with a user-configured capacity to Explorer. The WinFsp engine compiles into every Windows CGO build of the bridge (no build tag); `third_party/winfsp/inc/fuse` headers are vendored in the repo and pointed at via `CPATH` by `run_windows.ps1`, `build_desktop_packages.sh`, `windows/CMakeLists.txt`, and the `Makefile` `bridge-windows` target. Only the non-CGO (`CGO_ENABLED=0`) path uses the stub and reports the engine unavailable.

#### Key files

- `go/mount/backend_windows.go` — `newPlatformMountBackend` now branches on `cfg.WindowsMountEngine`: `winfsp` -> `newWindowsWinFspBackend`, otherwise the existing Cloud Files / WebDAV mode switch. `cleanupAllManagedMounts` also calls `cleanupManagedWindowsWinFspArtifacts`.
- `go/mount/backend_windows_winfsp_cgo.go` — `windowsWinFspBackend` (`//go:build windows && cgo`). `Initialize` requires a requested drive letter and rejects directory targets, because this virtual-volume configuration only mounts reliably as a drive. `Start` resolves capacity in order: bucket custom quota, provider `GetBucketQuota` total/used data, then the global WinFsp fallback when the provider exposes none or its lookup fails. It builds a `winFspBucketFS`, runs `fuse.FileSystemHost.Mount` on a goroutine, polls `IsActive` until ready, and reports volume label `Cloud Volume <bucket>` via `-o volname=...`. It explicitly passes `SectorSize=4096` and `SectorsPerAllocationUnit=1`, matching `Statfs`, so Explorer computes capacity from the same geometry on every supported WinFsp release. `Stop` unmounts once (`stopHost`), waits for the serving goroutine, drains writeback, and releases the bucket access.
- `go/mount/backend_windows_winfsp_stub.go` — `//go:build windows && !cgo`. Reports a clear unavailable error for the pure-Go build; also defines `cleanupManagedWindowsWinFspArtifacts` as a no-op for that path. (The `windows && cgo && !winfsp` stub was removed once the `winfsp` build tag was dropped.)
- `go/mount/winfsp_fs_windows.go` + `go/mount/winfsp_fs_helpers_windows.go` — cgofuse `FileSystemInterface` over `bucketAccess` (`//go:build windows && cgo`; Getattr/Readdir/Open/Create/Read/Write/Truncate/Flush/Release/Mkdir/Unlink/Rmdir/Rename/Statfs). Reads/writes reuse the cache + writeback queue. `Statfs` reports resolved total and provider-used bytes as total/free blocks, so Explorer reflects provider quota when available. Helper file holds Stat/error mapping to keep both files under 500 lines.
- `go/mount/windows_winfsp_probe_windows.go` — `WindowsWinFspAvailable()` mirrors cgofuse's DLL discovery (`winfsp-x64.dll`/`winfsp-a64.dll` then `HKLM\Software\WinFsp\InstallDir`). Also hosts `hasWinFspMountSuffix`/`isWindowsDriveMount` so tests and cleanup work without the `winfsp` tag.
- `go/mount/windows_winfsp_embedded_windows.go` — `//go:embed embedded/winfsp.msi` ships the ~2.1 MB WinFsp installer inside the bridge.
- `go/mount/windows_winfsp_install_windows.go` — `InstallWindowsWinFsp` prefers the side-by-side `{app}\winfsp\winfsp.msi` (shipped by the installer), otherwise writes the embedded MSI to temp, then elevates `msiexec /i ... /qn /norestart` via PowerShell `Start-Process -Verb RunAs -Wait` and re-probes availability.
- `go/mount/winfsp_backend_windows_test.go` / `go/mount/winfsp_statfs_windows_test.go` — unit tests for WinFsp drive-letter validation, path classification, and Explorer-facing Statfs blocks (no mounted driver needed).
- `bridge/dispatch.go` / `bridge/dispatch_mount_winfsp_windows.go` / `bridge/dispatch_mount_winfsp_other.go` — the common dispatcher delegates platform-specific WinFsp routing before its portable switch. Windows registers and implements `list_windows_winfsp_available` / `install_windows_winfsp`; non-Windows builds leave both methods unhandled so they resolve to the standard unsupported-method error without importing Windows mount symbols.
- `lib/services/remote_storage_gateway.dart` — `WindowsWinFspQuery` interface (`listWindowsWinFspAvailable` + `installWindowsWinFsp`).
- `lib/services/remote_storage_api_desktop_storage.dart` — desktop bridge implementation of `WindowsWinFspQuery`.
- `lib/widgets/windows_settings_sections.dart` — `WindowsMountEngineSection`: engine dropdown (WinFsp option hidden when driver missing), inline note + "安装 WinFsp" button when absent, capacity input shown only for WinFsp.
- `lib/pages/settings_page.dart` / `settings_page_actions.dart` / `settings_page_sections.dart` — `_winFspAvailable` / `_installingWindowsWinFsp` state, `_refreshWindowsWinFspAvailability` probe on dependency change, `_installWindowsWinFsp` action.
- `lib/pages/file_manager_page_mount.dart` — before showing the mount dialog for a WinFsp-engine bucket, probes availability and offers the in-app install confirmation modal when missing. When the dialog changes an engine, it saves the bucket's originating named profile rather than `saveConfig` (which always writes `default`); this prevents a non-default account from being cloned and showing duplicated buckets after refresh.
- `lib/widgets/mount_bucket_dialog.dart` / `test/mount_bucket_dialog_test.dart` — WinFsp selections only render an available-drive selector; path mounting stays available to Cloud Files but is hidden for WinFsp, with submit disabled when no free letter exists.
- `scripts/run_windows.ps1` — sets `CPATH=third_party/winfsp/inc/fuse` before the bridge build; the WinFsp engine compiles in by default (no `-tags`), and the script fails fast if the vendored headers are missing.
- `scripts/build_desktop_packages.sh` — `build_windows` exports `CPATH` at the vendored header dir and fails if `fuse_common.h` is absent, so CI and local release builds compile the WinFsp engine the same way.
- `windows/CMakeLists.txt` — the `remote_storage_bridge` custom target passes `CPATH=<repo>/third_party/winfsp/inc/fuse` to the `go build` env so a bare `flutter build windows` (without `run_windows.ps1`) also gets the WinFsp engine.
- `Makefile` — `bridge-windows` passes `CPATH=<repo>/third_party/winfsp/inc/fuse` to `go build`.
- `scripts/setup_windows_dev.ps1` — `Ensure-WinFsp` installs WinFsp from the bundled MSI (or winget) for new dev machines.
- `scripts/windows_installer.iss` / `scripts/build_windows_installer.ps1` — Inno Setup now ships `winfsp.msi` to `{app}\winfsp` and adds an optional "Install WinFsp" task that runs `msiexec /qn` during setup.
- `third_party/winfsp/inc/{fuse,fuse3,winfsp}` — WinFsp 2.1 headers extracted from the MSI and committed so every Windows bridge build (local + CI) can compile cgofuse without a system WinFsp install.
- `go/mount/embedded/winfsp.msi` — WinFsp 2.1.25156 installer payload embedded via `go:embed` and reused by the installer.

#### Gotchas

- Bridge dispatch is built on every desktop platform. Keep WinFsp cases inside `dispatch_mount_winfsp_windows.go`; the matching `!windows` file must leave those method names unhandled. Putting the cases in the common `dispatch.go` switch or calling `WindowsWinFspAvailable` / `InstallWindowsWinFsp` from `dispatch_mount.go` breaks `go test ./...` and macOS `make run` while compiling the bridge.
- The WinFsp engine is compiled into every Windows CGO bridge build (no `winfsp` build tag). Only the pure-Go (`CGO_ENABLED=0`) path hits the stub and reports the engine unavailable, which also cannot host Cloud Files. The UI hides the WinFsp option at runtime when `WindowsWinFspAvailable()` reports the driver DLL is not installed.
- cgofuse's cgo variant (`host_cgo.go`) requires the WinFsp fuse headers via `CPATH` (it hard-codes `-I/usr/local/include/winfsp` which only works under xgo/docker). Missing headers fail the bridge build with `fatal error: 'fuse_common.h' file not found`; the build scripts therefore fail fast instead of silently building a bridge without the WinFsp engine.
- WinFsp is a user-mode driver, not a kernel one; the embedded MSI is per-machine and needs a UAC elevation. `InstallWindowsWinFsp` surfaces elevation cancellation (exit 1223) as an error so the UI can fall back gracefully.
- WinFsp reports capacity from `Statfs.Blocks * Frsize`; bucket `CustomQuotaBytes` overrides provider quota, provider quota overrides global `windowsWinFspCapacityGB`, and unavailable provider data uses that global fallback. `winFspBlockBytes` is fixed at 4096; `Bfree`/`Bavail` subtract provider-used bytes when supplied, otherwise mirror total blocks. Capacity is snapshotted at mount start, so settings changes require remounting.
- Drive-letter WinFsp mounts (`Z:`) are owned by WinFsp itself; `Stop` must not call `subst /D` on them (it would fail). `isWindowsDriveMount` distinguishes these from Cloud Files `subst` mappings.
- Do not reintroduce a directory fallback for WinFsp. The backend rejects it as a contract violation, and the dialog must require an available drive letter before enabling the mount command.

**Shutdown lifecycle fix (2026-07-15):** Normal confirmed exit and tray-menu Exit both route through Flutter before native destruction. `AppBootstrapPage` registers the active gateway with `AppExitCleanup`; `DesktopWindowControls` first calls native `hideForExit` (hide window and remove tray icon), then awaits background `cleanupMounts`, then calls `exitApp`; tray Exit emits `requestExit` and reuses that handler. Go `CleanupMounts` stops every session, and the Windows Cloud Files backend performs `Disconnect` -> watcher close -> `Deregister`. Hide-to-tray/minimize deliberately keep mounts active. Forced process termination still relies on next-start stale cleanup because no in-process callback can run after a kill/crash.

**Shell refresh gotcha:** `windows_shell_namespace_windows.go` must call `notifyExplorerShellChanged` only when a managed This PC namespace key was actually added or removed. Broadcasting `SHCNE_ASSOCCHANGED | SHCNF_FLUSH` on every cleanup, including when no namespace entry exists, causes an unnecessary whole-desktop/Explorer refresh during exit.

**Mounted-exit warning:** `DesktopWindowControls` always shows the close choice dialog, even with zero active mounts, so users can minimize/hide to tray instead of exiting. It calls `AppExitCleanup.activeMountCount`; any live mount changes the copy to explain that Exit unmounts active roots and that "后台运行" preserves them. On Windows the keep-alive action hides to tray; on Linux it minimizes while keeping the process and mounts alive.

**Close dialog layout:** The action row must span the available dialog width (`double.infinity`) before using `MainAxisAlignment.end`; a fixed narrow width centers the buttons inside a wide warning dialog instead of placing them at the lower right.

### Feature: JWanFS FGW SDK (go/jwanfs)

The JWanFS file-gateway SDK was migrated from `jwanfs/pkg/sdk/s3` into `go/jwanfs` so the project maintains its own copy without depending on the legacy `jwanfs/pkg/{jtool,types,consts,minio,s3ext}` tree.

#### Key files

- `go/jwanfs/client.go` - `Client` with multi-gateway upstream pool, `doWithFallback` generic failover, `normalizeServers`/`firstConfiguredEndpoint`/`parseServer` helpers.
- `go/jwanfs/lb.go` - `GatewayBalancer`: gateway-list discovery via `fgwapi=gateway-list`, concurrent `/status` health probes, latency-sorted fallback pool, hourly background refresh.
- `go/jwanfs/sign.go` - Self-contained AWS SigV4 signing (`NewSignedRequestV4`, `SignRequestV4`) + `NewFGWAPI` URL builder. No AWS SDK dependency.
- `go/jwanfs/fgw.go` - FGW business API methods: `FileInfo`/`FileInfoDetail`, `GetFileMD5`, `MoveObject`/`RenameObject`, `BucketQuota`, `FileSearch`, `CreateTempToken`/`UpdateTempToken`, `ShareDetail`, `AuthInfo`, `GetExpire`, `ShareFileURL`/`ResourceFileURL`/`StaticFileURL`.
- `go/jwanfs/fgw_request.go` - `DoFGWAPIRaw`/`DoFGWAPI[T]`/`doPublicFGWAPI[T]` transport: signed FGW request with failover + `FGWResp[T]` envelope decoding.
- `go/jwanfs/query.go` - `QueryValues` wrapper + `structToQueryValues` reflection encoder (replaces the legacy `url.Values` + struct-tag approach).
- `go/jwanfs/errors.go` - Sentinel errors (`ErrNoServer`, `ErrNoAvailableUpstreams`, `ErrAccessDenied`), `shouldFallback` classification, `httpStatusError`.
- `go/jwanfs/http_client.go` - `DefaultHTTPClient()` shared connection-pooled client with relaxed TLS (replaces `jtool.GetHttpClient`).
- `go/jwanfs/detect.go` - **JWanFS gateway detection**: `IsJWanFSGateway` probes `auth-info` FGW route; cached per endpoint+credentials (10 min TTL). `DetectionMode` = `auto` (default) | `jwanfs` | `generic_s3`.
- `go/jwanfs/types/` - FGW business types migrated from `jwanfs/pkg/types` (all `size.B` → `int64`, `consts.*` → local enums): `FileInfoDetailRes`, `ChunkList`/`ChunkInfo`, `GetBucketQuotaRes`, `S3FileSearchReq`/`Res`, `S3AuthInfoRes`, `AKSKBucketPermission`, `UserTempTokenReq`/`Res`, `ResourceFileInfo`, `S3GetShareFile`, `FGWResp[T]`, `FGWS3API` route constants.
- `go/s3/failover_pool.go` / `go/s3/client.go` - Existing AWS SDK v2 S3 operations enter through `NewClient`, which uses `NewFailoverClient` to select the active JWanFS gateway before returning an AWS client. The selected endpoint is cached per endpoint/access-key/detection-mode for one minute to avoid control-plane discovery per object request, and the transient pool is then stopped. Callers that need one operation retried across multiple upstreams must retain a pool and invoke `DoWithFallback` themselves.

#### What was NOT migrated

- `s3iface_bridge*.go` (~3000 lines) - Adapted `*Client` to `s3iface.S3API` from the vendored aws-sdk-go-v1 fork. This project uses `aws-sdk-go-v2` which has no `s3iface`; the bridge is not needed here.
- `s3.go` minio/aws wrapper methods (`PutObject`, `GetObject`, `ListObjects`, `CreateMultipartUpload`, etc.) - This project already has these via `go/s3/` using `aws-sdk-go-v2` directly.
- `AutoPutObject`/`AutoGetObject` resumable transfer - This project has its own resumable upload/download in `go/s3/upload_resume*.go` and `go/s3/object_transfer_*.go`.

#### Data flow

1. `NewClient(opt)` → `GatewayBalancer.Refresh()` discovers gateway list from the first configured endpoint.
2. Each gateway is probed via `GET /status`; the fastest healthy responder becomes the primary upstream.
3. FGW API calls (`DoFGWAPIRaw`) iterate the ordered upstream pool; on transferable errors (5xx/429/network) they failover to the next upstream and update the default.
4. `IsJWanFSGateway(ctx, cfg, mode)` builds a transient client and calls `AuthInfo`; success means the endpoint is a JWanFS gateway. The result is cached so callers can cheaply gate FGW-only features (e.g. `BucketQuota`, `FileInfo`, `FileSearch`).
5. `go/s3.NewClient(cfg)` reuses a one-minute cached endpoint or calls `NewFailoverClient(cfg)` to select that gateway's current AWS SDK v2 endpoint for ordinary S3 operations, then stops the transient balancer.

#### Gotchas

- `go/s3` remains the AWS SDK v2 data plane, while `go/jwanfs` provides FGW business APIs plus gateway discovery. `go/s3/failover_pool.go` intentionally imports `go/jwanfs` to select a live endpoint for a JWanFS account.
- The FGW `bucket-quota` route returns `Total`/`Free`/`Used` as JSON numbers; the legacy `size.B` type was just `int64`, so the migrated `GetBucketQuotaRes` uses `int64` directly.
- `DetectionMode` is a string enum persisted in config (`jwanfsGatewayMode` field). `auto` probes once and caches; `jwanfs`/`generic_s3` force the result without probing. `InvalidateDetectionCache(cfg)` should be called when endpoint or credentials change.
- `DefaultHTTPClient` uses `InsecureSkipVerify: true` to match the legacy `jtool` client behavior (self-hosted gateways often use self-signed certs). If this project later enforces strict TLS, update both `DefaultHTTPClient` and the gateway probe.

### Feature: FTP / SFTP Remote Storage Backends

FTP and SFTP expose the remote server as a single virtual bucket, retaining the shared backend interface used by the file manager, transfer queue, and bridge.

#### Key files

- `go/config/config.go` - Defines `ftp` / `sftp` storage types and shared FTP/SFTP connection fields (`FTPUsername`, `FTPPassword`, `FTPPort`, `FTPAnonymous`). The zero port selects protocol defaults: 21 for FTP and 22 for SFTP.
- `go/storage/types.go` - `ForConfig` selects either backend and applies `scopedBackend` when `RootPrefix` is configured, so ordinary object operations remain view-relative.
- `go/storage/ftp_backend*.go` - Implements classic FTP listing, file I/O, directory mutation, recursive listing/copy, and hard deletion. FTP returns an unknown quota because the protocol has no standard capacity API.
- `go/storage/sftp_backend*.go` - Implements SFTP listing, file I/O, and mutations through `pkg/sftp`; `sftp_backend_quota.go` uses the optional `statvfs@openssh.com` extension when offered by the server.
- `go/storage/ftp_mock_test.go` / `go/storage/sftp_mock_test.go` and their backend tests - Run protocol-level integration tests against in-process mock servers.
- `lib/models/remote_storage_config.dart`, `lib/models/cloud_storage_account_draft.dart`, `lib/utils/account_config_builder.dart`, `lib/widgets/cloud_storage_account_dialog*.dart`, `lib/pages/config_setup_page.dart`, and `lib/widgets/config_right_form*.dart` - Persist the settings and present protocol-specific account forms.

#### Gotchas

- `FTPPort` and the `FTP*` credential fields are also used for SFTP for now; do not infer the default port from the field name.
- Optional backend capabilities are hidden by `scopedBackend` unless that wrapper forwards them. When adding/changing `BucketQuotaProvider` behavior, verify `storage.GetBucketQuota` with a non-empty `RootPrefix`, not only by calling the concrete backend directly.
- SFTP directory deletion is recursive. Keep `TestSFTPCreateAndDeleteDirectory` populated with a nested file so future refactors cannot regress to `RemoveDirectory`-only behavior.
- FTP and SFTP `UploadFile` / `UploadReader` consume non-empty transfer task IDs through the shared `runTrackedUpload` helper. Keep both protocol-level regression tests asserting completed `14/14` snapshots so mount writeback cannot regress to stale `sync_wait` rows.
- Treat SSH host-key verification as a security boundary. A password-authenticated SFTP backend must not silently accept a changed host key in production.
