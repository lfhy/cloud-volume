# Desktop-only Flutter plugin forks

`super_native_extensions` 0.9.1 and `irondash_engine_context` 0.5.5 are
vendored from pub.dev with their Android plugin registrations removed. The
unused Android-only device-information workaround is also removed so current
desktop picker packages can use `win32` 6. Their desktop registrations and
desktop behavior are unchanged, so the application retains native drag-and-drop
and file URI clipboard support.

Do not restore the Android registrations until their CargoKit Gradle scripts
support the Android Gradle Plugin version used by this application.
