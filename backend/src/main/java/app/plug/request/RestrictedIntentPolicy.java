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

    static final List<Rule> RULES = List.of(
            rule("illegal_goods", "cocaine|crack cocaine|heroin|meth|methamphetamine|fentanyl|mdma|ecstasy|lsd|"
                    + "ketamine|xanax without|oxy(?:codone|contin)? without|stolen\\w*|counterfeit\\w*|fake ids?|"
                    + "forged \\w+|credit card numbers|ssn|social security numbers?|buy (?:a |some )?(?:weed|drugs)|"
                    + "sell (?:me )?(?:weed|drugs)"),
            rule("weapons", "guns?|firearms?|handguns?|rifles?|ammo|ammunition|silencers?|suppressors?|"
                    + "explosives?|bombs?|grenades?|ghost guns?|3d printed guns?"),
            rule("violence", "kill (?:him|her|them|someone|somebody|a person|people|my \\w+)|murder|assassinat\\w*|hitman|hit man|hurt (?:him|her|them|someone|somebody)|"
                    + "beat (?:him|her|them|someone|somebody) up|rough (?:him|her|them|someone) up|kidnap\\w*|poison (?:him|her|them|someone|somebody|my \\w+)"),
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
                    + "phone number of (?:my ex|him|her|someone|somebody|a person)"),
            rule("unsupported_regulated", "babysit\\w*|nanny|nannies|child ?care|daycare|look after (?:my )?(?:kids?|child|baby)|"
                    + "elder ?care|caregiver|carer for|diagnose (?:me|my|him|her)|medical diagnosis|prescribe|"
                    + "prescription without|medical advice|legal advice|"
                    + "lawyer|attorney|financial advice|tax advice|invest my money"));

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
