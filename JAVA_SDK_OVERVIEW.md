# BAML Java SDK — Architecture & Usage Overview

## What It Is

The BAML Java SDK lets you call BAML-defined LLM functions from Java. It consists of two layers:

1. **`baml-runtime-java`** — a pure-Java library that bridges to the core Rust runtime via JNA (Java Native Access)
2. **Generated `baml_client`** — Java source files produced by `baml-cli generate` from your `.baml` schema files

---

## Architecture

```
Your Java Code
      │
      ▼
baml_client/Functions.java       ← generated; one method per BAML function
      │  BamlEncoder.encodeArgs()
      │  BamlDecoder.decodeResult()
      ▼
BamlRuntime (JNA bridge)
      │  JNA → libbaml_cffi.so / .dylib / .dll
      ▼
Rust CFFI layer (engine/language_client_cffi)
      │
      ▼
Core BAML Rust runtime
```

### Key Classes (`com.boundaryml.baml`)

| Class | Role |
|---|---|
| `BamlRuntime` | Loads the native library, manages call lifecycle, callback dispatch, retry logic |
| `BamlEncoder` | Serializes Java objects → `HostFunctionArguments` protobuf |
| `BamlDecoder` | Deserializes `CFFIValueHolder` protobuf → Java objects |
| `BamlStream<PartialT, FinalT>` | Pull-based streaming wrapper backed by a `BlockingQueue` |
| `BamlException` | Base runtime exception; typed subclasses below |
| `BamlRateLimitError` | 429 / rate limit responses |
| `BamlTimeoutError` | Timeout errors from the native layer |
| `BamlValidationError` | Parse / validation failures |
| `BamlProviderError` | LLM provider / API errors |
| `BamlClientRegistry` | Per-call LLM client override (name, provider, options) |
| `BamlReactor` | Optional Project Reactor adapter — converts `BamlStream` to `Flux` |

### Generated `baml_client` Files

| File | Contents |
|---|---|
| `Globals.java` | Singleton `BamlRuntime`; reads `baml.root.path` system property |
| `Functions.java` | One blocking, one async, one streaming method per BAML function |
| `Types.java` | BAML class types as JavaBean POJOs |
| `Enums.java` | BAML enum types as Java enums |
| `Unions.java` | Union type stubs (runtime dispatch via `BamlDecoder`) |
| `BamlSourceMap.java` | Inlined `.baml` source files as a JSON string |

### Call Lifecycle

**Blocking call**
```
callFunctionParse()
  → doCallFunctionParse()
  → cffi.call_function_from_c()        // registers a CompletableFuture in pendingCalls
  ← RESULT_CALLBACK fires (native thread)
  ← future.get(5 min)
  → BamlDecoder.decodeResult()
```

**Async call**
```
callFunctionParseAsync()
  → CompletableFuture.supplyAsync(callFunctionParse, ASYNC_EXECUTOR)
     (daemon thread pool: "baml-async-N")
```

**Streaming call**
```
callFunctionStream()
  → cffi.call_function_stream_from_c()  // registers a StreamState in pendingStreams
  ← RESULT_CALLBACK fires N times (isDone=0 → partial, isDone=1 → final)
  → BamlStream.iterator() / getFinalResult() / getFinalResultAsync()
```

### Codegen Pipeline

```
.baml source files
      │
      ▼
BAML IR (Intermediate Representation)
      │
      ▼  engine/generators/languages/java/
   lib.rs          — IR traversal
   ir_to_java/     — type mapping (TypeJava)
   functions.rs    — Askama templates → Functions.java, Globals.java,
                     Types.java, Enums.java, Unions.java, BamlSourceMap.java
```

---

## Published Artifact

The runtime is published to Maven Central:

**Maven:**
```xml
<dependency>
    <groupId>io.github.arckansupada</groupId>
    <artifactId>baml-runtime-java</artifactId>
    <version>0.220.0</version>
</dependency>
```

**Gradle:**
```groovy
implementation 'io.github.arckansupada:baml-runtime-java:0.220.0'
```

---

## Running the Examples

### Prerequisites (one-time setup)

```bash
# 1. Build the native CFFI library
cd engine
cargo build --release -p baml_cffi
# Output: engine/target/release/libbaml_cffi.so  (Linux)
#                              libbaml_cffi.dylib (macOS)
#                              baml_cffi.dll      (Windows)

# 2. Build baml-cli
cargo build --release -p baml-cli
```

> The Java runtime JAR is now pulled from Maven Central automatically — no local `mvn install` needed.

### Gradle Example

```bash
cd examples/java-gradle

# Generate baml_client from the schema
../../engine/target/release/baml-cli generate --from baml_src

# Set environment variables
export BAML_LIBRARY_PATH=../../engine/target/release/libbaml_cffi.so
export OPENAI_API_KEY=sk-...

# Run (stop any stale Gradle daemon first to pick up new env vars)
./gradlew --stop
./gradlew run
```

**Expected output**
```
=== Blocking call ===
Summary: BAML is a domain-specific language for building type-safe LLM workflows.

=== Async call ===
Async result: BAML is a domain-specific language for building type-safe LLM workflows.

=== Streaming call ===
Partial: BAML is a domain-specific...
Stream final (async): BAML is a domain-specific language for building type-safe LLM workflows.
```

### Maven Example

```bash
cd examples/java-maven

../../engine/target/release/baml-cli generate --from baml_src

export BAML_LIBRARY_PATH=../../engine/target/release/libbaml_cffi.so
export OPENAI_API_KEY=sk-...

mvn compile exec:java -Dexec.mainClass=com.example.Main
```

---

## Running the Integration Tests

```bash
# Option A: full run (installs JAR, generates client, runs tests)
./tools/bctl integ-tests --suite java

# Option B: skip the mvn install step if the JAR is already installed
# (edit tools/bctl_src/integ_tests.py and pass skip_install=True, or call directly)
cd integ-tests/java
export BAML_LIBRARY_PATH=../../engine/target/release/libbaml_cffi.so
export OPENAI_API_KEY=sk-...
mvn test
```

Tests are in `integ-tests/java/src/test/java/WorkflowTest.java` and are skipped automatically when `OPENAI_API_KEY` is not set.

---

## Version

Current published version: **`0.220.0`** (`io.github.arckansupada:baml-runtime-java`)

View on Maven Central: https://central.sonatype.com/artifact/io.github.arckansupada/baml-runtime-java

---

## Configuring rootPath

By default `Globals.java` looks for BAML source files at `./baml_src`. Override this at runtime:

```bash
java -Dbaml.root.path=/opt/app/baml_src -jar myapp.jar
```

---

## Per-Call Client Override

To swap the LLM client for a single call without modifying your `.baml` files:

```java
BamlClientOptions client = new BamlClientOptions.Builder()
    .name("gpt4")
    .provider("openai")
    .option("model", "gpt-4o")
    .option("api_key", System.getenv("OPENAI_API_KEY"))
    .build();

BamlClientRegistry registry = new BamlClientRegistry.Builder()
    .primary("gpt4")
    .client(client)
    .build();

byte[] encoded = BamlEncoder.encodeArgs(kwargs, registry);
```

---

## Module Layout

```
engine/
  language_client_java/         # baml-runtime-java library (Maven artifact)
  language_client_java_reactor/ # optional Project Reactor extensions
  language_client_kotlin/       # Kotlin façade (planned)
  generators/languages/java/    # Rust codegen: IR → Java source files

examples/
  java-gradle/                  # minimal Gradle project
  java-maven/                   # minimal Maven project

integ-tests/java/               # live LLM integration tests (JUnit 5)
```
