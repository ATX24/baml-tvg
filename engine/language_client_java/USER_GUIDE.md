# BAML Java SDK — User Guide

This guide walks you through using the BAML Java SDK from scratch: defining your AI functions in BAML, generating a type-safe Java client, and calling LLMs with both blocking and streaming APIs.

---

## Table of Contents

1. [What is BAML?](#what-is-baml)
2. [Prerequisites](#prerequisites)
3. [Step 1: Add the Dependency](#step-1-add-the-dependency)
4. [Step 2: Install the Native Library](#step-2-install-the-native-library)
5. [Step 3: Write Your BAML Files](#step-3-write-your-baml-files)
6. [Step 4: Generate the Java Client](#step-4-generate-the-java-client)
7. [Step 5: Wire Up the Source Tree](#step-5-wire-up-the-source-tree)
8. [Step 6: Make a Blocking Call](#step-6-make-a-blocking-call)
9. [Step 7: Make a Streaming Call](#step-7-make-a-streaming-call)
10. [Step 8: Handle Errors](#step-8-handle-errors)
11. [Step 9: Use Retry Policies](#step-9-use-retry-policies)
12. [Step 10: Override Clients at Runtime](#step-10-override-clients-at-runtime)
13. [Step 11: Reactive Streams (Optional)](#step-11-reactive-streams-optional)
14. [Type Mapping Reference](#type-mapping-reference)
15. [Environment Variables Reference](#environment-variables-reference)
16. [Troubleshooting](#troubleshooting)

---

## What is BAML?

BAML (Boundary AI Markup Language) is a domain-specific language for defining LLM functions with strong types and structured prompts. You write function signatures and prompt templates in `.baml` files; a code generator (`baml-cli`) produces a fully-typed Java client. At runtime, the BAML Java SDK serializes your arguments, calls the LLM via a native Rust core, and deserializes the structured response back into Java objects.

**Key benefits:**
- Type-safe LLM calls — no manual JSON parsing
- Streaming built in — the same function works blocking or streaming
- Provider-agnostic — switch between OpenAI, Anthropic, Gemini, and others by changing one line in your BAML file
- Retry and fallback policies defined in BAML, not scattered through application code

---

## Prerequisites

| Tool | Minimum Version | How to Get |
|------|----------------|------------|
| Java | 11 | [adoptium.net](https://adoptium.net) |
| Maven or Gradle | Maven 3.6+ / Gradle 7+ | [maven.apache.org](https://maven.apache.org) / [gradle.org](https://gradle.org) |
| `baml-cli` | matching SDK version | See [install instructions](#installing-baml-cli) |
| `libbaml_cffi` | matching SDK version | See [Step 2](#step-2-install-the-native-library) |

### Installing baml-cli

`baml-cli` is the code generator. Install it by building from source:

```bash
cd engine
cargo build --release -p baml-cli
# Binary: engine/target/release/baml-cli
```

Or add it to your `PATH`:

```bash
export PATH="$PATH:/path/to/engine/target/release"
```

---

## Step 1: Add the Dependency

### Maven

Add to your `pom.xml`:

```xml
<dependency>
    <groupId>com.boundaryml</groupId>
    <artifactId>baml-runtime-java</artifactId>
    <version>0.219.0</version>
</dependency>
```

If the artifact is not yet on Maven Central, install it locally first (see the [Deployment Guide](DEPLOY_GUIDE.md)) and add `mavenLocal()` to your repositories:

```xml
<repositories>
    <repository>
        <id>local</id>
        <url>file://${user.home}/.m2/repository</url>
    </repository>
</repositories>
```

### Gradle

Add to your `build.gradle`:

```gradle
repositories {
    mavenLocal()   // only needed until published to Maven Central
    mavenCentral()
}

dependencies {
    implementation 'com.boundaryml:baml-runtime-java:0.219.0'
}
```

---

## Step 2: Install the Native Library

The Java SDK delegates to a native Rust library (`libbaml_cffi`) for all LLM logic. You must make this library available at runtime.

### Build from source

```bash
cd engine
cargo build --release -p baml_cffi
```

This produces:
- **Linux:** `engine/target/release/libbaml_cffi.so`
- **macOS:** `engine/target/release/libbaml_cffi.dylib`
- **Windows:** `engine/target/release/baml_cffi.dll`

> **Note:** The output is in the workspace-level `engine/target/release/`, not in a crate-local `target/` directory.

### Make it available at runtime

Set the `BAML_LIBRARY_PATH` environment variable to the full path of the library before starting your application:

```bash
# Linux
export BAML_LIBRARY_PATH=/path/to/engine/target/release/libbaml_cffi.so

# macOS
export BAML_LIBRARY_PATH=/path/to/engine/target/release/libbaml_cffi.dylib

# Windows (Git Bash or PowerShell)
export BAML_LIBRARY_PATH=C:/path/to/engine/target/release/baml_cffi.dll
```

If `BAML_LIBRARY_PATH` is not set, the SDK will attempt to find `libbaml_cffi` on the system library path (`LD_LIBRARY_PATH` on Linux, `DYLD_LIBRARY_PATH` on macOS, `PATH` on Windows).

---

## Step 3: Write Your BAML Files

Create a `baml_src/` directory at the root of your project. This is where all `.baml` files live.

### generators.baml

This file tells `baml-cli` how to generate your Java client.

```
baml_src/
└── generators.baml
```

```baml
// baml_src/generators.baml
generator lang_java {
  output_type java
  output_dir ".."            // relative to baml_src/; the client lands one level up
  version "0.219.0"
  client_package_name "baml_client"
}
```

| Field | Description |
|-------|-------------|
| `output_type` | Must be `java` |
| `output_dir` | Where `baml_client/` is written (relative to `baml_src/`) |
| `version` | Must match the `baml-runtime-java` version in your build file |
| `client_package_name` | Java package name for generated classes |

### main.baml

Define your LLM client and functions here.

```baml
// baml_src/main.baml

// Declare an LLM client
client<llm> Gemini {
  provider google-ai
  options {
    model "gemini-2.0-flash"
    api_key env.GOOGLE_API_KEY    // resolved from environment at call time
  }
}

// Define a typed function
function Summarize(text: string) -> string {
  client Gemini
  prompt #"
    Summarize the following text in one sentence:
    {{ text }}
  "#
}
```

**Supported providers:** `openai`, `anthropic`, `google-ai`, `azure-openai`, and others.

**Using environment variables in BAML:** `env.VAR_NAME` is resolved from the process environment at the time of each function call. The SDK automatically passes all environment variables from `System.getenv()` to the native runtime.

### Complex return types

BAML functions can return structured data, not just strings:

```baml
class SentimentResult {
  sentiment string
  confidence float
  explanation string
}

function AnalyzeSentiment(text: string) -> SentimentResult {
  client Gemini
  prompt #"
    Analyze the sentiment of the following text.
    Return a JSON object with "sentiment" (positive/negative/neutral),
    "confidence" (0.0 to 1.0), and "explanation".
    {{ text }}
    {{ ctx.output_format }}
  "#
}
```

The generated Java client will have a method:

```java
// Blocking
SentimentResult result = functions.AnalyzeSentiment(text);

// Streaming
BamlStream<SentimentResult, SentimentResult> stream = functions.AnalyzeSentimentStream(text);
```

---

## Step 4: Generate the Java Client

Run this command from your project root (or wherever `baml_src/` lives):

```bash
baml-cli generate --from baml_src
```

Output (three files in `baml_client/baml_client/`):

```
baml_client/
└── baml_client/
    ├── Functions.java       # One method per BAML function
    ├── Globals.java         # Singleton runtime accessor
    └── BamlSourceMap.java   # Embedded BAML source (do not edit)
```

**Re-run this command every time you change a `.baml` file.** The generated files should be committed to source control so that teammates do not need `baml-cli` installed to build the project.

> Generated files contain a header comment: `// This file was generated by BAML: please do not edit it.`

---

## Step 5: Wire Up the Source Tree

The generated `baml_client/` directory must be included as a source root in your build.

### Gradle

```gradle
sourceSets {
    main {
        java {
            srcDirs 'src/main/java', 'baml_client'
        }
    }
}
```

### Maven

```xml
<build>
    <plugins>
        <plugin>
            <groupId>org.codehaus.mojo</groupId>
            <artifactId>build-helper-maven-plugin</artifactId>
            <version>3.4.0</version>
            <executions>
                <execution>
                    <id>add-baml-client-sources</id>
                    <phase>generate-sources</phase>
                    <goals><goal>add-source</goal></goals>
                    <configuration>
                        <sources>
                            <source>${project.basedir}/baml_client</source>
                        </sources>
                    </configuration>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```

---

## Step 6: Make a Blocking Call

The generated `Globals` class provides a singleton `BamlRuntime`. Wrap it with `Functions` to call your BAML-defined functions.

```java
import baml_client.Functions;
import baml_client.Globals;
import com.boundaryml.baml.BamlRuntime;

public class Main {
    public static void main(String[] args) {
        BamlRuntime runtime = Globals.getRuntime();
        Functions functions = new Functions(runtime);

        String text = "BAML is a DSL for building reliable AI workflows.";
        String summary = functions.Summarize(text);

        System.out.println("Summary: " + summary);
    }
}
```

`Globals.getRuntime()` is thread-safe and lazily initializes the runtime on the first call. The runtime is a singleton for the lifetime of the process.

---

## Step 7: Make a Streaming Call

Every BAML function generates a `XxxStream` method that returns a `BamlStream<PartialType, FinalType>`. The stream starts immediately; partial tokens arrive as they are generated.

```java
import com.boundaryml.baml.BamlStream;

BamlStream<String, String> stream = functions.SummarizeStream(text);

// Iterate partial results as they arrive
System.out.print("Streaming: ");
for (String chunk : stream) {
    System.out.print(chunk);
    System.out.flush();
}
System.out.println();

// Get the final assembled result (blocks until complete)
String finalResult = stream.getFinalResult();
System.out.println("Final: " + finalResult);
```

### Async final result

If you want to process the final result without blocking the current thread:

```java
import java.util.concurrent.CompletableFuture;

BamlStream<String, String> stream = functions.SummarizeStream(text);

CompletableFuture<String> finalFuture = stream.getFinalResultAsync();

// Process partials on this thread while final result builds in the background
for (String chunk : stream) {
    System.out.print(chunk);
}

// Join when ready
String finalResult = finalFuture.join();
```

### Spring WebFlux / Project Reactor

If you use Spring WebFlux, the optional `BamlReactor` adapter converts a `BamlStream` to a `Flux`:

```xml
<!-- Add reactor-core if not already present -->
<dependency>
    <groupId>io.projectreactor</groupId>
    <artifactId>reactor-core</artifactId>
    <version>3.6.5</version>
</dependency>
```

```java
import com.boundaryml.baml.BamlReactor;
import reactor.core.publisher.Flux;

BamlStream<String, String> stream = functions.SummarizeStream(text);

// Turns partial events into a Flux running on Schedulers.boundedElastic()
Flux<String> flux = BamlReactor.toFlux(stream);

// Use in a Spring WebFlux endpoint
return ServerResponse.ok()
    .contentType(MediaType.TEXT_EVENT_STREAM)
    .body(flux, String.class);
```

---

## Step 8: Handle Errors

All BAML exceptions extend `com.boundaryml.baml.BamlException` (which is a `RuntimeException`). Catch specific subtypes for precise error handling.

### Exception hierarchy

```
BamlException
├── BamlValidationError      — LLM response failed schema validation
└── BamlClientError          — Error from the LLM provider
    ├── BamlRateLimitError   — HTTP 429 / rate limit exceeded
    ├── BamlTimeoutError     — Call exceeded time limit
    └── BamlProviderError    — Other HTTP errors (4xx, 5xx)
        └── getStatusCode()  — HTTP status code
```

### Example

```java
import com.boundaryml.baml.*;

try {
    String result = functions.Summarize(text);
    System.out.println(result);

} catch (BamlRateLimitError e) {
    System.err.println("Rate limit hit — back off and retry: " + e.getMessage());

} catch (BamlTimeoutError e) {
    System.err.println("LLM call timed out: " + e.getMessage());

} catch (BamlProviderError e) {
    System.err.printf("Provider error (HTTP %d): %s%n", e.getStatusCode(), e.getMessage());

} catch (BamlValidationError e) {
    System.err.println("LLM returned invalid schema: " + e.getMessage());

} catch (BamlException e) {
    System.err.println("Unexpected BAML error: " + e.getMessage());
}
```

Errors during streaming are thrown by `getFinalResult()` or by the `for` loop iterator:

```java
try {
    for (String chunk : stream) {
        System.out.print(chunk);
    }
    String final_ = stream.getFinalResult();
} catch (BamlException e) {
    System.err.println("Stream failed: " + e.getMessage());
}
```

---

## Step 9: Use Retry Policies

Configure automatic retry with exponential backoff when creating the runtime:

```java
import com.boundaryml.baml.BamlRuntime;
import com.boundaryml.baml.BamlRuntime.BamlRuntimeOptions;
import com.boundaryml.baml.BamlRuntime.RetryPolicy;
import java.time.Duration;

RetryPolicy retry = RetryPolicy.exponentialBackoff(
    3,                       // maxAttempts (first attempt + 2 retries)
    Duration.ofSeconds(30),  // maxDelay cap per attempt
    500L,                    // baseDelayMs for first retry
    2.0                      // multiplier (500ms → 1000ms → 2000ms, capped at 30s)
);

BamlRuntimeOptions options = BamlRuntimeOptions.builder()
    .retryPolicy(retry)
    .build();

BamlRuntime runtime = BamlRuntime.create(
    "./baml_src",
    BamlSourceMap.getSourceMap(),
    "{}",
    options
);
```

Retries apply only to blocking calls (`callFunctionParse`). Streaming calls (`callFunctionStream`) do not retry automatically.

---

## Step 10: Override Clients at Runtime

You can replace the LLM client defined in your `.baml` file at call time — useful for A/B testing, user-specific API keys, or dynamic model selection.

```java
import com.boundaryml.baml.BamlClientRegistry;
import com.boundaryml.baml.BamlClientOptions;
import com.boundaryml.baml.BamlEncoder;

// Build a client registry override
BamlClientRegistry registry = BamlClientRegistry.builder()
    .primary("FastModel")
    .client(BamlClientOptions.builder("FastModel")
        .provider("openai")
        .option("model", "gpt-4o-mini")
        .option("api_key", System.getenv("OPENAI_API_KEY"))
        .build())
    .build();

// Encode args with the registry override
java.util.Map<String, Object> kwargs = new java.util.LinkedHashMap<>();
kwargs.put("text", text);
byte[] encoded = BamlEncoder.encodeArgs(kwargs, registry);

// Call directly on the runtime
byte[] response = runtime.callFunctionParse("Summarize", encoded);
String result = (String) BamlDecoder.decodeResult(response);
```

> **Tip:** For most use cases, prefer controlling the client through `env.VAR_NAME` in your BAML file. Use `BamlClientRegistry` only when you need fully dynamic client selection (e.g., per-request API keys).

---

## Step 11: Reactive Streams (Optional)

`BamlReactor` requires `reactor-core` on the classpath (it is an optional dependency of `baml-runtime-java`). It does not require Spring; it works with any Reactor-based framework.

```java
Flux<String> partials = BamlReactor.toFlux(stream);

partials
    .doOnNext(chunk -> log.debug("Partial: {}", chunk))
    .doOnError(err -> log.error("Stream error", err))
    .blockLast(); // or subscribe(), return as ServerSentEvent, etc.
```

---

## Type Mapping Reference

### BAML types → Java types

| BAML Type | Java Type | Notes |
|-----------|-----------|-------|
| `string` | `String` | |
| `int` | `Long` | BAML integers are 64-bit |
| `float` | `Double` | |
| `bool` | `Boolean` | |
| `null` | `null` | |
| `string[]` | `List<Object>` | Elements decoded recursively |
| `MyClass` | `BamlClassValue` | `.getFields()` returns `Map<String, Object>` |
| `MyEnum` | `BamlEnumValue` | `.getValue()` returns the variant name as `String` |
| `MyClass \| string` | `BamlUnionValue` | `.getValue()` returns the matched variant |

> When BAML functions return simple `string`, the decoded Java type is directly `String`. When they return a complex class, cast the decoded result to `BamlClassValue` and access fields by name, or define Java POJOs and populate them from the field map.

### Java types → BAML (encoding)

`BamlEncoder.encodeArgs()` automatically maps:

| Java Type | Encoded As |
|-----------|------------|
| `String` | string |
| `Integer`, `Long`, `Short`, `Byte` | int (64-bit) |
| `Float`, `Double` | float (double precision) |
| `Boolean` | bool |
| `null` | null |
| `List<?>`, arrays | list |
| `Map<String, ?>` | map |
| `Enum` | enum (uses `.name()`) |
| POJO with JavaBean getters | class (field names from getters) |

---

## Environment Variables Reference

| Variable | Required | Description |
|----------|----------|-------------|
| `BAML_LIBRARY_PATH` | Yes (unless on system path) | Full path to `libbaml_cffi.so` / `.dylib` / `.dll` |
| `GOOGLE_API_KEY` | When using `google-ai` provider | Google AI Studio API key |
| `OPENAI_API_KEY` | When using `openai` provider | OpenAI API key |
| `ANTHROPIC_API_KEY` | When using `anthropic` provider | Anthropic API key |

LLM API keys are referenced in your `.baml` file with `env.VAR_NAME` and are resolved from `System.getenv()` at the time of each function call. You do not need to pass them to the `BamlRuntime` constructor.

### Passing API keys to a Gradle daemon

The Gradle daemon captures the environment at startup. If you export a variable after the daemon started, use one of:

```bash
# Option A: Pass as a project property (no daemon restart needed)
./gradlew run -PGOOGLE_API_KEY=your-key

# Option B: Kill the daemon and re-run
./gradlew --stop && ./gradlew run

# Option C: Always bypass the daemon
./gradlew run --no-daemon
```

The provided Gradle example forwards project properties automatically:

```gradle
run {
    environment System.getenv()
    ['GOOGLE_API_KEY', 'BAML_LIBRARY_PATH'].each { key ->
        if (project.hasProperty(key)) {
            environment key, project.getProperty(key)
        }
    }
}
```

---

## Project Layout

After following this guide, your project should look like:

```
my-project/
├── build.gradle (or pom.xml)
├── baml_src/
│   ├── generators.baml       ← codegen config
│   └── main.baml             ← client + function definitions
├── baml_client/              ← generated; commit to source control
│   └── baml_client/
│       ├── Functions.java
│       ├── Globals.java
│       └── BamlSourceMap.java
└── src/main/java/com/example/
    └── Main.java             ← your application code
```

---

## Troubleshooting

### `UnsatisfiedLinkError: Unable to load library 'baml_cffi'`

The native library cannot be found. Set `BAML_LIBRARY_PATH` to its full path:

```bash
export BAML_LIBRARY_PATH=/absolute/path/to/libbaml_cffi.so
```

### `Required environment variable 'FOO' is set but is empty`

The API key variable is set to an empty string. Check that your shell export is correct, or that the Gradle daemon has picked up the new value (see [Passing API keys to a Gradle daemon](#passing-api-keys-to-a-gradle-daemon)).

### `A BAML file must have the file extension .baml`

The generated `BamlSourceMap.java` is stale or corrupted. Re-run the generator:

```bash
baml-cli generate --from baml_src
```

### `Call did not complete: … LLM client failed with status code: NotSupported (403)`

The API key is invalid or not authorized for the model you requested. Verify the key is correct and the model name is supported by your account.

### `Cannot find symbol: class StreamState`

You are using a `baml-runtime-java` JAR that is older than the sources. Rebuild and reinstall:

```bash
cd engine/language_client_java
mvn install -DskipTests
```
