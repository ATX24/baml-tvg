import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import static org.junit.jupiter.api.Assertions.*;

import baml_client.Globals;
import baml_client.Functions;
import baml_client.Types;
import baml_client.Unions;
import com.boundaryml.baml.BamlRuntime;
import com.boundaryml.baml.BamlStream;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

/**
 * Integration tests for BAML Java client.
 *
 * <p>All tests in this class require:
 * <ul>
 *   <li>{@code OPENAI_API_KEY} — set to a valid OpenAI key</li>
 *   <li>{@code BAML_LIBRARY_PATH} — path to libbaml_cffi.so/dylib/dll</li>
 *   <li>Generated baml_client (run {@code baml-cli generate --from ../baml_src})</li>
 * </ul>
 *
 * <p>Tests are skipped automatically when {@code OPENAI_API_KEY} is not set.
 */
@EnabledIfEnvironmentVariable(named = "OPENAI_API_KEY", matches = ".+",
    disabledReason = "OPENAI_API_KEY not set — skipping live LLM integration tests")
public class WorkflowTest {
    private static Functions functions;

    @BeforeAll
    public static void setup() {
        BamlRuntime runtime = Globals.getRuntime();
        functions = new Functions(runtime);
    }

    @Test
    public void testLLMEcho() throws Exception {
        // Requires: baml-cli generate --from ../baml_src, BAML_LIBRARY_PATH, OPENAI_API_KEY
        String result = functions.LLMEcho("Hello, world!");
        assertNotNull(result);
        assertTrue(result.contains("Hello") || result.contains("hello"),
            "LLMEcho should echo the input; got: " + result);
    }

    @Test
    public void testDescribePerson() throws Exception {
        Types.Person person = new Types.Person();
        person.setName("Ada");
        person.setAge(37L);

        String result = functions.DescribePerson(person);
        assertNotNull(result);
        assertTrue(result.contains("Ada") || result.contains("ada"),
            "DescribePerson should mention the name; got: " + result);
    }

    @Test
    public void testClassifyMood() throws Exception {
        String result = functions.ClassifyMood("I am very happy today!");
        assertNotNull(result);
        String upper = result.trim().toUpperCase();
        assertTrue(upper.contains("HAPPY") || upper.contains("SAD"),
            "ClassifyMood should return HAPPY or SAD; got: " + result);
    }

    @Test
    public void testUseIntOrStringWithUnionVariants() throws Exception {
        Unions.Union2IntOrString asInt = Unions.Union2IntOrString.ofVariant0(42L);
        String resultInt = functions.UseIntOrString(asInt);
        assertNotNull(resultInt);

        Unions.Union2IntOrString asString = Unions.Union2IntOrString.ofVariant1("forty two");
        String resultString = functions.UseIntOrString(asString);
        assertNotNull(resultString);
    }

    // -------------------------------------------------------------------------
    // Async tests
    // -------------------------------------------------------------------------

    @Test
    public void testLLMEchoAsync() throws Exception {
        CompletableFuture<String> future = functions.LLMEchoAsync("Hello async!");
        assertNotNull(future, "LLMEchoAsync must return a non-null future");

        String result = future.get(60, TimeUnit.SECONDS);
        assertNotNull(result);
        assertFalse(result.isEmpty(), "Async result should not be empty");
    }

    @Test
    public void testLLMEchoAsync_parallelCalls() throws Exception {
        // Fire two LLM calls concurrently and verify both complete independently.
        CompletableFuture<String> f1 = functions.LLMEchoAsync("Parallel call one");
        CompletableFuture<String> f2 = functions.LLMEchoAsync("Parallel call two");

        CompletableFuture.allOf(f1, f2).get(60, TimeUnit.SECONDS);

        String r1 = f1.get();
        String r2 = f2.get();
        assertNotNull(r1, "First parallel async result should not be null");
        assertNotNull(r2, "Second parallel async result should not be null");
        assertFalse(r1.isEmpty());
        assertFalse(r2.isEmpty());
    }

    @Test
    public void testLLMEchoAsync_completesWithinTimeout() throws Exception {
        // Verify that an async call completes within a reasonable timeout and
        // returns a non-empty string — guards against silent hangs.
        CompletableFuture<String> future = functions.LLMEchoAsync("timeout guard");
        assertNotNull(future, "LLMEchoAsync must return a non-null future");

        String result = future.get(60, TimeUnit.SECONDS);
        assertNotNull(result, "Result should not be null");
        assertFalse(result.isEmpty(), "Result should not be empty");
    }

    // -------------------------------------------------------------------------
    // Streaming tests
    // -------------------------------------------------------------------------

    @Test
    public void testLLMEchoStream_collectsPartials() throws Exception {
        BamlStream<String, String> stream = functions.LLMEchoStream("Hello streaming!");

        List<String> partials = new ArrayList<>();
        for (String chunk : stream) {
            assertNotNull(chunk, "Partial chunk should not be null");
            partials.add(chunk);
        }

        // At least one partial should have been emitted.
        assertFalse(partials.isEmpty(), "Stream should emit at least one partial result");

        String finalResult = stream.getFinalResult();
        assertNotNull(finalResult, "Final result should not be null");
        assertFalse(finalResult.isEmpty(), "Final result should not be empty");
    }

    @Test
    public void testLLMEchoStream_getFinalResult_withoutIterating() throws Exception {
        // Callers should be able to skip iteration and go straight to the final result.
        BamlStream<String, String> stream = functions.LLMEchoStream("Skip partials");
        String finalResult = stream.getFinalResult();
        assertNotNull(finalResult, "Final result without iterating should not be null");
        assertFalse(finalResult.isEmpty());
    }

    @Test
    public void testLLMEchoStream_getFinalResultAsync() throws Exception {
        BamlStream<String, String> stream = functions.LLMEchoStream("Async final");

        // getFinalResultAsync() should not block the calling thread.
        CompletableFuture<String> future = stream.getFinalResultAsync();
        assertNotNull(future, "CompletableFuture should not be null");

        // Give the stream up to 60 s to complete (LLM call).
        String finalResult = future.get(60, TimeUnit.SECONDS);
        assertNotNull(finalResult);
        assertFalse(finalResult.isEmpty());
    }

    @Test
    public void testDescribePersonStream() throws Exception {
        Types.Person person = new Types.Person();
        person.setName("Grace");
        person.setAge(45L);

        BamlStream<String, String> stream = functions.DescribePersonStream(person);

        // Drain the stream so it completes.
        for (String chunk : stream) {
            assertNotNull(chunk);
        }

        String finalResult = stream.getFinalResult();
        assertNotNull(finalResult);
        assertTrue(
            finalResult.contains("Grace") || finalResult.contains("grace"),
            "DescribePersonStream final result should mention the name; got: " + finalResult
        );
    }
}
