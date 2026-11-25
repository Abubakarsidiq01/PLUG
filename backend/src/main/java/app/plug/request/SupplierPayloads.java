package app.plug.request;

import app.plug.request.ProviderPayloads.AvailabilityWindow;
import java.time.Instant;
import java.util.List;

/// Contract 0.7.7 supplier bodies (SupplierOptIn, SupplierCreate, SupplierProfile) and answers
/// (Supplier, AdminOptOut). Spring web logs bodies through toString at DEBUG, so none shows a value.
public final class SupplierPayloads {
    private SupplierPayloads() {}
    public record OptIn(String businessName, String phone, String consentVersion) {
        @Override public String toString() { return "SupplierOptIn[redacted]"; }
    }
    public record Create(String businessName, String phone, String reason) {
        @Override public String toString() { return "SupplierCreate[redacted]"; }
    }
    public record Profile(String businessName, List<String> skillTags, String address, RequestPayloads.Location location,
            int serviceRadiusM, List<AvailabilityWindow> hours, String timeZone, String licenceRef, String contactName) {
        @Override public String toString() { return "SupplierProfile[redacted]"; }
    }
    public record Receipt(String status) {
        static final Receipt SENT_IF_ELIGIBLE = new Receipt("confirmation_sent_if_eligible");
    }
    public record Verification(String status, Instant decidedAt, String reason) {
        @Override public String toString() { return "Verification[redacted]"; }
    }
    public record Consent(String state, String version, Instant changedAt, Instant pausedUntil) {}
    public record ConsentEvent(String state, String source, String version, Instant occurredAt) {}
    public record Supplier(String supplierId, String businessName, String phoneMasked, List<String> skillTags, String placeId,
            String address, Integer serviceRadiusM, List<AvailabilityWindow> hours, String timeZone, boolean licenceOnFile,
            String contactName, Verification verification, Consent consent, List<ConsentEvent> consentTrail,
            Instant createdAt, Instant updatedAt) {
        @Override public String toString() { return "Supplier[redacted]"; }
    }
    public record OptOut(String phoneMasked, String supplierId, String state, String source, Instant since, Instant pausedUntil) {
        @Override public String toString() { return "AdminOptOut[redacted]"; }
    }
}
