# Stim

A haptics toy for iPhone. A single grey orb sits on a blank field; moving, tapping,
and shaking it drive Core Haptics in real time.

- **Move** the orb for a continuous, modulated buzz plus a distance-tied texture.
- **Tap** for a hard slam paired with a full-screen flash (colour is configurable).
- **Shake** for a swelling rumble.
- The orb is lit from a direction pinned to the real world via the compass, so its
  highlight and shadow stay put as you turn.

Four haptic "feels" — Aggressive, Smooth, Melodic, and Off-key — are selectable from
the settings gear, along with a rainbow flash-colour picker.

## Running it

Open `Heptics.xcodeproj` in Xcode, sign the target with your Apple ID under
Signing & Capabilities, and run on a physical device. **Core Haptics does not work in
the Simulator** — the feel only exists on real hardware.

Requires iOS 17+.
