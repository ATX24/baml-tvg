import XCTest
import BamlClient

/// Integration tests using the generated typed BAML client.
///
/// Requires:
///   export OPENROUTER_API_KEY=<your-key>
///   export BAML_LIBRARY_PATH=<path-to-libbaml_cffi.dylib>
///
/// Run with:
///   swift test --filter BamlIntegTests
final class BamlIntegTests: XCTestCase {

    // Skip all tests if the API key is absent
    var shouldSkip: Bool {
        ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] == nil
    }

    // MARK: - SayHello (string return)

    func testSayHello() async throws {
        guard !shouldSkip else {
            print("Skipping testSayHello: OPENROUTER_API_KEY not set")
            return
        }
        let result = try await SayHello(name: "World")
        XCTAssertTrue(result.lowercased().contains("hello"), "Expected greeting, got: \(result)")
        print("SayHello result: \(result)")
    }

    // MARK: - ClassifySentiment (enum return)

    func testClassifySentimentPositive() async throws {
        guard !shouldSkip else {
            print("Skipping testClassifySentimentPositive: OPENROUTER_API_KEY not set")
            return
        }
        let result = try await ClassifySentiment(text: "I love this product! It's amazing!")
        XCTAssertEqual(result, .Positive)
        print("ClassifySentiment result: \(result)")
    }

    func testClassifySentimentNegative() async throws {
        guard !shouldSkip else {
            print("Skipping testClassifySentimentNegative: OPENROUTER_API_KEY not set")
            return
        }
        let result = try await ClassifySentiment(text: "This is terrible and I hate it.")
        XCTAssertEqual(result, .Negative)
        print("ClassifySentiment result: \(result)")
    }

    // MARK: - ExtractGreeting (struct return)

    func testExtractGreeting() async throws {
        guard !shouldSkip else {
            print("Skipping testExtractGreeting: OPENROUTER_API_KEY not set")
            return
        }
        let result = try await ExtractGreeting(text: "Good morning, Alice!")
        XCTAssertFalse(result.name.isEmpty, "name should not be empty")
        XCTAssertFalse(result.greeting.isEmpty, "greeting should not be empty")
        print("ExtractGreeting result: name=\(result.name), greeting=\(result.greeting)")
    }

    // MARK: - ExtractResume (struct with array return)

    func testExtractResume() async throws {
        guard !shouldSkip else {
            print("Skipping testExtractResume: OPENROUTER_API_KEY not set")
            return
        }
        let resumeText = """
        Jane Smith is a software engineer with 5 years of experience.
        She is skilled in Swift, Rust, and Python.
        """
        let result = try await ExtractResume(text: resumeText)
        XCTAssertFalse(result.name.isEmpty, "name should not be empty")
        XCTAssertFalse(result.skills.isEmpty, "skills should not be empty")
        XCTAssertGreaterThan(result.years_experience, 0)
        print("ExtractResume result: name=\(result.name), skills=\(result.skills), years=\(result.years_experience)")
    }

    // MARK: - Streaming

    func testSayHelloStream() async throws {
        guard !shouldSkip else {
            print("Skipping testSayHelloStream: OPENROUTER_API_KEY not set")
            return
        }
        var chunks: [String] = []
        for try await chunk in try SayHelloStream(name: "Swift") {
            chunks.append(chunk)
        }
        XCTAssertFalse(chunks.isEmpty, "Should receive at least one streaming chunk")
        let combined = chunks.joined()
        XCTAssertFalse(combined.isEmpty, "Combined streaming result should not be empty")
        print("SayHelloStream received \(chunks.count) chunks: \(combined)")
    }
}
