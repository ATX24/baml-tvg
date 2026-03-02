import XCTest
import BamlSwift
import BamlClient

/// iOS smoke tests — verify XCFramework static linking and BAML setup.
///
/// These tests do NOT call any LLM endpoints and require no API keys.
/// They confirm:
///   1. XCFramework is correctly linked (Rust FFI symbols resolve at load time)
///   2. BAML runtime initialises from the generated file map
///   3. Generated Swift types instantiate and encode correctly
final class BamlIOSIntegTests: XCTestCase {

    // MARK: - Static linking smoke test

    func testRuntimeInitializes() {
        // If the XCFramework is correctly linked, bamlClient will initialize
        // without crashing. This test passes simply by reaching this line.
        _ = bamlClient
    }

    // MARK: - Generated type instantiation

    func testGeneratedTypesInstantiate() {
        let resume = Resume(name: "Alice", skills: ["Swift", "Rust"], years_experience: 5)
        XCTAssertEqual(resume.name, "Alice")
        XCTAssertEqual(resume.skills.count, 2)
        XCTAssertEqual(resume.years_experience, 5)

        let greeting = NamedGreeting(greeting: "Hello", name: "Bob")
        XCTAssertEqual(greeting.greeting, "Hello")
        XCTAssertEqual(greeting.name, "Bob")

        XCTAssertEqual(Sentiment.Positive.rawValue, "Positive")
        XCTAssertEqual(Sentiment.Negative.rawValue, "Negative")
    }

    // MARK: - Encoder smoke test

    func testEncoderProducesData() throws {
        // Exercises the protobuf encoding path in the Swift ↔ Rust bridge.
        let data = try BamlEncoder.encodeFunctionArgs(
            kwargs: ["name": "World"],
            envVars: [:]
        )
        XCTAssertFalse(data.isEmpty, "Encoded protobuf data should be non-empty")
    }
}
