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

### Asks in the person's own words — 2026-10-05 (contract 0.6.0)

Owner decision: "any name of skills or anything the user typed should be used in matching
keywords and displayed to them". A clear service ask that names no listed skill and matches no
provider's own words is no longer turned into a category question. It becomes a request
labelled in the asker's words: Claude's `service_label` when a key is configured (validated:
3–40 characters, letters, digits and simple punctuation, at least one specific word), otherwise
the meaningful words of the ask after a service cue such as "someone to", "need" or "fix"
("Someone to regrout my bathroom tiles under $80" -> "Regrout bathroom tiles"). The label is
registered as a `custom_` tag and matching reaches every provider whose own words share its
keywords, under the usual rules. Listed skills still win; place questions, refusals and vague
asks ("Something", "I need help with something") are unchanged, and Claude answering
"unclear" still asks the one question. Claude still never creates a listed tag.

### Own-words requests need a model's reading — 2026-10-07 (contract 0.6.1)

Person Two's rerun of the labelled ask dataset on 0.6.0 (`docs/testing/phase2-person-two-rerun-2026-10-06.md`
§2.1) found that, with the rules alone, reworded harmful asks ("Pay someone to beat up my
roommate", painkillers "no doctor involved", a hidden camera in a roommate's room, watching
someone's kids) became requests in the asker's words, and that described problems ("my
kitchen sink is leaking") missed the listed skill and its licence rule. Fixed in four layers:

1. **Policy.** `RestrictedIntentPolicy` refuses the same intents in other words: violence
   against a person, prescription drugs without a prescription, forged documents described
   rather than named, tailing, following or checking where a particular person is, doing
   something "without her knowing", hidden cameras, diagnosis of a body complaint, watching or
   minding children, therapy and mental-health counselling. Ordinary asks that share words
   ("shoot my daughter's graduation", "diagnose my car", "psychology tutor", "passport photo")
   are tested to stay accepted.
2. **Model.** Claude's schema gains `restricted`; an ask it flags is refused like a rule
   refusal (422, nothing created, audit `restricted_intent:model_flagged`). The rules still run
   first and do not depend on it.
3. **Own words only with a model.** A request in the asker's words is created only from the
   model's `service_label`, after the policy checks the label too. With the rules alone the
   person gets the one question, as before 0.6.0.
4. **Listed skills win.** A label that names a listed skill becomes that skill, so its licence
   rule applies. Synonyms from Person Two's review were added to `skills.yaml`, and the matcher
   now reads "clean my mom's house" and "mount a 55 inch TV".

The dataset is now a backend test (`AsksDatasetTest`, 91/91 with the rules) and the
model paths are tested against a scripted model (`OwnWordsWithModelTest`).
