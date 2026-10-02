package app.plug.request;

import app.plug.foundation.ApiException;
import app.plug.request.RequestPayloads.Constraints;
import app.plug.request.RequestPayloads.Create;
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

// Turns the person's words into constraints for any lawful service (ADR-009).
// Precedence: explicit client fields, then unambiguous rule-based parses of numbers and times,
// then the provider (Claude) for the service, then the built-in service dictionary. Provider
// output is untrusted: it is strictly parsed and range-checked, and it can never set status,
// offers, prices or truth labels. Any provider failure falls back to the rules, never a 500.
public class IntentAdapter implements AutoCloseable {
    private final java.util.concurrent.ExecutorService providerPool = new java.util.concurrent.ThreadPoolExecutor(
            0, 2, 30, java.util.concurrent.TimeUnit.SECONDS, new java.util.concurrent.SynchronousQueue<>(),
            task -> { Thread thread = new Thread(task, "intent-provider"); thread.setDaemon(true); return thread; });
    @Override public void close() { providerPool.shutdownNow(); }

    @FunctionalInterface public interface Provider {
        /** The provider's raw JSON, or null when none is configured or it declined. */
        String extract(String text, Instant now, ZoneId zone, Duration deadline) throws Exception;
    }
    public record Extracted(String category, String serviceName, List<String> searchTerms, Integer budgetCents,
            Instant neededBy, Integer maxDistanceM, List<Option> candidates) {}
    /** Constraints plus, when the service is unknown, the one question's options. */
    public record Result(Constraints constraints, List<Option> clarificationOptions) {}

    public static final int MIN_BUDGET = 500;
    public static final int MAX_BUDGET = 500_000;
    static final int DEFAULT_DISTANCE_M = 10_000;
    private static final Pattern CATEGORY = Pattern.compile("[a-z][a-z0-9_]{1,39}");
    private static final Pattern LABEL = Pattern.compile("[\\p{L}\\p{N} &'(),./+-]{1,80}");
    private static final Pattern TERM = Pattern.compile("[\\p{L}\\p{N} &'./+-]{1,60}");
    private static final Pattern RESTRICTED = Pattern.compile("\\b(stolen|credit card numbers|cocaine|heroin|meth|fentanyl|weapon|gun|kill|murder|assassin|prostitut|escort|fake id|forged|fraud|hack|explosive|bomb)\\w*\\b");

    record Service(String category, String name, List<String> terms, Pattern pattern) {
        Service(String category, String name, List<String> terms, String regex) {
            this(category, name, terms, Pattern.compile("\\b(" + regex + ")\\b"));
        }
    }
    // The rule-based fallback when no provider is configured or it fails. Barber and beauty
    // keep the identifiers the seeded suppliers use; everything else is open (ADR-009).
    static final List<Service> SERVICES = List.of(
            new Service("barber", "Barber", List.of("barber", "barbershop"), "barber\\w*|haircut|hair cut|fresh cut|fade|beard|trim"),
            new Service("beauty", "Beauty & nails", List.of("nail salon", "beauty salon"), "beauty|manicure|pedicure|nails?|salon|lashes|makeup|braids|brows"),
            new Service("shoe_repair", "Shoe repair", List.of("shoe repair", "cobbler"), "cobbler|shoe repair|(repair|fix|resole)\\w* (my |a |the )?(shoes?|boots?|sneakers?|heels?)"),
            new Service("plumber", "Plumber", List.of("plumber", "plumbing"), "plumb\\w*|leak\\w*|clogged|toilet|drain"),
            new Service("electrician", "Electrician", List.of("electrician"), "electrician|electrical|wiring|outlet|breaker"),
            new Service("auto_repair", "Auto repair", List.of("auto repair", "mechanic"), "mechanic|car repair|auto repair|oil change|brakes?|flat tire|engine"),
            new Service("locksmith", "Locksmith", List.of("locksmith"), "locksmith|locked out|lockout|rekey"),
            new Service("house_cleaning", "House cleaning", List.of("house cleaning", "cleaning service"), "cleaner|cleaning|maid|housekeep\\w*"),
            new Service("tailor", "Tailor", List.of("tailor", "alterations"), "tailor\\w*|alterations?|hem|hemming"),
            new Service("phone_repair", "Phone repair", List.of("phone repair", "cell phone repair"), "phone repair|iphone repair|cracked screen|(fix|repair) (my )?(phone|iphone)"),
            new Service("computer_repair", "Computer repair", List.of("computer repair", "laptop repair"), "(computer|laptop|pc) repair|(fix|repair) (my )?(computer|laptop|pc)"),
            new Service("tutor", "Tutor", List.of("tutor", "tutoring"), "tutor\\w*|homework help"),
            new Service("handyman", "Handyman", List.of("handyman"), "handyman|handy man|furniture assembly|mount (a |my )?tv"),
            new Service("movers", "Movers", List.of("movers", "moving company"), "movers?|moving help"),
            new Service("laundry", "Laundry & dry cleaning", List.of("dry cleaning", "laundry"), "laundry|laundromat|dry clean\\w*"),
            new Service("car_wash", "Car wash", List.of("car wash", "auto detailing"), "car wash|detailing"),
            new Service("pet_grooming", "Pet grooming", List.of("pet grooming", "dog groomer"), "(dog|pet|cat) groom\\w*|groomer"),
            new Service("veterinarian", "Veterinarian", List.of("veterinarian", "animal hospital"), "vet|veterinar\\w*"),
            new Service("dentist", "Dentist", List.of("dentist"), "dentist|dental|toothache"),
            new Service("doctor", "Doctor", List.of("urgent care", "doctor"), "doctor|clinic|urgent care"),
            new Service("pharmacy", "Pharmacy", List.of("pharmacy"), "pharmacy|prescription"),
            new Service("massage", "Massage", List.of("massage"), "massage"),
            new Service("photographer", "Photographer", List.of("photographer"), "photographer|photo ?shoot"),
            new Service("towing", "Towing", List.of("towing", "tow truck"), "tow truck|towing|tow my"),
            new Service("restaurant", "Restaurant", List.of("restaurant"), "restaurant|dinner|lunch|breakfast|pizza|food"));
    /** Offered when the service could not be determined at all. */
    static final List<Option> POPULAR = SERVICES.stream().limit(8).map(s -> new Option(s.category(), s.name())).toList();

    private final ObjectMapper mapper;
    private final Clock clock;
    private final Provider provider;
    private final Duration deadline;

    public IntentAdapter(ObjectMapper mapper, Clock clock, Provider provider) {
        this(mapper, clock, provider, Duration.ofSeconds(6));
    }
    public IntentAdapter(ObjectMapper mapper, Clock clock, Provider provider, Duration deadline) {
        this.mapper = mapper.copy();
        this.clock = clock;
        this.provider = provider;
        this.deadline = deadline;
    }

    public boolean restricted(String text) {
        return RESTRICTED.matcher(normalize(text)).find();
    }

    public Result extract(Create input) {
        if (input.text().isBlank() || input.text().codePoints().anyMatch(c -> Character.isISOControl(c) && c != '\n')) {
            throw ApiException.validation("text", "invalid", "Describe the service using plain text.");
        }
        if (input.currency() != null && !input.currency().equals("USD")) {
            throw ApiException.validation("currency", "unsupported", "Only USD is supported.");
        }
        if (input.budgetCents() != null && input.currency() == null) {
            throw ApiException.validation("currency", "required", "Choose a currency for the budget.");
        }
        ZoneId zone = zone(input.timeZone());
        checkTime(input.neededBy());
        String text = normalize(input.text());
        Integer ruleBudget = input.budgetCents() == null ? budget(text) : null;
        Instant ruleTime = input.neededBy() == null ? neededBy(text, zone) : null;
        Integer ruleDistance = input.maxDistanceM() == null ? distance(text) : null;
        Extracted model = provided(input.text(), zone);

        String category = null;
        String name = null;
        List<String> terms = List.of();
        List<Option> options = null;
        List<Service> matches = SERVICES.stream().filter(s -> s.pattern().matcher(text).find()).toList();
        if (input.category() != null) {
            category = input.category();
            name = SERVICES.stream().filter(s -> s.category().equals(input.category())).map(Service::name).findFirst()
                    .orElse(humanize(input.category()));
            terms = List.of(name.toLowerCase(Locale.ROOT));
        } else if (model != null && model.category() != null) {
            category = model.category();
            name = model.serviceName() != null ? model.serviceName() : humanize(model.category());
            terms = model.searchTerms() == null || model.searchTerms().isEmpty()
                    ? List.of(name.toLowerCase(Locale.ROOT)) : model.searchTerms();
        } else if (matches.size() == 1) {
            category = matches.getFirst().category();
            name = matches.getFirst().name();
            terms = matches.getFirst().terms();
        } else {
            // The one blocking question (manual §27.3): which service. Never two questions.
            options = model != null && model.candidates() != null && model.candidates().size() >= 2 ? model.candidates()
                    : matches.size() >= 2 ? matches.stream().limit(8).map(s -> new Option(s.category(), s.name())).toList()
                    : POPULAR;
        }
        Integer budget = input.budgetCents() != null ? input.budgetCents() : ruleBudget != null ? ruleBudget
                : model == null ? null : model.budgetCents();
        Instant needed = input.neededBy() != null ? input.neededBy() : ruleTime != null ? ruleTime
                : model == null ? null : model.neededBy();
        checkTime(needed);
        int distance = input.maxDistanceM() != null ? input.maxDistanceM() : ruleDistance != null ? ruleDistance
                : model != null && model.maxDistanceM() != null ? model.maxDistanceM() : DEFAULT_DISTANCE_M;
        return new Result(new Constraints(category, name, terms, budget, "USD", needed, distance,
                input.location().rounded()), options);
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
        if (value == null) return false;
        boolean named = value.category() != null;
        if (named && (!CATEGORY.matcher(value.category()).matches()
                || value.serviceName() == null || !LABEL.matcher(value.serviceName()).matches())) return false;
        if (!named && value.serviceName() != null) return false;
        if (value.searchTerms() != null && (value.searchTerms().size() > 5
                || value.searchTerms().stream().anyMatch(t -> t == null || !TERM.matcher(t).matches()))) return false;
        if (value.candidates() != null && (value.candidates().size() > 8 || value.candidates().stream().anyMatch(o -> o == null
                || o.value() == null || !CATEGORY.matcher(o.value()).matches()
                || o.label() == null || !LABEL.matcher(o.label()).matches()))) return false;
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

    static String humanize(String category) {
        String words = category.replace('_', ' ');
        return Character.toUpperCase(words.charAt(0)) + words.substring(1);
    }

    private static String normalize(String text) {
        return Normalizer.normalize(text, Normalizer.Form.NFKC).toLowerCase(Locale.ROOT);
    }
}
