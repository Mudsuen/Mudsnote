# iOS capture ablation and replay throughput

## Scope

The work is iOS-only and follows the durable File Provider save repair from
iteration 276. The macOS target and its existing working-tree changes are
outside scope.

## Measured boundaries

The ablation suite keeps each protection independently observable:

| Boundary | Control condition | Protected result |
| --- | --- | --- |
| UTF-8 filename bound | An 80-emoji title produces a filename component above 255 bytes | The generated Markdown relative path stays at or below 184 UTF-8 bytes and writes successfully |
| Coordinated exclusive creation | Two captures have identical title, content, and timestamp | Both writes survive at distinct paths |
| Durable fallback | The foreground writer injects a transient Cocoa write failure | The composer finishes with one replayable queue item, then replay creates the Markdown file |
| Post-save inventory | The full-library refresh is held behind a test barrier | The durable save and exact list projection finish without waiting for the refresh |
| Startup replay | A pending capture exists and replay is held behind the initial-load barrier | The library shell becomes interactive with pending status before replay or indexing |
| Queue cleanup | Twenty healthy items replay with per-item cleanup versus batched cleanup | Queue-file persistence falls from 20 full rewrites to 1 |

## Recovery invariants

- Batched cleanup rereads the latest persisted queue and removes only IDs that
  completed, so an App Intent or extension can enqueue concurrently without
  having its item overwritten.
- If a later item hits a transient failure, completed IDs are committed once
  before the original failure returns and the failed item remains active.
- A crash after a note write but before the batched queue commit is safe because
  pending-note writes are idempotent through the existing claim and receipt
  records.
- Irrecoverable items are still preserved outside the active queue before their
  IDs enter the completed batch.

## Interaction policy

The foreground path waits only for the direct Markdown write or the durable
fallback enqueue. A successful write publishes its exact projection and clears
the sending state. Text-only captures do not rescan the library. Attachment
captures schedule a 150 ms debounced inventory refresh so the attachment browser
and ownership index converge; multiple captures inside the debounce window
share one refresh. A refresh failure is logged by error domain and code and does
not replace the successful save toast; scene activation and manual refresh
remain recovery paths.
