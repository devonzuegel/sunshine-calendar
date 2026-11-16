# Date command palette performance

Replaced the Command-K modal sheet with a reusable, fixed-size native panel. Its SwiftUI view is prepared after the main window appears, before keyboard invocation. Opening the panel does not publish a presentation property on CalendarModel or dim/re-layout the calendar. Input and parsed results live in a separate small DateJumpSession. The native text field is focused directly when opening.

Parser expressions and month aliases are compiled once; the result is computed on input changes rather than repeatedly during rendering. Oversized pasted input is rejected before regex work.

## Local optimized parser comparison

Same machine, swiftc -O, warmed implementations, 7,000 identical mixed queries (numeric, month name, explicit year, relative, and invalid). Results matched exactly.

- Previous parser: 634.8 ms
- Cached parser: 57.2 ms
- Ratio: 11.10x faster

These are parser timings, not a measurement of visible window-opening latency. The presentation improvement comes from eliminating sheet animation and reusing the prepared window. Light/dark empty and result views were rendered offscreen; the full 930-check suite passed.
