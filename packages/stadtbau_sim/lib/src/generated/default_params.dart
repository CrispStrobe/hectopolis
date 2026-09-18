// SPDX-License-Identifier: AGPL-3.0-or-later
// GENERATED FILE - do not edit. Source: data/params/tiles.json
// Regenerate with: dart run tools/gen_params.dart

/// Default simulation parameters as JSON.
///
/// Values only: the `source` and `note` fields of
/// data/params/tiles.json are stripped here, because nothing
/// reads them at run time and they are 15 KB gzipped of every
/// first load. The citations live in the JSON, and the
/// generated Quellen page renders them from it.
const String defaultParamsJson = r'''
{
  "schemaVersion": 1,
  "notes": "Source of truth for all simulation parameters. Regenerate the Dart mirror with `dart run tools/gen_params.dart`. Every numeric entry is {value, source, note?}. Values marked 'initial estimate' must be verified in task T-103.",
  "grid": {
    "cellSizeM": {
      "value": 100
    },
    "tickMonths": {
      "value": 1
    }
  },
  "tiles": {
    "meadow": {
      "category": "nature",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 0
      },
      "sealing": {
        "value": 0.0
      },
      "biotopeValue": {
        "value": 18
      },
      "biotopeStart": {
        "value": 0.45
      },
      "recoveryMonths": {
        "value": 120
      },
      "noiseEmissionDb": {
        "value": 0
      },
      "airEmission": {
        "value": 0.0
      },
      "airSink": {
        "value": 0.05
      },
      "shade": {
        "value": 0.05
      },
      "albedo": {
        "value": 0.2
      },
      "eti": {
        "value": 0.8
      },
      "greenWeight": {
        "value": 0.6
      },
      "co2PerHaYear": {
        "value": -1.0
      },
      "buildCostKEur": {
        "value": 5
      },
      "maintenanceKEurYear": {
        "value": 1
      },
      "noiseNightReductionDb": {
        "value": 0
      },
      "perviousCurveNumber": {
        "value": 58
      }
    },
    "cropland": {
      "category": "nature",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 1
      },
      "sealing": {
        "value": 0.0
      },
      "biotopeValue": {
        "value": 6
      },
      "biotopeStart": {
        "value": 1.0
      },
      "recoveryMonths": {
        "value": 1
      },
      "noiseEmissionDb": {
        "value": 0
      },
      "airEmission": {
        "value": 0.05
      },
      "airSink": {
        "value": 0.02
      },
      "shade": {
        "value": 0.02
      },
      "albedo": {
        "value": 0.2
      },
      "eti": {
        "value": 0.6
      },
      "greenWeight": {
        "value": 0.3
      },
      "co2PerHaYear": {
        "value": 1.5
      },
      "buildCostKEur": {
        "value": 2
      },
      "maintenanceKEurYear": {
        "value": 0
      },
      "noiseNightReductionDb": {
        "value": 0
      },
      "perviousCurveNumber": {
        "value": 78
      }
    },
    "forest": {
      "category": "nature",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 0
      },
      "sealing": {
        "value": 0.0
      },
      "biotopeValue": {
        "value": 18
      },
      "biotopeStart": {
        "value": 0.4
      },
      "recoveryMonths": {
        "value": 240
      },
      "noiseEmissionDb": {
        "value": 0
      },
      "airEmission": {
        "value": 0.0
      },
      "airSink": {
        "value": 0.2
      },
      "shade": {
        "value": 0.9
      },
      "albedo": {
        "value": 0.15
      },
      "eti": {
        "value": 1.0
      },
      "greenWeight": {
        "value": 0.9
      },
      "co2PerHaYear": {
        "value": -10.0
      },
      "buildCostKEur": {
        "value": 20
      },
      "maintenanceKEurYear": {
        "value": 1
      },
      "noiseNightReductionDb": {
        "value": 0
      },
      "perviousCurveNumber": {
        "value": 55
      }
    },
    "water": {
      "category": "nature",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 0
      },
      "sealing": {
        "value": 0.0
      },
      "biotopeValue": {
        "value": 16
      },
      "biotopeStart": {
        "value": 0.5
      },
      "recoveryMonths": {
        "value": 120
      },
      "noiseEmissionDb": {
        "value": 0
      },
      "airEmission": {
        "value": 0.0
      },
      "airSink": {
        "value": 0.03
      },
      "shade": {
        "value": 0.0
      },
      "albedo": {
        "value": 0.08
      },
      "eti": {
        "value": 1.0
      },
      "greenWeight": {
        "value": 0.7
      },
      "co2PerHaYear": {
        "value": 0.0
      },
      "buildCostKEur": {
        "value": 200
      },
      "maintenanceKEurYear": {
        "value": 2
      },
      "noiseNightReductionDb": {
        "value": 0
      },
      "perviousCurveNumber": {
        "value": 98
      }
    },
    "park": {
      "category": "green_urban",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 2
      },
      "sealing": {
        "value": 0.1
      },
      "biotopeValue": {
        "value": 13
      },
      "biotopeStart": {
        "value": 0.5
      },
      "recoveryMonths": {
        "value": 240
      },
      "noiseEmissionDb": {
        "value": 0
      },
      "airEmission": {
        "value": 0.0
      },
      "airSink": {
        "value": 0.1
      },
      "shade": {
        "value": 0.5
      },
      "albedo": {
        "value": 0.18
      },
      "eti": {
        "value": 0.7
      },
      "greenWeight": {
        "value": 1.0
      },
      "co2PerHaYear": {
        "value": -3.0
      },
      "buildCostKEur": {
        "value": 400
      },
      "maintenanceKEurYear": {
        "value": 20
      },
      "noiseNightReductionDb": {
        "value": 0
      },
      "perviousCurveNumber": {
        "value": 61
      }
    },
    "housing_low": {
      "category": "residential",
      "residentsPerHa": {
        "value": 45
      },
      "jobsPerHa": {
        "value": 3
      },
      "sealing": {
        "value": 0.45
      },
      "biotopeValue": {
        "value": 5
      },
      "biotopeStart": {
        "value": 1.0
      },
      "recoveryMonths": {
        "value": 1
      },
      "noiseEmissionDb": {
        "value": 45
      },
      "airEmission": {
        "value": 0.15
      },
      "airSink": {
        "value": 0.03
      },
      "shade": {
        "value": 0.15
      },
      "albedo": {
        "value": 0.2
      },
      "eti": {
        "value": 0.3
      },
      "greenWeight": {
        "value": 0.0
      },
      "co2PerHaYear": {
        "value": 42
      },
      "buildCostKEur": {
        "value": 200
      },
      "maintenanceKEurYear": {
        "value": 2
      },
      "noiseNightReductionDb": {
        "value": 5
      },
      "perviousCurveNumber": {
        "value": 61
      }
    },
    "housing_high": {
      "category": "residential",
      "residentsPerHa": {
        "value": 180
      },
      "jobsPerHa": {
        "value": 15
      },
      "sealing": {
        "value": 0.75
      },
      "biotopeValue": {
        "value": 4
      },
      "biotopeStart": {
        "value": 1.0
      },
      "recoveryMonths": {
        "value": 1
      },
      "noiseEmissionDb": {
        "value": 50
      },
      "airEmission": {
        "value": 0.3
      },
      "airSink": {
        "value": 0.01
      },
      "shade": {
        "value": 0.1
      },
      "albedo": {
        "value": 0.15
      },
      "eti": {
        "value": 0.15
      },
      "greenWeight": {
        "value": 0.0
      },
      "co2PerHaYear": {
        "value": 166
      },
      "buildCostKEur": {
        "value": 400
      },
      "maintenanceKEurYear": {
        "value": 4
      },
      "noiseNightReductionDb": {
        "value": 5
      },
      "perviousCurveNumber": {
        "value": 61
      }
    },
    "commercial": {
      "category": "work",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 100
      },
      "retailFloorM2": {
        "value": 2000
      },
      "sealing": {
        "value": 0.85
      },
      "biotopeValue": {
        "value": 2
      },
      "biotopeStart": {
        "value": 1.0
      },
      "recoveryMonths": {
        "value": 1
      },
      "noiseEmissionDb": {
        "value": 58
      },
      "airEmission": {
        "value": 0.6
      },
      "airSink": {
        "value": 0.0
      },
      "shade": {
        "value": 0.05
      },
      "albedo": {
        "value": 0.2
      },
      "eti": {
        "value": 0.1
      },
      "greenWeight": {
        "value": 0.0
      },
      "co2PerHaYear": {
        "value": 66
      },
      "buildCostKEur": {
        "value": 300
      },
      "maintenanceKEurYear": {
        "value": 3
      },
      "noiseNightReductionDb": {
        "value": 8
      },
      "perviousCurveNumber": {
        "value": 61
      }
    },
    "industry": {
      "category": "work",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 45
      },
      "sealing": {
        "value": 0.88
      },
      "biotopeValue": {
        "value": 2
      },
      "biotopeStart": {
        "value": 1.0
      },
      "recoveryMonths": {
        "value": 1
      },
      "noiseEmissionDb": {
        "value": 63
      },
      "airEmission": {
        "value": 3.0
      },
      "airSink": {
        "value": 0.0
      },
      "shade": {
        "value": 0.02
      },
      "albedo": {
        "value": 0.25
      },
      "eti": {
        "value": 0.05
      },
      "greenWeight": {
        "value": 0.0
      },
      "co2PerHaYear": {
        "value": 1220
      },
      "buildCostKEur": {
        "value": 300
      },
      "maintenanceKEurYear": {
        "value": 3
      },
      "noiseNightReductionDb": {
        "value": 5
      },
      "perviousCurveNumber": {
        "value": 61
      }
    },
    "road": {
      "category": "infrastructure",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 0
      },
      "sealing": {
        "value": 0.95
      },
      "biotopeValue": {
        "value": 0
      },
      "biotopeStart": {
        "value": 1.0
      },
      "recoveryMonths": {
        "value": 1
      },
      "noiseEmissionDb": {
        "value": 60
      },
      "airEmission": {
        "value": 1.0
      },
      "airSink": {
        "value": 0.0
      },
      "shade": {
        "value": 0.05
      },
      "albedo": {
        "value": 0.1
      },
      "eti": {
        "value": 0.02
      },
      "greenWeight": {
        "value": 0.0
      },
      "co2PerHaYear": {
        "value": 0
      },
      "buildCostKEur": {
        "value": 300
      },
      "maintenanceKEurYear": {
        "value": 10
      },
      "noiseNightReductionDb": {
        "value": 6.5
      },
      "perviousCurveNumber": {
        "value": 61
      }
    },
    "wetland": {
      "category": "nature",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 0
      },
      "sealing": {
        "value": 0.0
      },
      "biotopeValue": {
        "value": 22
      },
      "biotopeStart": {
        "value": 0.35
      },
      "recoveryMonths": {
        "value": 180
      },
      "noiseEmissionDb": {
        "value": 0
      },
      "airEmission": {
        "value": 0.0
      },
      "airSink": {
        "value": 0.08
      },
      "shade": {
        "value": 0.1
      },
      "albedo": {
        "value": 0.12
      },
      "eti": {
        "value": 0.95
      },
      "greenWeight": {
        "value": 0.5
      },
      "co2PerHaYear": {
        "value": -5.0
      },
      "buildCostKEur": {
        "value": 20
      },
      "maintenanceKEurYear": {
        "value": 1
      },
      "retailFloorM2": {
        "value": 0
      },
      "noiseNightReductionDb": {
        "value": 0
      },
      "perviousCurveNumber": {
        "value": 98
      }
    },
    "solar_field": {
      "category": "infrastructure",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 0.5
      },
      "sealing": {
        "value": 0.1
      },
      "biotopeValue": {
        "value": 8
      },
      "biotopeStart": {
        "value": 0.7
      },
      "recoveryMonths": {
        "value": 60
      },
      "noiseEmissionDb": {
        "value": 0
      },
      "airEmission": {
        "value": 0.0
      },
      "airSink": {
        "value": 0.02
      },
      "shade": {
        "value": 0.3
      },
      "albedo": {
        "value": 0.1
      },
      "eti": {
        "value": 0.3
      },
      "greenWeight": {
        "value": 0.1
      },
      "co2PerHaYear": {
        "value": -266.0
      },
      "buildCostKEur": {
        "value": 700
      },
      "maintenanceKEurYear": {
        "value": 8
      },
      "retailFloorM2": {
        "value": 0
      },
      "noiseNightReductionDb": {
        "value": 0
      },
      "perviousCurveNumber": {
        "value": 61
      }
    },
    "mixed_use": {
      "category": "residential",
      "residentsPerHa": {
        "value": 120
      },
      "jobsPerHa": {
        "value": 45
      },
      "sealing": {
        "value": 0.7
      },
      "biotopeValue": {
        "value": 4
      },
      "biotopeStart": {
        "value": 1.0
      },
      "recoveryMonths": {
        "value": 1
      },
      "noiseEmissionDb": {
        "value": 55
      },
      "airEmission": {
        "value": 0.35
      },
      "airSink": {
        "value": 0.02
      },
      "shade": {
        "value": 0.35
      },
      "albedo": {
        "value": 0.2
      },
      "eti": {
        "value": 0.25
      },
      "greenWeight": {
        "value": 0.05
      },
      "co2PerHaYear": {
        "value": 140
      },
      "buildCostKEur": {
        "value": 450
      },
      "maintenanceKEurYear": {
        "value": 10
      },
      "retailFloorM2": {
        "value": 3000
      },
      "noiseNightReductionDb": {
        "value": 6
      },
      "perviousCurveNumber": {
        "value": 61
      }
    },
    "school": {
      "category": "work",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 25
      },
      "sealing": {
        "value": 0.5
      },
      "biotopeValue": {
        "value": 6
      },
      "biotopeStart": {
        "value": 0.8
      },
      "recoveryMonths": {
        "value": 120
      },
      "noiseEmissionDb": {
        "value": 52
      },
      "airEmission": {
        "value": 0.15
      },
      "airSink": {
        "value": 0.05
      },
      "shade": {
        "value": 0.4
      },
      "albedo": {
        "value": 0.22
      },
      "eti": {
        "value": 0.4
      },
      "greenWeight": {
        "value": 0.3
      },
      "co2PerHaYear": {
        "value": 33
      },
      "buildCostKEur": {
        "value": 900
      },
      "maintenanceKEurYear": {
        "value": 45
      },
      "retailFloorM2": {
        "value": 0
      },
      "noiseNightReductionDb": {
        "value": 12
      },
      "perviousCurveNumber": {
        "value": 61
      }
    },
    "tram_stop": {
      "category": "infrastructure",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 1
      },
      "sealing": {
        "value": 0.85
      },
      "biotopeValue": {
        "value": 1
      },
      "biotopeStart": {
        "value": 1.0
      },
      "recoveryMonths": {
        "value": 1
      },
      "noiseEmissionDb": {
        "value": 56
      },
      "airEmission": {
        "value": 0.05
      },
      "airSink": {
        "value": 0.0
      },
      "shade": {
        "value": 0.1
      },
      "albedo": {
        "value": 0.12
      },
      "eti": {
        "value": 0.05
      },
      "greenWeight": {
        "value": 0.0
      },
      "co2PerHaYear": {
        "value": 0.0
      },
      "buildCostKEur": {
        "value": 800
      },
      "maintenanceKEurYear": {
        "value": 25
      },
      "retailFloorM2": {
        "value": 0
      },
      "noiseNightReductionDb": {
        "value": 9
      },
      "perviousCurveNumber": {
        "value": 61
      }
    },
    "cycle_path": {
      "category": "infrastructure",
      "residentsPerHa": {
        "value": 0
      },
      "jobsPerHa": {
        "value": 0
      },
      "sealing": {
        "value": 0.35
      },
      "biotopeValue": {
        "value": 12
      },
      "biotopeStart": {
        "value": 0.6
      },
      "recoveryMonths": {
        "value": 120
      },
      "noiseEmissionDb": {
        "value": 0
      },
      "airEmission": {
        "value": 0.0
      },
      "airSink": {
        "value": 0.06
      },
      "shade": {
        "value": 0.35
      },
      "albedo": {
        "value": 0.15
      },
      "eti": {
        "value": 0.55
      },
      "greenWeight": {
        "value": 0.4
      },
      "co2PerHaYear": {
        "value": -1.0
      },
      "buildCostKEur": {
        "value": 120
      },
      "maintenanceKEurYear": {
        "value": 3
      },
      "retailFloorM2": {
        "value": 0
      },
      "noiseNightReductionDb": {
        "value": 0
      },
      "perviousCurveNumber": {
        "value": 58
      }
    }
  },
  "noise": {
    "areaReferenceDistanceM": {
      "value": 50
    },
    "areaDecayDbPerDecade": {
      "value": 20
    },
    "foliageAttenuationDbPerTile": {
      "value": 2
    },
    "buildingScreeningDbPerTile": {
      "value": 5
    },
    "maxPathAttenuationDb": {
      "value": 20
    },
    "backgroundDb": {
      "value": 35
    },
    "radiusTiles": {
      "value": 8
    },
    "trafficReferenceVehiclesPerDay": {
      "value": 10000
    },
    "baselineThroughTraffic": {
      "value": 2000
    },
    "limitDayDb": {
      "value": 55
    },
    "limitBadDb": {
      "value": 65
    },
    "nightGuidelineDb": {
      "value": 45
    },
    "nightLoaelDb": {
      "value": 40
    },
    "nightHighRiskDb": {
      "value": 55
    }
  },
  "air": {
    "decayLengthM": {
      "value": 300
    },
    "radiusTiles": {
      "value": 6
    },
    "sinkRadiusTiles": {
      "value": 3
    },
    "indexScale": {
      "value": 1.0
    },
    "trafficReferenceVehiclesPerDay": {
      "value": 10000
    },
    "windFromDegrees": {
      "value": 225
    },
    "windSpeedMs": {
      "value": 0
    },
    "windStretchPerMs": {
      "value": 0.35
    }
  },
  "heat": {
    "shadeWeight": {
      "value": 0.6
    },
    "albedoWeight": {
      "value": 0.2
    },
    "etiWeight": {
      "value": 0.2
    },
    "uhiMaxC": {
      "value": 3.0
    },
    "greenPatchMinHa": {
      "value": 2
    },
    "coolingDistanceTiles": {
      "value": 3
    }
  },
  "access": {
    "greenRadiusTiles": {
      "value": 3
    },
    "greenVarietyBonus": {
      "value": 0.2
    },
    "greenVarietyMinTiles": {
      "value": 3
    },
    "retailRadiusTiles": {
      "value": 7
    },
    "huffLambda": {
      "value": 2.0
    },
    "retailM2PerResident": {
      "value": 1.4
    },
    "retailReferenceSupply": {
      "value": 222
    },
    "jobDecayM": {
      "value": 2000
    },
    "jobReferenceJobs": {
      "value": 400
    }
  },
  "habitat": {
    "halfSaturation": {
      "value": 0.5
    },
    "scalingZ": {
      "value": 2.5
    },
    "speciesAreaZ": {
      "value": 0.3
    },
    "threats": {
      "road": {
        "weight": {
          "value": 1.0
        },
        "maxDistanceM": {
          "value": 300
        }
      },
      "industry": {
        "weight": {
          "value": 0.8
        },
        "maxDistanceM": {
          "value": 500
        }
      },
      "commercial": {
        "weight": {
          "value": 0.6
        },
        "maxDistanceM": {
          "value": 300
        }
      },
      "housing_high": {
        "weight": {
          "value": 0.5
        },
        "maxDistanceM": {
          "value": 200
        }
      },
      "housing_low": {
        "weight": {
          "value": 0.3
        },
        "maxDistanceM": {
          "value": 200
        }
      }
    }
  },
  "commute": {
    "labourParticipation": {
      "value": 0.52
    },
    "modeShareByDistance": {
      "bins": [
        {
          "maxKm": 1,
          "walk": 0.55,
          "bike": 0.2,
          "car": 0.25
        },
        {
          "maxKm": 3,
          "walk": 0.15,
          "bike": 0.35,
          "car": 0.5
        },
        {
          "maxKm": 1000,
          "walk": 0.02,
          "bike": 0.13,
          "car": 0.85
        }
      ]
    },
    "roadSearchRadiusTiles": {
      "value": 3
    },
    "externalCommuteKm": {
      "value": 15
    },
    "externalCarShare": {
      "value": 0.8
    },
    "carKgCo2PerKm": {
      "value": 0.15
    },
    "workingDaysPerMonth": {
      "value": 20
    },
    "referenceCommuteKm": {
      "value": 20
    },
    "transitWalkRadiusTiles": {
      "value": 4
    },
    "transitCarReduction": {
      "value": 0.25
    },
    "cyclePathRadiusTiles": {
      "value": 2
    },
    "cycleCarReduction": {
      "value": 0.15
    },
    "cycleCompetitiveKm": {
      "value": 5.0
    },
    "minCarShareFactor": {
      "value": 0.5
    }
  },
  "economy": {
    "incomeTaxPerResidentYear": {
      "value": 550
    },
    "propertyTaxPerResidentYear": {
      "value": 180
    },
    "businessTaxPerJobYear": {
      "value": 2100
    },
    "startBudgetKEur": {
      "value": 25000
    },
    "demolitionCostKEur": {
      "value": 50
    },
    "immigrationRate": {
      "value": 0.08
    },
    "emigrationRate": {
      "value": 0.03
    },
    "unconnectedAttractivenessFactor": {
      "value": 0.7
    },
    "attractivenessWeights": {
      "noise": 0.25,
      "air": 0.2,
      "green": 0.15,
      "retail": 0.15,
      "jobs": 0.15,
      "heat": 0.1
    }
  },
  "seasons": {
    "amplitude": {
      "value": 1.0
    },
    "growth": {
      "monthly": [
        0.278,
        0.333,
        0.667,
        1.111,
        1.5,
        1.722,
        1.778,
        1.667,
        1.333,
        0.889,
        0.444,
        0.278
      ]
    },
    "heat": {
      "monthly": [
        0.275,
        0.33,
        0.606,
        0.991,
        1.431,
        1.761,
        1.927,
        1.872,
        1.321,
        0.771,
        0.44,
        0.275
      ]
    }
  },
  "climate": {
    "zeroScoreTonsPerPerson": {
      "value": 5.0
    }
  },
  "water": {
    "designStormMm": {
      "value": 22.1
    },
    "imperviousCurveNumber": {
      "value": 98
    },
    "initialAbstractionRatio": {
      "value": 0.2
    },
    "retentionRadiusTiles": {
      "value": 2
    },
    "retentionMmPerCell": {
      "value": 30
    },
    "floodRiskMm": {
      "value": 10
    }
  }
}''';
