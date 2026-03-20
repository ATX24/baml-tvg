# BAML Java Runtime Library

This is the Java runtime library for BAML that uses JNA to call the C FFI (`libbaml_cffi`).

## Building

The runtime library requires:
- Java 11+
- Maven or Gradle
- The `libbaml_cffi` shared library (built from `engine/language_client_cffi`)

## Usage

Add this dependency to your project:

```xml
<dependency>
    <groupId>com.boundaryml</groupId>
    <artifactId>baml-runtime-java</artifactId>
    <version>0.219.0</version>
</dependency>
```

Or for Gradle:

```gradle
implementation 'com.boundaryml:baml-runtime-java:0.219.0'
```

The generated BAML client code will use `BamlRuntime` from this library.

## Native Library Loading

The library will attempt to load `libbaml_cffi` from:
1. `BAML_LIBRARY_PATH` environment variable
2. System library path
3. JAR resources (if bundled)
