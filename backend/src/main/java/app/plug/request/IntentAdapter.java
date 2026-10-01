package app.plug.request;

import app.plug.foundation.ApiException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.Set;
import java.util.regex.Pattern;
import app.plug.request.RequestPayloads.Constraints;
import app.plug.request.RequestPayloads.Create;

// The provider can extract constraints only. It cannot write offers, state or truth labels.
// No paid provider is connected in Phase 2; the default implementation is deterministic.
public class IntentAdapter implements AutoCloseable {
    private final java.util.concurrent.ExecutorService providerPool = new java.util.concurrent.ThreadPoolExecutor(
            0, 2, 30, java.util.concurrent.TimeUnit.SECONDS, new java.util.concurrent.SynchronousQueue<>(),
            task -> { Thread thread = new Thread(task, "intent-provider"); thread.setDaemon(true); return thread; });
    @Override public void close() { providerPool.shutdownNow(); }
    @FunctionalInterface public interface Provider {
        String extract(String text, Duration deadline) throws Exception;
    }
    public record Extracted(String category, Integer budgetCents, Instant neededBy, Integer maxDistanceM) {}
    private final ObjectMapper mapper;
    private final Clock clock;
    private final Provider provider;
    private static final Pattern BARBER = Pattern.compile("\\b(barber|haircut|hair cut|fresh cut|fade|beard|trim)\\b");
    private static final Pattern BEAUTY = Pattern.compile("\\b(beauty|manicure|pedicure|nails?|salon|lashes|makeup|braids)\\b");
    private static final Pattern UNSUPPORTED = Pattern.compile("\\b(plumber|restaurant|dinner|electrician|doctor|dentist|mechanic|taxi|pizza)\\b");
    private static final Pattern RESTRICTED = Pattern.compile("\\b(stolen|credit card numbers|cocaine|heroin|meth|fentanyl|weapon|gun|kill|murder|assassin|prostitut|escort|fake id|forged|fraud|hack|explosive|bomb)\\w*\\b");
    public IntentAdapter(ObjectMapper mapper, Clock clock, Provider provider) {
        this.mapper = mapper.copy();
        this.clock = clock;
        this.provider = provider;
    }
    public boolean restricted(String text) {
        return RESTRICTED.matcher(java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFKC)
                .toLowerCase(Locale.ROOT)).find();
    }
    public Constraints extract(Create input) {
        String text = input.text().toLowerCase(Locale.ROOT);
        if (input.text().isBlank() || input.text().codePoints().anyMatch(c -> Character.isISOControl(c) && c != '\n')) {
            throw ApiException.validation("text", "invalid", "Describe the service using plain text.");
        }
        if (input.currency() != null && !input.currency().equals("USD")) {
            throw ApiException.validation("currency", "unsupported", "Only USD is supported.");
        }
        if (input.budgetCents() != null && input.currency() == null) {
            throw ApiException.validation("currency", "required", "Choose a currency for the budget.");
        }
        checkTime(input.neededBy());
        if (UNSUPPORTED.matcher(text).find() && input.category() == null) {
            throw ApiException.validation("text", "unsupported_category", "PLUG currently supports barbers and beauty services.");
        }
        Extracted fallback = deterministic(text, input.budgetCents() == null, input.neededBy() == null);
        Extracted extracted = fallback;
        try {
            String raw = boundedExtract(input.text());
            if (raw != null && raw.length() <= 4096) {
                Extracted candidate = mapper.readValue(raw, Extracted.class);
                if (valid(candidate)) extracted = candidate;
            }
        } catch (Exception ignored) {
            // Provider content, reasoning and exceptions never reach logs or users.
        }
        // A recognised deterministic constraint cannot be replaced by model hallucination.
        String category = input.category() != null ? input.category() : fallback.category() != null
                ? fallback.category() : extracted.category();
        boolean ambiguous = BARBER.matcher(text).find() && BEAUTY.matcher(text).find();
        if (ambiguous && input.category() == null) category = null;
        Integer budget = input.budgetCents() != null ? input.budgetCents() : fallback.budgetCents() != null
                ? fallback.budgetCents() : extracted.budgetCents();
        Instant needed = input.neededBy() != null ? input.neededBy() : fallback.neededBy() != null
                ? fallback.neededBy() : extracted.neededBy();
        checkTime(needed);
        int distance = input.maxDistanceM() != null ? input.maxDistanceM()
                : extracted.maxDistanceM() != null ? extracted.maxDistanceM() : 10000;
        return new Constraints(category, budget, "USD", needed, distance, input.location().rounded());
    }
    private String boundedExtract(String text) throws Exception {
        var result = providerPool.submit(() -> provider.extract(text, Duration.ofSeconds(6)));
        try { return result.get(6, java.util.concurrent.TimeUnit.SECONDS); }
        finally { result.cancel(true); }
    }
    private boolean valid(Extracted value) {
        if (value == null || value.category() == null || !Set.of("barber", "beauty").contains(value.category())) return false;
        if (value.budgetCents() != null && (value.budgetCents() < 500 || value.budgetCents() > 50000)) return false;
        if (value.maxDistanceM() != null && (value.maxDistanceM() < 100 || value.maxDistanceM() > 50000)) return false;
        try { checkTime(value.neededBy()); } catch (ApiException invalid) { return false; }
        return true;
    }
    private Extracted deterministic(String text, boolean extractBudget, boolean extractTime) {
        boolean barber = BARBER.matcher(text).find();
        boolean beauty = BEAUTY.matcher(text).find();
        String category = barber == beauty ? null : barber ? "barber" : "beauty";
        Integer budget = null;
        if (extractBudget && text.matches("(?s).*\\$\\s*$")) {
            throw ApiException.validation("text", "invalid_budget", "Write the budget as dollars and cents.");
        }
        var money = Pattern.compile("\\$\\s*([^\\s]+)").matcher(text);
        while (extractBudget && money.find()) {
            String amount = money.group(1).replaceFirst("[,.!?]$", "");
            if (!amount.matches("[0-9]+(?:\\.[0-9]{1,2})?")) {
                throw ApiException.validation("text", "invalid_budget", "Write the budget as dollars and cents.");
            }
            int candidate;
            try { candidate = new BigDecimal(amount).movePointRight(2).intValueExact(); }
            catch (ArithmeticException failure) { throw ApiException.validation("text", "out_of_range", "Choose a budget from $5 to $500."); }
            if (candidate < 500 || candidate > 50000) throw ApiException.validation("text", "out_of_range", "Choose a budget from $5 to $500.");
            if (budget != null && budget != candidate) throw ApiException.validation("text", "ambiguous_budget", "Choose one budget.");
            budget = candidate;
        }
        Instant needed = null;
        Instant extractionTime = clock.instant();
        var relative = Pattern.compile("\\bin\\s+([+-]?[0-9]+(?:\\.[0-9]+)?)\\s*(minutes?|mins?|hours?|hrs?|days?)\\b").matcher(text);
        while (extractTime && relative.find()) {
            long count;
            try { count = new BigDecimal(relative.group(1)).longValueExact(); }
            catch (ArithmeticException failure) { throw ApiException.validation("text", "invalid_time", "Use a whole number of minutes, hours or days."); }
            String unit = relative.group(2);
            long multiplier = unit.startsWith("d") ? 86400 : unit.startsWith("h") ? 3600 : 60;
            if (count <= 0) throw ApiException.validation("needed_by", "in_the_past", "Choose a future time.");
            if (count > 604800 / multiplier) throw ApiException.validation("needed_by", "too_far_ahead", "Choose a time within seven days.");
            Instant candidate = extractionTime.plusSeconds(count * multiplier);
            if (needed != null && !needed.equals(candidate)) throw ApiException.validation("text", "ambiguous_time", "Choose one time.");
            needed = candidate;
        }
        return new Extracted(category, budget, needed, null);
    }
    private void checkTime(Instant value) {
        if (value == null) return;
        if (!value.isAfter(clock.instant())) throw ApiException.validation("needed_by", "in_the_past", "Choose a future time.");
        if (value.isAfter(clock.instant().plus(Duration.ofDays(7)))) {
            throw ApiException.validation("needed_by", "too_far_ahead", "Choose a time within seven days.");
        }
    }
}
