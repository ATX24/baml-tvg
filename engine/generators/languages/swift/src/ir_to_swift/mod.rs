use baml_types::{
    baml_value::TypeLookups,
    ir_type::{TypeNonStreaming, TypeStreaming},
    BamlMediaType, ConstraintLevel, TypeValue,
};

use crate::r#type::{MediaTypeSwift, TypeSwift};

pub mod classes;
pub mod enums;
pub mod functions;
pub mod type_aliases;
pub mod unions;

pub(crate) fn stream_type_to_swift(
    field: &TypeStreaming,
    lookup: &impl TypeLookups,
) -> TypeSwift {
    use TypeStreaming as T;
    let recursive_fn = |field| stream_type_to_swift(field, lookup);

    let field_has_checks = field
        .meta()
        .constraints
        .iter()
        .any(|c| matches!(c.level, ConstraintLevel::Check));

    let field_has_stream_state = field.meta().streaming_behavior.state;

    let type_swift: TypeSwift = match field {
        T::Primitive(type_value, _) => type_value.into(),
        T::Enum { name, dynamic, .. } => TypeSwift::Enum {
            name: name.clone(),
            dynamic: *dynamic,
        },
        T::Literal(literal_value, _) => match literal_value {
            baml_types::LiteralValue::String(val) => TypeSwift::String(Some(val.clone())),
            baml_types::LiteralValue::Int(val) => TypeSwift::Int(Some(*val)),
            baml_types::LiteralValue::Bool(val) => TypeSwift::Bool(Some(*val)),
        },
        T::Class {
            name, dynamic, ..
        } => TypeSwift::Class {
            name: name.clone(),
            dynamic: *dynamic,
        },
        T::List(type_generic, _) => TypeSwift::List(Box::new(recursive_fn(type_generic))),
        T::Map(type_generic, type_generic1, _) => TypeSwift::Map(
            Box::new(recursive_fn(type_generic)),
            Box::new(recursive_fn(type_generic1)),
        ),
        T::RecursiveTypeAlias { name, .. } => {
            if lookup.expand_recursive_type(name).is_err() {
                TypeSwift::Any {
                    reason: format!("Recursive type alias {name} is not supported in Swift"),
                }
            } else {
                TypeSwift::TypeAlias {
                    name: name.clone(),
                }
            }
        }
        T::Tuple(..) => TypeSwift::Any {
            reason: "tuples are not yet supported in Swift codegen".to_string(),
        },
        T::Arrow(..) => TypeSwift::Any {
            reason: "arrow types are not supported in Swift".to_string(),
        },
        T::Union(union_type_generic, union_meta) => {
            let has_union_checks = union_meta
                .constraints
                .iter()
                .any(|c| matches!(c.level, ConstraintLevel::Check));
            let has_union_stream_state = union_meta.streaming_behavior.state;

            match union_type_generic.view() {
                baml_types::ir_type::UnionTypeViewGeneric::Null => TypeSwift::Null,
                baml_types::ir_type::UnionTypeViewGeneric::Optional(type_generic) => {
                    let mut type_swift = recursive_fn(type_generic);
                    type_swift = type_swift.make_optional();
                    if has_union_checks {
                        type_swift = type_swift.make_checked();
                    }
                    if has_union_stream_state {
                        type_swift = type_swift.make_stream_state();
                    }
                    type_swift
                }
                baml_types::ir_type::UnionTypeViewGeneric::OneOf(type_generics) => {
                    let options: Vec<_> = type_generics.into_iter().map(&recursive_fn).collect();
                    let num_options = options.len();
                    let mut name = options
                        .iter()
                        .map(|t| t.default_name_within_union())
                        .collect::<Vec<_>>();
                    name.sort();
                    let name = name.join("Or");
                    let mut union_type = TypeSwift::Union {
                        name: format!("Union{num_options}{name}"),
                    };
                    if has_union_checks {
                        union_type = union_type.make_checked();
                    }
                    if has_union_stream_state {
                        union_type = union_type.make_stream_state();
                    }
                    union_type
                }
                baml_types::ir_type::UnionTypeViewGeneric::OneOfOptional(type_generics) => {
                    let options: Vec<_> = type_generics.into_iter().map(recursive_fn).collect();
                    let num_options = options.len();
                    let mut name = options
                        .iter()
                        .map(|t| t.default_name_within_union())
                        .collect::<Vec<_>>();
                    name.sort();
                    let name = name.join("Or");
                    let mut union_type = TypeSwift::Union {
                        name: format!("Union{num_options}{name}"),
                    };
                    if has_union_checks {
                        union_type = union_type.make_checked();
                    }
                    union_type = union_type.make_optional();
                    if has_union_stream_state {
                        union_type = union_type.make_stream_state();
                    }
                    union_type
                }
            }
        }
        T::Top(_) => panic!(
            "TypeGeneric::Top should have been resolved by the compiler before code generation. \
             This indicates a bug in the type resolution phase."
        ),
    };

    if matches!(field, T::Union(..)) {
        return type_swift;
    }

    let type_swift = if field_has_checks {
        type_swift.make_checked()
    } else {
        type_swift
    };

    if field_has_stream_state {
        type_swift.make_stream_state()
    } else {
        type_swift
    }
}

pub(crate) fn type_to_swift(field: &TypeNonStreaming, _lookup: &impl TypeLookups) -> TypeSwift {
    use TypeNonStreaming as T;
    let recursive_fn = |field| type_to_swift(field, _lookup);

    let field_has_checks = field
        .meta()
        .constraints
        .iter()
        .any(|c| matches!(c.level, ConstraintLevel::Check));

    let type_swift = match field {
        T::Primitive(type_value, _) => type_value.into(),
        T::Enum { name, dynamic, .. } => TypeSwift::Enum {
            name: name.clone(),
            dynamic: *dynamic,
        },
        T::Literal(literal_value, _) => match literal_value {
            baml_types::LiteralValue::String(val) => TypeSwift::String(Some(val.clone())),
            baml_types::LiteralValue::Int(val) => TypeSwift::Int(Some(*val)),
            baml_types::LiteralValue::Bool(val) => TypeSwift::Bool(Some(*val)),
        },
        T::Class { name, dynamic, .. } => TypeSwift::Class {
            name: name.clone(),
            dynamic: *dynamic,
        },
        T::List(type_generic, _) => TypeSwift::List(Box::new(recursive_fn(type_generic))),
        T::Map(type_generic, type_generic1, _) => TypeSwift::Map(
            Box::new(recursive_fn(type_generic)),
            Box::new(recursive_fn(type_generic1)),
        ),
        T::Tuple(..) => TypeSwift::Any {
            reason: "tuples are not yet supported in Swift codegen".to_string(),
        },
        T::Arrow(..) => TypeSwift::Any {
            reason: "arrow types are not supported in Swift".to_string(),
        },
        T::RecursiveTypeAlias { name, .. } => {
            if _lookup.expand_recursive_type(name).is_err() {
                TypeSwift::Any {
                    reason: format!("Recursive type alias {name} is not supported in Swift"),
                }
            } else {
                TypeSwift::TypeAlias {
                    name: name.clone(),
                }
            }
        }
        T::Union(union_type_generic, union_meta) => {
            let has_union_checks = union_meta
                .constraints
                .iter()
                .any(|c| matches!(c.level, ConstraintLevel::Check));

            match union_type_generic.view() {
                baml_types::ir_type::UnionTypeViewGeneric::Null => TypeSwift::Null,
                baml_types::ir_type::UnionTypeViewGeneric::Optional(type_generic) => {
                    let mut type_swift = recursive_fn(type_generic);
                    type_swift = type_swift.make_optional();
                    if has_union_checks {
                        type_swift = type_swift.make_checked();
                    }
                    type_swift
                }
                baml_types::ir_type::UnionTypeViewGeneric::OneOf(type_generics) => {
                    let options: Vec<_> = type_generics.into_iter().map(&recursive_fn).collect();
                    let num_options = options.len();
                    let mut name = options
                        .iter()
                        .map(|t| t.default_name_within_union())
                        .collect::<Vec<_>>();
                    name.sort();
                    let name = name.join("Or");
                    let mut union_type = TypeSwift::Union {
                        name: format!("Union{num_options}{name}"),
                    };
                    if has_union_checks {
                        union_type = union_type.make_checked();
                    }
                    union_type
                }
                baml_types::ir_type::UnionTypeViewGeneric::OneOfOptional(type_generics) => {
                    let options: Vec<_> = type_generics.into_iter().map(recursive_fn).collect();
                    let num_options = options.len();
                    let mut name = options
                        .iter()
                        .map(|t| t.default_name_within_union())
                        .collect::<Vec<_>>();
                    name.sort();
                    let name = name.join("Or");
                    let mut union_type = TypeSwift::Union {
                        name: format!("Union{num_options}{name}"),
                    };
                    if has_union_checks {
                        union_type = union_type.make_checked();
                    }
                    union_type = union_type.make_optional();
                    union_type
                }
            }
        }
        T::Top(_) => panic!(
            "TypeGeneric::Top should have been resolved by the compiler before code generation. \
             This indicates a bug in the type resolution phase."
        ),
    };

    if field_has_checks && !matches!(field, T::Union(..)) {
        type_swift.make_checked()
    } else {
        type_swift
    }
}

impl From<&TypeValue> for TypeSwift {
    fn from(type_value: &TypeValue) -> Self {
        match type_value {
            TypeValue::String => TypeSwift::String(None),
            TypeValue::Int => TypeSwift::Int(None),
            TypeValue::Float => TypeSwift::Float,
            TypeValue::Bool => TypeSwift::Bool(None),
            TypeValue::Null => TypeSwift::Null,
            TypeValue::Media(baml_media_type) => TypeSwift::Media(baml_media_type.into()),
        }
    }
}

impl From<&BamlMediaType> for MediaTypeSwift {
    fn from(baml_media_type: &BamlMediaType) -> Self {
        match baml_media_type {
            BamlMediaType::Image => MediaTypeSwift::Image,
            BamlMediaType::Audio => MediaTypeSwift::Audio,
            BamlMediaType::Pdf => MediaTypeSwift::Pdf,
            BamlMediaType::Video => MediaTypeSwift::Video,
        }
    }
}
