# Swift Type Serialization Tests — Implementation Plan

This document describes how to add Swift to the shared BAML type serialization test
infrastructure (`type_serialization_tests.md`), mirroring what exists for Python,
TypeScript, Go, and Rust.

---

## Background

`type_serialization_tests.md` is a single markdown spec that defines expected type
strings for every BAML primitive, container, and constructed type across all
supported output languages. Each test case names a BAML source snippet, a target
path (`Class.field` or `TypeAlias`), and per-language expected strings for both
non-streaming and streaming representations.

Each language generator has:
1. A `test_macros.rs` file with a `test_<lang>_type!` macro.
2. A `build.rs` that calls `type_test_spec::generate_test_code("<lang>")` and writes
   auto-generated test functions to `$OUT_DIR/generated_type_tests.rs`.
3. An `include!(concat!(env!("OUT_DIR"), "/generated_type_tests.rs"))` in `lib.rs`
   so those functions compile as real `#[test]` items.

Swift currently has `ir_class_to_swift` and `stream_type_to_swift` but lacks the
streaming class converter, test macro, and build.rs wiring. This plan adds all of
that.

---

## Swift Type Mappings

Derived from `engine/generators/languages/swift/src/type.rs` (`SerializeType` impl):

| BAML type      | Non-streaming Swift | Streaming Swift  |
|----------------|---------------------|------------------|
| `string`       | `String`            | `String?`        |
| `int`          | `Int64`             | `Int64?`         |
| `float`        | `Double`            | `Double?`        |
| `bool`         | `Bool`              | `Bool?`          |
| `null`         | `Any?`              | `Any??`          |
| `image`        | `BamlImage`         | `BamlImage?`     |
| `audio`        | `BamlAudio`         | `BamlAudio?`     |
| `string?`      | `String?`           | `String?`        |
| `int?`         | `Int64?`            | `Int64?`         |
| `float?`       | `Double?`           | `Double?`        |
| `bool?`        | `Bool?`             | `Bool?`          |
| `image?`       | `BamlImage?`        | `BamlImage?`     |
| `audio?`       | `BamlAudio?`        | `BamlAudio?`     |
| `"hello"`      | `String`            | `String?`        |
| `42`           | `Int64`             | `Int64?`         |
| `true`         | `Bool`              | `Bool?`          |
| `ClassName`    | `ClassName`         | `ClassName?`     |
| `EnumName`     | `EnumName`          | `EnumName?`      |
| `[string]`     | `[String]`          | `[String]?`      |
| `[string: int]`| `[String: Int64]`   | `[String: Int64]?` |
| `A \| B`       | `Union2AOrB`        | `Union2AOrB?`    |
| `(A \| B)?`    | `Union2AOrB?`       | `Union2AOrB?`    |
| `any` (dynamic)| `Any`               | `Any?`           |

Streaming wraps required types in `?` (Swift Optional) — the same semantic as
Rust's `Option<T>`, Go's `*T`, Python's `typing.Optional[T]`.

Already-optional fields (`T?`) are idempotent — they stay `T?` in streaming mode.

### Constraints / Checked types

| BAML | Non-streaming | Streaming |
|------|---------------|-----------|
| `T @check(...)` | `Checked<T>` | `Checked<T>?` |

### StreamState

`@stream.with_state` wraps the type in `StreamState<T>`:

| BAML | Non-streaming | Streaming |
|------|---------------|-----------|
| `T @stream.with_state` | `T` | `StreamState<T>` |

---

## File Changes

### 1. `utils/type_test_spec/src/lib.rs`

Add `swift` as a recognised language throughout:

**`TestCase` struct** — add field:
```rust
pub swift: Option<(String, String)>,
```

**`TestCaseBuilder`** — add field and initialiser default.

**`parse_test_spec`** — add `"Swift"` branch in the `### Language` matching block:
```rust
} else if section == "Swift" {
    current_language = Some("swift");
    ...
}
```
And in every `match current_language` that stores `(ns, s)`, add:
```rust
Some("swift") => test.swift = Some((ns, s)),
```

**`generate_test_code`** — add `"swift"` to the match:
```rust
"swift" => ("type_gen", "swift", "serialize_type"),
```
And in the `has_type_test` match:
```rust
"swift" => test.swift.is_some(),
```
And in the `(non_streaming, streaming)` extraction match:
```rust
"swift" => test.swift.as_ref().unwrap(),
```

**`language_short`** — add:
```rust
"swift" => "swift",
```

### 2. `type_serialization_tests.md`

Add a `### Swift` section to every test case that has Go/Rust entries. Use the
mappings table above. Example for `string_field`:

```markdown
### Swift

- Non-streaming: `String`
- Streaming: `String?`
```

For long types (constraints, stream state), use fenced code blocks:

```markdown
### Swift

- Non-streaming:
```swift
Checked<String>
```
- Streaming:
```swift
Checked<String>?
```
```

**Scope** — add Swift entries to all test categories:

| Category | # cases (approx) |
|----------|-------------------|
| Primitives (string, int, float, bool) | 4 |
| Media types (image, audio, image?, audio?) | 4 |
| Optional types (string?, int?, float?, bool?) | 4 |
| Literal types (string, int, bool) | 3 |
| Class references | 2 |
| Enum references | 2 |
| List types | 4 |
| Map types | 3 |
| Union types (2-way, 3-way, optional union) | 5 |
| Nested types (list of class, map of enum, etc.) | 4 |
| Checked constraints | 3 |
| StreamState | 2 |
| Dynamic classes | 2 |
| Type aliases | 3 |

Enum test cases (`### enum_values:`) need no streaming column — they apply to all
languages uniformly via the enum variant form.

### 3. `languages/swift/src/test_macros.rs` — new file

Mirrors `languages/go/src/test_macros.rs`. Key differences: calls
`ir_class_to_swift` / `ir_class_to_swift_stream` / `ir_enum_to_swift` from the Swift
`ir_to_swift` module; uses `SerializeType` from `crate::type_`.

```rust
#[macro_export]
macro_rules! test_swift_type {
    // Class field — non-streaming and streaming expectations
    (
        $baml:expr,
        $class_dot_field:expr,
        $line_number:expr,
        $expected_non_streaming:expr,
        $expected_streaming:expr
    ) => {{
        use internal_baml_core::ir::{repr::make_test_ir, IRHelper};
        use $crate::ir_to_swift::classes::{ir_class_to_swift, ir_class_to_swift_stream};
        use $crate::r#type::SerializeType;

        let path = $class_dot_field;
        let line_num: usize = $line_number;
        let parts: Vec<&str> = path.split('.').collect();
        let ir = make_test_ir($baml).expect("Valid BAML");
        let ir = std::sync::Arc::new(ir);

        if parts.len() == 2 {
            let class_name = parts[0];
            let field_name = parts[1];
            let class = ir.find_class(class_name).unwrap().item;

            // Non-streaming
            let class_swift = ir_class_to_swift(class, ir.as_ref());
            let field = class_swift.fields.iter()
                .find(|f| f.name == field_name).unwrap();
            assert_eq!(
                field.r#type.serialize_type(), $expected_non_streaming,
                "Non-streaming mismatch for {} (type_serialization_tests.md:{})",
                path, line_num
            );

            // Streaming
            let class_swift_stream = ir_class_to_swift_stream(class, ir.as_ref());
            let field = class_swift_stream.fields.iter()
                .find(|f| f.name == field_name).unwrap();
            assert_eq!(
                field.r#type.serialize_type(), $expected_streaming,
                "Streaming mismatch for {} (type_serialization_tests.md:{})",
                path, line_num
            );
        } else if parts.len() == 1 {
            use $crate::ir_to_swift::type_aliases::{
                ir_type_alias_to_swift, ir_type_alias_to_swift_stream,
            };
            let alias = ir.find_type_alias(parts[0]).unwrap().item;

            let alias_swift = ir_type_alias_to_swift(alias, ir.as_ref(), None);
            assert_eq!(alias_swift.swift_type(), $expected_non_streaming, ...);

            let alias_swift_stream = ir_type_alias_to_swift_stream(alias, ir.as_ref(), None);
            assert_eq!(alias_swift_stream.swift_type(), $expected_streaming, ...);
        }
    }};

    // Enum case
    (
        $baml:expr,
        $enum_name:expr,
        $line_number:expr,
        [$( $value:expr ),* $(,)?]
    ) => {{
        use internal_baml_core::ir::{repr::make_test_ir, IRHelper};
        use $crate::ir_to_swift::enums::ir_enum_to_swift;

        let ir = make_test_ir($baml).expect("Valid BAML");
        let ir = std::sync::Arc::new(ir);
        let enm = ir.find_enum($enum_name).unwrap().item;
        let enum_swift = ir_enum_to_swift(enm);

        let expected: Vec<&str> = vec![$( $value ),*];
        let actual: Vec<&str> = enum_swift.values.iter().map(|(v, _)| v.as_str()).collect();
        assert_eq!(actual, expected, ...);
    }};
}

// Include auto-generated tests
include!(concat!(env!("OUT_DIR"), "/generated_type_tests.rs"));
```

### 4. `languages/swift/src/ir_to_swift/classes.rs` — add streaming variant

Add `ir_class_to_swift_stream` alongside the existing `ir_class_to_swift`:

```rust
pub fn ir_class_to_swift_stream(
    class: &Class,
    lookup: &impl baml_types::baml_value::TypeLookups,
) -> ClassSwift {
    ClassSwift {
        name: class.elem.name.clone(),
        docstring: class.elem.docstring.clone().map(|d| d.0.clone()),
        dynamic: class.attributes.dynamic(),
        fields: class.elem.static_fields.iter()
            .map(|field| ir_field_to_swift_stream(field, lookup))
            .collect(),
    }
}

fn ir_field_to_swift_stream(
    field: &Field,
    lookup: &impl baml_types::baml_value::TypeLookups,
) -> FieldSwift {
    let streaming = field.elem.r#type.elem.to_streaming_type(lookup);
    let swift_type = super::super::ir_to_swift::stream_type_to_swift(&streaming, lookup);
    FieldSwift {
        name: field.elem.name.clone(),
        r#type: swift_type,
        docstring: field.elem.docstring.clone().map(|d| d.0.clone()),
    }
}
```

> **Note**: verify the exact IR method name (`to_streaming_type`) by checking the
> `baml_types::ir_type` API. Go's `ir_class_to_go_stream` uses the same pattern.

### 5. `languages/swift/src/ir_to_swift/type_aliases.rs` — add streaming variant

Add `ir_type_alias_to_swift_stream` analogous to `ir_type_alias_to_go_stream`.
This uses `stream_type_to_swift` instead of `type_to_swift`.

### 6. `languages/swift/Cargo.toml` — add build-dependency

```toml
[build-dependencies]
type-test-spec = { path = "../../utils/type_test_spec" }
```

### 7. `languages/swift/build.rs` — new file

```rust
use std::{env, fs, path::Path};

fn main() {
    let out_dir = env::var("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("generated_type_tests.rs");
    let code = type_test_spec::generate_test_code("swift");
    fs::write(&dest_path, code).unwrap();
    println!("cargo:rerun-if-changed=../../type_serialization_tests.md");
}
```

### 8. `languages/swift/src/lib.rs` — wire in test module

Add at the top of the module declarations:
```rust
#[cfg(test)]
mod test_macros;
```

And at the bottom of the file:
```rust
#[cfg(test)]
include!(concat!(env!("OUT_DIR"), "/generated_type_tests.rs"));
```

---

## Running the Tests

From `engine/`:

```bash
# All Swift type serialization tests
cargo test -p generators-swift --lib type_gen

# Specific test
cargo test -p generators-swift --lib type_gen::string_field

# All languages at once
cargo test --lib type_gen
```

---

## Implementation Order

1. Add `ir_class_to_swift_stream` to `ir_to_swift/classes.rs`.
2. Add `ir_type_alias_to_swift_stream` to `ir_to_swift/type_aliases.rs`.
3. Add Swift support to `type_test_spec/src/lib.rs`.
4. Add `build.rs` and update `Cargo.toml` for the Swift generator.
5. Add `test_macros.rs` with `test_swift_type!`.
6. Wire `mod test_macros` and `include!` into `lib.rs`.
7. Add `### Swift` sections to `type_serialization_tests.md` for all test cases.
8. Run `cargo test -p generators-swift --lib type_gen` and fix any mismatches.

---

## Differences from Other Languages

| Aspect | Go | Rust | Swift |
|--------|----|------|-------|
| Streaming required `T` | `*T` | `Option<T>` | `T?` |
| Optional `T?` (streaming) | `*T` | `Option<T>` | `T?` |
| List `[T]` (streaming) | `[]*T` | `Vec<Option<T>>` | `[T]?` |
| Package context | `CurrentRenderPackage` needed | not needed | not needed |
| Enum test | values list | values list | values list |

Swift is simpler than Go in that there's no package-context object required —
`serialize_type()` is a plain method call with no render package argument.
