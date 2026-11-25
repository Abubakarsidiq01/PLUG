package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class SupplierPhonesTest {
    static final String KEY = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    final SupplierPhones phones = new SupplierPhones("unit-test-pepper-unit-test-pepper-0000", KEY);

    @Test void encryptsWithAFreshNonceAndDecryptsBack() {
        String aad = phones.hash("+12125550142");
        byte[] one = phones.encrypt("+12125550142", aad), two = phones.encrypt("+12125550142", aad);
        assertThat(one).isNotEqualTo(two).hasSize(12 + 12 + 16);
        assertThat(phones.decrypt(one, aad)).isEqualTo("+12125550142");
        one[20] ^= 1;
        assertThatThrownBy(() -> phones.decrypt(one, aad)).isInstanceOf(IllegalStateException.class);
    }

    @Test void aCiphertextSwappedOntoAnotherRowFailsToDecrypt() {
        byte[] sealed = phones.encrypt("+12125550142", phones.hash("+12125550142"));
        assertThatThrownBy(() -> phones.decrypt(sealed, phones.hash("+13125550199"))).isInstanceOf(IllegalStateException.class);
    }

    @Test void hashesAreKeyedAndDomainSeparatedAndTheMaskShowsTwoDigits() {
        assertThat(phones.hash("+12125550142")).isEqualTo(phones.hash("+12125550142"))
                .isNotEqualTo(phones.keyed("+12125550142")).doesNotContain("2125550142");
        assertThat(SupplierPhones.mask("42")).isEqualTo("+1 *** *** **42");
    }

    @Test void refusesAMissingOrShortKeyAndAShortPepper() {
        assertThatThrownBy(() -> new SupplierPhones("unit-test-pepper-unit-test-pepper-0000", "")).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> new SupplierPhones("unit-test-pepper-unit-test-pepper-0000", "AAAA")).isInstanceOf(IllegalStateException.class);
        assertThatThrownBy(() -> new SupplierPhones("short", KEY)).isInstanceOf(IllegalStateException.class);
    }
}
