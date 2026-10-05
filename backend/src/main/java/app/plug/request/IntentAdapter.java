package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.request.RequestPayloads.Constraints;
import app.plug.request.RequestPayloads.Create;
import app.plug.request.RequestPayloads.Location;
import app.plug.request.RequestPayloads.Option;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.text.Normalizer;
import java.time.Clock;
import java.time.DateTimeException;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/// Classifies an ask and extracts its structure (manual v4 §12A, §19A.1, P2.S11/S12).
/// The model only classifies, points at vocabulary tags and reads numbers; it never sets
/// a fact. Precedence: explicit client fields, then unambiguous rule-based parses of money,
/// time and distance, then the model. Skill tags exist only if contracts/skills.yaml has
/// them. Any provider failure falls back to the rules, never a 500.
public class IntentAdapter implements AutoCloseable {
    private final java.util.concurrent.ExecutorService providerPool = new java.util.concurrent.ThreadPoolExecutor(
            0, 2, 30, java.util.concurrent.TimeUnit.SECONDS, new java.util.concurrent.SynchronousQueue<>(),
            task -> { Thread thread = new Thread(task, "intent-provider"); thread.setDaemon(true); return thread; });
    @Override public void close() { providerPool.shutdownNow(); }

    @FunctionalInterface public interface Provider {
        /** The provider's raw JSON, or null when none is configured or it declined. */
        String extract(String text, Instant now, ZoneId zone, Duration deadline) throws Exception;
    }
    /** The model's untrusted output. Every field is validated before use. */
    public record Extracted(String askType, List<String> skillTags, String placeName, Integer budgetCents,
            Instant neededBy, Integer maxDistanceM) {}
    public enum AskType { SERVICE_REQUEST, PLACE_QUESTION, UNCLEAR }
    /** The classification: constraints for a service ask, the place for a place question, or the one question. */
    public record Result(AskType askType, Constraints constraints, String clarificationField,
            List<Option> clarificationOptions, String placeName) {
        public List<Option> clarificationOptionsOrNull() { return clarificationOptions; }
    }

    public static final int MIN_BUDGET = 500;
    public static final int MAX_BUDGET = 500_000;
    static final int DEFAULT_DISTANCE_M = 10_000;
    static final Option PLACE_OPTION = new Option("place_question", "Something happening at a place");
    /** Offered when nothing could be resolved: common asks first. */
    static final List<String> POPULAR = List.of("barber", "braids", "nails", "plumbing_minor", "laptop_repair",
            "house_cleaning", "moving_help", "auto_repair");
    // "How long is the line", "is it busy", "is it open": a question about a place's state.
    private static final Pattern PLACE = Pattern.compile("\\b(how (long|busy|crowded|packed|full) (is|are)|"
            + "how long is the (line|wait|queue)|(line|queue|wait|traffic) (at|in|on)|"
            + "is (it|the|there|\\w+) .{0,40}\\b(busy|crowded|packed|quiet|open|closed|full)\\b|"
            + "(busy|crowded|packed) (right )?now|parking (at|near)|any (seats|tables|parking) (at|in))");
    private static final Pattern PLACE_NAME = Pattern.compile("\\b(?:at|in|on)\\s+(?:the\\s+)?([^?.!,]{2,80})");

    private final ObjectMapper mapper;
    private final Clock clock;
    private final Provider provider;
    private final Duration deadline;
    private final SkillVocabulary vocabulary;
    /// Provider-described skills (ADR-011); null where no database is wired, as in unit tests.
    private CustomSkills customSkills;

    public IntentAdapter(ObjectMapper mapper, Clock clock, Provider provider) {
        this(mapper, clock, provider, Duration.ofSeconds(6), SkillVocabulary.load());
    }
    public IntentAdapter(ObjectMapper mapper, Clock clock, Provider provider, Duration deadline, SkillVocabulary vocabulary) {
        this.mapper = mapper.copy()
                .enable(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_MISSING_CREATOR_PROPERTIES);
        this.clock = clock;
        this.provider = provider;
        this.deadline = deadline;
        this.vocabulary = vocabulary;
    }

    public SkillVocabulary vocabulary() { return vocabulary; }

    public IntentAdapter withCustomSkills(CustomSkills customSkills) {
        this.customSkills = customSkills;
        return this;
    }

    /// POST /v1/requests: a service request by definition. A missing skill is the one question.
    public Result extract(Create input) { return classify(input, true, null); }

    /// As above, also matching skills providers described themselves, never the caller's own.
    public Result extract(Create input, String requesterId) { return classify(input, true, requesterId); }

    /// POST /v1/asks: classify, then extract for the pipeline that will run.
    public Result classify(String text, Location location, String timeZone) {
        return classify(text, location, timeZone, null);
    }

    public Result classify(String text, Location location, String timeZone, String requesterId) {
        return classify(new Create(text, null, null, null, null, null, location, timeZone), false, requesterId);
    }

    private Result classify(Create input, boolean serviceOnly, String requesterId) {
        if (input.text().isBlank() || input.text().codePoints().anyMatch(c -> Character.isISOControl(c) && c != '\n')) {
            throw ApiException.validation("text", "invalid", "Describe what you need using plain text.");
        }
        if (input.currency() != null && !input.currency().equals("USD")) {
            throw ApiException.validation("currency", "unsupported", "Only USD is supported.");
        }
        if (input.budgetCents() != null && input.currency() == null) {
            throw ApiException.validation("currency", "required", "Choose a currency for the budget.");
        }
        if (input.category() != null && !vocabulary.contains(input.category())) {
            throw ApiException.validation("category", "unknown_skill", "Choose a service PLUG lists.");
        }
        ZoneId zone = zone(input.timeZone());
        checkTime(input.neededBy());
        String text = normalize(input.text());
        Extracted model = provided(input.text(), zone);

        boolean placeByRules = PLACE.matcher(text).find();
        List<SkillVocabulary.Skill> ruleSkills = vocabulary.findIn(text);
        List<SkillVocabulary.Skill> modelSkills = model == null ? List.of() : vocabulary.resolve(model.skillTags());
        AskType type;
        if (serviceOnly || input.category() != null) type = AskType.SERVICE_REQUEST;
        else if (model != null && "place_question".equals(model.askType())) type = AskType.PLACE_QUESTION;
        else if (model != null && "service_request".equals(model.askType())) type = AskType.SERVICE_REQUEST;
        else if (placeByRules) type = AskType.PLACE_QUESTION;
        else if (!ruleSkills.isEmpty() || !modelSkills.isEmpty()) type = AskType.SERVICE_REQUEST;
        else type = AskType.UNCLEAR;
        // Listed skills always win. Only an ask that names none, and is not about a place, is
        // checked against skills providers described in their own words.
        CustomSkills.Match custom = null;
        if (type != AskType.PLACE_QUESTION && input.category() == null && ruleSkills.isEmpty() && modelSkills.isEmpty()
                && customSkills != null && requesterId != null) {
            custom = customSkills.bestFor(input.text(), requesterId).orElse(null);
            if (custom != null) type = AskType.SERVICE_REQUEST;
        }

        if (type == AskType.PLACE_QUESTION) {
            String place = model != null && model.placeName() != null ? model.placeName() : placeName(input.text());
            return new Result(type, null, null, null, place);
        }

        List<SkillVocabulary.Skill> skills = input.category() != null ? List.of(vocabulary.get(input.category()))
                : !modelSkills.isEmpty() ? modelSkills : ruleSkills;
        skills = skills.stream().distinct().limit(5).toList();
        // Money, time and distance only matter once a service ask exists.
        Integer budget = input.budgetCents() != null ? input.budgetCents() : budget(text);
        if (budget == null && model != null) budget = model.budgetCents();
        Instant needed = input.neededBy() != null ? input.neededBy() : neededBy(text, zone);
        if (needed == null && model != null) needed = model.neededBy();
        checkTime(needed);
        Integer ruleDistance = input.maxDistanceM() == null ? distance(text) : null;
        int distance = input.maxDistanceM() != null ? input.maxDistanceM() : ruleDistance != null ? ruleDistance
                : model != null && model.maxDistanceM() != null ? model.maxDistanceM() : DEFAULT_DISTANCE_M;

        if (custom != null) {
            return new Result(AskType.SERVICE_REQUEST, new Constraints(custom.tag(), custom.label(), List.of(custom.tag()),
                    false, budget, "USD", needed, distance, input.location().rounded()), null, null, null);
        }
        SkillVocabulary.Skill primary = skills.isEmpty() ? null : skills.getFirst();
        Constraints constraints = new Constraints(primary == null ? null : primary.tag(),
                primary == null ? null : primary.display(), skills.stream().map(SkillVocabulary.Skill::tag).toList(),
                skills.stream().anyMatch(SkillVocabulary.Skill::requiresLicence), budget, "USD", needed, distance,
                input.location().rounded());
        if (primary != null) return new Result(AskType.SERVICE_REQUEST, constraints, null, null, null);
        // The one blocking question (manual §27.3, v4 §19A.1). For an unclassifiable ask it also
        // offers the place pipeline, so one answer resolves both and PLUG never asks twice.
        List<Option> options = new ArrayList<>(POPULAR.stream().limit(type == AskType.UNCLEAR ? 6 : 8)
                .map(tag -> new Option(tag, vocabulary.get(tag).display())).toList());
        if (type == AskType.UNCLEAR) options.add(PLACE_OPTION);
        return new Result(type, constraints, type == AskType.UNCLEAR ? "ask" : "category", List.copyOf(options), null);
    }

    /// The model's reading of a provider's own description, as vocabulary tags only.
    public List<SkillVocabulary.Skill> proposedSkills(String description) {
        Extracted model = provided(description, ZoneOffset.UTC);
        return model == null ? List.of() : vocabulary.resolve(model.skillTags());
    }

    static String placeName(String text) {
        Matcher matcher = PLACE_NAME.matcher(text);
        String found = null;
        while (matcher.find()) {
            String candidate = matcher.group(1).replaceAll("\\s+(right )?now$", "").trim();
            if (!candidate.matches("(?i)(right )?now|the moment|line|queue")) { found = candidate; break; }
        }
        return found == null || found.isBlank() ? null : found.length() > 120 ? found.substring(0, 120) : found;
    }

    private Extracted provided(String text, ZoneId zone) {
        try {
            var result = providerPool.submit(() -> provider.extract(text, clock.instant(), zone, deadline));
            String raw;
            try { raw = result.get(deadline.toMillis(), java.util.concurrent.TimeUnit.MILLISECONDS); }
            finally { result.cancel(true); }
            if (raw == null || raw.length() > 8192) return null;
            Extracted candidate = mapper.readValue(raw, Extracted.class);
            return valid(candidate) ? candidate : null;
        } catch (Exception ignored) {
            // Provider content, reasoning and exceptions never reach logs or users.
            return null;
        }
    }

    private boolean valid(Extracted value) {
        if (value == null || value.askType() == null
                || !List.of("service_request", "place_question", "unclear").contains(value.askType())) return false;
        // Tags the vocabulary does not have are dropped later; a malformed list is rejected outright.
        if (value.skillTags() == null || value.skillTags().size() > 5
                || value.skillTags().stream().anyMatch(tag -> tag == null || tag.length() > 60)) return false;
        if (value.placeName() != null && (value.placeName().isBlank() || value.placeName().length() > 120
                || value.placeName().codePoints().anyMatch(Character::isISOControl))) return false;
        if (value.budgetCents() != null && (value.budgetCents() < MIN_BUDGET || value.budgetCents() > MAX_BUDGET)) return false;
        if (value.maxDistanceM() != null && (value.maxDistanceM() < 100 || value.maxDistanceM() > 50_000)) return false;
        try { checkTime(value.neededBy()); } catch (ApiException invalid) { return false; }
        return true;
    }

    private static Integer budget(String text) {
        if (text.matches("(?s).*\\$\\s*$")) {
            throw ApiException.validation("text", "invalid_budget", "Write the budget as dollars and cents.");
        }
        List<String> amounts = new ArrayList<>();
        Matcher dollars = Pattern.compile("\\$\\s*([^\\s]+)").matcher(text);
        while (dollars.find()) amounts.add(dollars.group(1).replaceFirst("[,.!?]$", ""));
        Matcher words = Pattern.compile("\\b([0-9]{1,3}(?:,[0-9]{3})+(?:\\.[0-9]{1,2})?|[0-9]+(?:\\.[0-9]{1,2})?)\\s*(?:dollars?|bucks|usd)\\b").matcher(text);
        while (words.find()) amounts.add(words.group(1));
        Integer budget = null;
        for (String written : amounts) {
            // "$1,000" is a normal way to write money; "$1,00" or "$10,0000" is not.
            String amount = written.matches("[0-9]{1,3}(?:,[0-9]{3})+(?:\\.[0-9]{1,2})?") ? written.replace(",", "") : written;
            if (!amount.matches("[0-9]+(?:\\.[0-9]{1,2})?")) {
                throw ApiException.validation("text", "invalid_budget", "Write the budget as dollars and cents.");
            }
            int candidate;
            try { candidate = new BigDecimal(amount).movePointRight(2).intValueExact(); }
            catch (ArithmeticException failure) { throw outOfRange(); }
            if (candidate < MIN_BUDGET || candidate > MAX_BUDGET) throw outOfRange();
            if (budget != null && budget != candidate) throw ApiException.validation("text", "ambiguous_budget", "Choose one budget.");
            budget = candidate;
        }
        return budget;
    }
    private static ApiException outOfRange() {
        return ApiException.validation("text", "out_of_range", "Choose a budget from $5 to $5,000.");
    }

    private Instant neededBy(String text, ZoneId zone) {
        Map<String, Instant> found = new LinkedHashMap<>();
        Instant now = clock.instant();
        Matcher relative = Pattern.compile("\\bin\\s+([+-]?[0-9]+(?:\\.[0-9]+)?)\\s*(minutes?|mins?|hours?|hrs?|days?)\\b").matcher(text);
        while (relative.find()) {
            long count;
            try { count = new BigDecimal(relative.group(1)).longValueExact(); }
            catch (ArithmeticException failure) { throw ApiException.validation("text", "invalid_time", "Use a whole number of minutes, hours or days."); }
            String unit = relative.group(2);
            long multiplier = unit.startsWith("d") ? 86400 : unit.startsWith("h") ? 3600 : 60;
            if (count <= 0) throw ApiException.validation("needed_by", "in_the_past", "Choose a future time.");
            if (count > 604800 / multiplier) throw ApiException.validation("needed_by", "too_far_ahead", "Choose a time within seven days.");
            found.put(relative.group(), now.plusSeconds(count * multiplier));
        }
        LocalDate today = now.atZone(zone).toLocalDate();
        Matcher day = Pattern.compile("\\b(tomorrow|today|tonight)(?:\\s+(morning|afternoon|evening|night))?\\b").matcher(text);
        while (day.find()) {
            LocalDate date = day.group(1).equals("tomorrow") ? today.plusDays(1) : today;
            String part = day.group(1).equals("tonight") ? "night" : day.group(2);
            LocalTime time = part == null ? LocalTime.of(23, 59) : switch (part) {
                case "morning" -> LocalTime.NOON;
                case "afternoon" -> LocalTime.of(17, 0);
                default -> LocalTime.of(21, 0);
            };
            found.put(day.group(), date.atTime(time).atZone(zone).toInstant());
        }
        if (found.values().stream().distinct().count() > 1) {
            throw ApiException.validation("text", "ambiguous_time", "Choose one time.");
        }
        return found.values().stream().findFirst().orElse(null);
    }

    private static Integer distance(String text) {
        Matcher within = Pattern.compile("\\bwithin\\s+([0-9]+(?:\\.[0-9]+)?)\\s*(miles?|mi|km|kilomet(?:er|re)s?)\\b").matcher(text);
        if (!within.find()) return null;
        double metres = Double.parseDouble(within.group(1)) * (within.group(2).startsWith("k") ? 1000 : 1609.344);
        if (metres < 100 || metres > 50_000) {
            throw ApiException.validation("text", "out_of_range", "Choose a distance up to about 30 miles.");
        }
        return (int) Math.round(metres);
    }

    private static ZoneId zone(String id) {
        if (id == null) return ZoneOffset.UTC;
        try { return ZoneId.of(id); }
        catch (DateTimeException invalid) { throw ApiException.validation("time_zone", "invalid", "Use an IANA time zone."); }
    }

    private void checkTime(Instant value) {
        if (value == null) return;
        if (!value.isAfter(clock.instant())) throw ApiException.validation("needed_by", "in_the_past", "Choose a future time.");
        if (value.isAfter(clock.instant().plus(Duration.ofDays(7)))) {
            throw ApiException.validation("needed_by", "too_far_ahead", "Choose a time within seven days.");
        }
    }

    private static String normalize(String text) {
        return Normalizer.normalize(text, Normalizer.Form.NFKC).toLowerCase(Locale.ROOT);
    }
}
