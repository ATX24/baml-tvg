use baml_types::{
    baml_value::TypeLookups,
    ir_type::{TypeGeneric, TypeNonStreaming},
    ConstraintLevel, TypeValue,
};

pub mod classes;
pub mod enums;
pub mod functions;

#[derive(Clone, Debug, PartialEq)]
pub enum TypeJava {
    String,
    Int,
    Float,
    Bool,
    Null,
    Class {
        name: String,
        dynamic: bool,
    },
    Enum {
        name: String,
        dynamic: bool,
    },
    Union {
        name: String,
        /// Java type representations for each variant in the union.
        /// Used by the code generator to emit concrete union helper types.
        options: Vec<TypeJava>,
    },
    TypeAlias {
        name: String,
    },
    List(Box<TypeJava>),
    Map(Box<TypeJava>, Box<TypeJava>),
    Optional(Box<TypeJava>),
    Any {
        reason: String,
    },
}

impl TypeJava {
    /// Returns the Java type string used in the *partial* (streaming) variant of a generated class.
    ///
    /// Rules:
    /// - Primitives (`String`, `long`, `double`, `boolean`) keep their type — a partial string is
    ///   just the string emitted so far; no wrapper is needed.
    /// - BAML class fields become `java.util.Optional<Types.PartialClassName>`.
    /// - Enum / union fields become `java.util.Optional<…>` (may not be resolved mid-stream).
    /// - `java.util.List<T>` → `java.util.Optional<java.util.List<T>>`.
    /// - Types already wrapped in `Optional` stay as-is.
    /// - `Object` / `Void` fall back to their normal type.
    pub fn to_partial_java_type(&self) -> String {
        match self {
            // Primitives — the partial value IS the value produced so far.
            TypeJava::String => "String".to_string(),
            TypeJava::Int => "long".to_string(),
            TypeJava::Float => "double".to_string(),
            TypeJava::Bool => "boolean".to_string(),
            TypeJava::Null => "Void".to_string(),
            // Class fields reference the generated Partial sibling.
            TypeJava::Class { name, .. } => {
                format!("java.util.Optional<Types.Partial{name}>")
            }
            // Enum / union / alias — may not be resolved yet in a partial result.
            TypeJava::Enum { name, .. } => format!("java.util.Optional<Enums.{name}>"),
            TypeJava::Union { name, .. } => format!("java.util.Optional<Unions.{name}>"),
            TypeJava::TypeAlias { name } => format!("java.util.Optional<{name}>"),
            // Collections — wrap the whole collection as optional.
            TypeJava::List(inner) => {
                format!("java.util.Optional<java.util.List<{}>>", inner.to_java_type())
            }
            TypeJava::Map(k, v) => format!(
                "java.util.Optional<java.util.Map<{}, {}>>",
                k.to_java_type(),
                v.to_java_type()
            ),
            // Already optional — keep as-is.
            TypeJava::Optional(inner) => {
                format!("java.util.Optional<{}>", inner.to_java_type())
            }
            TypeJava::Any { .. } => "Object".to_string(),
        }
    }

    pub fn to_java_type(&self) -> String {
        match self {
            TypeJava::String => "String".to_string(),
            TypeJava::Int => "long".to_string(),
            TypeJava::Float => "double".to_string(),
            TypeJava::Bool => "boolean".to_string(),
            TypeJava::Null => "Void".to_string(),
            TypeJava::Class { name, .. }
            | TypeJava::Enum { name, .. }
            | TypeJava::Union { name, .. }
            | TypeJava::TypeAlias { name } => name.clone(),
            TypeJava::List(inner) => format!("java.util.List<{}>", inner.to_java_type()),
            TypeJava::Map(k, v) => {
                format!("java.util.Map<{}, {}>", k.to_java_type(), v.to_java_type())
            }
            TypeJava::Optional(inner) => format!("java.util.Optional<{}>", inner.to_java_type()),
            TypeJava::Any { reason: _ } => "Object".to_string(),
        }
    }
}

pub fn type_to_java(field: &TypeNonStreaming, lookup: &impl TypeLookups) -> TypeJava {
    use TypeJava as J;

    let recursive_fn = |f: &TypeNonStreaming| type_to_java(f, lookup);

    match field {
        TypeGeneric::Primitive(type_value, _) => match type_value {
            TypeValue::String => J::String,
            TypeValue::Int => J::Int,
            TypeValue::Float => J::Float,
            TypeValue::Bool => J::Bool,
            TypeValue::Null => J::Null,
            _ => J::Any {
                reason: format!("Unsupported primitive: {type_value:?}"),
            },
        },
        TypeGeneric::Enum { name, dynamic, .. } => J::Enum {
            name: name.clone(),
            dynamic: *dynamic,
        },
        TypeGeneric::Literal(literal_value, _) => match literal_value {
            baml_types::LiteralValue::String(_) => J::String,
            baml_types::LiteralValue::Int(_) => J::Int,
            baml_types::LiteralValue::Bool(_) => J::Bool,
        },
        TypeGeneric::Class { name, dynamic, .. } => J::Class {
            name: name.clone(),
            dynamic: *dynamic,
        },
        TypeGeneric::List(type_generic, _) => J::List(Box::new(recursive_fn(type_generic))),
        TypeGeneric::Map(k, v, _) => J::Map(Box::new(recursive_fn(k)), Box::new(recursive_fn(v))),
        TypeGeneric::RecursiveTypeAlias { name, .. } => match lookup.expand_recursive_type(name) {
            Ok(expanded_ir) => {
                // Resolve the alias to its underlying non-streaming type and translate that.
                let expanded_non_streaming = expanded_ir.to_non_streaming_type(lookup);
                type_to_java(&expanded_non_streaming, lookup)
            }
            Err(_) => J::Any {
                reason: format!("Recursive type alias {name} not fully supported"),
            },
        },
        TypeGeneric::Tuple(..) => J::Any {
            reason: "Tuples are not supported in Java".to_string(),
        },
        TypeGeneric::Arrow(..) => J::Any {
            reason: "Arrow types are not supported in Java".to_string(),
        },
        TypeGeneric::Union(union_type_generic, union_meta) => {
            let has_checks = union_meta
                .constraints
                .iter()
                .any(|c| matches!(c.level, ConstraintLevel::Check));

            match union_type_generic.view() {
                baml_types::ir_type::UnionTypeViewGeneric::Null => J::Null,
                baml_types::ir_type::UnionTypeViewGeneric::Optional(type_generic) => {
                    let inner = recursive_fn(type_generic);
                    if has_checks {
                        J::Optional(Box::new(inner))
                    } else {
                        J::Optional(Box::new(inner))
                    }
                }
                baml_types::ir_type::UnionTypeViewGeneric::OneOf(type_generics) => {
                    let options: Vec<_> = type_generics.iter().map(|t| recursive_fn(t)).collect();
                    let num_options = options.len();
                    let mut names: Vec<String> =
                        options.iter().map(|t| t.default_union_name()).collect();
                    names.sort();
                    let name = format!("Union{num_options}{}", names.join("Or"));
                    J::Union { name, options }
                }
                baml_types::ir_type::UnionTypeViewGeneric::OneOfOptional(type_generics) => {
                    let options: Vec<_> = type_generics.iter().map(|t| recursive_fn(t)).collect();
                    let num_options = options.len();
                    let mut names: Vec<String> =
                        options.iter().map(|t| t.default_union_name()).collect();
                    names.sort();
                    let name = format!("Union{num_options}{}Optional", names.join("Or"));
                    J::Union { name, options }
                }
            }
        }
        TypeGeneric::Top(_) => J::Any {
            reason: "Top type not supported".to_string(),
        },
    }
}

impl TypeJava {
    fn default_union_name(&self) -> String {
        match self {
            TypeJava::Null => "Null".to_string(),
            TypeJava::String => "String".to_string(),
            TypeJava::Int => "Int".to_string(),
            TypeJava::Float => "Float".to_string(),
            TypeJava::Bool => "Bool".to_string(),
            TypeJava::Class { name, .. }
            | TypeJava::Enum { name, .. }
            | TypeJava::Union { name, .. }
            | TypeJava::TypeAlias { name } => name.clone(),
            TypeJava::List(inner) => format!("List{}", inner.default_union_name()),
            TypeJava::Map(k, v) => {
                format!("Map{}{}", k.default_union_name(), v.default_union_name())
            }
            TypeJava::Optional(inner) => format!("Optional{}", inner.default_union_name()),
            TypeJava::Any { .. } => "Any".to_string(),
        }
    }
}
