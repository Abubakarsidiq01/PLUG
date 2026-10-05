package app.plug.request;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import org.junit.jupiter.api.Test;

class SkillVocabularyTest {
    private final SkillVocabulary vocabulary = SkillVocabulary.load();

    private List<String> tags(String text) {
        return vocabulary.findIn(text).stream().map(SkillVocabulary.Skill::tag).toList();
    }

    @Test
    void actionFirstPhrasingMapsOntoListedSkills() {
        assertEquals(List.of("phone_repair"), tags("I repair phones"));
        assertEquals(List.of("phone_repair"), tags("I fix my phone"));
        assertEquals(List.of("laptop_repair"), tags("I fix laptops"));
        assertEquals(List.of("bike_repair"), tags("I repair bikes"));
        assertEquals(List.of("house_cleaning"), tags("I clean houses"));
        assertEquals(List.of("dog_walking"), tags("I walk dogs"));
        assertEquals(List.of("tv_mounting"), tags("I mount TVs"));
        assertEquals(List.of("furniture_assembly"), tags("I assemble furniture"));
        assertEquals(List.of("phone_repair", "laptop_repair"), tags("I repair phones and fix laptops"));
    }

    @Test
    void actionFirstPhrasesAreNotLeftAsUnmatchedTerms() {
        assertTrue(vocabulary.unmatchedTerms("I repair phones").isEmpty());
    }

    @Test
    void actionWordsAloneNeverInventASkill() {
        assertTrue(tags("I fix things and clean up").isEmpty());
        assertTrue(tags("I repair").isEmpty());
    }
}
