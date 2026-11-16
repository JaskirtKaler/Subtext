---
name: Editorial Precision
colors:
  surface: '#fcf8fb'
  surface-dim: '#dcd9dc'
  surface-bright: '#fcf8fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f6f3f5'
  surface-container: '#f0edef'
  surface-container-high: '#eae7ea'
  surface-container-highest: '#e4e2e4'
  on-surface: '#1b1b1d'
  on-surface-variant: '#414755'
  inverse-surface: '#303032'
  inverse-on-surface: '#f3f0f2'
  outline: '#717786'
  outline-variant: '#c1c6d7'
  surface-tint: '#005bc1'
  primary: '#0058bc'
  on-primary: '#ffffff'
  primary-container: '#0070eb'
  on-primary-container: '#fefcff'
  inverse-primary: '#adc6ff'
  secondary: '#bc000a'
  on-secondary: '#ffffff'
  secondary-container: '#e2241f'
  on-secondary-container: '#fffbff'
  tertiary: '#264bdd'
  on-tertiary: '#ffffff'
  tertiary-container: '#4666f7'
  on-tertiary-container: '#fffbff'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d8e2ff'
  primary-fixed-dim: '#adc6ff'
  on-primary-fixed: '#001a41'
  on-primary-fixed-variant: '#004493'
  secondary-fixed: '#ffdad5'
  secondary-fixed-dim: '#ffb4aa'
  on-secondary-fixed: '#410001'
  on-secondary-fixed-variant: '#930005'
  tertiary-fixed: '#dee1ff'
  tertiary-fixed-dim: '#b9c3ff'
  on-tertiary-fixed: '#001258'
  on-tertiary-fixed-variant: '#0033c2'
  background: '#fcf8fb'
  on-background: '#1b1b1d'
  surface-variant: '#e4e2e4'
typography:
  large-title:
    fontFamily: Inter
    fontSize: 34px
    fontWeight: '700'
    lineHeight: 41px
    letterSpacing: 0.37px
  large-title-mobile:
    fontFamily: Inter
    fontSize: 30px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: 0.35px
  title-1:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 34px
    letterSpacing: 0.36px
  title-2:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: 0.35px
  title-3:
    fontFamily: Inter
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 25px
    letterSpacing: 0.38px
  headline:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '600'
    lineHeight: 22px
    letterSpacing: -0.41px
  body:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: -0.41px
  callout:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 21px
    letterSpacing: -0.32px
  subheadline:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: -0.24px
  footnote:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 18px
    letterSpacing: -0.08px
  caption-1:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0px
  caption-2:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 13px
    letterSpacing: 0.07px
  timestamp:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: -0.2px
  timestamp-bold:
    fontFamily: JetBrains Mono
    fontSize: 13px
    fontWeight: '700'
    lineHeight: 18px
    letterSpacing: 0px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-tablet: 1.25rem
  margin: 1rem
  margin-tablet: 1.5rem
  margin-desktop: 2rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

This design system delivers an authentic, premium iOS Human Interface Guidelines (HIG) aesthetic tailored for investigative journalists, biographers, and academic researchers. The design prioritizes extreme legibility, rapid cognitive parsing, and unobtrusive utility under intense, time-critical interview conditions.

The visual style is **Minimalist / iOS Native Modern**. It emphasizes:
- Frictionless recording workflows with immediate visual confirmations.
- Deep respect for native Apple interaction conventions: prominent large title collapsibility, dynamic grouped list behaviors, frictionless sheet presentations, and standard gesture vocabularies.
- High editorial clarity: UI chrome steps into the background, elevating recorded audio intelligence, verbatim transcripts, and speaker attribution to first-class content.

## Colors

The color palette is engineered around functional role allocation, maintaining low visual noise during long analytical sessions while reserving high-saturation signals for critical states.

### Core Palettes
- **Primary Accent (`#007AFF`)**: iOS system blue used for primary navigation actions, interactive controls, audio playhead scrubbing, and actionable links.
- **Recording Accent (`#FF3B30`)**: Reserved strictly for active recording indications, live pulsing waveforms, destructive alert prompts, and mic mute/unmute states. Never use this red for decorative elements or non-critical statuses.
- **Neutral Canvas**: Default background is `#F8F9FA` (System Grouped Background) with `#FFFFFF` for elevated inset cards and list items. Dark mode transitions directly to `#000000` (Pure Black Canvas) and `#1C1C1E` (Secondary Grouped Container).
- **Text & Structure**: Primary text sits at Charcoal `#1C1C1E` (Dark Mode: `#FFFFFF`), Secondary labels at `#8E8E93`, and subtle hairline dividers at `#C7C7CC` (Dark Mode: `#38383A`).

### Semantic Speaker Diarization
Muted, distinct editorial tints isolate speakers without creating visual fatigue:
- **Speaker A (Interviewer/Journalist)**: Key `#4B6BFB`, Light Tint `#EEF2FF`, Dark Tint `#1E2548`.
- **Speaker B (Subject/Primary Source)**: Key `#8B5CF6`, Light Tint `#F5F3FF`, Dark Tint `#291D47`.
- **Speaker C (Third Party/Secondary Source)**: Key `#10B981`, Light Tint `#ECFDF5`, Dark Tint `#063124`.

### Verification Status Tokens
- **Answered**: Fill `#EBF5EA`, Label `#2E7D32`.
- **Partial**: Fill `#FEF6E6`, Label `#B45309`.
- **Unclear / Needs Review**: Fill `#F3F4F6`, Label `#6B7280`.

## Typography

The typography mirrors Apple's San Francisco system proportions using `Inter` for exceptional digital neutral legibility across variable dynamic ranges, alongside `JetBrains Mono` for precise, tabular timestamp rendering.

- **Editorial Reading Rhythm**: Paragraphs in the transcript view maintain a 24px line-height on 17px body type to avoid reading strain during long investigative reviews.
- **Diarization Attribution**: Speaker names are set in `subheadline` with `fontWeight: 600`.
- **Monospace Alignment**: Audio timestamps (e.g., `00:14:28.4`) utilize the `timestamp` level with fixed-width numerals to eliminate horizontal jitter during live recording and playback scrubbing.
- **Dynamic Hierarchy**: Transitions between compact navigation bar titles and expanded `large-title` headers must track iOS scroll offset curves precisely.

## Layout & Spacing

The layout model is based on an inset grouped standard optimized for single-handed mobile operation and responsive multi-column iPad split views.

- **Horizontal Canvas Margins**: Native iOS standard 16px (`1rem`) on iPhone screens, expanding to 20px–24px on iPadOS layouts.
- **Vertical Hierarchy**: 
  - Standard spacing between adjacent grouped card cells is `space-sm` (8px).
  - Spacing between semantic sections is `space-xl` (32px).
  - Transcript paragraph blocks maintain `space-md` (16px) separation to distinguish changing speakers.
- **Touch Targets**: Minimum interactive tap target is 44×44pt across all buttons, waveform scrubbers, and expandable card triggers.
- **Safe Area Insets**: Floating recording bars and dock controls must factor in `env(safe-area-inset-bottom)` to sit comfortably above the iOS home indicator bar.

## Elevation & Depth

Visual depth follows the physical layered substrate model of modern iOS:
- **Base Canvas (Level 0)**: `#F8F9FA` (Light) / `#000000` (Dark).
- **Grouped Card Surfaces (Level 1)**: `#FFFFFF` (Light) / `#1C1C1E` (Dark). Elevated strictly by surface color contrast and hairline borders (`0.5px solid rgba(0, 0, 0, 0.08)` in light mode, `0.5px solid rgba(255, 255, 255, 0.12)` in dark mode). Drop shadows are avoided on stationary list cards to preserve native cleanliness.
- **Floating Controls & Modals (Level 2)**: Floating Record Button and Playback Control Bars use real-time blur backdrops:
  - Material: iOS System Ultra Thin / Chrome Material Blur (`backdrop-filter: blur(20px)`).
  - Ambient Shadow: `0 8px 32px rgba(0, 0, 0, 0.12)`, tinted slightly toward neutral darks.
- **Scrubber Heads & Active Micro-overlays (Level 3)**: `0 2px 8px rgba(0, 0, 0, 0.16)`.

## Shapes

The interface embraces native Apple continuous curves (squircle geometry), avoiding sharp boxy intersections while preventing generic pill styling on structured layout components.

- **Grouped Inset Cards & Sheets**: Set to `roundedness: 2` (10px–12px corner radii) using continuous corner smoothing (`corner-smoothing: 60%`).
- **Interactive Buttons & Badges**: Standard buttons match card corner curvature (8px–10px).
- **Audio Scrubber Pillars & Chips**: Verification badges and speaker selection chips use a full continuous radius (pill-shaped) to distinguish transient metadata from structural layout cards.
- **Floating Recording Action Button (FAB)**: Perfectly circular (50% radius) to maintain physical hardware microphone metaphor.

## Components

### Navigation Bar
- Large title collapsing behavior: transitions smoothly into a centered inline title upon upward scroll.
- Leading and trailing items strictly use standard iOS action icons or primary blue text buttons (`#007AFF`, 17px).

### Floating Record Button (FAB)
- Centered dock position, 64×64pt footprint.
- Default state: Pure white container, 1.5px crimson ring, center crimson recording dot (`#FF3B30`).
- Active Recording state: Pulsing outer crimson aura, center circle animates to an 18×18pt rounded square stop symbol. Displays an integrated monospace counter (`timestamp-bold`) directly above the FAB.

### Scrubber Waveforms & Audio Canvas
- Real-time decibel bars rendered as vertical pill-shaped capsules (width 2.5px, gap 2px).
- Speaker color-coded: sections of the waveform correspond directly to Speaker A (`#4B6BFB`), Speaker B (`#8B5CF6`), and Speaker C (`#10B981`).
- Playhead: 2px wide vertical rule with a 10px circular scrub handle elevated with Level 3 ambient shadow.

### Editorial Transcript Card View
- Distinct container blocks for each dialogue turn, grouped by speaker.
- Left-aligned indicator hairline (3px wide) tinted to the active speaker's key color.
- Embedded metadata header: Speaker pill badge (tint background, solid text), timestamp anchor, and right-aligned verification badge (e.g., "Answered", "Partial").
- Selecting transcript text reveals native iOS UIMenuController actions: "Highlight Quote", "Verify Fact", "Clip Audio".

### iOS Segmented Controls
- Background: System Fill `#767680` with 12% opacity.
- Selected segment: `#FFFFFF` with standard Apple micro-shadow (`0 3px 8px rgba(0, 0, 0, 0.12)`).
- Typography: 13px medium, smooth slide physics between options ("Transcript", "Audio Intelligence", "Key Quotes").

### Checkboxes & Verification Chips
- Native iOS circular check state: `#007AFF` fill with white checkmark when verified.
- Status badges feature inset 4px dot indicators paired with uppercase `caption-2` typography.