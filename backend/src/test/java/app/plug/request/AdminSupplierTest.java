package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.authentication;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import app.plug.foundation.ContractSchemas;
import app.plug.security.PlugPrincipal;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.logging.LogLevel;
import org.springframework.boot.logging.LoggingSystem;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;

/// P3.S2 staff supplier routes (contract 0.7.7 listSuppliers, createSupplier, getSupplier,
/// updateSupplierProfile, decideSupplierVerification, listOptOuts). Staff can never mark consent given;
/// every write and every read is audited; a number appears only masked; nothing sensitive is logged.
@Tag("database")
@SpringBootTest(properties = {"plug.supplier-messaging.enabled=true", "plug.supplier-messaging.delivery=simulator",
        "plug.supplier-messaging.phone-key=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
        "plug.identity.pepper=phase2-testing-pepper-not-used-in-production"})
@ActiveProfiles("db")
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
class AdminSupplierTest {
    static final String VERSION = "sms-2026-10-09";
    static final String MARK = "Sup-test ";
    static final String HOURS = "[{\"days\":\"weekdays\",\"from\":\"09:00\",\"to\":\"19:00\"}]";
    static final String PLACE = "{\"address\":\"310 Example Street\",\"location\":{\"latitude\":44.0,\"longitude\":-101.0,\"precision\":\"coarse\"}}";
    static final String OTHER_PLACE = "{\"address\":\"12 Other Road\",\"location\":{\"latitude\":44.05,\"longitude\":-101.05,\"precision\":\"coarse\"}}";
    // The text each marker below must never reach a log line.
    static final String CONTACT = "Zephyrwick Contact";
    static final String REASON = "Crimson ledger onboarding visit.";
    static final String LICENCE = "LIC-ZX9917";

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper mapper;
    @Autowired JdbcTemplate jdbc;
    private final List<String> staff = new ArrayList<>();
    private final List<String> places = new ArrayList<>();

    @AfterEach void removeOnlyThisTestsRecords() {
        jdbc.update("DELETE FROM sms_outbox WHERE supplier_id IN (SELECT id FROM suppliers WHERE business_name LIKE ?)", MARK + "%");
        jdbc.update("DELETE FROM supplier_consent_events WHERE supplier_id IN (SELECT id FROM suppliers WHERE business_name LIKE ?)", MARK + "%");
        jdbc.update("DELETE FROM suppliers WHERE business_name LIKE ?", MARK + "%");
        for (String place : places) jdbc.update("DELETE FROM places WHERE id=?", place);
        for (String id : staff) jdbc.update("DELETE FROM users WHERE id=?", id);
    }

    // ---- helpers -------------------------------------------------------------------------

    PlugPrincipal staffMember(String role, boolean secondFactor) {
        String id = "usr_staff-" + UUID.randomUUID();
        jdbc.update("INSERT INTO users(id,account_type) VALUES(?,'staff')", id);
        jdbc.update("INSERT INTO staff_accounts(user_id,email,password_hash,role) VALUES(?,?,'not-a-real-hash',?)", id,
                id.substring(4, 24).toLowerCase() + "@example.com", role);
        staff.add(id);
        return new PlugPrincipal(id, "ses_staff", Set.of(PlugPrincipal.SCOPE_ADMIN), secondFactor);
    }
    PlugPrincipal owner() { return staffMember("owner", true); }
    ResultActions asStaff(PlugPrincipal principal, MockHttpServletRequestBuilder request) throws Exception {
        request.with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; });
        return mvc.perform(request.with(authentication(new UsernamePasswordAuthenticationToken(principal, null, List.of()))));
    }
    ResultActions send(PlugPrincipal who, String method, String path, String body) throws Exception {
        var request = method.equals("GET") ? MockMvcRequestBuilders.get(path) : MockMvcRequestBuilders.post(path);
        if (body != null) request.contentType(MediaType.APPLICATION_JSON).content(body);
        if (method.equals("POST") && path.equals("/v1/admin/suppliers")) request.header("Idempotency-Key", "k-" + UUID.randomUUID());
        if (who == null) {
            request.with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; });
            return mvc.perform(request);
        }
        return asStaff(who, request);
    }
    JsonNode json(ResultActions result, String schema) throws Exception {
        JsonNode body = mapper.readTree(result.andReturn().getResponse().getContentAsString());
        ContractSchemas.validate(body.has("error") ? "Error" : schema, body);
        return body;
    }
    JsonNode errorOf(ResultActions result, int status) throws Exception {
        result.andExpect(status().is(status));
        return json(result, "Error").get("error");
    }
    void assertDetail(JsonNode error, String field, String code) {
        assertThat(error.at("/details/0/field").asText()).isEqualTo(field);
        assertThat(error.at("/details/0/code").asText()).isEqualTo(code);
    }
    void assertRateLimited(ResultActions result) throws Exception {
        result.andExpect(status().isTooManyRequests()).andExpect(header().exists("Retry-After"));
        assertThat(json(result, "Error").at("/error/code").asText()).isEqualTo("rate_limited");
    }
    static String newPhone() {
        var r = ThreadLocalRandom.current();
        return "+1" + (2 + r.nextInt(8)) + String.format("%02d", r.nextInt(100)) + (2 + r.nextInt(8)) + String.format("%06d", r.nextInt(1_000_000));
    }
    // Letters only: a business name may not hold five digits in a row.
    static String name() { return MARK + UUID.randomUUID().toString().substring(0, 8).replaceAll("[0-9]", "g"); }
    static String mask(String phone) { return "+1 *** *** **" + phone.substring(phone.length() - 2); }
    String quote(String text) {
        try { return mapper.writeValueAsString(text); } catch (Exception e) { throw new RuntimeException(e); }
    }
    String createBody(String name, String phone, String reason) {
        return "{\"business_name\":" + quote(name) + ",\"phone\":\"" + phone + "\",\"reason\":" + quote(reason) + "}";
    }
    ResultActions create(PlugPrincipal who, String name, String phone) throws Exception {
        return send(who, "POST", "/v1/admin/suppliers", createBody(name, phone, REASON));
    }
    JsonNode created(PlugPrincipal who, String phone) throws Exception {
        return json(create(who, name(), phone).andExpect(status().isCreated()), "Supplier");
    }
    String profile(List<String> tags, String place, int radius, String licence) {
        String tagJson = String.join(",", tags.stream().map(t -> "\"" + t + "\"").toList());
        return "{\"business_name\":\"" + MARK + "Profile\",\"skill_tags\":[" + tagJson + "],\"place\":" + place + ",\"service_radius_m\":" + radius
                + ",\"hours\":" + HOURS + ",\"time_zone\":\"America/Chicago\""
                + (licence == null ? "" : ",\"licence_ref\":\"" + licence + "\"") + ",\"contact_name\":\"" + CONTACT + "\"}";
    }
    JsonNode update(PlugPrincipal who, String id, String body) throws Exception {
        JsonNode supplier = json(send(who, "POST", "/v1/admin/suppliers/" + id, body).andExpect(status().isOk()), "Supplier");
        if (supplier.has("place_id")) places.add(supplier.get("place_id").asText());
        return supplier;
    }
    ResultActions decide(PlugPrincipal who, String id, String status, String reason) throws Exception {
        return send(who, "POST", "/v1/admin/suppliers/" + id + "/verification",
                "{\"status\":\"" + status + "\",\"reason\":" + quote(reason) + "}");
    }
    /// A created supplier given a full profile and verified, ready for the re-verification tests.
    String verifiedSupplier(PlugPrincipal owner) throws Exception {
        String id = created(owner, newPhone()).get("supplier_id").asText();
        update(owner, id, profile(List.of("barber"), PLACE, 5000, null));
        json(decide(owner, id, "verified", "Visited the shop.").andExpect(status().isOk()), "Supplier");
        return id;
    }
    String verificationOf(String id) { return jdbc.queryForObject("SELECT verification_status FROM suppliers WHERE id=?", String.class, id); }
    int audits(String action, String actor, String resourceId) {
        return jdbc.queryForObject("SELECT count(*) FROM audit_events WHERE action=? AND actor_id=? AND resource='supplier' AND resource_id=?",
                Integer.class, action, actor, resourceId);
    }
    int readAudits(PlugPrincipal who) {
        return jdbc.queryForObject("SELECT count(*) FROM audit_events WHERE actor_id=? AND action='admin.read'", Integer.class, who.userId());
    }
    JsonNode findItem(JsonNode page, String id) {
        for (JsonNode item : page.get("items")) if (item.path("supplier_id").asText().equals(id)) return item;
        return null;
    }
    void setConsent(String id, String state, String source, String pausedUntilSql) {
        jdbc.update("UPDATE suppliers SET consent_state=?, consent_changed_at=now(), paused_until=" + pausedUntilSql + " WHERE id=?", state, id);
        jdbc.update("INSERT INTO supplier_consent_events(supplier_id,state,source,version,occurred_at) VALUES(?,?,?,?,now())",
                id, state, source, VERSION);
    }

    // ---- 1. sessions and roles -----------------------------------------------------------

    @Test void everyAdminSupplierRouteIs401WithoutASession() throws Exception {
        String id = "sup_" + UUID.randomUUID();
        for (String[] call : new String[][] {{"GET", "/v1/admin/suppliers"}, {"POST", "/v1/admin/suppliers"}, {"GET", "/v1/admin/suppliers/" + id},
                {"POST", "/v1/admin/suppliers/" + id}, {"POST", "/v1/admin/suppliers/" + id + "/verification"}, {"GET", "/v1/admin/opt-outs"}}) {
            var request = call[0].equals("GET") ? MockMvcRequestBuilders.get(call[1]) : MockMvcRequestBuilders.post(call[1])
                    .contentType(MediaType.APPLICATION_JSON).content("{}").header("Idempotency-Key", "k-" + UUID.randomUUID());
            mvc.perform(request.with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })).andExpect(status().isUnauthorized());
        }
    }

    @Test void adminWithoutASecondFactorIsForbiddenOnEverySupplierRoute() throws Exception {
        var noSecondFactor = staffMember("owner", false);
        String id = "sup_" + UUID.randomUUID();
        errorOf(send(noSecondFactor, "GET", "/v1/admin/suppliers", null), 403);
        errorOf(create(noSecondFactor, name(), newPhone()), 403);
        errorOf(send(noSecondFactor, "GET", "/v1/admin/suppliers/" + id, null), 403);
        errorOf(send(noSecondFactor, "POST", "/v1/admin/suppliers/" + id, profile(List.of("barber"), PLACE, 5000, null)), 403);
        errorOf(decide(noSecondFactor, id, "verified", "Visited."), 403);
        errorOf(send(noSecondFactor, "GET", "/v1/admin/opt-outs", null), 403);
    }

    @Test void onlyAnOwnerCanCreateUpdateOrDecideVerificationWhileStaffMayRead() throws Exception {
        var owner = owner();
        var member = staffMember("staff", true);
        String name = name();
        errorOf(create(member, name, newPhone()), 403);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM suppliers WHERE business_name=?", Integer.class, name)).isZero();
        String id = created(owner, newPhone()).get("supplier_id").asText();
        errorOf(send(member, "POST", "/v1/admin/suppliers/" + id, profile(List.of("barber"), PLACE, 5000, null)), 403);
        errorOf(decide(member, id, "verified", "Looks fine."), 403);
        assertThat(verificationOf(id)).isEqualTo("pending_verification");
        json(send(member, "GET", "/v1/admin/suppliers", null).andExpect(status().isOk()), "AdminSupplierPage");
        json(send(member, "GET", "/v1/admin/suppliers/" + id, null).andExpect(status().isOk()), "Supplier");
        json(send(member, "GET", "/v1/admin/opt-outs", null).andExpect(status().isOk()), "AdminOptOutPage");
    }

    // ---- 2. create -----------------------------------------------------------------------

    @Test void staffCreateRecordsAPendingSupplierWithStaffEntryConsentOneQueuedTextAndAnAuditRowWithTheReason() throws Exception {
        var owner = owner();
        String phone = newPhone();
        var result = create(owner, name(), phone).andExpect(status().isCreated());
        JsonNode supplier = json(result, "Supplier");
        String id = supplier.get("supplier_id").asText();
        assertThat(supplier.at("/consent/state").asText()).isEqualTo("pending_confirmation");
        assertThat(supplier.at("/consent/version").asText()).isEqualTo(VERSION);
        assertThat(supplier.at("/verification/status").asText()).isEqualTo("pending_verification");
        assertThat(supplier.get("phone_masked").asText()).isEqualTo(mask(phone));
        assertThat(supplier.has("consent_trail")).isFalse();
        assertThat(supplier.has("open_context")).isFalse();
        var events = jdbc.queryForList("SELECT state, source, version FROM supplier_consent_events WHERE supplier_id=?", id);
        assertThat(events).hasSize(1);
        assertThat(events.getFirst()).containsEntry("state", "pending_confirmation").containsEntry("source", "staff_entry")
                .containsEntry("version", VERSION);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM sms_outbox WHERE supplier_id=? AND template='optin_confirm' AND status='queued'",
                Integer.class, id)).isEqualTo(1);
        assertThat(jdbc.queryForList("SELECT reason FROM audit_events WHERE action='supplier.created' AND actor_id=? AND resource='supplier' AND resource_id=?",
                String.class, owner.userId(), id)).containsExactly(REASON);
    }

    @Test void creatingASupplierWithANumberAlreadyOnFileIs409SupplierExistsOnThePhoneField() throws Exception {
        var owner = owner();
        String phone = newPhone();
        created(owner, phone);
        JsonNode error = errorOf(create(owner, name(), phone), 409);
        assertThat(error.get("code").asText()).isEqualTo("conflict");
        assertDetail(error, "phone", "supplier_exists");
    }

    @Test void createRejectsABadPhoneAShortReasonAndAnUnknownField() throws Exception {
        var owner = owner();
        errorOf(send(owner, "POST", "/v1/admin/suppliers", createBody(name(), "+15551234567", REASON)), 400);
        errorOf(send(owner, "POST", "/v1/admin/suppliers", createBody(name(), newPhone(), "ab")), 400);
        errorOf(send(owner, "POST", "/v1/admin/suppliers",
                "{\"business_name\":\"" + name() + "\",\"phone\":\"" + newPhone() + "\",\"reason\":\"Visited.\",\"consent\":true}"), 400);
    }

    @Test void createRefusesALinkOrNumberInTheBusinessNameAndAPhoneNumberInTheReason() throws Exception {
        var owner = owner();
        for (String bad : List.of("Shop example.com", "Shop 2125550")) {
            assertDetail(errorOf(send(owner, "POST", "/v1/admin/suppliers", createBody(MARK + bad, newPhone(), REASON)), 400),
                    "business_name", "invalid");
        }
        for (String bad : List.of("Call +12125550142.", "Called 2125550142 today.")) {
            assertDetail(errorOf(send(owner, "POST", "/v1/admin/suppliers", createBody(name(), newPhone(), bad)), 400), "reason", "invalid");
        }
        assertThat(jdbc.queryForObject("SELECT count(*) FROM suppliers WHERE business_name LIKE ? AND business_name LIKE 'Sup-test Shop%'",
                Integer.class, MARK + "%")).isZero();
    }

    // ---- 3. list and get -----------------------------------------------------------------

    @Test void theListMasksNumbersFiltersByVerificationPagesByCursorAndNeverCarriesTrailContextOrLicenceRef() throws Exception {
        var owner = owner();
        String phone = newPhone();
        String a = created(owner, phone).get("supplier_id").asText();
        String b = created(owner, newPhone()).get("supplier_id").asText();
        String c = verifiedSupplier(owner);
        update(owner, a, profile(List.of("massage"), PLACE, 5000, LICENCE));

        JsonNode all = json(send(owner, "GET", "/v1/admin/suppliers?limit=100", null).andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store")), "AdminSupplierPage");
        JsonNode item = findItem(all, a);
        assertThat(item).isNotNull();
        assertThat(item.get("phone_masked").asText()).isEqualTo(mask(phone));
        assertThat(item.has("consent_trail")).isFalse();
        assertThat(item.has("open_context")).isFalse();
        assertThat(item.has("licence_ref")).isFalse();
        assertThat(item.get("licence_on_file").asBoolean()).isTrue();
        assertThat(all.toString()).doesNotContain(LICENCE);

        JsonNode verified = json(send(owner, "GET", "/v1/admin/suppliers?limit=100&verification=verified", null).andExpect(status().isOk()),
                "AdminSupplierPage");
        assertThat(findItem(verified, c)).isNotNull();
        assertThat(findItem(verified, b)).isNull();
        for (JsonNode each : verified.get("items")) assertThat(each.at("/verification/status").asText()).isEqualTo("verified");

        // Cursor paging: one row a page walks every supplier once, newest first, and ends with a null cursor.
        List<String> seen = new ArrayList<>();
        String cursor = null;
        do {
            JsonNode page = json(send(owner, "GET", "/v1/admin/suppliers?limit=1" + (cursor == null ? "" : "&cursor=" + cursor), null)
                    .andExpect(status().isOk()), "AdminSupplierPage");
            assertThat(page.get("items").size()).isLessThanOrEqualTo(1);
            for (JsonNode each : page.get("items")) seen.add(each.get("supplier_id").asText());
            cursor = page.get("next_cursor").isNull() ? null : page.get("next_cursor").asText();
        } while (cursor != null);
        assertThat(seen).doesNotHaveDuplicates().contains(a, b, c);
        assertThat(seen.indexOf(c)).isLessThan(seen.indexOf(b));
        assertThat(seen.indexOf(b)).isLessThan(seen.indexOf(a));

        var error = errorOf(send(owner, "GET", "/v1/admin/suppliers?cursor=not-a-cursor", null), 400);
        assertThat(error.get("code").asText()).isEqualTo("validation_failed");
    }

    @Test void everySupplierAndOptOutReadWritesAnAdminReadAuditRow() throws Exception {
        var owner = owner();
        String id = created(owner, newPhone()).get("supplier_id").asText();
        assertThat(readAudits(owner)).isZero();
        send(owner, "GET", "/v1/admin/suppliers", null).andExpect(status().isOk());
        assertThat(readAudits(owner)).isEqualTo(1);
        send(owner, "GET", "/v1/admin/suppliers/" + id, null).andExpect(status().isOk());
        assertThat(readAudits(owner)).isEqualTo(2);
        assertThat(jdbc.queryForObject("SELECT count(*) FROM audit_events WHERE actor_id=? AND action='admin.read' AND resource_id=?",
                Integer.class, owner.userId(), id)).isEqualTo(1);
        send(owner, "GET", "/v1/admin/opt-outs", null).andExpect(status().isOk());
        assertThat(readAudits(owner)).isEqualTo(3);
    }

    @Test void getByIdCarriesTheConsentTrailNewestFirstAndNeverOpenContextOrLicenceRef() throws Exception {
        var owner = owner();
        String id = created(owner, newPhone()).get("supplier_id").asText();
        update(owner, id, profile(List.of("massage"), PLACE, 5000, LICENCE));
        setConsent(id, "granted", "sms_keyword", "NULL");
        JsonNode supplier = json(send(owner, "GET", "/v1/admin/suppliers/" + id, null).andExpect(status().isOk()), "Supplier");
        JsonNode trail = supplier.get("consent_trail");
        assertThat(trail.size()).isEqualTo(2);
        assertThat(trail.get(0).get("state").asText()).isEqualTo("granted");
        assertThat(trail.get(0).get("source").asText()).isEqualTo("sms_keyword");
        assertThat(trail.get(1).get("source").asText()).isEqualTo("staff_entry");
        assertThat(supplier.at("/consent/state").asText()).isEqualTo("granted");
        assertThat(supplier.has("open_context")).isFalse();
        assertThat(supplier.has("licence_ref")).isFalse();
        assertThat(supplier.get("licence_on_file").asBoolean()).isTrue();
        assertThat(supplier.get("contact_name").asText()).isEqualTo(CONTACT);
    }

    @Test void anUnknownWellFormedSupplierIdAndAMalformedIdAreBothNotFoundOnEveryByIdRoute() throws Exception {
        var owner = owner();
        for (String id : List.of("sup_" + UUID.randomUUID(), "not-a-supplier", "usr_" + UUID.randomUUID(), "sup_bad_id!")) {
            errorOf(send(owner, "GET", "/v1/admin/suppliers/" + id, null), 404);
            errorOf(send(owner, "POST", "/v1/admin/suppliers/" + id, profile(List.of("barber"), PLACE, 5000, null)), 404);
            errorOf(decide(owner, id, "rejected", "No such business."), 404);
        }
    }

    // ---- 4. profile update ---------------------------------------------------------------

    @Test void updateStoresTheProfileReturnsASupplierWithLicenceOnFileAndWritesAnAuditRow() throws Exception {
        var owner = owner();
        String id = created(owner, newPhone()).get("supplier_id").asText();
        JsonNode supplier = update(owner, id, profile(List.of("massage"), PLACE, 5000, LICENCE));
        assertThat(supplier.get("skill_tags")).hasSize(1);
        assertThat(supplier.get("place_id").asText()).startsWith("plc_");
        assertThat(supplier.get("licence_on_file").asBoolean()).isTrue();
        assertThat(supplier.has("licence_ref")).isFalse();
        assertThat(supplier.has("consent_trail")).isFalse();
        assertThat(supplier.has("open_context")).isFalse();
        assertThat(audits("supplier.profile_updated", owner.userId(), id)).isEqualTo(1);
    }

    @Test void updateRejectsAnUnknownSkillAndALicencedSkillWithoutALicenceRef() throws Exception {
        var owner = owner();
        String id = created(owner, newPhone()).get("supplier_id").asText();
        JsonNode unknown = errorOf(send(owner, "POST", "/v1/admin/suppliers/" + id, profile(List.of("underwater_basket_weaving"), PLACE, 5000, null)), 400);
        assertDetail(unknown, "skill_tags", "unknown_skill");
        JsonNode licence = errorOf(send(owner, "POST", "/v1/admin/suppliers/" + id, profile(List.of("massage"), PLACE, 5000, null)), 400);
        assertDetail(licence, "licence_ref", "licence_required");
        assertThat(audits("supplier.profile_updated", owner.userId(), id)).isZero();
    }

    @Test void changingServicesOrServiceAreaOfAVerifiedSupplierReturnsItToPendingVerificationAndIsAudited() throws Exception {
        for (String changed : List.of("skills", "radius", "place")) {
            // A fresh owner each round: three rounds of four writes would pass the 10-write limit.
            var owner = owner();
            String id = verifiedSupplier(owner);
            // verifiedSupplier() already wrote one profile update; count only the change under test.
            int before = audits("supplier.profile_updated", owner.userId(), id);
            String body = switch (changed) {
                case "skills" -> profile(List.of("barber", "braids"), PLACE, 5000, null);
                case "radius" -> profile(List.of("barber"), PLACE, 8000, null);
                default -> profile(List.of("barber"), OTHER_PLACE, 5000, null);
            };
            JsonNode supplier = update(owner, id, body);
            assertThat(supplier.at("/verification/status").asText()).as(changed).isEqualTo("pending_verification");
            assertThat(verificationOf(id)).as(changed).isEqualTo("pending_verification");
            assertThat(audits("supplier.profile_updated", owner.userId(), id) - before).as(changed).isEqualTo(1);
        }
    }

    @Test void anUnchangedProfileResubmittedLeavesAVerifiedSupplierVerified() throws Exception {
        var owner = owner();
        String id = verifiedSupplier(owner);
        update(owner, id, profile(List.of("barber"), PLACE, 5000, null));
        assertThat(verificationOf(id)).isEqualTo("verified");
    }

    // ---- 5. verification -----------------------------------------------------------------

    @Test void verifiedWithoutServicesHoursAndAPlaceIsProfileIncompleteOnTheStatusField() throws Exception {
        var owner = owner();
        String id = created(owner, newPhone()).get("supplier_id").asText();
        JsonNode error = errorOf(decide(owner, id, "verified", "Visited the shop."), 400);
        assertDetail(error, "status", "profile_incomplete");
        assertThat(verificationOf(id)).isEqualTo("pending_verification");
        // Rejecting does not need a profile.
        json(decide(owner, id, "rejected", "Not a real business.").andExpect(status().isOk()), "Supplier");
    }

    @Test void verifyingSuspendingReinstatingAndRejectingEachWriteAnAuditRowWithTheReason() throws Exception {
        var owner = owner();
        String id = created(owner, newPhone()).get("supplier_id").asText();
        update(owner, id, profile(List.of("barber"), PLACE, 5000, null));
        JsonNode verified = json(decide(owner, id, "verified", "Visited the shop.").andExpect(status().isOk()), "Supplier");
        assertThat(verified.at("/verification/status").asText()).isEqualTo("verified");
        assertThat(verified.at("/verification/reason").asText()).isEqualTo("Visited the shop.");
        assertThat(verified.at("/verification/decided_at").asText()).isNotBlank();
        assertThat(verified.has("consent_trail")).isFalse();
        assertThat(verified.has("open_context")).isFalse();
        JsonNode suspended = json(decide(owner, id, "suspended", "Customer complaint.").andExpect(status().isOk()), "Supplier");
        assertThat(suspended.at("/verification/status").asText()).isEqualTo("suspended");
        JsonNode reinstated = json(decide(owner, id, "verified", "Complaint resolved.").andExpect(status().isOk()), "Supplier");
        assertThat(reinstated.at("/verification/status").asText()).isEqualTo("verified");
        JsonNode rejected = json(decide(owner, id, "rejected", "Closed down.").andExpect(status().isOk()), "Supplier");
        assertThat(rejected.at("/verification/status").asText()).isEqualTo("rejected");
        assertThat(jdbc.queryForList("SELECT reason FROM audit_events WHERE action='supplier.verification' AND actor_id=? AND resource_id=? ORDER BY id",
                String.class, owner.userId(), id)).containsExactly("Visited the shop.", "Customer complaint.", "Complaint resolved.", "Closed down.");
    }

    @Test void verificationRejectsAnUnknownStatusAShortReasonAndTheStatePendingVerification() throws Exception {
        var owner = owner();
        String id = created(owner, newPhone()).get("supplier_id").asText();
        errorOf(decide(owner, id, "granted", "Visited the shop."), 400);
        errorOf(decide(owner, id, "pending_verification", "Visited the shop."), 400);
        errorOf(decide(owner, id, "rejected", "no"), 400);
        assertDetail(errorOf(decide(owner, id, "rejected", "Owner said call 5550142."), 400), "reason", "invalid");
        assertThat(verificationOf(id)).isEqualTo("pending_verification");
    }

    // ---- 6. opt-outs ---------------------------------------------------------------------

    @Test void optOutsListRevokedAndStillPausedSuppliersMaskedWithTheirLatestSourceAndLeaveOutElapsedPausesAndPendingOnes() throws Exception {
        var owner = owner();
        String revokedPhone = newPhone(), pausedPhone = newPhone();
        String revoked = created(owner, revokedPhone).get("supplier_id").asText();
        String paused = created(owner, pausedPhone).get("supplier_id").asText();
        String elapsed = created(owner, newPhone()).get("supplier_id").asText();
        String pending = created(owner, newPhone()).get("supplier_id").asText();
        setConsent(revoked, "revoked", "carrier", "NULL");
        setConsent(paused, "paused", "sms_keyword", "now() + interval '1 day'");
        setConsent(elapsed, "paused", "sms_keyword", "now() - interval '1 hour'");
        JsonNode page = json(send(owner, "GET", "/v1/admin/opt-outs?limit=100", null).andExpect(status().isOk()), "AdminOptOutPage");
        JsonNode r = findItem(page, revoked), p = findItem(page, paused);
        assertThat(r).isNotNull();
        assertThat(r.get("state").asText()).isEqualTo("revoked");
        assertThat(r.get("source").asText()).isEqualTo("carrier");
        assertThat(r.get("phone_masked").asText()).isEqualTo(mask(revokedPhone));
        assertThat(r.has("paused_until")).isFalse();
        assertThat(p).isNotNull();
        assertThat(p.get("state").asText()).isEqualTo("paused");
        assertThat(p.get("source").asText()).isEqualTo("sms_keyword");
        assertThat(p.get("phone_masked").asText()).isEqualTo(mask(pausedPhone));
        assertThat(p.get("paused_until").asText()).isNotBlank();
        assertThat(findItem(page, elapsed)).as("an elapsed pause is not an opt-out").isNull();
        assertThat(findItem(page, pending)).isNull();
    }

    // ---- 7. per-staff limits -------------------------------------------------------------

    @Test void theThirtyFirstSupplierReadInAWindowFromOneStaffMemberIsRateLimitedWithRetryAfter() throws Exception {
        var member = staffMember("staff", true);
        for (int n = 0; n < 30; n++) send(member, "GET", "/v1/admin/suppliers?limit=1", null).andExpect(status().isOk());
        assertRateLimited(send(member, "GET", "/v1/admin/suppliers?limit=1", null));
        // The limit is per staff member: a second one is not held back.
        send(staffMember("staff", true), "GET", "/v1/admin/suppliers?limit=1", null).andExpect(status().isOk());
    }

    @Test void theEleventhSupplierWriteInAWindowFromOneStaffMemberIsRateLimitedWithRetryAfter() throws Exception {
        var owner = owner();
        String unknown = "sup_" + UUID.randomUUID();
        for (int n = 0; n < 10; n++) errorOf(decide(owner, unknown, "rejected", "Under review."), 404);
        assertRateLimited(decide(owner, unknown, "rejected", "Under review."));
        // Writes are counted before the role check, so a non-owner past the limit is limited too.
        var member = staffMember("staff", true);
        for (int n = 0; n < 10; n++) errorOf(decide(member, unknown, "rejected", "Under review."), 403);
        assertRateLimited(decide(member, unknown, "rejected", "Under review."));
    }

    // ---- 8. the log ----------------------------------------------------------------------

    @Test void aWholeSupplierSceneLeavesNoPhoneContactNameReasonLicenceTokenOrStaffIdInTheLog(CapturedOutput output) throws Exception {
        String logger = "org.springframework.web";
        var logging = LoggingSystem.get(getClass().getClassLoader());
        var previous = logging.getLoggerConfiguration(logger).getConfiguredLevel();
        logging.setLogLevel(logger, LogLevel.DEBUG);
        try {
            var owner = owner();
            String optInPhone = newPhone(), staffPhone = newPhone();
            mvc.perform(MockMvcRequestBuilders.post("/v1/suppliers/opt-in").with(r -> { r.setRemoteAddr(UUID.randomUUID().toString()); return r; })
                    .contentType(MediaType.APPLICATION_JSON).header("Idempotency-Key", "k-" + UUID.randomUUID())
                    .content("{\"business_name\":\"" + name() + "\",\"phone\":\"" + optInPhone + "\",\"consent_version\":\"" + VERSION
                            + "\",\"consent\":true}")).andExpect(status().isAccepted());
            String id = created(owner, staffPhone).get("supplier_id").asText();
            update(owner, id, profile(List.of("massage"), PLACE, 5000, LICENCE));
            json(decide(owner, id, "verified", REASON).andExpect(status().isOk()), "Supplier");
            send(owner, "GET", "/v1/admin/suppliers", null).andExpect(status().isOk());
            send(owner, "GET", "/v1/admin/suppliers/" + id, null).andExpect(status().isOk());
            setConsent(id, "revoked", "sms_keyword", "NULL");
            send(owner, "GET", "/v1/admin/opt-outs", null).andExpect(status().isOk());

            String logged = output.getAll();
            List<String> secrets = new ArrayList<>();
            for (String phone : List.of(optInPhone, staffPhone)) {
                secrets.add(phone);
                secrets.add(phone.substring(1));
                secrets.add(phone.substring(2));
            }
            secrets.addAll(List.of(CONTACT, "Zephyrwick", REASON, "Crimson ledger", LICENCE, "Bearer ", owner.userId()));
            for (String secret : secrets) {
                assertThat(logged).as("a sensitive value reached the log").doesNotContain(secret);
            }
            assertThat(logged).contains("request_id=").doesNotContain("request_id=null");
        } finally {
            logging.setLogLevel(logger, previous);
        }
    }
}
