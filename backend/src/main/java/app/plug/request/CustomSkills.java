package app.plug.request;

import app.plug.foundation.ApiException;
import java.text.Normalizer;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import org.springframework.jdbc.core.JdbcTemplate;

/// Provider-described skills (owner decision 2026-10-02, ADR-011). A provider may keep a skill
/// the vocabulary does not list. It is stored as its own label plus the meaningful keywords in
/// it; an ask that names no listed skill is matched to providers whose keywords it shares.
/// Listed skills always win, a label that names a listed skill must use that skill (so a
/// licensed skill cannot be re-entered as a custom one), and the restricted-intent policy
/// guards every label exactly as it guards asks.
public class CustomSkills {
    static final int MAX_PER_PROVIDER = 5;
    private static final Set<String> IGNORED = Set.copyOf(List.of(
            // Function words.
            "a", "an", "and", "the", "or", "of", "for", "to", "in", "on", "at", "by", "with", "my", "your", "our",
            "their", "his", "her", "its", "me", "you", "i", "im", "we", "they", "it", "is", "are", "be", "do", "does",
            "can", "could", "will", "would", "please", "also", "just", "some", "any", "all", "this", "that", "who",
            "what", "where", "when", "how", "from", "up", "out", "off", "into", "about", "near", "nearby", "local",
            // Words that describe asking or offering, not the skill itself.
            "need", "needs", "want", "wants", "looking", "find", "get", "someone", "somebody", "anyone", "anybody",
            "person", "people", "help", "helper", "service", "services", "offer", "offering", "provide", "providing",
            "professional", "pro", "expert", "specialist", "available", "today", "tomorrow", "tonight", "now",
            "asap", "soon", "cheap", "affordable", "best", "good", "quick", "fast", "under", "budget", "price",
            "cost", "dollar", "dollars", "minute", "minutes", "hour", "hours", "day", "week", "job", "work", "done",
            "make", "making", "do", "doing", "can", "lesson", "lessons", "class", "classes", "session", "sessions",
            "repair", "repairs", "repairing", "fix", "fixing", "fixed", "install", "installation", "installing",
            "custom", "new", "old", "small", "big", "home", "house", "mobile", "come", "comes"));

    public record Match(String tag, String label) {}

    private final JdbcTemplate jdbc;

    public CustomSkills(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    /// Lower-case, singular, meaningful words: "Crochet Locs install" -> [crochet, loc].
    static List<String> keywords(String text) {
        String normal = Normalizer.normalize(text, Normalizer.Form.NFKC).toLowerCase(Locale.ROOT).replace('’', '\'');
        Set<String> words = new LinkedHashSet<>();
        for (String raw : normal.split("[^\\p{L}\\p{N}']+")) {
            String word = raw.replaceAll("^'+|'+$", "").replaceAll("'s$", "");
            if (word.length() < 3 || IGNORED.contains(word) || word.chars().allMatch(Character::isDigit)) continue;
            String stem = stem(word);
            if (!IGNORED.contains(stem)) words.add(stem);
        }
        return List.copyOf(words);
    }

    private static String stem(String word) {
        // "sweeping" and "sweep" are the same skill; short words like "wing" are left alone.
        if (word.length() > 6 && word.endsWith("ing")) word = word.substring(0, word.length() - 3);
        if (word.length() > 4 && word.endsWith("ies")) return word.substring(0, word.length() - 3) + "y";
        if (word.length() > 4 && word.matches(".*(ss|sh|ch|x|z)es")) return word.substring(0, word.length() - 2);
        if (word.length() > 3 && word.endsWith("s") && !word.endsWith("ss") && !word.endsWith("us")) {
            return word.substring(0, word.length() - 1);
        }
        return word;
    }

    /// A stable tag for a label: "Crochet locs" -> custom_crochet_loc.
    static String tag(List<String> keywords) {
        String slug = String.join("_", keywords).replaceAll("[^a-z0-9_]", "");
        if (slug.length() > 33) slug = slug.substring(0, 33).replaceAll("_+$", "");
        return "custom_" + slug;
    }

    /// Validates and normalises the labels a provider keeps. Throws on anything unusable.
    /// The restricted-intent policy has already refused anything unsafe (with its audit event).
    List<Prepared> prepare(List<String> labels, SkillVocabulary vocabulary) {
        if (labels == null) return List.of();
        if (labels.size() > MAX_PER_PROVIDER) {
            throw ApiException.validation("custom_skills", "too_many", "Keep up to five of your own skills.");
        }
        List<Prepared> prepared = new ArrayList<>();
        Set<String> tags = new LinkedHashSet<>();
        for (String raw : labels) {
            String label = raw == null ? "" : raw.strip().replaceAll("\\s+", " ");
            if (label.length() < 3 || label.length() > 40 || !label.matches("[\\p{L}\\p{N} &'./+-]+")) {
                throw ApiException.validation("custom_skills", "invalid", "Describe each skill in 3 to 40 letters or numbers.");
            }
            if (!vocabulary.findIn(label).isEmpty()) {
                throw ApiException.validation("custom_skills", "listed_skill", "That skill is on PLUG's list. Choose it instead.");
            }
            List<String> keywords = keywords(label);
            if (keywords.isEmpty() || keywords.size() > 8) {
                throw ApiException.validation("custom_skills", "too_vague", "Name the skill itself, for example \"crochet locs\".");
            }
            String tag = tag(keywords);
            if (tags.add(tag)) prepared.add(new Prepared(tag, Character.toUpperCase(label.charAt(0)) + label.substring(1), keywords));
        }
        return prepared;
    }

    record Prepared(String tag, String label, List<String> keywords) {}

    /// Stores a provider's own skills, registering each tag so requests can reference it.
    void replace(String userId, List<Prepared> skills) {
        jdbc.update("DELETE FROM provider_custom_skills WHERE user_id=?", userId);
        int position = 0;
        for (Prepared skill : skills) {
            jdbc.update("INSERT INTO skill_vocabulary(tag,display,parent,requires_licence) VALUES(?,?,'custom',FALSE)"
                    + " ON CONFLICT (tag) DO NOTHING", skill.tag(), skill.label());
            jdbc.update("INSERT INTO provider_custom_skills(user_id,tag,label,keywords,position) VALUES(?,?,?,?,?)",
                    userId, skill.tag(), skill.label(), skill.keywords().toArray(String[]::new), position++);
        }
    }

    List<String> labels(String userId) {
        return jdbc.queryForList("SELECT label FROM provider_custom_skills WHERE user_id=? ORDER BY position", String.class, userId);
    }

    /// The provider-described skill an ask names, if any accepting provider offers one. A skill
    /// of one keyword needs that word; a longer one needs at least two of its words, so "watch"
    /// alone never matches "watch strap repair".
    public Optional<Match> bestFor(String text, String requesterId) {
        List<String> words = keywords(text);
        if (words.isEmpty()) return Optional.empty();
        List<Match> found = jdbc.query("""
                SELECT c.tag, min(c.label) AS label
                  FROM provider_custom_skills c JOIN provider_profiles p ON p.user_id = c.user_id
                 WHERE p.accepting AND c.user_id <> ?
                   AND cardinality(ARRAY(SELECT unnest(c.keywords) INTERSECT SELECT unnest(?::text[])))
                       >= LEAST(2, cardinality(c.keywords))
                 GROUP BY c.tag
                 ORDER BY max(cardinality(ARRAY(SELECT unnest(c.keywords) INTERSECT SELECT unnest(?::text[])))) DESC,
                          count(*) DESC, c.tag
                 LIMIT 1
                """, (rs, row) -> new Match(rs.getString("tag"), rs.getString("label")),
                requesterId, words.toArray(String[]::new), words.toArray(String[]::new));
        return found.stream().findFirst();
    }
}
