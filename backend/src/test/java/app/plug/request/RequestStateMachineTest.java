package app.plug.request;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import java.util.Set;
import org.junit.jupiter.api.Test;

class RequestStateMachineTest {
    // Independent table transcribed from the contract: every one of the 121 pairs is checked.
    @Test void everyLegalAndIllegalTransitionIncludingSupplierOnlyConfirmation() {
        Set<String> legal=Set.of("draft:submitted","draft:expired","draft:canceled",
                "submitted:routed","submitted:blocked","submitted:canceled",
                "routed:awaiting_responses","routed:expired","routed:canceled",
                "awaiting_responses:ranked","awaiting_responses:expired","awaiting_responses:canceled",
                "ranked:user_selected","ranked:expired","ranked:canceled",
                "user_selected:confirmed","user_selected:expired","user_selected:canceled",
                "confirmed:completed","confirmed:canceled");
        for(String current:RequestStateMachine.STATES) for(String next:RequestStateMachine.STATES) {
            assertThat(RequestStateMachine.allows(current,next,true)).as(current+"->"+next).isEqualTo(legal.contains(current+":"+next));
            if(!legal.contains(current+":"+next)) assertThatThrownBy(()->RequestStateMachine.require(current,next,true))
                    .isInstanceOf(IllegalStateException.class);
        }
        assertThat(RequestStateMachine.allows("user_selected","confirmed",false)).isFalse();
        assertThat(RequestStateMachine.allows("unknown","submitted",true)).isFalse();
    }
}
