# iPadOS human-interface checklist

This checklist is a release gate for CodexPad.

## Structure and adaptation

- Use `NavigationSplitView` for the thread sidebar and conversation, with the optional workbench in a native inspector.
- Preserve selection across column changes; at constrained widths or accessibility text sizes, hide the inspector, use a single-column conversation, and keep thread navigation reachable from a native sheet.
- Test full screen, half, third, quarter, portrait, landscape, and Stage Manager window sizes.
- Keep content inside safe areas and use system bars, sheets, menus, and popovers for their standard roles.

## Input

- Make every primary workflow usable with touch, pointer, Apple Pencil, and Full Keyboard Access.
- Preserve standard shortcuts; provide discoverable commands for new thread, send, interrupt, search, inspector, and terminal.
- Use system controls so pointer effects and focus behavior are automatic.
- Keep interactive targets at least 44 by 44 points without inflating their visible artwork.

## Accessibility

- Use Dynamic Type styles and verify accessibility text sizes without clipped actions.
- Give icons, status indicators, diffs, and activity nodes meaningful VoiceOver labels and values.
- Never encode approval state or diff meaning with color alone.
- Respect Reduce Motion, Increase Contrast, Differentiate Without Color, and Reduce Transparency.
- Maintain logical focus order and announce streamed completion and approval requests without reading every token delta.

## Behavior

- Preserve work when a scene disconnects or the app enters the background.
- Use destructive confirmation only for irreversible actions.
- Explain connection, authentication, storage, and runtime errors with a concrete recovery action.
- Keep the terminal visible as a recoverable tool, not as a prerequisite for ordinary use.

## Verification

- Build with the current hosted Xcode runner.
- Run unit tests for protocol parsing and state reduction.
- Run UI tests at two iPad sizes and at an accessibility text size.
- Audit with Accessibility Inspector and VoiceOver on a physical iPad before release.
