// SPDX-License-Identifier: AGPL-3.0-or-later
// GENERATED FILE - do not edit. Source: data/levels/*.json
// Regenerate with: dart run tools/gen_params.dart

/// Built-in levels as JSON, in file order (mirror of data/levels/).
const List<String> defaultLevelsJson = [
  r'''
{
  "id": "village",
  "order": 1,
  "budgetKEur": 6000,
  "turnLimitMonths": 120,
  "learning": {
    "tier": "starter",
    "concepts": ["access", "tradeoffs"],
    "features": ["prediction", "debrief"],
    "predictionId": "village_access",
    "challenges": ["village_quiet", "village_nature"]
  },
  "tiles": { "housing_low": 16, "commercial": 2, "park": 2, "road": 6, "forest": 8, "meadow": null },
  "goals": [
    { "indicator": "housing", "min": 60 },
    { "indicator": "shopping", "min": 50 },
    { "indicator": "noise", "min": 80 },
    { "indicator": "biodiversity", "min": 45 }
  ],
  "map": [
    "cccccccccccc",
    "cccccccccccc",
    "ccccffcccccc",
    "cccffffccccc",
    "cccc..cccccc",
    "rrrrrrrrrrrr",
    "cccc..cccccc",
    "ccccc.wwcccc",
    "cccccc.wcccc",
    "cccccccccccc",
    "cccccccccccc",
    "cccccccccccc"
  ]
}
''',
  r'''
{
  "id": "noise",
  "order": 2,
  "budgetKEur": 9000,
  "turnLimitMonths": 96,
  "learning": {
    "tier": "starter",
    "concepts": ["noise_distance", "noise_shielding", "exposure"],
    "features": ["prediction", "causalView", "experiment", "debrief", "challenges"],
    "predictionId": "noise_homes",
    "challenges": ["noise_no_roads", "noise_two_designs"]
  },
  "tiles": {
    "housing_high": 8,
    "housing_low": 8,
    "forest": 14,
    "park": 3,
    "commercial": 1,
    "meadow": null,
    "road": 4
  },
  "goals": [
    {
      "indicator": "housing",
      "min": 70
    },
    {
      "indicator": "noise",
      "min": 75
    },
    {
      "indicator": "recreation",
      "min": 60
    },
    {
      "metric": "population",
      "min": 1200
    }
  ],
  "paramOverrides": {
    "noise": {
      "baselineThroughTraffic": {
        "value": 14000,
        "source": "level: regional through road"
      }
    }
  },
  "map": [
    "IIII............",
    "IIII............",
    "IIII............",
    "IIII............",
    "................",
    "rrrrrrrrrrrrrrrr",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
    "..........ww....",
    "..........ww....",
    "................",
    "................"
  ]
}
''',
  r'''
{
  "id": "habitat",
  "order": 3,
  "budgetKEur": 4000,
  "turnLimitMonths": 240,
  "learning": {
    "tier": "guided",
    "concepts": ["connectivity", "fragmentation", "maturity"],
    "features": ["prediction", "causalView", "experiment", "debrief", "challenges"],
    "predictionId": "habitat_corridor",
    "challenges": ["habitat_no_water", "habitat_fast"]
  },
  "tiles": { "forest": 12, "meadow": null, "water": 2, "park": 2, "cropland": null },
  "goals": [
    { "indicator": "biodiversity", "min": 70 },
    { "indicator": "housing", "min": 50 },
    { "indicator": "recreation", "min": 60 }
  ],
  "map": [
    "ffffcccccccccccc",
    "ffffcccccccccccc",
    "ffffcccccccccccc",
    "ffffcccccccccccc",
    "cccccccccccccccc",
    "cccccccccccccccc",
    "rrrrrrrrrrrrrrrr",
    "cchhhhcccccccccc",
    "cchhhhcccccccccc",
    "ccccccccccccccff",
    "ccccccccccccffff",
    "ccccccccccccffff",
    "ccccccccccccffff",
    "cccccccccccccccc",
    "cccccccccccccccc",
    "cccccccccccccccc"
  ]
}
''',
  r'''
{
  "id": "budget",
  "order": 4,
  "budgetKEur": 4000,
  "turnLimitMonths": 72,
  "learning": {
    "tier": "guided",
    "concepts": ["budget_loop", "delay", "tradeoffs"],
    "features": ["prediction", "causalView", "experiment", "debrief", "challenges"],
    "predictionId": "budget_recovery",
    "challenges": ["budget_reserve", "budget_clean_air"]
  },
  "tiles": {
    "housing_high": 6,
    "housing_low": 6,
    "commercial": 4,
    "industry": 2,
    "road": 4,
    "park": 1,
    "meadow": null
  },
  "goals": [
    {
      "indicator": "economy",
      "min": 75
    },
    {
      "metric": "population",
      "min": 1000
    },
    {
      "metric": "budgetKEur",
      "min": 1000
    },
    {
      "indicator": "air",
      "min": 60
    }
  ],
  "map": [
    "................",
    ".rrrrrrrrrrrrrr.",
    ".r....p.....p.r.",
    ".r..hh..........",
    ".r..hh.....pp.r.",
    ".r.........pp.r.",
    ".r......p.....r.",
    ".rrrrrrrrrrrrrr.",
    ".r......p.....r.",
    ".r..pp........r.",
    ".r..pp..hh....r.",
    ".r......hh....r.",
    ".r............r.",
    ".r....p....p..r.",
    ".rrrrrrrrrrrrrr.",
    "................"
  ]
}
''',
  r'''
{
  "id": "quarter",
  "order": 5,
  "budgetKEur": 25000,
  "turnLimitMonths": 180,
  "learning": {
    "tier": "explorer",
    "concepts": ["feedback", "mixed_city", "resilience"],
    "features": ["causalView", "experiment", "debrief", "challenges"],
    "challenges": ["quarter_no_new_roads", "quarter_balanced"]
  },
  "tiles": {
    "housing_high": null,
    "housing_low": null,
    "commercial": null,
    "park": null,
    "forest": null,
    "meadow": null,
    "water": null,
    "road": null,
    "cropland": null
  },
  "goals": [
    {
      "metric": "population",
      "min": 3000
    },
    {
      "indicator": "air",
      "min": 75
    },
    {
      "indicator": "noise",
      "min": 70
    },
    {
      "indicator": "recreation",
      "min": 60
    },
    {
      "indicator": "biodiversity",
      "min": 35
    },
    {
      "indicator": "commuting",
      "min": 45
    }
  ],
  "map": [
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r...............",
    "r..............."
  ]
}
''',
];
