# Debug Windows runs load the bridge directly from bin/bridge so the runner can
# rebuild without replacing a DLL that the currently running app still has open.
if(NOT DEFINED BUILD_CONFIG)
  message(FATAL_ERROR "BUILD_CONFIG is required")
endif()
if(NOT DEFINED SOURCE_PATH)
  message(FATAL_ERROR "SOURCE_PATH is required")
endif()
if(NOT DEFINED DEST_PATH)
  message(FATAL_ERROR "DEST_PATH is required")
endif()

if(BUILD_CONFIG STREQUAL "Debug")
  message(STATUS "Skipping Debug bridge staging; runner loads bin/bridge directly.")
  return()
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${SOURCE_PATH}" "${DEST_PATH}"
  RESULT_VARIABLE COPY_RESULT
)

if(NOT COPY_RESULT EQUAL 0)
  message(FATAL_ERROR "Failed to stage Windows Go bridge")
endif()
