# Untethered

WoW: Forever addon. When your warrior hits 100 rage, Dennis screams "I am untethered and my rage knows no bounds" at you. That's it. That's the addon.

Made for the Forever beta (client 1.60.1). Should work at launch unless Blizzard renames the player frame again.

## Install

Grab the zip from [Releases](https://github.com/AlrikOlson/untethered/releases) (or CurseForge once it's up there) and unzip it into

```
C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\
```

so you end up with `AddOns\Untethered\Untethered.toc`. If you're cloning instead, clone straight into a folder called `Untethered` inside AddOns. The folder name matters.

Then **restart the game**. `/reload` isn't enough the first time. WoW only picks up sound files that existed when the client started, so if you skip this you'll get a "could not play rage.ogg" message and no Dennis.

If the addon list says it's out of date, tick "Load out of date AddOns". The Interface number in the .toc (16001) is what other Forever addons are using but Blizzard hasn't confirmed it anywhere I could find.

## Usage

Roll a warrior. Get hit. That's honestly the whole loop, but there are a few commands:

```
/rage test          play it now
/rage on            turn it on (default)
/rage off           turn it off
/rage cd 30         seconds between plays, default 30. 0 = every single time
/rage channel sfx   master (default), sfx, music, ambience or dialog
/rage debug         what it's hooked into and whether it's seen anything fire
/rage verbose       spam chat every time a trigger fires, handy for checking it works
/rage reset         re-arm the fallback sensor. only matters if you see it fire out of sync
```

Only does anything on warriors. Loads fine on other classes, just sits there.

## How it works

You'd think this is `if UnitPower("player") == UnitPowerMax("player")`. It isn't, and that's the reason this addon is more than 10 lines.

Forever runs the retail 12.x "secret value" system. Your own rage comes back from `UnitPower` as a secret number, and not just in combat, always. You can't compare it, do math on it, format it, or read it back out of a StatusBar or FontString. I tried all of those. Every one comes back secret.

So the addon never reads the number. Two things it does instead:

- Blizzard's own player frame has a `FullPowerFrame` on the mana bar that plays a `SpikeAnim` the moment power caps. Blizzard's code runs secure and is allowed to compare secrets. Hooking `OnPlay` on that animation is allowed, so that's the trigger. This is what actually fires in practice.
- Fallback, only used if the frame above isn't found: a hidden StatusBar with range max-1..max gets fed the secret value. Its fill texture is 0 wide below max and full width at max, so it only resizes when you cross the cap. A frame anchored to that texture gets `OnSizeChanged` on each crossing, and crossings alternate in/out. Works in testing, but it assumes rage isn't full when the addon arms itself at login. If it ever gets flipped, `/rage reset` while you're below 100.

If Blizzard renames `SpikeAnim` or moves `FullPowerFrame`, the first path breaks silently and the fallback takes over. Run `/rage debug` and it'll tell you which one it's on.

## The audio

`rage.ogg` is a 4.5 second clip from It's Always Sunny (S10E06, "The Gang Misses the Boat"). It's obviously not mine. It's here because the addon is pointless without it. If you want a different line, drop in any `.ogg` or `.mp3` at 44.1 kHz with the same name and restart the client.

## Releasing

Push a tag and GitHub Actions runs the [BigWigs packager](https://github.com/BigWigsMods/packager), which zips it, makes a GitHub release, and uploads to CurseForge if the `CF_API_KEY` secret is set and the toc has an `X-Curse-Project-ID`.

```sh
git tag v1.0.2
git push origin v1.0.2
```

## Known issues

- Only tested on one warrior, on the beta, on Windows. Retail and Classic Era have different frame layouts and I haven't tried either.
- The Interface number is unconfirmed (see Install).
- It fires once per cap. Sitting at 100 doesn't loop it. If you want that, change `trigger` in the Lua to also match `PulseAnim`.
- This used to be called RageKnowsNoBounds. If you installed that version, delete the old folder or you'll get Dennis in stereo.

## License

MIT for the code. The audio clip belongs to FX.
