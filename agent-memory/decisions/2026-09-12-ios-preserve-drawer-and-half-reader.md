# Preserve iPhone interaction model

The user rejected the broad native-sheet/large-reader redesign on 2026-09-12.
Both task commits were reverted, restoring the pre-task source layout.
The phone's signed recovery app was reinstalled and launched successfully.

UI polish must retain the side-sliding folder drawer, default half-screen
reader, expansion into editing, and return to half-screen after editing.
Do not substitute a bottom folder sheet or large-only reader.

The remaining candidate changes only primary-control and saved-toast text
contrast in light appearance. Dark appearance and all interaction code stay
unchanged. Keep the physical phone on the restored version while this small
candidate is reviewed in the simulator.
