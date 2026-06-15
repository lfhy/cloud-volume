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
- The macOS app must be started through the Go binding workflow, not plain Flutter alone.
- `make run` is the canonical local launch command. It first runs `make bridge`, which builds `./bridge` as `bin/bridge/libremote_storage_bridge.dylib`, then launches Flutter with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer flutter run -d macos`.
- When validating integrated app startup, prefer `make run` over a bare `flutter run -d macos` so the bridge binary and Xcode path are both set correctly.

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
