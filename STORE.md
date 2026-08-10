# App Store listing copy

Everything App Store Connect asks for, ready to paste. Character limits are
Apple's and are counted here.

---

## Name (30 max)

```
Pocket Stim
```

11 chars. **Check availability when you create the app record** — App Store
names are globally unique and this one is plausible enough that someone may
have it. Fallbacks: `Pocket Stim: Haptic Goo` (23), `Goo — Pocket Stim` (17).

## Subtitle (30 max)

```
Haptic goo for restless hands
```

29 chars.

## Promotional text (170 max)

Editable any time without submitting a new build, so use it for what's new.

```
Now easier to throw. Swipe out from the orb at any speed and a droplet tears
off and flies — no need to drag it all the way clear.
```

130 chars.

## Description

```
A ball of goo that lives in your pocket.

Press into it and it gives. Drag and it stretches, thinning into a neck that
strains, then lets go with a snap you feel in your hand. Tear off a piece and
throw it and it wanders back on its own, finds the mass in the middle, and
melts into it.

None of it is animation. Every blob is a body in a physics field, and the
haptics are fired by what the goo actually does — the strain in a neck, the
moment it parts, a droplet hitting the edge of the screen, two pieces running
together. The texture under your fingertip is metered against distance moved
rather than time, so it feels like dragging across a surface instead of a
buzzer switching on and off.

Use every finger. Each one works its own piece of goo at the same time.

FOUR FEELS, OR BUILD YOUR OWN
Aggressive, Smooth, Melodic and Off-key each give the goo a different
character. Custom opens up the machinery underneath: how finely the texture is
grained, how fast it can repeat, sharpness, jitter, the body of the tap and the
knocks that follow it, and the pitch line the texture walks through as you
drag.

TAP TO FLASH
Tap the orb and the whole screen throws light in a colour you choose from a
full spectrum. Not for everyone — it can be switched off entirely in Settings,
and with it off the app never touches your screen brightness.

SHAKE IT
The goo feels the phone move. Shake it and the whole field scatters.

PRIVATE BY CONSTRUCTION
No accounts, no analytics, no advertising, no network connection of any kind.
Pocket Stim collects nothing, because it cannot — there is nowhere for anything
to go.

Requires an iPhone. The whole app is built around the Taptic Engine, so there
is no iPad version.
```

## Keywords (100 max, comma separated, no spaces)

**Safer set** — avoids health-adjacent terms, 87 chars:

```
fidget,stim,sensory,squishy,goo,slime,haptic,vibration,texture,calm,relax,toy,blob,idle
```

**Higher-traffic set** — adds `anxiety` and `adhd`, 96 chars:

```
stim,fidget,haptic,vibration,sensory,calm,focus,anxiety,squishy,goo,slime,toy,relax,adhd,texture
```

The tradeoff: those two words are where the search volume is for this kind of
app, but they invite a reviewer to read the listing as a health claim, which
raises the bar. Keywords are not shown to users. For a first submission I'd
ship the safer set, get approved, then try the other in a later update — a
keyword change alone is a metadata update, not a new build.

## Category

- **Primary:** Entertainment
- **Secondary:** Lifestyle

Health & Fitness would put you in front of the right audience but drags in
scrutiny about therapeutic claims. Not worth it for version 1.

## Age rating

**4+.** Answer "None" to every content question — no violence, no profanity,
no user content, no web access, no gambling.

## Privacy nutrition label

**Data Not Collected.** Verified in the source: no `URLSession`, no analytics
SDK, no third-party packages, no CloudKit, no StoreKit. Answer "No" to tracking
— there is no ATT prompt.

## URLs

- **Privacy policy URL** (required):
  `https://willluik27.github.io/Stim-App/privacy.html`
- **Support URL** (required): `https://willluik27.github.io/Stim-App/`
- **Marketing URL** (optional): leave blank

Served by GitHub Pages from `/docs` on `main`. Both must load anonymously —
test them in a private browser window before submitting.

## Copyright

```
2026 William Luik
```

## App Review notes

```
Pocket Stim is a single-screen haptic toy. Drag out from the orb in the middle
of the screen to pull goo out of it; swipe to tear a piece off; tap the orb for
a flash of colour. The gear in the top right opens settings.

The haptics are the app. They cannot be felt in the Simulator — please review
on a physical iPhone.

Tapping the orb flashes the screen and briefly raises screen brightness. This
is a deliberate feature and can be switched off in Settings ("Flash on tap"),
in which case the app never modifies screen brightness. The original brightness
is always restored, including if the app is backgrounded mid-flash.

No account or demo credentials needed. The app has no network access.
```

## Screenshots

At least one 6.9" iPhone set (1320 × 2868). iPhone-only portrait, so that is
the only size required — Apple scales it for other devices. Up to 10.

Suggested sequence:

1. The orb at rest — establishes the object
2. A droplet drawn out with the neck stretched thin — the moment that sells it
3. Several droplets loose on screen mid-throw
4. The flash firing in a colour
5. The Custom tuning screen — evidence of depth, which is what a 4.2 reviewer
   is looking for

---

## Before you submit

- [ ] Test on a physical iPhone via TestFlight — haptics cannot be checked any
      other way
- [ ] Bump `CURRENT_PROJECT_VERSION` if that build number was already uploaded
- [ ] Privacy policy and support pages live on a **public** host and loading
      anonymously
- [ ] Screenshots captured at 1320 × 2868
- [ ] App name availability confirmed
