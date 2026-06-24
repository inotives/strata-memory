# Warn when the compiled index backend changes

Compiled configuration will retain the previously selected `index.backend`. When `strata config-compile` detects a change, it warns that the newly selected index database may require `strata refresh`; compilation does not create, migrate, rebuild, delete, or inspect either backend database.
