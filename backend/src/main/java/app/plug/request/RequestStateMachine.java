package app.plug.request;

import java.util.Map;
import java.util.Set;

public final class RequestStateMachine {
    private RequestStateMachine() {}
    public static final Set<String> STATES = Set.of("draft", "submitted", "routed", "awaiting_responses", "ranked",
            "user_selected", "confirmed", "completed", "expired", "canceled", "blocked");
    private static final Map<String, Set<String>> LEGAL = Map.of(
            "draft", Set.of("submitted", "expired", "canceled"),
            "submitted", Set.of("routed", "blocked", "canceled"),
            "routed", Set.of("awaiting_responses", "expired", "canceled"),
            "awaiting_responses", Set.of("ranked", "expired", "canceled"),
            "ranked", Set.of("user_selected", "expired", "canceled"),
            "user_selected", Set.of("confirmed", "expired", "canceled"),
            "confirmed", Set.of("completed", "canceled"));
    public static boolean allows(String current, String next, boolean supplierEvent) {
        return LEGAL.getOrDefault(current, Set.of()).contains(next) && (!next.equals("confirmed") || supplierEvent);
    }
    public static void require(String current, String next, boolean supplierEvent) {
        if (!allows(current, next, supplierEvent)) throw new IllegalStateException("Illegal request transition");
    }
    public static String action(String status) {
        return switch (status) {
            case "draft" -> "answer_clarification";
            case "submitted", "routed", "awaiting_responses" -> "wait_for_offers";
            case "ranked" -> "choose_offer";
            case "user_selected" -> "await_supplier_confirmation";
            case "confirmed", "completed" -> "show_result";
            case "expired" -> "show_no_result";
            default -> "none";
        };
    }
}
