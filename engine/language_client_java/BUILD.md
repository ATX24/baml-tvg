# Building BAML Java Runtime in DevContainer

The Java runtime can be built in the devcontainer environment. Java and Maven are automatically installed via `mise` when you run `./scripts/setup-dev.sh`.

## Prerequisites

1. **DevContainer**: Open the project in VS Code with the Remote Containers extension
2. **Setup**: Run `./scripts/setup-dev.sh` to install all tools including Java and Maven
3. **Verify**: Check that Java and Maven are available:
   ```bash
   java -version  # Should show Java 23 (Temurin)
   mvn --version  # Should show Maven 3.9
   ```

## Building

1. **Build libbaml_cffi** (required for Java runtime):
   ```bash
   cd engine/language_client_cffi
   cargo build --release
   ```

2. **Build Java runtime**:
   ```bash
   cd engine/language_client_java
   mvn clean install
   ```

   This will:
   - Compile protobuf `.proto` files to Java classes
   - Compile the Java runtime library
   - Create `target/baml-runtime-java-0.219.0.jar`

3. **Set BAML_LIBRARY_PATH** for testing:
   ```bash
   export BAML_LIBRARY_PATH=$(pwd)/../../engine/target/release/libbaml_cffi.so
   # Or for macOS:
   export BAML_LIBRARY_PATH=$(pwd)/../../engine/target/release/libbaml_cffi.dylib
   ```

## Running Integration Tests

1. **Generate Java client**:
   ```bash
   cd integ-tests/java
   baml-cli generate --from ../baml_src
   ```

2. **Run tests**:
   ```bash
   # Set environment variables
   export BAML_LIBRARY_PATH=../../engine/target/release/libbaml_cffi.so
   export OPENAI_API_KEY=your_key_here
   
   # Run tests
   mvn test
   ```

## Reactor and WebFlux

The runtime has an **optional** dependency on Project Reactor. If you add `reactor-core` to your project, you can use `BamlReactor.toFlux(BamlStream)` to adapt a BAML stream to a `Flux` for use in Spring WebFlux or other reactive pipelines.

**Example (Spring WebFlux):** return a Server-Sent Events response from a streaming BAML function:

```java
// In a @RestController or RouterFunction:
BamlStream<MyPartial, MyFinal> stream = runtime.callFunctionStream("MyStreamingFunc", encoded, partialDecoder, finalDecoder);

return ServerResponse.ok()
    .contentType(MediaType.TEXT_EVENT_STREAM)
    .body(BamlReactor.toFlux(stream).map(Object::toString), String.class);
```

**Maven:** add the optional runtime dependency (and reactor-core if not already present):

```xml
<dependency>
    <groupId>com.boundaryml</groupId>
    <artifactId>baml-runtime-java</artifactId>
    <version>0.219.0</version>
</dependency>
<dependency>
    <groupId>io.projectreactor</groupId>
    <artifactId>reactor-core</artifactId>
    <version>3.6.5</version>
</dependency>
```

## Troubleshooting

- **Maven not found**: Ensure `mise install` has completed and your shell has mise activated
- **Protobuf compilation fails**: Check that `protoc` is available (installed via mise or system)
- **Library not found**: Verify `BAML_LIBRARY_PATH` points to the correct `libbaml_cffi` shared library
- **Java version mismatch**: Ensure Java 11+ is installed (Java 23 via mise in devcontainer)
