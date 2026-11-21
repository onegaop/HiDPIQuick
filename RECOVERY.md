# Recovery baseline

This directory restores HiDPI Quick 2.4.1 (build 8), before any new optimization.

- Six Swift source files, Info.plist, build script and README were recovered from the original development patch history, through 2026-07-19 07:55 UTC.
- 64 file patch operations were applied in their original order. Historical shell commands were not replayed. Three plist patch contexts required whitespace normalization because historical plist formatting had changed.
- Resources/AppIcon.png is the original generated image referenced by that development history, not a newly recreated icon.
- Source content was checked for embedded local user paths or credentials; none were found. The bundle identifier is retained for application identity compatibility.
- This is a source-history recovery, not a claim of binary reproducibility against the previously installed application. Compiler and SDK versions may differ.

Validation: Swift strict-concurrency type checking, plist lint and shell syntax checks passed on the recovery machine. No application was launched or installed during recovery.
