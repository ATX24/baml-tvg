import XCTest
@testable import BamlSwift

/// Integration tests calling real LLM endpoints via OpenRouter.
///
/// Required environment variables:
///   OPENROUTER_API_KEY — your OpenRouter API key
///   BAML_LIBRARY_PATH  — path to libbaml_cffi.dylib (macOS only; skips download)
///
/// Run with:
///   OPENROUTER_API_KEY=sk-or-... BAML_LIBRARY_PATH=/path/to/libbaml_cffi.dylib swift test
final class BamlSwiftTests: XCTestCase {

    // MARK: - Shared runtime (created once per test suite)

    private static var runtime: BamlRuntime?

    override class func setUp() {
        super.setUp()
        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
              !apiKey.isEmpty else {
            // Tests will each be skipped via XCTSkip
            return
        }
        do {
            let srcFiles: [String: String] = [
                "clients.baml": clientsBaml,
                "functions.baml": functionsBaml,
            ]
            runtime = try BamlRuntime(
                rootPath: "/",
                srcFiles: srcFiles,
                envVars: ["OPENROUTER_API_KEY": apiKey]
            )
        } catch {
            XCTFail("Failed to create BamlRuntime: \(error)")
        }
    }

    // MARK: - Helpers

    /// Calls a BAML function and decodes the response to the expected Swift type.
    private func callBaml<T>(_ fn: String, args: [String: Any]) async throws -> T {
        guard let rt = Self.runtime else {
            throw XCTSkip("OPENROUTER_API_KEY not set — skipping integration test")
        }
        let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        let encoded = try BamlEncoder.encodeFunctionArgs(
            kwargs: args,
            envVars: ["OPENROUTER_API_KEY": apiKey]
        )
        let responseData = try await rt.callFunction(name: fn, args: encoded)
        let holder = try BamlDecoder.decodeResponse(responseData)
        guard let value = BamlDecoder.decode(holder) as? T else {
            throw BamlError.decodingFailed(
                "Expected \(T.self), got: \(String(describing: BamlDecoder.decode(holder)))"
            )
        }
        return value
    }

    // MARK: - String output tests

    func testSayHello() async throws {
        guard Self.runtime != nil else { throw XCTSkip("OPENROUTER_API_KEY not set") }
        let result: String = try await callBaml("SayHello", args: ["name": "World"])
        XCTAssert(
            result.lowercased().contains("hello"),
            "Expected greeting to contain 'hello', got: \(result)"
        )
    }

    func testSayHelloWithUnicodeName() async throws {
        guard Self.runtime != nil else { throw XCTSkip("OPENROUTER_API_KEY not set") }
        let result: String = try await callBaml("SayHello", args: ["name": "世界"])
        XCTAssert(!result.isEmpty, "Expected non-empty response, got empty string")
    }

    // MARK: - Enum output tests

    func testClassifySentimentPositive() async throws {
        guard Self.runtime != nil else { throw XCTSkip("OPENROUTER_API_KEY not set") }
        let result: String = try await callBaml(
            "ClassifySentiment",
            args: ["text": "I absolutely love this product! It's fantastic!"]
        )
        XCTAssertEqual(result, "Positive", "Expected Positive sentiment")
    }

    func testClassifySentimentNegative() async throws {
        guard Self.runtime != nil else { throw XCTSkip("OPENROUTER_API_KEY not set") }
        let result: String = try await callBaml(
            "ClassifySentiment",
            args: ["text": "This is terrible. I hate it completely."]
        )
        XCTAssertEqual(result, "Negative", "Expected Negative sentiment")
    }

    func testClassifySentimentNeutral() async throws {
        guard Self.runtime != nil else { throw XCTSkip("OPENROUTER_API_KEY not set") }
        let result: String = try await callBaml(
            "ClassifySentiment",
            args: ["text": "The package arrived on Tuesday."]
        )
        XCTAssertEqual(result, "Neutral", "Expected Neutral sentiment")
    }

    // MARK: - Class (struct) output tests

    func testExtractGreeting() async throws {
        guard Self.runtime != nil else { throw XCTSkip("OPENROUTER_API_KEY not set") }
        let result: [String: Any?] = try await callBaml(
            "ExtractGreeting",
            args: ["text": "Good morning, Alice!"]
        )
        XCTAssertNotNil(result["name"] as Any?, "Expected 'name' field in result")
        let name = result["name"] as? String ?? ""
        XCTAssert(
            name.contains("Alice"),
            "Expected 'Alice' in name field, got: \(name)"
        )
    }

    // MARK: - Streaming tests

    func testSayHelloStream() async throws {
        guard let rt = Self.runtime else { throw XCTSkip("OPENROUTER_API_KEY not set") }
        let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? ""
        let encoded = try BamlEncoder.encodeFunctionArgs(
            kwargs: ["name": "Swift"],
            envVars: ["OPENROUTER_API_KEY": apiKey]
        )

        var chunks: [String] = []
        var lastHolder: Baml_Cffi_V1_CFFIValueHolder?

        for try await data in rt.callFunctionStream(name: "SayHello", args: encoded) {
            let holder = try BamlDecoder.decodeResponse(data)
            lastHolder = holder
            // Streaming chunks may be partial strings or StreamingState wrappers
            if let s = BamlDecoder.decode(holder) as? String {
                chunks.append(s)
            }
        }

        XCTAssertNotNil(lastHolder, "Expected at least one stream chunk")
        // The final decoded value should contain "hello"
        let finalValue = lastHolder.flatMap { BamlDecoder.decode($0) }
        let finalString = finalValue as? String ?? ""
        XCTAssert(
            finalString.lowercased().contains("hello"),
            "Expected 'hello' in final stream value, got: \(finalString)"
        )
    }

    // MARK: - Embedded BAML sources

    private static let clientsBaml = """
    retry_policy Retry {
      max_retries 3
      strategy {
        type exponential_backoff
      }
    }

    client<llm> OpenRouterTest {
      provider openrouter
      retry_policy Retry
      options {
        model "stepfun/step-3.5-flash:free"
        api_key env.OPENROUTER_API_KEY
        temperature 0
        max_tokens 8192
      }
    }
    """

    private static let functionsBaml = """
    function SayHello(name: string) -> string {
      client OpenRouterTest
      prompt #"
        Say "Hello, {{ name }}!" and nothing else.
      "#
    }

    enum Sentiment {
      Positive
      Negative
      Neutral
    }

    function ClassifySentiment(text: string) -> Sentiment {
      client OpenRouterTest
      prompt #"
        Classify the sentiment of the following text as Positive, Negative, or Neutral.

        Text: {{ text }}

        {{ ctx.output_format }}
      "#
    }

    class NamedGreeting {
      greeting string
      name string
    }

    function ExtractGreeting(text: string) -> NamedGreeting {
      client OpenRouterTest
      prompt #"
        Extract the greeting and name from this text.

        Text: {{ text }}

        {{ ctx.output_format }}
      "#
    }
    """
}
