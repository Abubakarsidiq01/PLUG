package app.plug.request;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;
import java.io.IOException;
import java.io.InputStream;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/// The controlled skill vocabulary (manual v4 §12B.3, §19A.2), loaded from the
/// contracts/skills.yaml shipped inside the application. The model maps free text onto
/// these tags; it never creates one. Anything unresolved is dropped, and the caller then
/// asks rather than matching on nothing.
public final class SkillVocabulary {
    public record Skill(String tag, String display, String parent, boolean requiresLicence) {}

    private final Map<String, Skill> byTag = new LinkedHashMap<>();
    private final Map<String, String> bySynonym = new TreeMap<>();
    /** Longest phrases first, so "laptop repair" wins over "repair". */
    private final List<Map.Entry<Pattern, String>> phrases = new ArrayList<>();

    public static SkillVocabulary load() {
        try (InputStream in = SkillVocabulary.class.getResourceAsStream("/contracts/skills.yaml")) {
            if (in == null) throw new IllegalStateException("contracts/skills.yaml is missing from the application");
            return new SkillVocabulary(new ObjectMapper(new YAMLFactory()).readTree(in));
        } catch (IOException failure) {
            throw new IllegalStateException("contracts/skills.yaml could not be read", failure);
        }
    }

    SkillVocabulary(JsonNode entries) {
        List<String> all = new ArrayList<>();
        for (JsonNode entry : entries) {
            String tag = entry.path("tag").asText();
            if (!tag.matches("[a-z][a-z0-9_]{1,39}")) throw new IllegalStateException("Invalid skill tag " + tag);
            Skill skill = new Skill(tag, entry.path("display").asText(), entry.path("parent").asText(),
                    entry.path("requires_licence").asBoolean(false));
            if (byTag.put(tag, skill) != null) throw new IllegalStateException("Duplicate skill tag " + tag);
            bySynonym.put(normalize(tag.replace('_', ' ')), tag);
            bySynonym.put(normalize(skill.display()), tag);
            for (JsonNode synonym : entry.path("synonyms")) bySynonym.put(normalize(synonym.asText()), tag);
        }
        bySynonym.keySet().stream().sorted(Comparator.comparingInt(String::length).reversed()).forEach(all::add);
        for (String phrase : all) {
            // A plain plural ("wig installs", "box braids") still names the same skill.
            phrases.add(Map.entry(Pattern.compile("(?<![\\p{L}\\p{N}])" + Pattern.quote(phrase) + "(?:e?s)?(?![\\p{L}\\p{N}])"),
                    bySynonym.get(phrase)));
        }
        // People also put the action first: "phone repair" is said "I repair phones" or "fix my
        // phone". Derived only from listed two-word synonyms, so no new skill can appear.
        for (String phrase : all) {
            String[] words = phrase.split(" ");
            String verbs = words.length == 2 ? ACTIONS.get(words[1]) : null;
            if (verbs == null) continue;
            phrases.add(Map.entry(Pattern.compile("(?<![\\p{L}\\p{N}])(?:" + verbs + ")\\s+" + DETERMINER
                    + Pattern.quote(words[0]) + "(?:e?s)?(?![\\p{L}\\p{N}])"), bySynonym.get(phrase)));
        }
    }

    /// The action word of a listed synonym, and the ways people say it before the thing.
    private static final Map<String, String> ACTIONS = Map.ofEntries(
            Map.entry("repair", "repair|repairs|repairing|fix|fixes|fixing|mend|mends|mending"),
            Map.entry("cleaning", "clean|cleans|cleaning"),
            Map.entry("walking", "walk|walks|walking"),
            Map.entry("mounting", "mount|mounts|mounting"),
            Map.entry("assembly", "assemble|assembles|assembling|build|builds|building"),
            Map.entry("grooming", "groom|grooms|grooming"),
            Map.entry("sitting", "sit|sits|sitting|watch|watches|watching"),
            Map.entry("wash", "wash|washes|washing"),
            Map.entry("painting", "paint|paints|painting"),
            Map.entry("replacement", "replace|replaces|replacing"),
            Map.entry("lessons", "teach|teaches|teaching"),
            Map.entry("install", "install|installs|installing"));
    // "my", or "my mom's", and a size where things have one: "clean my mom's house", "mount a
    // 55 inch TV". Nothing here can name a skill, so it never changes which skill matches.
    private static final String DETERMINER = "(?:(?:my|a|an|the|your|their|his|her|our|people's|peoples|someone's|customers')\\s+)?"
            + "(?:[\\p{L}]+'s\\s+)?(?:\\d{1,3}(?:\\s*-?\\s*(?:inch|in|\")|\")\\s+)?";

    public Skill get(String tag) { return byTag.get(tag); }
    public boolean contains(String tag) { return tag != null && byTag.containsKey(tag); }
    public List<Skill> all() { return List.copyOf(byTag.values()); }

    /// Model or client terms onto tags. Unknown terms are dropped, never stored.
    public List<Skill> resolve(List<String> rawTerms) {
        if (rawTerms == null) return List.of();
        return rawTerms.stream().filter(Objects::nonNull).map(SkillVocabulary::normalize)
                .map(term -> byTag.containsKey(term.replace(' ', '_')) ? term.replace(' ', '_') : bySynonym.get(term))
                .filter(Objects::nonNull).distinct().map(byTag::get).toList();
    }

    /// Whole-phrase matches in the person's words, in the order they appear.
    public List<Skill> findIn(String text) {
        String normal = normalize(text);
        Map<String, Integer> firstSeen = new LinkedHashMap<>();
        boolean[] taken = new boolean[normal.length()];
        for (var phrase : phrases) {
            Matcher matcher = phrase.getKey().matcher(normal);
            while (matcher.find()) {
                boolean overlaps = false;
                for (int i = matcher.start(); i < matcher.end(); i++) overlaps |= taken[i];
                if (overlaps) continue;
                for (int i = matcher.start(); i < matcher.end(); i++) taken[i] = true;
                firstSeen.merge(phrase.getValue(), matcher.start(), Math::min);
            }
        }
        return firstSeen.entrySet().stream().sorted(Map.Entry.comparingByValue())
                .map(entry -> byTag.get(entry.getKey())).toList();
    }

    /// Plain-words terms that matched no tag, for the provider to see and the backlog.
    public List<String> unmatchedTerms(String text) {
        List<String> terms = new ArrayList<>();
        String rest = normalize(text);
        for (var phrase : phrases) rest = phrase.getKey().matcher(rest).replaceAll(" ");
        for (String part : rest.split("[,;/]| and | or |\\.")) {
            String term = part.replaceAll("\\b(i|i'm|im|do|can|offer|and|a|an|the|my|also|some|of|in|for|with)\\b", " ")
                    .replaceAll("[^\\p{L}\\p{N} '-]", " ").replaceAll("\\s+", " ").trim();
            if (term.length() >= 3 && term.length() <= 60 && terms.size() < 10) terms.add(term);
        }
        return terms;
    }

    static String normalize(String text) {
        return Normalizer.normalize(text, Normalizer.Form.NFKC).toLowerCase(Locale.ROOT).replace('’', '\'').trim();
    }
}
