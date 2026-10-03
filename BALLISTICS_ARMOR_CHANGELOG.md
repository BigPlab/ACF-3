# Ballistics, Spall and Armor Materials Revision

Branch: `Really-extensive-armor-change-test` (divergent ballistics testing). Also carries the earlier `ballistics-praxis` armor commits this work builds on (material changes, NERA). Merged with this branch's damage feathering: hits keep `Frac`, and RHA/DU keep the doubled `HealthMul` alongside praxis `CostMul`. Sources: Hazell, *Armour: Materials, Theory, and Design* (cited as "Hazell"), plus the analysis notes in `ArmorBooks/`.

## Goals

1. Outcomes that are more realistic and easier to tune.
2. Deadlier, more realistic spall. The core of the cone is hard to stop. A liner stops the periphery, which only narrows the cone.
3. Composites that beat the sum of their parts against KE and CE, for example steel/textolite/steel against equal-mass steel.
4. Rules that come from a few material properties instead of per-case rules. Keep existing infrastructure.

## Summary

| Area | Before | After |
|---|---|---|
| Layering | Energy rule after each plate, with penetration ∝ v^1.1. Splitting a plate helped the attacker (two equal plates acted as ~0.83x one plate for AP and ~0.76x for APFSDS). HEAT jets double-counted mass loss, which helped the defender. | Penetration is spent linearly for every projectile type, so splitting is neutral (Hazell p. 299: same-material laminates gain nothing). |
| Material model | One `KineticMul`/`ChemicalMul` per material, plus an experimental density-mismatch interface cost. | Three physical properties per material (`Hardness`, `Toughness`, `SoundSpeed`) drive all interactions. Base multipliers stay the main balance knobs. |
| Composites | Interface shear on every density change. Ignored gaps, and could be farmed. | Hard face over a tougher back (KE), confined soft interlayer (CE strong, KE mild), brittle damage loss, hardness-aware ricochet. All gated by contact, thickness and caliber. |
| Spall | Plug mass = bored channel. 0.5% of KE split across fragments (~110–130 m/s). Count tied to KE. Every perforated convex spalled. | Release gated by impedance. Mass from the rear crater. Fragment size from Grady (toughness). Fast heavy core and slow light edge. Weighted fragments conserve mass. |

## 1. Neutral layering (Tier 0)

- **`ammo_types/ap.lua` PropImpact**: exit speed is now `CalcSpeed(Overkill)`, which is penetration minus the armor defeated. Fragments already worked this way.
  - *Why:* with `Pen ∝ v^1.1`, the old energy rule left `Pen·(1−L)^0.55` after a layer instead of `Pen·(1−L)`, which penalized every multi-convex composite. A layered build now has to earn its bonus from the material rules. This applies to APHE, APFSDS, APCR and APDS through their `CalcSpeed`.
  - *Side effect:* residual penetration after a plate is lower than before (for example, 100 mm through 50 mm now leaves 50 instead of 68). Deadlier spall partly makes up for this.
- **`ammo_types/fl.lua`**: added the missing `CalcSpeed` inverse. Flechettes previously recovered speed using the parent shell's mass and caliber.
- **`ammo_types/heat.lua`**: `LostMassPct = Effective / FullPen`. Before, it divided by penetration already scaled by the remaining jet mass, so jets lost mass as `m²`.

## 2. Material properties

New fields on every armor type (`armor_types.lua`). Defaults in `registration.lua` are steel-like (`Hardness 1, Toughness 40, SoundSpeed 4570`), so third-party types stay neutral.

| Field | Unit | Drives |
|---|---|---|
| `Hardness` | × RHA (indentation) | Hard face erosion (only values > 1 count), ricochet |
| `Toughness` | MPa·m^0.5 (K_IC) | Backing quality, brittle damage loss, spall fragment size |
| `SoundSpeed` | m/s (bulk c₀) | Impedance `Z = ρc₀`: interlayer confinement, spall release, scab speed cap |

Values are approximate literature figures. RHA c₀ = 4570 m/s is from Hazell Table 5.5. SiC Hardness 6 ≈ HV 2700 / HV ~400.

### Multiplier changes

| Material | Field | Old → New | Justification |
|---|---|---|---|
| HHRHA | KE | 1.25 → 1.15 | Hazell Table 7.3: 550 BHN plate is 1.16x RHA alone. The DHA bonus comes from pairing (see 3a). |
| HHRHA | CE | 1.15 → 1.05 | Jets are near-hydrodynamic, so hardness adds little. |
| SiC | KE | 2.2 → 1.35 | Unbacked value. A tough backing raises it to ~2.2 vs AP and ~1.8 vs fast rods. |
| SiC | CE | 1.6 → 1.2 | Ceramic Em vs jets is ~2–3, which is ~1.0–1.2 by thickness. |
| Textolite | KE / CE | 0.5 / 0.7 → 0.4 / 0.45 | Hydrodynamic limit is 0.48. Its strength comes from confinement (Hazell 8.12, the glass/textolite sandwich). |
| Aluminum | CE | 0.3 → 0.45 | Hydrodynamic limit is 0.59. 0.3 made it worse per kg than steel against jets. |
| NERA | CE | 1.5 → 1.0 | Matches a hand-built steel/rubber/steel sandwich (~0.93) plus a small premium for the engineered cassette. |

Descriptions were updated for HHRHA, SiC, Textolite and Rubber. `SpallMul` is now explicitly a **mass** multiplier, as the header already said.

## 3. Composite rules (`volumetrics_sh.lua`, shared)

`ACF.ResolveConvexStack` now writes flat neighbor fields onto each hit: `FrontType/FrontThick/FrontGap` and `BackType/BackThick/BackGap`. They are flat so the hits have no cyclic links. `ACF.GetLayerMul(Hit, Chemical, Caliber, Speed)` returns the effective RHA multiplier. Every consumer uses it: bullets, fragments, jets and the armor trace tool. It replaces `ACF.GetInterfaceCost` and `ACF.InterfaceShear`.

Shared gates:
- **Contact**: `1 − Gap/Reach`, where `Reach = max(caliber, 10 mm)`. Spaced plates get no composite effect.
- **Engage**: `min(1, t / (0.25·caliber))`. A layer that is thin relative to the round contributes nothing extra.

### 3a. Hard face over tougher back (KE only)
`Mul ×= 1 + HardFaceBonus · tanh(2·ln Hardness) · Backing · Support · Contact · Engage · Fade`
- `Backing = clamp((K_back − K_face)/40)`. Two identical plates, or a softer-and-weaker back, give nothing.
- `Support = min(1, t_back / (0.5·t_face))`. This follows Florence's optimum of face ≈ 1.6–2.5× back (Hazell Eqs. 8.11–8.12).
- `Fade = min(1, (1200/v)²)`. Strength terms scale as R/ρv², so at rod velocities density dominates (Hazell 4.5).
- *Why:* DHA has Em 1.78 against 1.16 for uniform HHA (Hazell Table 7.3). A ceramic cone needs a back plate to catch it (Hazell 8.6, Florence).

### 3b. Confined interlayer (CE strong, KE mild)
`Mul += Bonus · min(R_front, R_back) · Support · Contact_f · Contact_b · Engage`
- `R` is the stress reflection coefficient `(Z_plate − Z_i)/(Z_plate + Z_i)` (Hazell Eq. 5.25). Only a layer softer than **both** neighbors qualifies.
- `Support = min(1, min(plate RHAe) / (0.25·t_i))`, so thin foils cannot confine.
- `Bonus = 0.5` (CE) or `0.2` (KE) RHA mm per mm.
- *Why:* one rule covers NERA bulging (Hazell 10.3), steel/glass/textolite sandwiches (Hazell 8.12) and liquid-filled columns (Hazell 10.4).

### 3c. Brittle damage
`Mul ×= 1 − 0.3 · Brittleness · (1 − Health/MaxHealth)`, where `Brittleness = 1 − min(1, K/40)`.
- *Why:* comminuted ceramic keeps ~70% of its efficiency (Hazell p. 340). This rewards tiling (small convexes) over one-piece ceramic blocks. It has no effect on ductile metals.

### 3d. Hardness-aware ricochet (`ballistics_sv.lua`)
The ricochet sigmoid center shifts by `−5° · clamp(ln Hardness, −2, 2)`: SiC about −9°, Aluminum +4.6°, rubber +10°. *Why:* hard plates turn rounds at lower obliquity (Hazell 4.3.3).

### Results (hand calc mirroring the Lua; `tool` = full engagement)

| Build | kg/m² | Steel of equal mass | AP 100 mm @800 | APFSDS 25 mm @1700 | Jet (6 mm) |
|---|---|---|---|---|---|
| RHA 100 | 784 | 100 | 100 | 100 | 100 |
| RHA 50 + 50 | 784 | 100 | 100 | 100 | 100 |
| HHRHA 100 | 785 | 100 | 115 | 115 | 105 |
| HHRHA 50 / RHA 50 (DHA) | 785 | 100 | **131** | 119 | 103 |
| SiC 60 alone | 193 | 25 | 81 | 81 | 72 |
| SiC 60 / RHA 30 | 428 | 55 | **164** | 137 | 102 |
| SiC 60 / Al 30 | 274 | 35 | 130 | 113 | 86 |
| RHA 20 / Textolite 50 / RHA 20 | 404 | 52 | **68** | 68 | **81** |
| RHA 6 / Rubber 8 / RHA 6 (hand-built NERA) | 103 | 13 | 15 | 16 | **19** |
| RHA 100 / Rubber 1 / RHA 1 (spam test) | 793 | 101 | 101 | 101 | 102 |

Without the composite rules, the textolite sandwich would give 60 (KE) / 62.5 (CE) and SiC/RHA would give 111.

## 4. Spall (`Ballistics.DoSpall`)

1. **Source and gate.** Spall comes from the exit convex (`DmgInfo` hits now carry `Source`). It is scaled by `ACF.GetSpallRelease`: 1 into air or a gap, `R` into a softer layer in contact, and 0 into an equal or stiffer layer. Steel backed by steel, or ceramic backed by steel, does not spall internally. Steel backed by a liner still spalls, and the liner catches it. Only meshed armor spalls; players and NPCs no longer throw "RHA" spall.
2. **Mass.** `0.25 · SpallMul · Release · ρ · π(r + 0.25t)² · min(t, 2r)`: a rear crater that widens through the plate, from the last caliber or so of thickness.
3. **Size and count.** Grady fragment diameter `(20K/(ρc₀ε̇))^(2/3)` with `ε̇ = v/d` (Hazell Eq. 3.61). Tough RHA gives a few chunky pieces, SiC gives fine debris, HHRHA is in between. Traced count is `min(real count, 0.2/mm of bore, 20)`.
4. **Weighting.** Each traced fragment carries `Weight = spalled mass / traced mass` and scales damage area and bored volume, but **not** penetration. Mass is conserved at a fixed trace budget.
5. **Speed.** `Core = min(v·max(√(1−Loss), 0.25), c₀/3)`. The core follows the residual penetrator. The 0.25 floor represents a scab that still flies near the ballistic limit, and `c₀/3` is the scab rule (Hazell p. 92). Speed falls to 30% at the cone edge.
6. **Cone.** Half-angle is 20° at heavy overmatch and 60° near the limit (Horsfall saw ~40°, Hazell 9.5). Heavy fragments sit near the axis because the same Mott draw sets both mass and angle.
7. **Filtering.** Fragments now filter only the convexes already bored, not the whole struck entity. A liner convex in the same prop now catches spall. Each fragment gets its own copy of the filter.

| Case | Old | New |
|---|---|---|
| 100 mm AP (18.6 kg @800) through 60 RHA | 20 frags, ~127 m/s, 47° | 8 traced, core 681 m/s, 31°, ~350 kJ |
| 30 mm AP through 30 RHA | 2 frags, ~110 m/s | 6 traced, core 769 m/s |
| APFSDS through 300 RHA | n/a | 5 traced, core 1106 m/s |

With a 20 mm aramid liner (9 mm RHAe), 80–99% of the spall *mass* (the core) still gets through. 95% of the fragments that get through stay within **6–14°**, against a full cone of 31–43°. The liner narrows the cone and cannot stop its center.

## 5. Other files

- `damage_sv.lua getBulletDamage`: uses `GetLayerMul`, `DamageWeight` and the jet's `EntityHits`, and records `Source` on each hit. The `PenPrev` state is removed.
- `ballistics_sv.lua`: `GatherMeshIntersections` takes an optional end point. New `Ballistics.GetEntityHits` resolves the jet's whole line once, so jets see composites across separate props.
- `fragments_sv.lua`: `ConvexFilter` and `DamageWeight` are copied per fragment.
- `globals.lua`: 10 composite tunables replace `InterfaceShear`. Spall tunables stay file-local in `ballistics_sv.lua` for hot reload.
- Tools: the armor trace shows composite-inclusive KE/CE (full engagement). The material panel shows Hardness, Toughness and Impedance.

## Tunables

| Knob | Default | Effect |
|---|---|---|
| `ACF.HardFaceBonus` | 0.65 | Max hard-face gain (SiC ≈ +65%, HHRHA ≈ +41%) |
| `ACF.HardFaceSpeed` | 1200 | m/s where the hard-face bonus starts fading |
| `ACF.BackingToughness` | 40 | Toughness margin for full backing; also the "fully ductile" reference |
| `ACF.BackingRatio` | 0.5 | Back/face thickness for full support |
| `ACF.InterlayerBonusCE` / `KE` | 0.5 / 0.2 | Confined interlayer gain, RHA mm per mm |
| `ACF.InterlayerPlateRatio` | 0.25 | Plate RHAe / interlayer thickness for full confinement |
| `ACF.CompositeContactGap` | 10 | mm; minimum contact reach |
| `ACF.CompositeMinThickness` | 0.25 | Calibers of thickness for full engagement |
| `ACF.BrittleDamageLoss` | 0.3 | Effectiveness a fully brittle layer loses at 0 HP |
| `SpallMassFraction` … `SpallMinToughness` | see file | Spall mass, speed, cone, trace budget |

Setting any bonus to 0 disables that rule.

## Known limits and balance watch items

- **Not verified in game.** All numbers come from hand calculations that mirror the Lua. `glualint` passes on every touched file.
- **Fuel as an interlayer.** Diesel confined between plates gets a large CE gain (liquid columns, Hazell 10.4). Diesel can't be assigned with the tool, but fuel tanks placed between plates would benefit. Watch for abuse; if it becomes a problem, lower Diesel's `SoundSpeed` or gate the rule on `Toughness > 0`.
- **HE blast and fragments** (`explosion_sv.lua`) still use the base multipliers, with no composite effects.
- **Spall cost.** There are more traced fragments per penetration than before for mid calibers (for example, 2 → 6 for 30 mm), although contact gating removes spall between touching plates. Lower `SpallFragsPerMm` if the server load is too high.
- **Residual penetration** after each plate is lower (linear rule), so expect fewer clean pass-throughs into internals. Spall now carries much of the behind-armor damage.
- Projectile hardness is not modeled. The hard face compares against RHA, and the velocity fade handles rods.

## Suggested in-game checks

1. RHA 100 against 50+50 (contact and spaced): same result against AP and APFSDS.
2. SiC/RHA at back/face ratios of 0.25, 0.5 and 1: bonus saturates at 0.5.
3. A 20 mm aramid liner behind 60 mm RHA: the fragment cone narrows, and the core still reaches the crew.
4. RHA/Textolite/RHA against HEAT, with and without a 20 mm gap: the bonus disappears when spaced.
5. A 30 mm autocannon burst on a liner-backed hull: check server frame time.
