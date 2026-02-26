use baml_types::{
    ir_type::{TypeGeneric, TypeNonStreaming, TypeStreaming},
    ToUnionName,
};

use crate::r#type::TypeSwift;

pub fn ir_union_to_swift(
    union: &TypeNonStreaming,
    lookup: &impl baml_types::baml_value::TypeLookups,
) -> impl Iterator<Item = crate::generated_types::UnionSwift> {
    let swift_type = crate::ir_to_swift::type_to_swift(union, lookup);
    let result: std::vec::IntoIter<crate::generated_types::UnionSwift> = swift_type
        .flatten_unions()
        .into_iter()
        .filter_map(|swift_type| {
            if let TypeSwift::Union { name, .. } = swift_type {
                let TypeNonStreaming::Union(union_type_generic, _) = union else {
                    panic!("ir_union_to_swift expects a union. Got: {union}");
                };
                let variants = union_type_generic
                    .iter_skip_null()
                    .iter()
                    .map(|t| {
                        let swift_type = crate::ir_to_swift::type_to_swift(t, lookup);
                        crate::generated_types::VariantSwift {
                            name: swift_type.default_name_within_union(),
                            cffi_name: t.to_union_name(false),
                            literal_repr: match t {
                                TypeGeneric::Literal(l, ..) => match l {
                                    baml_types::LiteralValue::String(s) => Some(format!(
                                        "\"{}\"",
                                        s.replace("\\", "\\\\").replace("\"", "\\\"")
                                    )),
                                    baml_types::LiteralValue::Int(i) => Some(i.to_string()),
                                    baml_types::LiteralValue::Bool(true) => {
                                        Some("true".to_string())
                                    }
                                    baml_types::LiteralValue::Bool(false) => {
                                        Some("false".to_string())
                                    }
                                },
                                _ => None,
                            },
                            type_: swift_type,
                        }
                    })
                    .collect::<Vec<_>>();
                Some(crate::generated_types::UnionSwift {
                    name: name.clone(),
                    cffi_name: union.to_union_name(false),
                    docstring: Some(format!("Generated from: {union}")),
                    variants,
                })
            } else {
                None
            }
        })
        .collect::<Vec<_>>()
        .into_iter();
    result
}

pub fn ir_union_to_swift_stream(
    stream_union: &TypeStreaming,
    lookup: &impl baml_types::baml_value::TypeLookups,
) -> impl Iterator<Item = crate::generated_types::UnionSwift> {
    if matches!(
        stream_union.mode(&baml_types::StreamingMode::Streaming, lookup, 1),
        Ok(baml_types::StreamingMode::NonStreaming) | Err(_)
    ) {
        return Vec::new().into_iter();
    }
    let swift_type = crate::ir_to_swift::stream_type_to_swift(stream_union, lookup);
    let result: Vec<crate::generated_types::UnionSwift> = swift_type
        .flatten_unions()
        .into_iter()
        .filter_map(|swift_type| {
            if let TypeSwift::Union { name, .. } = swift_type {
                let TypeStreaming::Union(union_type_generic, _) = stream_union else {
                    panic!("ir_union_to_swift expects a union. Got: {stream_union}");
                };
                let variants = union_type_generic
                    .iter_skip_null()
                    .iter()
                    .map(|t| {
                        let swift_type =
                            crate::ir_to_swift::stream_type_to_swift(t, lookup);
                        crate::generated_types::VariantSwift {
                            name: swift_type.default_name_within_union(),
                            cffi_name: t.to_union_name(false),
                            literal_repr: match t {
                                TypeGeneric::Literal(l, ..) => match l {
                                    baml_types::LiteralValue::String(s) => Some(format!(
                                        "\"{}\"",
                                        s.replace("\\", "\\\\").replace("\"", "\\\"")
                                    )),
                                    baml_types::LiteralValue::Int(i) => Some(i.to_string()),
                                    baml_types::LiteralValue::Bool(true) => {
                                        Some("true".to_string())
                                    }
                                    baml_types::LiteralValue::Bool(false) => {
                                        Some("false".to_string())
                                    }
                                },
                                _ => None,
                            },
                            type_: swift_type,
                        }
                    })
                    .collect::<Vec<_>>();
                Some(crate::generated_types::UnionSwift {
                    name,
                    cffi_name: stream_union.to_union_name(false),
                    docstring: Some(format!("Generated from: {stream_union}")),
                    variants,
                })
            } else {
                None
            }
        })
        .collect::<Vec<_>>();

    result.into_iter()
}
