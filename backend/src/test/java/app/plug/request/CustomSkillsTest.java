package app.plug.request;

import static org.junit.jupiter.api.Assertions.assertEquals;
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
    void tagIsStableAndFitsTheCategoryPattern() {
        assertEquals("custom_crochet_loc", CustomSkills.tag(CustomSkills.keywords("crochet locs")));
        assertEquals(CustomSkills.tag(CustomSkills.keywords("Crochet LOCS")), CustomSkills.tag(CustomSkills.keywords("crochet locs")));
        String longTag = CustomSkills.tag(CustomSkills.keywords("antique gramophone restoration and calibration specialist"));
        assertTrue(longTag.matches("custom_[a-z0-9_]{1,33}"), longTag);
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
