use askama::Template;

use crate::ir_to_java::{classes::ClassJava, enums::EnumJava, TypeJava};
use crate::package::CurrentRenderPackage;

pub struct FunctionJava {
    pub name: String,
    pub args: Vec<(String, TypeJava)>,
    pub return_type: TypeJava,
    pub partial_return_type: TypeJava,
}

pub struct UnionJava<'a> {
    pub name: String,
    pub variants: Vec<UnionJavaVariant>,
    pub _pkg: &'a CurrentRenderPackage,
}

pub struct UnionJavaVariant {
    pub index: usize,
    pub type_java: TypeJava,
}

fn escape_java_string(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
        .replace('\t', "\\t")
}

pub fn render_source_files(file_map: &[(String, String)]) -> Result<String, askama::Error> {
    // file_map_as_json_string already JSON-encodes each key and value (adds surrounding quotes
    // and escapes special chars). Assemble the JSON object directly — do NOT call serde_json
    // again or the strings will be double-encoded.
    let entries: Vec<String> = file_map
        .iter()
        .map(|(k, v)| format!("{}:{}", k, v))
        .collect();
    let json_str = format!("{{{}}}", entries.join(","));
    let escaped = escape_java_string(&json_str);
    SourceFilesTemplate {
        file_map_json: &escaped,
    }
    .render()
}

#[derive(askama::Template)]
#[template(
    source = "package baml_client;

/**
 * BAML source file map. Do not edit.
 */
public final class BamlSourceMap {
    public static String getSourceMap() {
        return \"{{ file_map_json }}\";
    }
}
",
    ext = "txt",
    escape = "none"
)]
struct SourceFilesTemplate<'a> {
    file_map_json: &'a str,
}

#[derive(askama::Template)]
#[template(
    source = "package baml_client;

import com.boundaryml.baml.BamlRuntime;

/**
 * Globals and runtime. Requires baml-runtime-java on classpath.
 *
 * <p>The BAML source root directory defaults to {@code ./baml_src} and can be
 * overridden via the system property {@code baml.root.path}:
 * <pre>{@code
 *   java -Dbaml.root.path=/opt/app/baml_src -jar myapp.jar
 * }</pre>
 */
public final class Globals {
    private static BamlRuntime runtime;

    public static synchronized BamlRuntime getRuntime() {
        if (runtime == null) {
            String rootPath = System.getProperty(\"baml.root.path\", \"./baml_src\");
            String srcFiles = BamlSourceMap.getSourceMap();
            String envVars = \"{}\";
            runtime = BamlRuntime.create(rootPath, srcFiles, envVars);
        }
        return runtime;
    }
}
",
    ext = "txt",
    escape = "none"
)]
struct RuntimeCodeTemplate;

pub fn render_runtime_code(_pkg: &CurrentRenderPackage) -> Result<String, askama::Error> {
    RuntimeCodeTemplate {}.render()
}

// Pre-computed data for the Functions template — avoids calling methods inside Askama templates.
struct FunctionData {
    name: String,
    return_type_str: String,
    partial_type_str: String,
    args: Vec<ArgData>,
}

struct ArgData {
    name: String,
    type_str: String,
}

pub fn render_functions(
    functions: &[FunctionJava],
    _pkg: &CurrentRenderPackage,
) -> Result<String, askama::Error> {
    let data: Vec<FunctionData> = functions
        .iter()
        .map(|f| FunctionData {
            name: f.name.clone(),
            return_type_str: f.return_type.to_java_type(),
            partial_type_str: f.partial_return_type.to_java_type(),
            args: f
                .args
                .iter()
                .map(|(n, t)| ArgData {
                    name: n.clone(),
                    type_str: t.to_java_type(),
                })
                .collect(),
        })
        .collect();
    FunctionsTemplate { functions: &data }.render()
}

#[derive(askama::Template)]
#[template(
    source = "package baml_client;

import com.boundaryml.baml.BamlEncoder;
import com.boundaryml.baml.BamlDecoder;
import com.boundaryml.baml.BamlException;
import com.boundaryml.baml.BamlStream;
import java.util.concurrent.CompletableFuture;
import java.util.function.Function;

/**
 * Generated BAML function wrappers.
 *
 * <p>Use the pre-initialized singleton {@link #B} for the default pattern:
 * <pre>{@code
 *   import static baml_client.Functions.B;
 *   String result = B.MyFunction(arg);
 * }</pre>
 *
 * <p>Or construct your own instance with a custom runtime:
 * <pre>{@code
 *   Functions f = new Functions(myRuntime);
 * }</pre>
 *
 * Requires baml-runtime-java for BamlRuntime, encode/decode helpers.
 */
public final class Functions {
    /** Shared singleton client. Equivalent to {@code B} in the Rust/Python SDKs. */
    public static final Functions B = new Functions(Globals.getRuntime());

    private final com.boundaryml.baml.BamlRuntime runtime;

    public Functions(com.boundaryml.baml.BamlRuntime runtime) {
        this.runtime = runtime;
    }

{% for function in functions %}
    @SuppressWarnings(\"unchecked\")
    public {{ function.return_type_str }} {{ function.name }}({% for arg in function.args %}{{ arg.type_str }} {{ arg.name }}{% if !loop.last %}, {% endif %}{% endfor %}) throws BamlException {
        java.util.Map<String, Object> kwargs = new java.util.LinkedHashMap<>();
{% for arg in function.args %}
        kwargs.put(\"{{ arg.name }}\", {{ arg.name }});
{% endfor %}
        byte[] encoded = BamlEncoder.encodeArgs(kwargs);
        byte[] response = runtime.callFunctionParse(\"{{ function.name }}\", encoded);
        return ({{ function.return_type_str }}) BamlDecoder.decodeResult(response);
    }

    @SuppressWarnings(\"unchecked\")
    public CompletableFuture<{{ function.return_type_str }}> {{ function.name }}Async({% for arg in function.args %}{{ arg.type_str }} {{ arg.name }}{% if !loop.last %}, {% endif %}{% endfor %}) {
        java.util.Map<String, Object> kwargs = new java.util.LinkedHashMap<>();
{% for arg in function.args %}
        kwargs.put(\"{{ arg.name }}\", {{ arg.name }});
{% endfor %}
        byte[] encoded = BamlEncoder.encodeArgs(kwargs);
        return runtime.callFunctionParseAsync(\"{{ function.name }}\", encoded)
            .thenApply(bytes -> ({{ function.return_type_str }}) BamlDecoder.decodeResult(bytes));
    }

    @SuppressWarnings(\"unchecked\")
    public BamlStream<{{ function.partial_type_str }}, {{ function.return_type_str }}> {{ function.name }}Stream({% for arg in function.args %}{{ arg.type_str }} {{ arg.name }}{% if !loop.last %}, {% endif %}{% endfor %}) {
        java.util.Map<String, Object> kwargs = new java.util.LinkedHashMap<>();
{% for arg in function.args %}
        kwargs.put(\"{{ arg.name }}\", {{ arg.name }});
{% endfor %}
        byte[] encoded = BamlEncoder.encodeArgs(kwargs);
        Function<byte[], {{ function.partial_type_str }}> partialDecoder =
            bytes -> ({{ function.partial_type_str }}) BamlDecoder.decodeResult(bytes);
        Function<byte[], {{ function.return_type_str }}> finalDecoder =
            bytes -> ({{ function.return_type_str }}) BamlDecoder.decodeResult(bytes);
        return runtime.callFunctionStream(\"{{ function.name }}\", encoded, partialDecoder, finalDecoder);
    }

{% endfor %}
}
",
    ext = "txt",
    escape = "none"
)]
struct FunctionsTemplate<'a> {
    functions: &'a [FunctionData],
}

// Helper to capitalize first letter
fn capitalize_first(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        None => String::new(),
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
    }
}

struct ClassFieldData {
    type_str: String,
    name: String,
    capitalized_name: String,
}

struct ClassData {
    name: String,
    fields: Vec<ClassFieldData>,
    dynamic: bool,
}

pub fn render_classes(
    classes: &[ClassJava],
    _pkg: &CurrentRenderPackage,
) -> Result<String, askama::Error> {
    let data: Vec<ClassData> = classes
        .iter()
        .map(|c| ClassData {
            name: c.name.clone(),
            dynamic: c.dynamic,
            fields: c
                .fields
                .iter()
                .map(|f| ClassFieldData {
                    type_str: f.r#type.to_java_type(),
                    name: f.name.clone(),
                    capitalized_name: capitalize_first(&f.name),
                })
                .collect(),
        })
        .collect();
    ClassesTemplate { classes: &data }.render()
}

#[derive(askama::Template)]
#[template(
    source = "package baml_client;

/**
 * Generated BAML class types.
 */
public class Types {
{% for class in classes %}
    public static class {{ class.name }} {
{% for field in class.fields %}
        private {{ field.type_str }} {{ field.name }};
{% endfor %}
{% if class.dynamic %}
        private java.util.Map<String, Object> dynamicProperties;
{% endif %}

{% for field in class.fields %}
        public {{ field.type_str }} get{{ field.capitalized_name }}() {
            return this.{{ field.name }};
        }

        public void set{{ field.capitalized_name }}({{ field.type_str }} {{ field.name }}) {
            this.{{ field.name }} = {{ field.name }};
        }
{% endfor %}
    }
{% endfor %}
}
",
    ext = "txt",
    escape = "none"
)]
struct ClassesTemplate<'a> {
    classes: &'a [ClassData],
}

pub fn render_enums(
    enums: &[EnumJava],
    pkg: &CurrentRenderPackage,
) -> Result<String, askama::Error> {
    EnumsTemplate { enums, _pkg: pkg }.render()
}

#[derive(askama::Template)]
#[template(
    source = "package baml_client;

/**
 * Generated BAML enum types.
 */
public class Enums {
{% for enum_ in enums %}
    public enum {{ enum_.name }} {
        {% for (value, _) in enum_.values %}
        {{ value }}{% if !loop.last %},{% endif %}
        {% endfor %}
    }
{% endfor %}
}
",
    ext = "txt",
    escape = "none"
)]
struct EnumsTemplate<'a> {
    enums: &'a [EnumJava<'a>],
    _pkg: &'a CurrentRenderPackage,
}

struct UnionData {
    name: String,
    variant_types: String,
}

/// Generates union type helper stubs for Java.
/// In Java (targeting Java 11+), union types are represented as Object at runtime;
/// each variant is accessed via instanceof checks or by calling BamlDecoder.decodeResult()
/// and casting to the expected type.
pub fn render_unions(
    unions: &[UnionJava<'_>],
    _pkg: &CurrentRenderPackage,
) -> Result<String, askama::Error> {
    let data: Vec<UnionData> = unions
        .iter()
        .map(|u| UnionData {
            name: u.name.clone(),
            variant_types: u
                .variants
                .iter()
                .map(|v| v.type_java.to_java_type())
                .collect::<Vec<_>>()
                .join(" | "),
        })
        .collect();
    UnionsTemplate { unions: &data }.render()
}

#[derive(askama::Template)]
#[template(
    source = "package baml_client;

/**
 * Generated BAML union type stubs.
 * Each union is represented as Object at runtime; cast to the expected variant.
 */
public final class Unions {
    private Unions() {}

{% for u in unions %}
    // Union: {{ u.name }} — variants: {{ u.variant_types }}
    // Use BamlDecoder.decodeResult(bytes) and cast to the expected variant.

{% endfor %}
}
",
    ext = "txt",
    escape = "none"
)]
struct UnionsTemplate<'a> {
    unions: &'a [UnionData],
}
