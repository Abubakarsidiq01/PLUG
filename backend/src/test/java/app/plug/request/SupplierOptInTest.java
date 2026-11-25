package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ContractSchemas;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;

/// P3.S2 public supplier opt-in (contract 0.7.7 supplierOptIn, SupplierOptIn, SupplierOptInReceipt).
/// Consent is explicit and recorded; the answer never says whether a number is known; nothing is sent
/// in P3.S2, one optin_confirm row is only queued.
@Tag("database")
@SpringBootTest(properties = {"plug.supplier-messaging.enabled=true", "plug.supplier-messaging.delivery=simulator",
        "plug.supplier-messaging.phone-key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
class SupplierOptInTest {
    static final String VERSION = "sms-2026-10-09";
    static final String MARK = "Sup-test ";

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;

    @AfterEach void removeOnlyThisTestsRecords() {
        jdbc.update("DELETE FROM sms_outbox WHERE supplier_id IN (SELECT id FROM suppliers WHERE business_name LIKE ?)", MARK + "%");
        jdbc.update("DELETE FROM supplier_consent_events WHERE supplier_id IN (SELECT id FROM suppliers WHERE business_name LIKE ?)", MARK + "%");
        jdbc.update("DELETE FROM suppliers WHERE business_name LIKE ?", MARK + "%");
    }

    // ---- helpers -------------------------------------------------------------------------

    static String newPhone() {
        var r = ThreadLocalRandom.current();
        return "+1" + (2 + r.nextInt(8)) + String.format("%02d", r.nextInt(100)) + (2 + r.nextInt(8))
                + String.format("%06d", r.nextInt(1_000_000));
    }
    // Letters only: a business name may not hold five digits in a row.
    static String name() { return MARK + UUID.randomUUID().toString().substring(0, 8).replaceAll("[0-9]", "g"); }
    static String body(String name, String phone, String version, Object consent) {
        return "{\"business_name\":\"" + name + "\",\"phone\":\"" + phone + "\",\"consent_version\":\"" + version
                + "\",\"consent\":" + consent + "}";
    }
    ResultActions optIn(String address, String body, String key) throws Exception {
        var request = MockMvcRequestBuilders.post("/v1/suppliers/opt-in").with(r -> { r.setRemoteAddr(address); return r; })
                .contentType(MediaType.APPLICATION_JSON).content(body);
        if (key != null) request.header("Idempotency-Key", key);
        return mvc.perform(request);
    }
    ResultActions optIn(String name, String phone) throws Exception {
        return optIn(UUID.randomUUID().toString(), body(name, phone, VERSION, true), "optin-" + UUID.randomUUID());
    }
    JsonNode json(ResultActions result, String schema) throws Exception {
        JsonNode body = mapper.readTree(result.andReturn().getResponse().getContentAsString());
        ContractSchemas.validate(body.has("error") ? "Error" : schema, body);
        return body;
    }
    JsonNode receipt(ResultActions result) throws Exception {
        return json(result.andExpect(status().isAccepted()), "SupplierOptInReceipt");
    }
    JsonNode errorOf(ResultActions result, int status) throws Exception {
        result.andExpect(status().is(status));
        return json(result, "Error").get("error");
    }
    String supplierId(String name) {
        return jdbc.queryForObject("SELECT id FROM suppliers WHERE business_name=?", String.class, name);
    }
    int suppliers(String name) {
        return jdbc.queryForObject("SELECT count(*) FROM suppliers WHERE business_name=?", Integer.class, name);
    }
    int events(String id) {
        return jdbc.queryForObject("SELECT count(*) FROM supplier_consent_events WHERE supplier_id=?", Integer.class, id);
    }
    int queued(String id) {
        return jdbc.queryForObject("SELECT count(*) FROM sms_outbox WHERE supplier_id=? AND template='optin_confirm' AND status='queued'",
                Integer.class, id);
    }
    String consent(String id) { return jdbc.queryForObject("SELECT consent_state FROM suppliers WHERE id=?", String.class, id); }
    void assertDetail(JsonNode error, String field, String code) {
        assertThat(error.at("/details/0/field").asText()).isEqualTo(field);
        assertThat(error.at("/details/0/code").asText()).isEqualTo(code);
    }

    // ---- 1. same receipt, whatever the number's state ------------------------------------

    @Test void theReceiptIsIdenticalForNewPendingGrantedPausedAndRevokedNumbers() throws Exception {
        JsonNode expected = mapper.readTree("{\"status\":\"confirmation_sent_if_eligible\"}");
        String pendingName = name(), pendingPhone = newPhone();
        assertThat(receipt(optIn(pendingName, pendingPhone))).as("new").isEqualTo(expected);
        assertThat(receipt(optIn(pendingName, pendingPhone))).as("pending").isEqualTo(expected);
        for (String state : List.of("granted", "paused", "revoked")) {
            String n = name(), phone = newPhone();
            receipt(optIn(n, phone));
            jdbc.update("UPDATE suppliers SET consent_state=?, paused_until=CASE WHEN ?='paused' THEN now()+interval '1 day' END WHERE id=?",
                    state, state, supplierId(n));
            assertThat(receipt(optIn(n, phone))).as(state).isEqualTo(expected);
        }
    }

    // ---- 2. new number: pending supplier, consent event, one queued text ------------------

    @Test void aNewNumberBecomesOnePendingSupplierWithAWebFormConsentEventAndOneQueuedOptInConfirm() throws Exception {
        String n = name();
        receipt(optIn(n, newPhone()));
        assertThat(suppliers(n)).isEqualTo(1);
        String id = supplierId(n);
        assertThat(id).startsWith("sup_");
        assertThat(jdbc.queryForObject("SELECT verification_status FROM suppliers WHERE id=?", String.class, id)).isEqualTo("pending_verification");
        assertThat(consent(id)).isEqualTo("pending_confirmation");
        var events = jdbc.queryForList("SELECT state, source, version FROM supplier_consent_events WHERE supplier_id=?", id);
        assertThat(events).hasSize(1);
        assertThat(events.getFirst()).containsEntry("state", "pending_confirmation").containsEntry("source", "web_form")
                .containsEntry("version", VERSION);
        assertThat(queued(id)).isEqualTo(1);
    }

    // ---- 3. pending number again ---------------------------------------------------------

    @Test void aPendingNumberOptingInAgainAddsAWebFormEventButNeverRenamesOrUnverifiesTheSupplier() throws Exception {
        String n = name(), phone = newPhone();
        receipt(optIn(n, phone));
        String id = supplierId(n);
        jdbc.update("UPDATE suppliers SET verification_status='verified' WHERE id=?", id);
        receipt(optIn(UUID.randomUUID().toString(), body(MARK + "Renamed " + UUID.randomUUID().toString().substring(0, 6).replaceAll("[0-9]", "g"), phone, VERSION, true),
                "optin-" + UUID.randomUUID()));
        assertThat(jdbc.queryForObject("SELECT business_name FROM suppliers WHERE id=?", String.class, id)).isEqualTo(n);
        assertThat(jdbc.queryForObject("SELECT verification_status FROM suppliers WHERE id=?", String.class, id)).isEqualTo("verified");
        assertThat(jdbc.queryForObject("SELECT count(*) FROM supplier_consent_events WHERE supplier_id=? AND source='web_form'",
                Integer.class, id)).isEqualTo(2);
        assertThat(queued(id)).isEqualTo(2);
    }

    // ---- 4. granted, paused, revoked: nothing queued, nothing changed ---------------------

    @Test void grantedPausedAndRevokedNumbersQueueNothingAndChangeNoState() throws Exception {
        for (String state : List.of("granted", "paused", "revoked")) {
            String n = name(), phone = newPhone();
            receipt(optIn(n, phone));
            String id = supplierId(n);
            jdbc.update("UPDATE suppliers SET consent_state=?, paused_until=CASE WHEN ?='paused' THEN now()+interval '1 day' END WHERE id=?",
                    state, state, id);
            jdbc.update("DELETE FROM sms_outbox WHERE supplier_id=?", id);
            int before = events(id);
            receipt(optIn(n, phone));
            assertThat(queued(id)).as(state + " queued").isZero();
            assertThat(events(id)).as(state + " events").isEqualTo(before);
            assertThat(consent(id)).as(state).isEqualTo(state);
        }
    }

    // ---- 5 to 7. validation --------------------------------------------------------------

    @Test void consentFalseIsRejectedWithConsentRequiredOnTheConsentField() throws Exception {
        String n = name();
        JsonNode error = errorOf(optIn(UUID.randomUUID().toString(), body(n, newPhone(), VERSION, false), "k-" + UUID.randomUUID()), 400);
        assertThat(error.get("code").asText()).isEqualTo("validation_failed");
        assertDetail(error, "consent", "consent_required");
        assertThat(suppliers(n)).isZero();
    }

    @Test void anOldOrMadeUpConsentVersionIsRejectedWithUnsupportedVersionOnTheConsentVersionField() throws Exception {
        for (String version : List.of("sms-2020-01-01", "bogus")) {
            String n = name();
            JsonNode error = errorOf(optIn(UUID.randomUUID().toString(), body(n, newPhone(), version, true), "k-" + UUID.randomUUID()), 400);
            assertDetail(error, "consent_version", "unsupported_version");
            assertThat(suppliers(n)).as(version).isZero();
        }
    }

    @Test void anUnknownFieldOrABadPhoneIsRejectedAndNothingIsStored() throws Exception {
        String n = name();
        errorOf(optIn(UUID.randomUUID().toString(), "{\"business_name\":\"" + n + "\",\"phone\":\"" + newPhone() + "\",\"consent_version\":\""
                + VERSION + "\",\"consent\":true,\"website\":\"x\"}", "k-" + UUID.randomUUID()), 400);
        errorOf(optIn(UUID.randomUUID().toString(), body(n, "+15551234567", VERSION, true), "k-" + UUID.randomUUID()), 400);
        assertThat(suppliers(n)).isZero();
    }

    @Test void aBusinessNameHoldingALinkADomainAnEmailOrADigitRunIsRejectedOnTheBusinessNameField() throws Exception {
        for (String bad : List.of("Shop https://x", "Shop www.example", "Shop example.com", "Shop a@b", "Shop 55501")) {
            String n = MARK + bad;
            JsonNode error = errorOf(optIn(UUID.randomUUID().toString(), body(n, newPhone(), VERSION, true), "k-" + UUID.randomUUID()), 400);
            assertDetail(error, "business_name", "invalid");
            assertThat(suppliers(n)).as(bad).isZero();
        }
    }

    // ---- 8 and 9. limits answer 202 and send nothing -------------------------------------

    @Test void theSixthOptInFromOneAddressInAnHourIsAnsweredAcceptedButNothingIsQueued() throws Exception {
        String address = UUID.randomUUID().toString();
        for (int n = 0; n < 5; n++) {
            receipt(optIn(address, body(name(), newPhone(), VERSION, true), "k-" + UUID.randomUUID()));
        }
        String sixth = name();
        receipt(optIn(address, body(sixth, newPhone(), VERSION, true), "k-" + UUID.randomUUID()));
        assertThat(jdbc.queryForObject("SELECT count(*) FROM sms_outbox o JOIN suppliers s ON s.id=o.supplier_id WHERE s.business_name=?",
                Integer.class, sixth)).isZero();
    }

    @Test void theFourthOptInForOnePhoneInADayIsAnsweredAcceptedButNothingIsQueued() throws Exception {
        String n = name(), phone = newPhone();
        for (int i = 0; i < 4; i++) receipt(optIn(n, phone));
        String id = supplierId(n);
        assertThat(queued(id)).isEqualTo(3);
        assertThat(events(id)).isEqualTo(3);
    }

    // ---- 10. idempotency -----------------------------------------------------------------

    @Test void theSameKeyAndBodyReplaysAndAnotherBodyUnderThatKeyIsAConflict() throws Exception {
        String n = name(), phone = newPhone(), key = "k-" + UUID.randomUUID();
        String body = body(n, phone, VERSION, true);
        JsonNode first = receipt(optIn(UUID.randomUUID().toString(), body, key));
        JsonNode second = receipt(optIn(UUID.randomUUID().toString(), body, key));
        assertThat(second).isEqualTo(first);
        String id = supplierId(n);
        assertThat(queued(id)).as("a replay queues nothing more").isEqualTo(1);
        assertThat(events(id)).isEqualTo(1);
        JsonNode error = errorOf(optIn(UUID.randomUUID().toString(), body(name(), newPhone(), VERSION, true), key), 409);
        assertThat(error.get("code").asText()).isEqualTo("conflict");
        assertDetail(error, "Idempotency-Key", "idempotency_key_reused");
    }

    // ---- 11. the number is never stored in the clear -------------------------------------

    @Test void thePhoneIsStoredOnlyAsAKeyedHashAndCiphertextNeverAsDigitsInAnyTable() throws Exception {
        String n = name(), phone = newPhone();
        receipt(optIn(n, phone));
        String id = supplierId(n);
        String digits = phone.substring(1), national = phone.substring(2);
        assertThat(jdbc.queryForObject("SELECT phone_hash IS NOT NULL AND phone_ciphertext IS NOT NULL FROM suppliers WHERE id=?",
                Boolean.class, id)).isTrue();
        for (String table : List.of("suppliers", "supplier_consent_events", "sms_outbox", "audit_events")) {
            for (String needle : List.of(phone, digits, national)) {
                assertThat(jdbc.queryForObject("SELECT count(*) FROM " + table + " t WHERE t::text LIKE ?", Integer.class, "%" + needle + "%"))
                        .as(table + " holds " + needle.length() + " phone digits").isZero();
            }
        }
    }
}
