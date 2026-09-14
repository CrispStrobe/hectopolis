# App Review appeal — Guideline 4.3(a)

Prepared 2026-09-14 for Hectopolis 0.1.1, Apple app ID `6809142647`.
The iOS and macOS version records are both `REJECTED`; build 4 remains valid
on both platforms.

## Recommended sequence

1. Do not upload or resubmit the unchanged binary. A new submission does not
   answer a policy rejection.
2. Reply once in the App Review section for this submission using the text
   below. Attach three screenshots showing the scenario screen, a spatial
   overlay, and the detailed per-cell model inspector.
3. Ask Apple to identify the app or submissions Hectopolis allegedly
   duplicates. This matters because the rejection did not identify the
   comparison.
4. If App Review maintains the rejection without identifying a duplicated app
   or addressing the distinctions below, file one appeal for this rejection
   with the App Review Board. Do not file duplicate appeals.
5. Handle every other rejected app separately. Reusing identical appeal text
   across the portfolio would obscure the products' real differences.

## Resolution Center reply

The following is deliberately below Apple's 4,000-character reply limit.

> Hello App Review,
>
> We respectfully request reconsideration of the Guideline 4.3(a) rejection
> for Hectopolis 0.1.1 on iOS and macOS. Hectopolis is not another Bundle ID or
> content variant of any other app. It is one original, self-contained
> educational urban-systems simulation distributed under one Bundle ID,
> `com.crispstrobe.hectopolis`, on Apple's two supported platforms.
>
> Its defining functionality is specific to this product. Players construct a
> town on a hectare-scale map and run a deterministic monthly simulation that
> couples population, jobs, municipal finance, commuting and traffic with
> spatial models for noise, air pollution, urban heat, access and habitat
> quality. Ten indicators respond to the same evolving world, so actions create
> visible trade-offs and feedback loops rather than merely changing themed
> content.
>
> The learning design is likewise product-specific. Five authored missions and
> a sandbox progress from Starter to Guided and Explorer depth. Missions ask
> the player to predict an effect, test it, compare a safe what-if experiment,
> inspect causes, and reflect in a debrief. Optional map layers expose the
> spatial effect; optional explanations separately describe cause and effect,
> the model representation, and the governing scientific or legal reference.
> Examples include CNOSSOS-EU-style sound propagation, Germany's TA Lärm,
> InVEST habitat/urban-cooling concepts, the Huff access model, and official
> German mobility and municipal-finance data.
>
> This is substantial original implementation and content: 9,104 lines of
> handwritten Dart application/simulation code, 1,503 lines of tests, 220
> localized messages in each of English and German, five scenario definitions,
> and eleven model documents in the public source repository. It has no account,
> ads, analytics, tracking, in-app purchases, remote content catalogue, or
> mechanism for producing branded variants.
>
> We understand that several independently developed products from this
> account were submitted close together and may have prompted a portfolio-level
> similarity check. They are not multiple versions of Hectopolis and do not
> share its simulation, scenarios, interaction model, educational material, or
> map-based interface. Common platform conventions and Flutter runtime code do
> not make them versions of the same app.
>
> A playable build is available at
> https://crispstrobe.github.io/hectopolis/ and the complete source, model,
> scenarios, tests, and citations are at
> https://github.com/CrispStrobe/hectopolis.
>
> Could you please identify which submitted app or apps Hectopolis was found to
> duplicate, and whether the concern is binary, metadata, or concept similarity?
> We would be grateful for a manual review of the attached product-specific
> screens and the distinctions above.
>
> Thank you.

## App Review Board appeal

> We appeal the rejection of Hectopolis 0.1.1 (Apple ID 6809142647; iOS and
> macOS) under Guideline 4.3(a).
>
> Guideline 4.3(a) prohibits multiple Bundle IDs of the same app. Hectopolis is
> a single cross-platform product under one Bundle ID, not a location, language,
> customer, institution, or branded content variant. It cannot generate other
> apps and is not a repackaged template.
>
> Hectopolis provides a distinct map-building and simulation experience. Its
> deterministic model couples land use, population, employment, municipal
> finance, commuting, traffic, noise, air pollution, urban heat, green and
> retail access, habitat maturation, fragmentation, biodiversity, and carbon
> balance. Players see ten interdependent indicators, spatial overlays, delayed
> effects, and feedback loops. Five authored missions plus sandbox mode use
> predictions, experiments, causal inspection, debriefs, and optional
> challenges. Explanations expose cause/effect, mathematical representation,
> and scientific or legal sources at user-selected depth in English and German.
>
> These are not minor content substitutions. They comprise 9,104 lines of
> handwritten Dart product code, 1,503 lines of tests, 440 localized message
> entries, five scenario definitions, and eleven public model documents. The
> implementation, scenario rules, educational writing, visual layers, and
> sourced parameter set were created specifically for Hectopolis. The public
> playable version and source are available at
> https://crispstrobe.github.io/hectopolis/ and
> https://github.com/CrispStrobe/hectopolis.
>
> Several independent apps from this developer account were submitted in a
> short period. We understand why that may justify closer review, but timing
> does not make those products multiple Bundle IDs of Hectopolis. No other app
> on the account shares this simulation core, hectare map, scenarios, model
> documentation, causal learning flow, or urban/ecological subject matter.
>
> The rejection did not identify the allegedly duplicated app. We asked App
> Review for that comparison and supplied product screenshots and reviewer
> navigation. We respectfully request that the Board evaluate Hectopolis on its
> actual functionality and reverse the 4.3(a) determination, or identify the
> specific duplication so that we can address a concrete concern.

## Reviewer navigation

- Start **Living by the road** to see a prediction, population goal, traffic
  noise propagation, and the causal learning flow.
- Open the layers control and select **Noise** or **Air quality** to see the
  spatial field respond to placement and simulated traffic.
- Open the mission notebook, then a concept's **Cause and effect**, **Model**,
  and **Source / law** sections.
- Use the safe experiment to compare a changed map without overwriting the
  active mission.
- Start **Habitat corridor** to see connectivity, fragmentation, threat decay,
  habitat maturation, and optional challenge constraints.
- Start **Balance the books** to see the population–jobs–revenue–maintenance
  feedback loop and delayed monthly state changes.

## Evidence to attach

Use product screens, not marketing title cards:

1. Scenario selection showing the five distinct missions and sandbox.
2. **Living by the road** with the noise overlay and goals visible.
3. Tile inspector showing local noise, air, heat, access, habitat, traffic,
   residents, commute, car share, road access, and tile age together.

The current screenshot artifact provides these exact English iPad files:

- `en_01_levels.png`
- `en_03_noise_overlay.png`
- `en_05_inspector.png`

They are in the `screenshots-ios` artifact from GitHub Actions run
`34256693938`. If a fresh fourth screenshot is captured, make it the mission
notebook's Model and Source / law view.

If the appeal form accepts a fourth attachment, include a one-page PDF with:

- the reviewer navigation above;
- the ten coupled indicators;
- the public demo and source links; and
- a short comparison stating that the other account apps have different
  purposes, interfaces, interaction models, content, and codebases.

Do not attach source-code dumps or lead with framework-level implementation
details. The screenshots and reviewer route establish the user-visible product
difference; the public code and measurements corroborate it.
