# Swift Type Mapping for the BAML Generator

This document explains how BAML's IR (Intermediate Representation) types are
translated to Swift types by `generators-swift`.

The source of truth is `type_ir_to_swift()` in `src/lib.rs`.

---

## Core Design Principle

BAML's IR type system (`TypeIR = TypeGeneric<type_meta::IR>`) is language-agnostic.
The Swift generator translates it into Swift types with two tiers of fidelity:

- **Tier 1 — Proper types**: primitives and simple collections, where a 1-to-1
  Swift type exists and is unambiguous.
- **Tier 2 — Escape hatch (`Any?`)**: complex types (classes, true unions, recursive
  aliases) where a proper mapping would require generating struct/enum definitions.
  Callers can still introspect the value at runtime with `as?` casts — `decode()`
  in `Decode.swift` always fills in the right shape.

This "very basic" strategy was chosen to ship a working end-to-end pipeline quickly.
Typed struct/enum generation is the natural next step.

---

## Mapping Table

| BAML IR type               | Swift type         | Notes |
|----------------------------|--------------------|-------|
| `string`                   | `String`           | |
| `int`                      | `Int`              | BAML int is 64-bit; Swift `Int` is 64-bit on 64-bit platforms |
| `float`                    | `Double`           | BAML float is f64 |
| `bool`                     | `Bool`             | |
| `null`                     | `Any?`             | Appears only as part of a union in practice |
| `image` / `audio` / media  | `Any`              | BamlMedia — no Swift type yet |
| `string` literal           | `String`           | e.g. `"foo"` — same storage as plain string |
| `int` literal              | `Int`              | e.g. `42` |
| `bool` literal             | `Bool`             | e.g. `true` |
| `T[]`                      | `[T]`              | Recursively maps inner type |
| `map<string, V>`           | `[String: V]`      | BAML map keys are always strings; value type is recursively mapped |
| `T?` (optional)            | `T?`               | See Optional section below |
| `class Foo { ... }`        | `[String: Any?]`   | See Classes section below |
| `enum Bar`                 | `String`           | See Enums section below |
| `T1 \| T2` (union)         | `Any`              | See Unions section below |
| recursive type alias       | `Any`              | Expansion not attempted |
| tuple / arrow              | `Any`              | Not expressible in Swift's type system cleanly |

---

## Optional (`T?`)

BAML represents optionals internally as a `Union` of `[T, null]`. The generator
detects this by calling `.view()` on the `UnionTypeGeneric`, which returns
`UnionTypeViewGeneric::Optional(inner)` when exactly one non-null type is present.

```
BAML: string?   →  Union([string, null]).view() == Optional(string)
Swift: String?
```

If the inner type is already optional (e.g. `Any?`), we avoid double-optionality
(`Any??`) by detecting the trailing `?` and not adding another one.

---

## Classes

```
BAML: class Resume { name: string, years: int }
Swift: [String: Any?]
```

The decode layer (`Decode.swift`) already materialises a class as a
`[String: Any?]` dictionary at runtime — keys are field names, values are
recursively decoded. The `[String: Any?]` type annotation matches this exactly,
so callers can subscript by key:

```swift
let result = try await client.ExtractResume(resume: text)
if let dict = result as? [String: Any?] {
    let name = dict["name"] as? String
}
```

**Future work:** generate a concrete Swift `struct` per BAML class, with
`Codable` conformance, and return that instead of `[String: Any?]`.

---

## Enums

```
BAML: enum Sentiment { Positive Negative Neutral }
Swift: String
```

The decode layer returns the enum variant name as a plain `String`. A proper
mapping would generate a Swift `enum` with `RawRepresentable`, but `String` is
correct and usable today:

```swift
let result = try await client.Classify(text: "I love this!") as? String
// result == "Positive"
```

**Future work:** generate `enum Sentiment: String { case Positive, Negative, Neutral }`.

---

## True Unions (multiple non-null types)

```
BAML: string | int | bool
Swift: Any
```

BAML supports discriminated unions across arbitrary types. Swift does not have
a direct equivalent without a generated enum. We fall back to `Any` and leave
the discrimination to the caller.

---

## Collections — Recursion Examples

The list and map rules apply recursively:

| BAML                  | Swift                    |
|-----------------------|--------------------------|
| `string[]`            | `[String]`               |
| `int[][]`             | `[[Int]]`                |
| `map<string, bool>`   | `[String: Bool]`         |
| `map<string, string[]>` | `[String: [String]]`  |
| `Resume[]`            | `[[String: Any?]]`       |
| `string?[]`           | `[String?]`              |

---

## What the Decode Layer Returns

The Swift type annotation is a compile-time promise. At runtime, `decode(holder)`
in `Decode.swift` fills in actual values from the `CFFIValueHolder` protobuf.
The two always agree:

| `CFFIValueHolder` variant | Decoded Swift value   | Annotated as |
|---------------------------|-----------------------|--------------|
| `.stringValue`            | `String`              | `String`     |
| `.intValue`               | `Int`                 | `Int`        |
| `.floatValue`             | `Double`              | `Double`     |
| `.boolValue`              | `Bool`                | `Bool`       |
| `.null`                   | `nil`                 | `Any?`       |
| `.list`                   | `[Any?]`              | `[T]`        |
| `.map`                    | `[String: Any?]`      | `[String: V]`|
| `.class`                  | `[String: Any?]`      | `[String: Any?]` |
| `.enum`                   | `String`              | `String`     |

---

## Roadmap

1. **Typed classes** — generate `struct Foo { var name: String; var years: Int }`
   per BAML class, and return `Foo` instead of `[String: Any?]`.
2. **Typed enums** — generate `enum Bar: String { case Positive, Negative }`.
3. **Typed unions** — generate `indirect enum` with associated values.
4. **Codable** — make generated structs conform to `Codable` for easy JSON
   interop in Xcode apps.
