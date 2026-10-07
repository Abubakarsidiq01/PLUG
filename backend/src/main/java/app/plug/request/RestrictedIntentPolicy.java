package app.plug.request;

import java.text.Normalizer;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.regex.Pattern;

/// The restricted-intent policy (manual v4 §2.2, §25.6, P2.S14). With the category
/// allow-list gone this is the only thing that blocks an ask, so it is stricter than the v3
/// word list and it runs first: a refused ask never reaches the model, a provider or a place
/// responder, and creates nothing beyond its audit event. The rule id goes to the audit log
/// only; the person sees one safe message that names no rule.
public final class RestrictedIntentPolicy {
    public record Rule(String id, Pattern pattern) {}

    private static Rule rule(String id, String regex) {
        return new Rule(id, Pattern.compile("(?<![\\p{L}\\p{N}])(" + regex + ")(?![\\p{L}\\p{N}])"));
    }

    // Ordinary things whose names contain a weapon word. Removed before the weapons rule runs.
    private static final Pattern TOOLS = Pattern.compile(
            "\\b((nail|glue|heat|staple|caulk|caulking|spray|paint|grease|massage|tattoo) guns?|bath bombs?)\\b");

    // People an ask may be about. Used where a verb alone is ordinary ("beat the traffic",
    // "watch the game") and only an object that is a person makes it harmful.
    private static final String PERSON = "(?:him|her|them|someone|somebody|a person|people|"
            + "(?:my|his|her|their|our|that|this) (?:ex|roommate|room mate|boyfriend|girlfriend|husband|wife|partner|"
            + "neighbou?r|coworker|co-worker|boss|friend|brother|sister|cousin|landlord|teacher|classmate|"
            + "dad|mom|mother|father|son|daughter|kid|child|guy|girl|man|woman)s?)";

    static final List<Rule> RULES = List.of(
            rule("illegal_goods", "cocaine|crack cocaine|heroin|meth|methamphetamine|fentanyl|mdma|ecstasy|lsd|"
                    + "ketamine|xanax without|oxy(?:codone|contin)? without|stolen\\w*|counterfeit\\w*|fake ids?|"
                    + "forged \\w+|credit card numbers|ssn|social security numbers?|buy (?:a |some )?(?:weed|drugs)|"
                    + "sell (?:me )?(?:weed|drugs)|"
                    // Prescription drugs, however they are named, without the prescription.
                    + "(?:pain ?killers?|opioids?|opiates?|percocets?|vicodin|adderall|oxy\\w*|xanax|codeine|"
                    + "pills?|meds|medication)\\b[^.?!]{0,40}(?:no doctor|without (?:a |any )?(?:doctor|prescription|script)|"
                    + "no prescription|no script)|"
                    // Forged documents, described rather than named.
                    + "(?:driver'?s )?licen[cs]e that says|fake (?:driver'?s )?(?:licen[cs]e|passport|diploma|degree|id card)|"
                    + "(?:make|forge) (?:me )?(?:a |an )?(?:driver'?s licen[cs]e|passport|id|id card|diploma)(?! photo)"),
            rule("weapons", "guns?|firearms?|handguns?|rifles?|ammo|ammunition|silencers?|suppressors?|"
                    + "explosives?|bombs?|grenades?|ghost guns?|3d printed guns?"),
            rule("violence", "kill (?:him|her|them|someone|somebody|a person|people|my \\w+)|murder|assassinat\\w*|hitman|hit man|hurt (?:him|her|them|someone|somebody)|"
                    + "beat (?:him|her|them|someone|somebody) up|rough (?:him|her|them|someone) up|kidnap\\w*|poison (?:him|her|them|someone|somebody|my \\w+)|"
                    + "beat (?:up )?" + PERSON + "(?: up)?|(?:hurt|attack|assault|stab|threaten) " + PERSON),
            rule("sexual_services", "escorts?|escort service|prostitut\\w*|sex work\\w*|happy ending|"
                    + "sugar (?:daddy|baby)|nudes|onlyfans account"),
            rule("fraud_cyber", "hack\\w*|phishing|ddos|crack (?:a |the |my |his |her )?password|"
                    + "into (?:his|her|their|someone'?s) (?:account|phone|email|instagram|snapchat)|launder\\w*|"
                    + "scam\\w*|identity theft|fake reviews?|bypass (?:the )?(?:verification|2fa|security)"),
            rule("stalking_tracking", "(?:is anyone|is somebody|is someone|who is|who's|anyone) (?:at|in|inside) "
                    + "(?:his|her|their|my ex'?s?|someone'?s|somebody'?s) (?:house|home|apartment|flat|place|room|dorm)|"
                    + "track (?:my |his |her |their )?(?:ex|wife|husband|girlfriend|boyfriend|partner|"
                    + "daughter|son|kids?)\\w*|track (?:him|her|them|someone|somebody|a person|people)|"
                    + "follow (?:him|her|them|my ex|someone|somebody)|find (?:out )?where (?:\\w+ ){0,3}lives?|"
                    + "where does (?:\\w+ ){0,3}live|home address|address of (?:my ex|him|her|them|someone|somebody|a person)|"
                    + "locate (?:my ex|him|her|them|someone|somebody|a person)|spy on|keep tabs on|"
                    + "(?:watch|monitor|check on) (?:my |his |her )?(?:ex|wife|husband|girlfriend|boyfriend|partner|"
                    + "neighbou?r)\\w*|is (?:he|she|my ex) (?:home|at home|there)|who is (?:he|she) (?:with|seeing)|"
                    + "(?:whose|run a|look up a) (?:license|licence) plate|look up (?:a |this )?person|"
                    + "phone number of (?:my ex|him|her|someone|somebody|a person)|"
                    // Watching where a particular person is, in other words.
                    + "tail " + PERSON + "|follow " + PERSON + "|" + PERSON + "'?s? (?:phone )?number|"
                    + "(?:check|see|find out|tell me) (?:if|whether) " + PERSON + " (?:is|was) (?:at|home|there|with|in)|"
                    + "is (?:my|his|her|their) (?:ex|roommate|boyfriend|girlfriend|husband|wife|partner|neighbou?r|coworker|boss) "
                    + "(?:at|in|still at|home)|"
                    + "is (?:anyone|anybody|someone|somebody) (?:home|in|there|inside) at \\d+|"
                    + "(?:still )?parked (?:outside|in front of|by) (?:the|his|her|their|a) (?:house|home|apartment|place)|"
                    + "without (?:him|her|them|his|her|their) (?:knowing|knowledge|consent|permission)|"
                    + "(?:hidden|secret|spy|covert) cam(?:era)?s?|spy ?cams?"),
            rule("unsupported_regulated", "babysit\\w*|nanny|nannies|child ?care|daycare|look after (?:my )?(?:kids?|child|baby)|"
                    + "elder ?care|caregiver|carer for|diagnose (?:me|him|her)|medical diagnosis|prescribe|"
                    + "prescription without|medical advice|legal advice|"
                    + "lawyer|attorney|financial advice|tax advice|invest my money|"
                    // Childcare and medical care described rather than named.
                    + "diagnos\\w* (?:my|this|a|the|his|her|our) (?:\\w+ )?(?:rash|pain|symptoms?|illness|sickness|condition|skin|mole|"
                    + "injury|cough|fever|infection|lump|bite|allergy|allergies)|(?:watch|mind|look after|care for|sit with) (?:my |our |his |her |the )?(?:\\w+ )?"
                    + "(?:kids?|children|child|baby|babies|toddlers?|infants?)|(?<!massage )therap(?:ist|y|ists)|"
                    + "(?:mental health|grief|marriage|couples?) counsell?(?:or|ing)|psychiatrists?|psychiatric|psychologists?"));

    /// A place question must be about a public place (manual v4 §2.2, §19A.1). Checked only
    /// once an ask is classified as a place question: "clean her house" is an ordinary job,
    /// "is anyone at her house" is surveillance.
    static final Rule PRIVATE_PLACE = rule("private_place", "(?:his|her|their|my ex'?s?|someone'?s|somebody'?s) "
                    + "(?:house|home|apartment|flat|room|dorm)|private residence|inside (?:his|her|their|someone'?s) \\w+|"
                    + "(?:hidden|secret) cameras?|record (?:him|her|them|someone)");

    public Optional<String> placeRefusal(String text) {
        return PRIVATE_PLACE.pattern().matcher(normalize(text)).find() ? Optional.of(PRIVATE_PLACE.id()) : Optional.empty();
    }

    /// The rule that refuses this ask, or empty when nothing does.
    public Optional<String> refusal(String text) {
        String normal = normalize(text);
        String withoutTools = TOOLS.matcher(normal).replaceAll(" ");
        for (Rule rule : RULES) {
            String subject = rule.id().equals("weapons") ? withoutTools : normal;
            if (rule.pattern().matcher(subject).find()) return Optional.of(rule.id());
        }
        return Optional.empty();
    }

    private static String normalize(String text) {
        return Normalizer.normalize(text, Normalizer.Form.NFKC).toLowerCase(Locale.ROOT).replace('’', '\'');
    }
}
