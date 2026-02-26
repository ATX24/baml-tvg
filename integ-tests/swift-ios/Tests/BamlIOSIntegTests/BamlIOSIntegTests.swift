import XCTest
import BamlClient

/// iOS integration tests using the generated typed BAML client.
///
/// These tests verify that the XCFramework static linking path works correctly.
/// No BAML_LIBRARY_PATH needed — the Rust library is statically linked at build time.
///
/// Run via xcodebuild:
///   xcodebuild test \
///     -scheme BamlIOSIntegTests \
///     -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
///     -testEnvironmentVariables "OPENROUTER_API_KEY=sk-or-..."
final class BamlIOSIntegTests: XCTestCase {

    var shouldSkip: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["OPENROUTER_API_KEY"] == nil && env["TEST_RUNNER_OPENROUTER_API_KEY"] == nil
    }

    // MARK: - Static linking smoke test

    func testRuntimeInitializes() {
        // If the XCFramework is correctly linked, bamlClient will initialize
        // without crashing. This test passes simply by reaching this line.
        _ = bamlClient
    }

    // MARK: - SayHello (string return)

    func testSayHello() async throws {
        guard !shouldSkip else { return }
        let result = try await SayHello(name: "iOS")
        XCTAssertTrue(result.lowercased().contains("hello"), "Expected greeting, got: \(result)")
        print("SayHello (iOS) result: \(result)")
    }

    // MARK: - ClassifySentiment (enum return)

    func testClassifySentimentPositive() async throws {
        guard !shouldSkip else { return }
        let result = try await ClassifySentiment(text: "I love this! It's fantastic!")
        XCTAssertEqual(result, .Positive)
        print("ClassifySentiment (iOS) result: \(result)")
    }

    func testClassifySentimentNegative() async throws {
        guard !shouldSkip else { return }
        let result = try await ClassifySentiment(text: "This is awful and terrible.")
        XCTAssertEqual(result, .Negative)
        print("ClassifySentiment (iOS) result: \(result)")
    }

    // MARK: - ExtractGreeting (struct return)

    func testExtractGreeting() async throws {
        guard !shouldSkip else { return }
        let result = try await ExtractGreeting(text: "Good morning, Bob!")
        XCTAssertFalse(result.name.isEmpty)
        XCTAssertFalse(result.greeting.isEmpty)
        print("ExtractGreeting (iOS) result: name=\(result.name), greeting=\(result.greeting)")
    }

    // MARK: - ExtractResume (struct with array)

    func testExtractResume() async throws {
        guard !shouldSkip else { return }
        let resumeText = """
        Alex Johnson is a mobile engineer with 3 years of experience.
        Skilled in Swift, SwiftUI, and Objective-C.
        """
        let result = try await ExtractResume(text: resumeText)
        XCTAssertFalse(result.name.isEmpty)
        XCTAssertFalse(result.skills.isEmpty)
        XCTAssertGreaterThan(result.years_experience, 0)
        print("ExtractResume (iOS) result: name=\(result.name), skills=\(result.skills), years=\(result.years_experience)")
    }

    // MARK: - Streaming

    func testSayHelloStream() async throws {
        guard !shouldSkip else { return }
        var chunks: [String] = []
        for try await chunk in try SayHelloStream(name: "iOS") {
            chunks.append(chunk)
        }
        XCTAssertFalse(chunks.isEmpty, "Should receive at least one streaming chunk")
        print("SayHelloStream (iOS) chunks: \(chunks.count), combined: \(chunks.joined())")
    }
}
