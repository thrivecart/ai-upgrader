# Graceful Stop - current behavior and future remote CI contract

In v1.0.0 the autonomous Bash loop checks `STOP_REQUESTED` between milestones, writer invocations, gates and reviews. An already-running synchronous local gate runs to completion; no additional gate, patch or milestone begins afterward. `ai-upgrader resume` explicitly clears the stop flag and continues from the frozen plan. A concurrent stop request cannot be overwritten by a long-running gate's stale state write.

**Not implemented:** remote CI polling or cancelling background builds, asynchronous build ownership, or automatic remote build handoff. If a remote CI adapter is required, the autonomous approval policy stops rather than silently claiming it passed. This document does not assert the original full remote-CI graceful-stop contract is complete.
