// SPDX-License-Identifier: AGPL-3.0-or-later

/// The fields whose value at a cell can be traced back to individual source
/// cells (`Simulation.sources`). Traffic and attractiveness are not here:
/// traffic is routed through the road network and attractiveness is a mix
/// of the others, so neither splits into a sum over source cells.
enum SourceField { noise, air, heat, green, retail, jobs, habitat }
