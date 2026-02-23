import XCTest
@testable import BamlSwift
import BamlClient

final class HelloWorldTests: XCTestCase {

    // Set BAML_LIBRARY_PATH to the compiled libbaml_cffi.dylib before running.
    // e.g. BAML_LIBRARY_PATH=engine/target/release/libbaml_cffi.dylib swift test
    static let libPath = ProcessInfo.processInfo.environment["BAML_LIBRARY_PATH"] ?? ""

    override class func setUp() {
        super.setUp()
        guard !libPath.isEmpty else { return }
        do {
            try loadBamlLibrary(path: libPath)
        } catch {
            XCTFail("Failed to load BAML library: \(error)")
        }
    }

    func testSkipIfNoLibrary() throws {
        guard !Self.libPath.isEmpty else {
            print("⚠️  Skipping BAML tests — set BAML_LIBRARY_PATH to run them")
            return
        }
    }

    // MARK: - Step 1: version()

    func testVersion() throws {
        guard !Self.libPath.isEmpty else { return }
        let v = try BamlRuntime.version()
        XCTAssertFalse(v.isEmpty, "version() should return a non-empty string")
        print("✅ BAML version: \(v)")
    }

    // MARK: - Step 2: create a runtime with inline BAML source

    func testCreateRuntime() throws {
        guard !Self.libPath.isEmpty else { return }

        let bamlSource = """
        function Greet(name: string) -> string {
          client "openai/gpt-4o-mini"
          prompt #"
            Say hello to {{ name }} in one sentence.
            {{ ctx.output_format }}
          "#
        }
        """

        // create_baml_runtime does NOT require an API key — it just parses the source.
        let runtime = try BamlRuntime(
            rootPath: ".",
            srcFiles: ["greet.baml": bamlSource],
            envVars: [:]
        )
        XCTAssertNotNil(runtime)
        print("✅ BamlRuntime created successfully")
    }

    // MARK: - Step 3: callFunction via generated BamlClient using OpenRouter

    func testGeneratedClientWithOpenRouter() async throws {
        guard !Self.libPath.isEmpty else { return }
        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !apiKey.isEmpty else {
            print("⚠️  Skipping LLM call — set OPENROUTER_API_KEY to run this test")
            return
        }

        // Read the BAML source files from disk (or inline them here)
        let bamlSource = """
        client<llm> OpenRouter {
          provider openai
          options {
            model "meta-llama/llama-3.2-3b-instruct:free"
            base_url "https://openrouter.ai/api/v1"
            api_key env.OPENROUTER_API_KEY
          }
        }

        function SayHello(name: string) -> string {
          client OpenRouter
          prompt #"
            Say hello to {{ name }} in a friendly one-sentence greeting.
            Return only the greeting, no extra text.
            {{ ctx.output_format }}
          "#
        }

        function Classify(text: string) -> string {
          client OpenRouter
          prompt #"
            Classify the following text as one of: positive, negative, or neutral.
            Reply with only the single word label.
            {{ ctx.output_format }}

            Text: {{ text }}
          "#
        }
        """

        let runtime = try BamlRuntime(
            rootPath: ".",
            srcFiles: ["main.baml": bamlSource],
            envVars: ["OPENROUTER_API_KEY": apiKey]
        )

        // Use the generated BamlClient — same API you'd use from an Xcode project
        let client = BamlClient(runtime: runtime)

        let greeting = try await client.SayHello(name: "Swift")
        print("✅ SayHello(\"Swift\") → \(greeting ?? "nil")")
        XCTAssertNotNil(greeting)

        let sentiment = try await client.Classify(text: "I absolutely love this!")
        print("✅ Classify(\"I absolutely love this!\") → \(sentiment ?? "nil")")
        XCTAssertNotNil(sentiment)
    }

    // MARK: - Legacy test (raw callFunction, kept for reference)

    func testCallFunctionRaw() async throws {
        guard !Self.libPath.isEmpty else { return }
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            print("⚠️  Skipping raw LLM call — set OPENAI_API_KEY to run this test")
            return
        }

        let bamlSource = """
        function Greet(name: string) -> string {
          client "openai/gpt-4o-mini"
          prompt #"
            Say hello to {{ name }} in one sentence.
            {{ ctx.output_format }}
          "#
        }
        """

        let runtime = try BamlRuntime(
            rootPath: ".",
            srcFiles: ["greet.baml": bamlSource],
            envVars: ["OPENAI_API_KEY": apiKey]
        )

        let args = try encodeArgs(kwargs: ["name": "World"])
        let result = try await runtime.callFunction(name: "Greet", args: args)
        let value = decode(result)

        print("✅ Greet(\"World\") returned: \(value ?? "nil")")
        XCTAssertNotNil(value)
    }
}
