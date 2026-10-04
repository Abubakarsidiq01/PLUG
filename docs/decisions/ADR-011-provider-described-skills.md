# ADR-011: A larger skill list, and skills in a provider's own words

- Status: Accepted by the project owner on 2026-10-02 ("add as many skills as possible…
  people should be able to create a skill even if PLUG doesn't have it, then when the skill
  is asked by a customer, use keywords to identify them"). Implemented behind `requests_v2`;
  the contract change is proposed with 0.5.0 and needs Person Two's approval like any other.
- Amends: manual v4 §12B.3 and §19A.2 ("the model never creates a tag; unmatched terms are
  never matched on") and ADR-010 point 2. Recorded in the manual's §27.3 Phase 2 amendments.

## Decision

1. **The vocabulary grows from 35 to 115 tags** (`contracts/skills.yaml`, migration V8), across
   hair and beauty, repairs and tech, home trades, vehicles, events and food, creative and
   digital work, lessons, pets and errands. Regulated trades carry `requires_licence`
   (HVAC, licensed plumbing, roofing, pest control, tattoo, piercing, facials, driving
   lessons, in addition to electrical, locksmith and massage). Childcare, elder care and
   medical, legal and financial advice stay absent until a safety policy exists for them.
2. **A provider may keep up to five skills in their own words** (`custom_skills` on provider
   setup). Each label is stored with its meaningful keywords (lower-case, singular, with
   function words and words like "help", "service" or "repair" removed).
3. **Asks find them by keywords.** Only an ask that names no listed skill and is not a place
   question is checked. A one-word skill needs that word; a longer one needs at least two of
   its words, so a single shared word ("chimney") does not trigger a match. The request is
   created with `category` `custom_<keywords>` and `service_name` set to the provider's label,
   and matching reaches every nearby, available provider whose own words share those
   keywords, under the same radius, availability, ranking and cap rules. Nobody is matched to
   their own skill.

## Guardrails

- Listed skills always win. Following the owner’s 2026-10-03 request for direct entry,
  labels naming listed skills resolve to their canonical tags when saved. Licensed skills
  still require a licence; entering the name directly cannot avoid that check.
- The app accepts a skill directly without first calling the suggestion service.
- The restricted-intent policy checks every label exactly as it checks asks: 422
  `restricted_intent` with an audit event. A label with no specific word is `too_vague`.
- A test keeps every listed skill clear of the policy, so the larger list cannot be refused
  by its own safety rules.
- Labels are shown as the provider wrote them and are not verified. Unmatched terms still
  feed `vocabulary_gaps`, so popular own-words skills can be promoted into the list by the
  normal pull request and migration.

## Consequences

- `ProviderSetup.skill_tags` may be empty when `custom_skills` is not; `ProviderProfile`
  returns `custom_skills`; `Category` may be a `custom_` tag on a request. Clients display
  `service_name` and never parse tags.
- Custom tags are registered in `skill_vocabulary` under parent `custom` so requests keep
  their foreign key; the startup check compares `skills.yaml` with the non-custom rows only.
- Keyword matching is deliberately simple and conservative. With a Claude key configured,
  Claude still maps free text onto listed skills first; it never creates a custom one.

### Identifier hardening — 2026-10-04

Short ASCII keyword tags keep their existing representation. If sanitising would remove
letters or truncate the tag, append a stable digest of the complete keywords within the
existing 40-character category limit. This prevents unrelated long or non-Latin labels
from sharing the same tag. Existing stored tags are not rewritten; re-saving a profile
uses the hardened identifier. Matching still uses the provider's keywords and clients
still display the label, never the identifier. No endpoint or response shape changes.
