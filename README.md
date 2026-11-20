# UncBars for WoW: Forever

UncBars 1.0.0 for Forever's interface 16001. No addon
dependencies, tooltip parsing, Nampower, SuperWoW, or Vanilla compatibility layer.

The default appearance is preserved: touching, borderless, shaded health and
power bars below screen center, centered white values, green health that turns
amber at 50% and red at 30%, blue mana, pale healing and shield segments, and a
light-blue mana-cost segment. The default shared width is 260, with 20px health and 14px power.
Settings and position are saved per character.

## Options and Forever appearance

Open `/ub` (or **Settings > AddOns > UncBars > Open UncBars options**) for a
movable options window with General, Appearance, Mana regen, and Druid & combo pages.
Mana regen has two sub-tabs, Timer strip and Bar colors, for its two displays.
Changes apply immediately and are saved for the current character.

- **Original UncBars** restores the familiar borderless bars and centered values.
- **Forever** uses the client's own bar artwork, a compact 200px width, 16px
  health and 12px resource bars, 4px spacing, percentage on the left, and current
  value on the right. Readable values use the client's number separators.
- Adjust width, health/resource heights, spacing, font size, and text independently.
  Text can show current value, current/max, percent, split percent/value, or nothing.
- **Replace Forever's personal resource display** hides the default display while
  UncBars is enabled. Turning this option or UncBars off restores its previous
  opacity. The game's display settings are preserved. Changes to the default
  frame wait until combat ends; disabling the addon itself restores it on reload.
- **Move bars / Lock bars** controls dragging. **Sample values** demonstrates
  healing, shields, mana costs, the regen timer, and combo points; it ends automatically in combat.

Presets change appearance settings; your saved position, resource choices, and
replacement preference stay as configured. **Reset all settings** restores all
defaults, including position.

## Druids and combo points

Druids keep cat energy visible outside cat form by default, with mana underneath.
The stack follows your current form without duplicating resources:

| Form | Default stack, top to bottom |
| --- | --- |
| Caster, travel, aquatic, moonkin | Health, energy, mana, combo points |
| Cat | Health, energy, mana, combo points |
| Bear | Health, rage, energy, mana, combo points |

Energy and mana use the client's actual power pools, including off-form updates.
Mana-cost predictions follow the mana row. Disable **Keep cat energy visible in
every form** to return to the active resource, and **Show mana while
shapeshifted** to remove the extra mana row in forms.

Druids and rogues get five native-style combo-point orbs below the bars, with
adjustable size and spacing. Empty orbs remain visible. Points follow the current
target, including target switches and transfers; death clears them. Restricted
counts go directly to native orb fills without Lua comparisons. Other classes
retain the two-bar display. The combo row can be disabled independently.

## Native predictions

- Spell costs use `C_Spell.GetSpellPowerCost` for the actual spell ID reported
  by `UnitCastingInfo` or its cast-start event. Downranked casts and cost modifiers use the client's
  values. Unknown costs are omitted. An opaque light-blue segment marks the
  part of the mana fill expected to be spent. It resembles the default full-regen
  color and stays consistent when the mana fill changes regen state. The central number remains
  actual mana. A native reverse-fill
  status bar anchored to the current mana fill also supports restricted mana
  and cost values without calculating their widths in Lua.
  While a targeting circle is active (such as Blizzard), `C_Spell.GetTargetSpellID`
  supplies the selected spell's exact ID for the same cost preview. Canceling
  targeting clears it; placing Blizzard clears the reservation when its paid
  channel begins. Selecting a spell alone never starts the regen wait.
- Self-healing uses `UnitGetIncomingHeals("player", "player")` during a normal
  cast. The client supplies both the amount and the confirmed recipient, so
  changing your selected target does not redirect the preview. Other people's
  heals and heals you cast on other players are excluded. No English-only
  tooltip estimates are needed. Restricted incoming healing and health values
  go directly to a native status bar anchored to actual HP, with overhealing
  clipped at maximum health. It leaves no fixed-width edge on an empty fill.
- Shields use `UnitGetTotalAbsorbs` and `UNIT_ABSORB_AMOUNT_CHANGED` to show the
  remaining total of active damage shields, including Power Word: Shield,
  Frost Ward, Fire Ward, Ice Barrier, and Mana Shield. Wards contribute their
  remaining school-specific protection to the shared pale shield segment;
  this does not mean they absorb other damage schools. A shield remains visible
  at full health by folding its overflow into the bar. During restricted combat
  values, a native bar follows the actual health fill. The client's absorb
  calculator selects a folded reverse fill only when health plus absorbs exceeds
  maximum health, keeping the shield connected as health drops.
  Restricted shield and mana-cost amounts go straight to native bar setters;
  the shield's fixed-width edge marker is hidden so an empty fill leaves no line.
- Completion, failure, interruption, death, and leaving the world clear pending
  predictions. Channels do not reserve their already-paid upfront cost.
- Rage, energy, and other active resources use `UnitPower` and native colors.

Unit events update the bars; a lightweight cursor check runs every 0.05 seconds
to catch targeting changes, and a short timeout check runs during an active
cast, and the regen indicator animates while its timer is active. Restricted values go directly to native bars, text, mana-cost previews,
self-healing previews, and shield displays.

## Mana regen timer

An amber strip along the bottom of the mana bar drains over five seconds,
then disappears. In Forever style it is inset inside the border. The strip stays
behind the resource text and follows the mana row, including while a druid is
shapeshifted. It is enabled by default; toggle **Show mana regen timer** on the
**Timer strip** sub-tab of the **Mana regen** page, or use `/ub regen`. The strip
and bar colors are exclusive: turning one on turns the other off.

On that page, adjust the height from 1-100% of the bar interior (minimum 1px),
toggle a numbered countdown inside the bar, and choose the indicator color and
opacity with the native color picker. Color changes preview immediately;
Cancel restores the previous color, and **Reset color** restores amber.
The countdown uses the selected color and is centered between split resource
values, or placed on the right for other text modes. The default height is 7%
(a thin 1px line at the default sizes), with the numbered countdown off.
These settings are saved per character and preserved by appearance presets.

This estimates the five-second wait for full regeneration from successful
mana-costing spells, including instant spells and upfront channel costs. Starting,
canceling, or failing an unpaid cast does not restart it. Readable zero costs and
spells without reported mana costs are ignored, as are weapon attacks (Auto
Shot, Shoot, Attack, Throw). Combat can restrict spell costs, so UncBars learns
which spells cost mana from your spellbook at login and whenever spells change,
and from every cast whose cost is readable. A restricted cost then uses what was
learned; a spell never verified to cost mana, such as an item, does not start
the wait. Once a spell is seen costing mana it stays known, so a free-cast proc
in combat can still restart the wait. Unknown costs are omitted. It does not measure actual regeneration,
predict the next server tick, or imply that talents and other regeneration stop.
Death and world transitions clear the timer. `/ub test` shows a sample strip.

### Bar colors

Instead of the strip, the **Bar colors** sub-tab of the **Mana regen** page can
show the same wait by recoloring the mana bar itself. Enable **Color the mana
bar by regen state** to reveal four color pickers; this turns off the timer
strip, and turning the strip back on (including with `/ub regen`) turns bar
colors off. The page opens on whichever display is in use, and each sub-tab is
marked "(on)" while its display is active.

| State | Default |
| --- | --- |
| Full | The usual mana blue |
| Not Full, Reduced Mana Regen (spent mana within the last five seconds) | The usual mana blue |
| Not Full, Full Mana Regen (have not spent mana within the last five seconds) | A lighter blue for faster regen |
| Supercharged Regen | An even lighter blue |

Supercharged regen covers detectable Innervate and Evocation, and any time the
client reports a casting regen rate at or above the full rate. Its color shows
at any mana level, including full, and takes priority over the other states.
Changes into and out of it fade at full mana too, including in combat. While
it shows, UncBars rechecks it every frame update and remembers when a detected
buff expires, so it ends on time even if the game sends no event.

In combat, Forever hides auras and regen rates. UncBars therefore keeps an
Innervate or Evocation it saw before the pull until that buff's expiry, starts
a 20-second Innervate when you cast it on yourself (including the automatic
self-cast with no target or an enemy targeted), and detects your own
Evocation channel. An Innervate someone else casts on you mid-combat cannot be
seen until combat ends, and a buff removed early in combat (for example,
dispelled) keeps its color until its normal expiry.

The fill changes color directly; no extra bar is drawn over it. Every color
change fades over 0.3 seconds: between states, when picking a new color, in
sample mode, and when turning bar colors on or off. Over the last 3% below full the fill shades
into the full color. The numbered countdown belongs to the timer strip and is
not shown with bar colors. The colors follow the mana row in every druid form
and are preserved by appearance presets. Settings saved by an earlier version
with both displays on keep bar colors. The mana-cost preview stays light blue,
slightly brighter than the default full-regen color so it remains visible while
choosing a targeting location.

During restricted combat values, a native color curve evaluates the mana
fraction, so mana is never compared in Lua. Regen-state changes still fade in
combat, since the addon tracks those itself; reaching full mana is shown only
through the near-full shading.

Starting a cast never changes the color; the wait begins when mana is spent.
Spending starts the wait as soon as the mana drop is seen, even if the spell's
success event arrives a moment later, so spending at full mana does not flash
the after-wait color. In combat that drop can be hidden, so the not-full color
becomes the waiting color only when a spend is near. For a mana-costing cast,
it fades over the cast's last 0.3 seconds, finishing as the mana is spent. An
instant's fade starts when it is sent.

At full mana the not-full color is hidden, so UncBars keeps it on the full
color; a spend from full then fades from the full color to the waiting color.
In combat, mana counts as full once 2.5 seconds pass after the wait without a
regen tick, since ticks arrive every two seconds while mana is below full. A
spend within those 2.5 seconds of the bar filling can still briefly show the
after-wait color.

The strip and optional number hide during detectable Evocation or Innervate,
or when the client reports that casting allows the full mana regen rate. If the
effect ends early, any time left on the original wait returns. Mana restores
such as potions leave the wait running. When the client restricts the needed
spell, aura, or regen data, the timer uses the information it can read.

## Commands

`/ub` is an alias for `/uncbars`.

| Command | Effect |
| --- | --- |
| `/ub`, `/ub options` | Open the options window |
| `/ub style forever`, `/ub style original` | Apply an appearance preset |
| `/ub unlock`, `/ub lock` | Drag the complete stack, then restore click-through |
| `/ub center` | Center horizontally, preserving vertical position |
| `/ub test` | Toggle labeled sample values and all preview segments; alive and out of combat only |
| `/ub width 260` | Shared width, 140-600 |
| `/ub healthheight 20` | Health height, 10-60 |
| `/ub manaheight 14` | Power height, 10-60 |
| `/ub height 20` | Set both heights, 10-60 |
| `/ub gap 0` | Space between bars, 0-20 |
| `/ub text current` | Centered current value; also accepts `full`, `percent`, `split`, or `hidden` |
| `/ub queue`, `/ub healqueue` | Toggle mana-cost or self-healing previews independently |
| `/ub regen` | Toggle the amber five-second mana regen estimate |
| `/ub on`, `/ub off` | Show or hide the HUD |
| `/ub reset` | Restore default layout and settings |
| `/ub status` | Report native prediction support, mana preview setting, current spell and cost |

Enable **UncBars** in the character-selection AddOns list, then log in or reload
the UI. If a running client does not discover the new folder, restart it.
The OctoWoW addon and its saved settings are untouched.

## Release packaging

From a Bash terminal in the repository directory, run:

```bash
./make
```

This creates `dist/UncBars 1.0.0.zip`, using the `## Version` in `UncBars.toc`
for the filename. Upload this ZIP to CurseForge. It contains only the `UncBars/`
folder with the TOC and the files listed in it (currently `Logic.lua`,
`UncBars.lua`, and `Options.lua`). Tests, documentation, Git files, the packaging
script, and previous archives are excluded. Re-running replaces the ZIP for that
version. Requires Git Bash on Windows; the launcher handles PowerShell for you.
It also works from another directory when given its full path.

## Verification

From `tests`, run `npm install` and `npm test` for Lua 5.1 syntax and a mocked
Forever runtime. Checks cover exact spell IDs, cost changes, absorbs, confirmed
self-healing, clipping, combat/death, cast event ordering and pushback, form
changes, positions, commands, and restricted values. Additional checks cover
off-form druid resources, target-bound combo points, options controls, presets,
saved-setting migration, and default-display restoration after combat.
Portal checks cover missing player power data and automatic layout recovery.
Healing checks cover restricted incoming amounts and health, native overheal
clipping, zero healing, target changes, interruption, and the healing toggle.
Regen checks cover completion event ordering, free and failed casts, instants,
channels, expiry without resource events, restricted costs, toggles, sample mode,
death, world transitions, the druid mana row, height scaling, countdown toggling,
color-picker changes and cancellation, and saved regen preferences.
Mana color checks cover defaults, the options toggle and pickers, each regen
state including Innervate, Evocation and full casting regen, fades and
near-full shading, expiry without power events, restricted mana, sample mode,
druid forms, presets, reset, and repaired saved colors. Spend checks cover cast
start, the end of a cast, cast bars ending before their mana arrives, canceled
casts, instants, drains, the mana-cost preview overlay and draw order, learned
spellbook costs, unverified restricted costs, free-cast procs, and weapon attacks.
Targeting checks cover Blizzard's cost, switching spells, modifiers, cancellation,
channel handoff, restricted values, toggles, death, world transitions, and druid forms.

In-game, use `/ub test` to inspect the style, then check dragging, saved position
after `/reload`, actual casts at different ranks, canceling a cast, healing
yourself versus someone else, shield depletion, and resource changes in forms.
Select Blizzard and verify the light-blue cost segment while its targeting circle
is active, then cancel it or place the spell. Repeat in combat and at another rank.
Travel through a portal and verify the bars return without Lua errors.
On a Mage, check Frost Ward against Frost damage and Fire Ward against Fire
damage, including at full HP, in combat, and alongside another absorb. The
shared segment should shrink as protection is spent and clear on expiration.
On a druid, verify energy regeneration in caster/travel form, shift between cat
and bear, build/spend combo points, and switch targets. Select Forever in the
options and compare the live native artwork and spacing with your default bars;
then enable replacement and verify it restores correctly when turned off.
The automated mock cannot validate artwork or execution inside the game client.
For the regen indicator, spend mana, wait for the strip to clear,
chain another spell, and cancel a cast. Check free procs and channels against the
actual return of full regen, especially when combat restricts spell costs.

API references: [Forever unit APIs](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)
and [Forever spell APIs](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua).
Native artwork follows [the personal resource display](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_PersonalResourceDisplay/Blizzard_PersonalResourceDisplay.xml)
and [combo-point orbs](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UnitFrame/Mainline/RogueComboPoint.xml).
Target updates follow [Forever's target-bound combo bar](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_UnitFrame/Camelot/TargetBoundComboPointBar.lua).
