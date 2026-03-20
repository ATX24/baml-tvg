# BAML Java SDK — Deployment Guide

This guide covers everything required to build, package, test, and publish the BAML Java SDK — from a local development build through to a Maven Central release.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Repository Structure](#repository-structure)
3. [Building the Native Library](#building-the-native-library)
4. [Building the Java Runtime JAR](#building-the-java-runtime-jar)
5. [Local Installation for Development](#local-installation-for-development)
6. [Running the Test Suite](#running-the-test-suite)
7. [Maven Artifact Coordinates & Versioning](#maven-artifact-coordinates--versioning)
8. [Publishing to Maven Central](#publishing-to-maven-central)
9. [Platform Support Matrix](#platform-support-matrix)
10. [Native Library Distribution Strategy](#native-library-distribution-strategy)
11. [CI/CD Pipeline Design](#cicd-pipeline-design)
12. [Docker / Container Considerations](#docker--container-considerations)
13. [Dev Environment Setup](#dev-environment-setup)
14. [Dependency Management](#dependency-management)
15. [Known Limitations & Future Work](#known-limitations--future-work)

---

## Architecture Overview

The BAML Java SDK is a two-layer system:

```
┌─────────────────────────────────────────┐
│           User Application              │
│   (baml_client.Functions / Globals)     │
└────────────────┬────────────────────────┘
                 │  Java method call
┌────────────────▼────────────────────────┐
│        baml-runtime-java (JAR)          │
│  BamlRuntime, BamlEncoder, BamlDecoder  │
│  BamlStream, BamlException hierarchy    │
│         JNA bindings                    │
└────────────────┬────────────────────────┘
                 │  JNA (C FFI over JNI)
┌────────────────▼────────────────────────┐
│       libbaml_cffi (.so/.dylib/.dll)    │
│   Rust: LLM HTTP calls, streaming,      │
│   protobuf encoding, BAML interpreter   │
└─────────────────────────────────────────┘
```

**Two artifacts must be deployed together:**

| Artifact | Type | Managed by |
|----------|------|-----------|
| `baml-runtime-java-{version}.jar` | JAR on Maven Central | Maven / Gradle |
| `libbaml_cffi.{so,dylib,dll}` | Platform native binary | Manual / bundled |

The JAR is pure Java and platform-independent. The native library is platform-specific and must be available at runtime via `BAML_LIBRARY_PATH` or the system library path.

---

## Repository Structure

```
engine/
├── Cargo.toml                        ← Rust workspace root
├── language_client_cffi/             ← Rust crate: produces libbaml_cffi
│   └── src/lib.rs
├── language_client_java/             ← Java runtime (this library)
│   ├── pom.xml
│   ├── src/
│   │   ├── main/
│   │   │   ├── java/com/boundaryml/baml/
│   │   │   │   ├── BamlRuntime.java
│   │   │   │   ├── BamlEncoder.java
│   │   │   │   ├── BamlDecoder.java
│   │   │   │   ├── BamlStream.java
│   │   │   │   ├── BamlReactor.java
│   │   │   │   ├── BamlException.java
│   │   │   │   ├── BamlClientError.java
│   │   │   │   ├── BamlProviderError.java
│   │   │   │   ├── BamlRateLimitError.java
│   │   │   │   ├── BamlTimeoutError.java
│   │   │   │   ├── BamlValidationError.java
│   │   │   │   ├── BamlClientRegistry.java
│   │   │   │   ├── BamlClientOptions.java
│   │   │   │   ├── BamlResponse.java
│   │   │   │   ├── BamlCallMetadata.java
│   │   │   │   ├── BamlClassValue.java
│   │   │   │   ├── BamlEnumValue.java
│   │   │   │   └── BamlUnionValue.java
│   │   │   └── proto/                ← Protobuf schemas for CFFI wire format
│   │   └── test/java/com/boundaryml/baml/
│   │       └── BamlRuntimeTest.java  ← Unit tests (stub-based, no native lib)
│   └── target/                       ← Maven build output
├── generators/languages/java/        ← Rust: Java code generator (baml-cli)
└── target/release/                   ← Cargo workspace build output
    ├── libbaml_cffi.so
    ├── libbaml_cffi.dylib
    └── baml_cffi.dll
```

---

## Building the Native Library

The native library must be rebuilt whenever the Rust source changes.

### Prerequisites

- Rust toolchain (stable channel): [rustup.rs](https://rustup.rs)
- C linker (gcc / clang / MSVC)
- Cargo workspace at `engine/`

### Build command

```bash
cd engine
cargo build --release -p baml_cffi
```

**Output location:** `engine/target/release/` (workspace target, NOT `engine/language_client_cffi/target/`)

| Platform | Output file |
|----------|-------------|
| Linux | `libbaml_cffi.so` |
| macOS | `libbaml_cffi.dylib` |
| Windows | `baml_cffi.dll` |

### Cross-compilation

To build for a different platform (e.g., building Linux `.so` on macOS):

```bash
# Add the target
rustup target add x86_64-unknown-linux-gnu

# Install cross-compilation linker (e.g., via brew or apt)
# Then build
cd engine
cargo build --release -p baml_cffi --target x86_64-unknown-linux-gnu
# Output: engine/target/x86_64-unknown-linux-gnu/release/libbaml_cffi.so
```

For production cross-compilation, use [`cross`](https://github.com/cross-rs/cross), which provides pre-built Docker images with the necessary toolchains:

```bash
cargo install cross
cd engine
cross build --release -p baml_cffi --target x86_64-unknown-linux-gnu
```

---

## Building the Java Runtime JAR

### Prerequisites

- Java 11+ (any distribution; Temurin recommended)
- Maven 3.6+

### Build command

```bash
cd engine/language_client_java
mvn clean package -DskipTests
```

**Output:** `engine/language_client_java/target/baml-runtime-java-0.219.0.jar`

Additional artifacts produced:
- `baml-runtime-java-0.219.0-sources.jar` — source JAR (required for Maven Central)
- `baml-runtime-java-0.219.0-javadoc.jar` — Javadoc JAR (required for Maven Central)

### What the build does

1. Runs `os-maven-plugin` to detect the host OS (required for `protoc` artifact selection)
2. Runs `protobuf-maven-plugin` to compile `.proto` files in `src/main/proto/` to Java classes in `target/generated-sources/`
3. Compiles all Java sources (main + generated) with `maven-compiler-plugin` targeting Java 11
4. Packages everything into a single JAR
5. Attaches sources and Javadoc JARs

---

## Local Installation for Development

To make `baml-runtime-java` available to local Maven and Gradle projects without publishing to Maven Central:

```bash
cd engine/language_client_java
mvn install -DskipTests
```

This installs the JAR, sources JAR, and POM to your local Maven repository (`~/.m2/repository/com/boundaryml/baml-runtime-java/0.219.0/`).

### Verifying the installation

```bash
ls ~/.m2/repository/com/boundaryml/baml-runtime-java/0.219.0/
# Expected:
# baml-runtime-java-0.219.0.jar
# baml-runtime-java-0.219.0-sources.jar
# baml-runtime-java-0.219.0-javadoc.jar
# baml-runtime-java-0.219.0.pom
```

---

## Running the Test Suite

The unit tests use a stub implementation of `BamlCFFI` and do not require the native library.

```bash
cd engine/language_client_java
mvn test
```

**Expected output:** 10 tests passing

### What the tests cover

| Test | Coverage |
|------|----------|
| `callFunctionParse_returnsDecodedResult` | Happy-path blocking call |
| `callFunctionParse_throwsOnError` | Error callback → `BamlException` |
| `callFunctionParse_retriesOnTransientError` | Retry policy: 3 attempts with exponential backoff |
| `callFunctionParse_retriesOnTimeoutLikeError` | Retry on timeout-like errors |
| `callFunctionParse_noRetryByDefault` | Default (no-retry) behavior |
| `callFunctionStream_basicStreamingFlow` | Partial events + final result |
| `callFunctionStream_errorMidStream` | Error during streaming |
| `callFunctionStream_emptyStream` | Stream with no partials |
| `setCffiForTests_resetsCallbackRegistration` | Test isolation helper |
| `buffer_byValue_structureLayout` | JNA ByValue struct ABI |

### Integration tests

End-to-end tests require `libbaml_cffi.so` and a valid API key:

```bash
export BAML_LIBRARY_PATH=/path/to/engine/target/release/libbaml_cffi.so
export GOOGLE_API_KEY=your-key

cd integ-tests/java
baml-cli generate --from ../baml_src
mvn test
```

---

## Maven Artifact Coordinates & Versioning

### Coordinates

```
groupId:    com.boundaryml
artifactId: baml-runtime-java
version:    0.219.0
```

### Versioning strategy

BAML uses a single version number across all language runtimes, synchronized with the `baml-cli` code generator. **The Java runtime version must match the `version` field in `generators.baml`** — this ensures generated client code is compatible with the runtime it links against.

| Version pattern | When to use |
|----------------|-------------|
| `0.X.Y` | Current pre-1.0 development; X is major feature increments |
| `0.X.Y-SNAPSHOT` | Unreleased development builds (Maven snapshot semantics) |
| `1.0.0` and above | Once the API is considered stable for production use |

**Incrementing the version requires:**
1. Update `version` in `engine/language_client_java/pom.xml`
2. Update the `version` field in example `generators.baml` files
3. Update the dependency version in example `build.gradle` / `pom.xml` files
4. Update the version constant in the Rust generator (`engine/generators/languages/java/`)

---

## Publishing to Maven Central

Maven Central requires artifacts to be signed with GPG and staged through Sonatype OSSRH.

### One-time setup

1. **Create a Sonatype JIRA account** at [issues.sonatype.org](https://issues.sonatype.org) and request access to the `com.boundaryml` namespace.

2. **Generate a GPG key pair:**

```bash
gpg --gen-key
# Follow prompts; use a strong passphrase
gpg --list-secret-keys --keyid-format=long
# Note the key ID (8-character hex after "sec rsa4096/")

# Publish the public key to a keyserver
gpg --keyserver keyserver.ubuntu.com --send-keys YOUR_KEY_ID
```

3. **Add credentials to Maven settings** (`~/.m2/settings.xml`):

```xml
<settings>
  <servers>
    <server>
      <id>ossrh</id>
      <username>your-sonatype-username</username>
      <password>your-sonatype-password</password>
    </server>
  </servers>

  <profiles>
    <profile>
      <id>ossrh</id>
      <activation>
        <activeByDefault>true</activeByDefault>
      </activation>
      <properties>
        <gpg.keyname>YOUR_KEY_ID</gpg.keyname>
        <gpg.passphrase>your-gpg-passphrase</gpg.passphrase>
      </properties>
    </profile>
  </profiles>
</settings>
```

### Publishing a snapshot

Snapshot builds can be deployed without signing and are immediately available to downstream consumers via the Sonatype snapshot repository.

```bash
# Ensure version in pom.xml ends with -SNAPSHOT (e.g., 0.220.0-SNAPSHOT)
cd engine/language_client_java
mvn deploy -DskipTests
```

Consumers can add the snapshot repository:

```xml
<repositories>
    <repository>
        <id>ossrh-snapshots</id>
        <url>https://s01.oss.sonatype.org/content/repositories/snapshots</url>
        <snapshots><enabled>true</enabled></snapshots>
    </repository>
</repositories>
```

### Publishing a release

```bash
# Ensure version in pom.xml does NOT end with -SNAPSHOT (e.g., 0.220.0)
cd engine/language_client_java
mvn deploy -P release -DskipTests
```

This:
1. Compiles, packages, and attaches sources + Javadoc JARs
2. Signs all artifacts with GPG (via `maven-gpg-plugin`)
3. Stages the release to Sonatype OSSRH (via `nexus-staging-maven-plugin`)

Then promote the staged release to Maven Central:

```bash
# List staging repositories
mvn nexus-staging:rc-list -DserverId=ossrh -DnexusUrl=https://s01.oss.sonatype.org/

# Close and release
mvn nexus-staging:close -DserverId=ossrh -DstagingRepositoryId=comboundaryml-XXXX
mvn nexus-staging:release -DserverId=ossrh -DstagingRepositoryId=comboundaryml-XXXX
```

Or use the Sonatype OSSRH web UI at [s01.oss.sonatype.org](https://s01.oss.sonatype.org) to promote manually.

**Sync time:** Maven Central syncs from OSSRH within 30–60 minutes after release.

---

## Platform Support Matrix

| Platform | Architecture | Native Library | Status |
|----------|-------------|---------------|--------|
| Linux (glibc ≥ 2.17) | x86_64 | `libbaml_cffi.so` | Supported |
| Linux (glibc ≥ 2.17) | aarch64 | `libbaml_cffi.so` | Supported |
| macOS | x86_64 | `libbaml_cffi.dylib` | Supported |
| macOS | Apple Silicon (aarch64) | `libbaml_cffi.dylib` | Supported |
| Windows | x86_64 | `baml_cffi.dll` | Supported |
| Linux (musl) | x86_64 | `libbaml_cffi.so` | Not tested |

**JVM requirements:** Any JVM that supports Java 11+. Tested with:
- Eclipse Temurin 11, 17, 21, 23
- GraalVM 21 (JVM mode only; native image not yet supported due to JNA reflection requirements)

**JNA version:** 5.13.0. JNA 5.x is required; JNA 4.x is not compatible with the `Structure.ByValue` semantics used by the `Buffer` struct.

---

## Native Library Distribution Strategy

The current approach requires users to build and set `BAML_LIBRARY_PATH` themselves. There are three paths to improve this:

### Option A: Manual distribution (current state)

Users build `libbaml_cffi` from source and set `BAML_LIBRARY_PATH`. Suitable for development and internal deployments.

**Pros:** Simple, no packaging overhead.
**Cons:** Users must build Rust; path must be configured per environment.

### Option B: Platform-specific JARs (recommended for production)

Package the native library inside platform-specific JARs and publish them alongside the main JAR. JNA can extract and load natives from the classpath automatically.

**JAR naming convention:**

```
baml-runtime-java-0.219.0.jar           (platform-independent, code only)
baml-runtime-java-0.219.0-linux-x86_64.jar
baml-runtime-java-0.219.0-linux-aarch64.jar
baml-runtime-java-0.219.0-osx-x86_64.jar
baml-runtime-java-0.219.0-osx-aarch64.jar
baml-runtime-java-0.219.0-windows-x86_64.jar
```

**Implementation steps:**

1. Place the native library in `src/main/resources/` under the platform-specific path expected by JNA:
   - `com/sun/jna/linux-x86-64/libbaml_cffi.so`
   - `com/sun/jna/darwin-aarch64/libbaml_cffi.dylib`
   - `com/sun/jna/win32-x86-64/baml_cffi.dll`

2. JNA automatically extracts and loads from the classpath before trying the system library path.

3. Update `BamlRuntime` static initializer: remove the explicit `Native.load(libPath, ...)` branch; let JNA handle extraction automatically when `BAML_LIBRARY_PATH` is not set.

4. Add a Maven Assembly or multi-module build to produce per-platform JARs from the CI pipeline.

### Option C: Uber-JAR with all platforms bundled

Bundle all platform natives into a single JAR. Largest download size, simplest user experience.

```
baml-runtime-java-0.219.0-all-platforms.jar
  ├── com/sun/jna/linux-x86-64/libbaml_cffi.so
  ├── com/sun/jna/darwin-aarch64/libbaml_cffi.dylib
  └── com/sun/jna/win32-x86-64/baml_cffi.dll
```

---

## CI/CD Pipeline Design

The recommended pipeline has three stages: build, test, and publish.

### Stage 1: Build native libraries (matrix)

Run in parallel across all target platforms:

```yaml
# Example: GitHub Actions matrix
strategy:
  matrix:
    include:
      - os: ubuntu-22.04
        target: x86_64-unknown-linux-gnu
        artifact: libbaml_cffi.so
      - os: ubuntu-22.04
        target: aarch64-unknown-linux-gnu
        artifact: libbaml_cffi.so
        use_cross: true
      - os: macos-14              # Apple Silicon runner
        target: aarch64-apple-darwin
        artifact: libbaml_cffi.dylib
      - os: macos-13              # Intel runner
        target: x86_64-apple-darwin
        artifact: libbaml_cffi.dylib
      - os: windows-2022
        target: x86_64-pc-windows-msvc
        artifact: baml_cffi.dll

steps:
  - uses: actions/checkout@v4
  - uses: dtolnay/rust-toolchain@stable
    with:
      targets: ${{ matrix.target }}
  - name: Build native library
    run: |
      cd engine
      cargo build --release -p baml_cffi --target ${{ matrix.target }}
  - uses: actions/upload-artifact@v4
    with:
      name: native-${{ matrix.target }}
      path: engine/target/${{ matrix.target }}/release/${{ matrix.artifact }}
```

### Stage 2: Build and test Java JAR

```yaml
steps:
  - uses: actions/setup-java@v4
    with:
      java-version: '11'
      distribution: 'temurin'
  - name: Build Java runtime
    run: |
      cd engine/language_client_java
      mvn clean package -DskipTests
  - name: Run unit tests (no native lib needed)
    run: |
      cd engine/language_client_java
      mvn test
  - name: Run integration tests
    run: |
      # Download linux native artifact from Stage 1
      export BAML_LIBRARY_PATH=$(pwd)/libbaml_cffi.so
      export GOOGLE_API_KEY=${{ secrets.GOOGLE_API_KEY }}
      cd integ-tests/java
      mvn test
```

### Stage 3: Publish

```yaml
# Only runs on version tags (e.g., v0.220.0)
if: startsWith(github.ref, 'refs/tags/v')
steps:
  - name: Import GPG key
    uses: crazy-max/ghaction-import-gpg@v6
    with:
      gpg_private_key: ${{ secrets.GPG_PRIVATE_KEY }}
      passphrase: ${{ secrets.GPG_PASSPHRASE }}
  - name: Deploy to Maven Central
    run: |
      cd engine/language_client_java
      mvn deploy -P release -DskipTests \
        -Dgpg.keyname=${{ secrets.GPG_KEY_ID }}
    env:
      MAVEN_USERNAME: ${{ secrets.OSSRH_USERNAME }}
      MAVEN_PASSWORD: ${{ secrets.OSSRH_PASSWORD }}
```

### Required CI secrets

| Secret | Description |
|--------|-------------|
| `GPG_PRIVATE_KEY` | Exported GPG private key (base64 or armored) |
| `GPG_PASSPHRASE` | GPG key passphrase |
| `GPG_KEY_ID` | GPG key fingerprint |
| `OSSRH_USERNAME` | Sonatype OSSRH account username |
| `OSSRH_PASSWORD` | Sonatype OSSRH account password |
| `GOOGLE_API_KEY` | For integration tests |

---

## Docker / Container Considerations

### Base image selection

The native library links against glibc. Use a glibc-based image (Debian, Ubuntu, Amazon Linux 2, Red Hat UBI):

```dockerfile
FROM eclipse-temurin:21-jre-jammy

WORKDIR /app

# Copy your application JAR
COPY target/myapp.jar .

# Copy the native library
COPY libbaml_cffi.so /usr/local/lib/

# Tell JNA where to find it
ENV BAML_LIBRARY_PATH=/usr/local/lib/libbaml_cffi.so

# Or add to system library path (then BAML_LIBRARY_PATH is not needed)
RUN ldconfig /usr/local/lib

CMD ["java", "-jar", "myapp.jar"]
```

### Alpine / musl images

The standard native library (`libbaml_cffi.so`) is built against glibc and **will not work** on Alpine Linux with musl libc. Options:

1. Use a glibc-based base image (recommended)
2. Build a musl-linked native library targeting `x86_64-unknown-linux-musl` and include it separately
3. Use `wolfi-base` (a glibc-compatible minimal image)

### Multi-stage build example

```dockerfile
# Stage 1: Build Rust native library
FROM rust:1.78-slim AS rust-build
WORKDIR /engine
COPY engine/ .
RUN cargo build --release -p baml_cffi

# Stage 2: Build Java application
FROM maven:3.9-eclipse-temurin-21 AS java-build
WORKDIR /app
COPY engine/language_client_java /baml-runtime
RUN cd /baml-runtime && mvn install -DskipTests

COPY pom.xml .
COPY src ./src
RUN mvn package -DskipTests

# Stage 3: Runtime
FROM eclipse-temurin:21-jre-jammy
WORKDIR /app
COPY --from=rust-build /engine/target/release/libbaml_cffi.so /usr/local/lib/
COPY --from=java-build /app/target/myapp.jar .
RUN ldconfig /usr/local/lib
ENV BAML_LIBRARY_PATH=/usr/local/lib/libbaml_cffi.so
CMD ["java", "-jar", "myapp.jar"]
```

---

## Dev Environment Setup

The recommended development environment is the provided devcontainer (VSCode Remote Containers or GitHub Codespaces).

### Devcontainer setup

```bash
# Open in VSCode → "Reopen in Container" (or use GitHub Codespaces)
# Then inside the container:
./scripts/setup-dev.sh     # installs Rust, Java, Maven, mise, protoc, baml-cli

java --version             # Should show Java 23 (Temurin)
mvn --version              # Should show Maven 3.9
cargo --version            # Should show Rust stable
baml-cli --version         # Should show 0.219.0
```

### Local (non-container) setup

If you prefer to work outside Docker:

```bash
# Install mise (tool version manager): https://mise.jdx.dev
curl https://mise.run | sh

# Install tools
mise use -g java@temurin-23
mise use -g maven@3.9.12
mise use -g rust@stable
```

### Useful development commands

```bash
# Rebuild native library after Rust changes
cd engine && cargo build --release -p baml_cffi

# Rebuild JAR and install to local .m2 (skip tests for speed)
cd engine/language_client_java && mvn install -DskipTests

# Run unit tests only
cd engine/language_client_java && mvn test

# Regenerate example client
cd examples/java-gradle && baml-cli generate --from baml_src

# Run Gradle example (no daemon to pick up fresh env)
cd examples/java-gradle
BAML_LIBRARY_PATH=/workspaces/baml-tvg/engine/target/release/libbaml_cffi.so \
GOOGLE_API_KEY=your-key \
./gradlew run --no-daemon

# Run Maven example
cd examples/java-maven
BAML_LIBRARY_PATH=/workspaces/baml-tvg/engine/target/release/libbaml_cffi.so \
GOOGLE_API_KEY=your-key \
mvn -q compile exec:java -Dexec.mainClass=com.example.Main
```

---

## Dependency Management

### Direct runtime dependencies

| Artifact | Version | License | Rationale |
|---------|---------|---------|-----------|
| `net.java.dev.jna:jna` | 5.13.0 | Apache 2.0 | JNA for native C FFI calls |
| `com.google.protobuf:protobuf-java` | 3.25.1 | BSD 3-Clause | Protobuf encoding for the CFFI wire format |

### Optional runtime dependencies

| Artifact | Version | License | When needed |
|---------|---------|---------|-------------|
| `io.projectreactor:reactor-core` | 3.6.5 | Apache 2.0 | Only when using `BamlReactor.toFlux()` |

### Dependency pinning policy

- JNA: pin to a specific minor version. JNA occasionally changes calling conventions between minor releases; validate on upgrade.
- protobuf-java: pin to a specific minor. Major version upgrades (3→4) are breaking.
- reactor-core: minor upgrades are generally safe; follow Reactor's BOM for Spring compatibility.

### Upgrading protobuf

If the `.proto` schema changes:
1. Update `protobuf.version` in `pom.xml`
2. Verify that `protoc` version (downloaded by `protobuf-maven-plugin`) matches
3. Regenerate and test

---

## Known Limitations & Future Work

### GraalVM native image

JNA uses reflection and dynamic class loading, which conflicts with GraalVM's closed-world assumption for native images. Using `baml-runtime-java` in a GraalVM native image requires:

1. A JNA GraalVM configuration (reflection, JNI, resource includes)
2. Potentially replacing JNA with a pure-JNI approach (no third-party dependency)

This is not supported in the current version.

### Android

JNA 5.x supports Android, and the Rust CFFI library can be cross-compiled for Android ABIs (`aarch64-linux-android`, `x86_64-linux-android`). However:
- The `BamlRuntime` static initializer and `System.getenv()` behave differently on Android
- Android's security model may restrict native library loading paths
- This is untested and not officially supported.

### Streaming retry

Retry logic is only applied to blocking calls (`callFunctionParse`). Streaming calls (`callFunctionStream`) do not retry automatically; if the stream errors mid-way, the `BamlException` is thrown and the caller must restart the call.

### Versioning automation

Currently the version in `pom.xml`, `generators.baml` example files, and the Rust generator must be updated manually in lockstep. A future improvement would be a single source of truth (e.g., `version.txt` at the repo root) with build scripts that propagate it automatically.
