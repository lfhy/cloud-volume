// Runtime version helpers keep the UI aligned with dev builds and tagged CI releases.

const String kAppRuntimeVersion = String.fromEnvironment(
  'APP_VERSION_LABEL',
  defaultValue: 'dev',
);
