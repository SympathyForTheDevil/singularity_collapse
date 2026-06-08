import 'dart:ui';

/// The cosmic mass ladder the puzzle climbs. The worldline must consume these
/// in order; the Black Hole is always the final milestone (and the final cell).
class CosmicTier {
  final String name;
  final Color  color;
  final bool   isBlackHole;
  const CosmicTier(this.name, this.color, {this.isBlackHole = false});
}

const List<CosmicTier> kLowerTiers = [
  CosmicTier('Particle',     Color(0xff88ccff)),
  CosmicTier('Asteroid',     Color(0xffb08858)),
  CosmicTier('Moon',         Color(0xffcccccc)),
  CosmicTier('Planet',       Color(0xff44aaff)),
  CosmicTier('Star',         Color(0xffffcc33)),
  CosmicTier('Neutron Star', Color(0xff99eeff)),
];

const CosmicTier kBlackHole = CosmicTier('Black Hole', Color(0xffbb55ff), isBlackHole: true);

/// Map a milestone number (1..count) to its cosmic tier. The top milestone is
/// always the Black Hole; the rest are the lower tiers in ascending order.
CosmicTier tierFor(int milestone, int count) {
  if (milestone >= count) return kBlackHole;
  final i = (milestone - 1).clamp(0, kLowerTiers.length - 1);
  return kLowerTiers[i];
}
