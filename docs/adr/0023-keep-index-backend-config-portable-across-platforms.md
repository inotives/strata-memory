# Keep index backend configuration portable across platforms

`strata config-compile` will validate only that `index.backend` is `sqlite` or `turso`; it will not reject a valid backend based on the current operating system or runtime capability. Backend availability is checked when index commands execute and by `strata doctor`, allowing the same vault configuration to move between supported machines.
