package app.plug.request;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class CustomSkillsTest {
    @Test
    void keywordsAreTheMeaningfulSingularWords() {
        assertEquals(List.of("crochet", "loc"), CustomSkills.keywords("Crochet Locs"));
        assertEquals(List.of("pottery"), CustomSkills.keywords("pottery classes"));
        assertEquals(List.of("crochet", "loc"), CustomSkills.keywords("I need someone to do crochet locs tomorrow under $80"));
        assertEquals(List.of("drone", "photography"), CustomSkills.keywords("drone photography"));
        assertEquals(List.of("chimney", "sweep"), CustomSkills.keywords("Chimney sweeping"));
        assertEquals(List.of("sweep", "chimney"), CustomSkills.keywords("Can someone sweep my chimney tomorrow?"));
        assertTrue(CustomSkills.keywords("I need help today please").isEmpty());
    }

    @Test
    void anAskNamingNoListedSkillIsLabelledInThePersonsOwnWords() {
        assertEquals("Regrout bathroom tiles", CustomSkills.labelFrom("Someone to regrout my bathroom tiles tomorrow under $80"));
        assertEquals("Fix garden gate", CustomSkills.labelFrom("I need someone to fix my garden gate this weekend"));
        assertEquals("Chimney", CustomSkills.labelFrom("Is anyone free to look at my chimney?"));
        assertEquals("Assemble IKEA wardrobe", CustomSkills.labelFrom("Can someone assemble my IKEA wardrobe within 5 miles"));
        for (String vague : List.of("Something", "I need help with something", "Can someone do a favor for me today",
                "Fix it please", "Need someone now", "")) {
            assertEquals(null, CustomSkills.labelFrom(vague), vague);
        }
        assertEquals("Tile regrouting", CustomSkills.cleanLabel("  tile   regrouting "));
        for (String bad : List.of("ab", "x".repeat(41), "tiles\u0000", "<script>", "something", "stuff and things")) {
            assertEquals(null, CustomSkills.cleanLabel(bad), bad);
        }
    }

    @Test
    void tagIsStableAndFitsTheCategoryPattern() {
        assertEquals("custom_crochet_loc", CustomSkills.tag(CustomSkills.keywords("crochet locs")));
        assertEquals(CustomSkills.tag(CustomSkills.keywords("Crochet LOCS")), CustomSkills.tag(CustomSkills.keywords("crochet locs")));
        String longTag = CustomSkills.tag(CustomSkills.keywords("antique gramophone restoration and calibration specialist"));
        assertTrue(longTag.matches("custom_[a-z0-9_]{1,33}"), longTag);
    }

    @Test
    void lossyLabelsDoNotAliasOtherSkills() {
        String first = CustomSkills.tag(List.of("abcdefghijklmnopqrstuvwxyzabcdefg", "one"));
        String second = CustomSkills.tag(List.of("abcdefghijklmnopqrstuvwxyzabcdefg", "two"));
        assertNotEquals(first, second);
        String nonLatin = CustomSkills.tag(List.of("家具修复"));
        assertNotEquals(nonLatin, CustomSkills.tag(List.of("庭园设计")));
        assertEquals(nonLatin, CustomSkills.tag(List.of("家具修复")));
        for (String tag : List.of(first, second, nonLatin)) assertTrue(tag.matches("custom_[a-z0-9_]{1,33}"), tag);
    }

    @Test
    void everyListedSkillPhrasePassesTheRestrictedIntentPolicy() {
        var policy = new RestrictedIntentPolicy();
        List<String> refused = new ArrayList<>();
        for (var skill : SkillVocabulary.load().all()) {
            if (policy.refusal("I do " + skill.display().toLowerCase()).isPresent()) refused.add(skill.tag());
        }
        assertEquals(List.of(), refused);
    }
}
