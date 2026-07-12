# ai_profile.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI personality model (Phase MC12, request 13).
#
# `AiProfile` is the PURE, IN-MEMORY schema for an AI commander's fixed
# personality. It is the "who this general IS" layer of the four-layer design
# from the plan (see docs/plan_android_fix_v3.md section 1.c):
#
#   1. Personality  (FIXED)      <- THIS FILE. Never reset by a match.
#   2. Relationship (per-match)  -> modules/diplomacy/relationship_util.gd (MC10)
#   3. Diplomacy actions         -> modules/diplomacy/* (MC10)
#   4. Reputation/Memory (cross- -> tools/ai_reputation_store.gd (MC13.3)
#      match, separate from #1)
#
# The profile is a normalised vector of 35 knobs across five categories:
#
#   * metadata      : id, display-name key, role key, archetype tag (cosmetic).
#   * personality   x10 : temperament traits (aggression, caution, ...).
#   * strategy_bias x10 : how it spends effort (economy, tech, expansion, ...).
#   * diplomacy_bias x7 : how it behaves toward others (trust, vengeance, ...).
#   * learning_bias  x5 : how fast/strongly it adapts within & across matches.
#   * difficulty     x3 : analysis quality, reaction speed, unforced-error rate.
#
# Every numeric knob is a normalised FLOAT in the closed range [0.0, 1.0]. A
# blank/missing knob defaults to 0.5 (neutral). `load()` accepts a partial dict
# and fills the rest; `validate()` reports why a dict is unusable; `clamp()`
# forces every value back into range; `normalise()` produces a fully-populated,
# clamped, deterministically-ordered dictionary.
#
# Design rules (consistent with GuiProject / ModProject):
#   - PURE MODEL: no WorldState, no SceneTree, no RNG. Behaviour derived from a
#     profile elsewhere (strategic_ai_module, ai_diplomacy_brain) stays
#     deterministic because the profile is a fixed input.
#   - SAFE + VALIDATING: unknown keys are dropped, out-of-range values clamped,
#     a missing id is the only hard error.
#   - DETERMINISTIC: to_dict() serialises keys in a stable sorted order so the
#     same profile always produces byte-identical JSON.
#   - English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiProfile
extends RefCounted

# The file extension a standalone AI profile is exported under (MC14).
const PROFILE_EXTENSION: String = "nexai"

# The neutral default every unspecified numeric knob falls back to.
const NEUTRAL: float = 0.5

# The 10 personality traits (temperament: "how it feels / reacts").
const PERSONALITY_KEYS: Array = [
	"aggression",     # bias toward offense over defense
	"caution",        # weigh risk / avoid overextension
	"ambition",       # desire to grow / dominate the map
	"patience",       # willingness to wait and mass before committing
	"boldness",       # take low-odds gambles when they pay off big
	"loyalty",        # honour commitments / stay with allies
	"pride",          # resist being pushed around / demand respect
	"greed",          # prioritise resources / territory grabs
	"adaptability",   # change plan when the situation changes
	"discipline",     # stick to a coherent plan, avoid flailing
]

# The 10 strategy biases (macro effort allocation: "where it spends attention").
const STRATEGY_KEYS: Array = [
	"economy",        # invest in resource income
	"military",       # invest in army size
	"technology",     # invest in research / upgrades
	"expansion",      # claim more territory / outposts
	"defense",        # fortify / hold ground
	"offense",        # press attacks
	"tempo",          # act fast / early vs slow / late
	"scouting",       # spend on vision / recon
	"harassment",     # raid / disrupt vs pitched battle
	"focus_fire",     # concentrate force vs spread out
]

# The 7 diplomacy biases ("how it treats other players").
const DIPLOMACY_KEYS: Array = [
	"trust",          # inclination to believe / accept offers
	"vengeance",      # punish betrayers / hold grudges
	"generosity",     # give resources / aid to allies
	"deceit",         # willingness to lie / betray for gain
	"sociability",    # seek treaties / alliances at all
	"forgiveness",    # let old wrongs fade over time
	"opportunism",    # switch sides when it profits
]

# The 5 learning biases ("how it adapts").
const LEARNING_KEYS: Array = [
	"in_match_rate",  # how fast it reinforces within one match (level 1)
	"memory_weight",  # how much cross-match reputation matters (level 2)
	"exploration",    # try new tactics vs repeat the known-good one
	"grudge_decay",   # how quickly remembered wrongs fade
	"imitation",      # copy tactics that beat it
]

# The 3 difficulty knobs ("skill ceiling"). Note discipline of the plan section
# 1.d: difficulty is QUALITY OF ANALYSIS, not error removal -- even at 1.0 the
# unforced-error floor is > 0 (enforced by the consumer in MC13.4).
const DIFFICULTY_KEYS: Array = [
	"analysis_quality",   # depth / accuracy of evaluation
	"reaction_speed",     # how quickly it responds to events
	"execution",          # inverse of the unforced-error tendency (1 = fewest)
]

# All numeric categories in a stable order, so callers can iterate uniformly.
const CATEGORIES: Array = ["personality", "strategy_bias", "diplomacy_bias", "learning_bias", "difficulty"]


# --- Instance state ---------------------------------------------------------

var _id: String = ""
var _display_name_key: String = ""
var _role_key: String = ""
var _archetype: String = ""
# category -> { knob -> float in [0,1] }
var _vectors: Dictionary = {}


# --- Construction -----------------------------------------------------------

# The ordered key list for a category, or [] for an unknown category.
static func keys_for(category: String) -> Array:
	match category:
		"personality":
			return PERSONALITY_KEYS.duplicate()
		"strategy_bias":
			return STRATEGY_KEYS.duplicate()
		"diplomacy_bias":
			return DIPLOMACY_KEYS.duplicate()
		"learning_bias":
			return LEARNING_KEYS.duplicate()
		"difficulty":
			return DIFFICULTY_KEYS.duplicate()
		_:
			return []


# The total number of numeric knobs across all categories (expected: 35).
static func knob_count() -> int:
	var total: int = 0
	for category in CATEGORIES:
		total += keys_for(category).size()
	return total


# Start a fresh, fully-neutral profile with the given id (every knob = 0.5).
func init_new(id: String) -> void:
	_id = str(id).strip_edges()
	_display_name_key = ""
	_role_key = ""
	_archetype = ""
	_vectors = {}
	for category in CATEGORIES:
		var vec: Dictionary = {}
		for knob in keys_for(category):
			vec[knob] = NEUTRAL
		_vectors[category] = vec
