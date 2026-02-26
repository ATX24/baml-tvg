use internal_baml_core::ir::{Class, Field};

use crate::generated_types::{ClassSwift, FieldSwift};

pub fn ir_class_to_swift(class: &Class, lookup: &impl baml_types::baml_value::TypeLookups) -> ClassSwift {
    ClassSwift {
        name: class.elem.name.clone(),
        docstring: class
            .elem
            .docstring
            .clone()
            .map(|docstring| docstring.0.clone()),
        dynamic: class.attributes.dynamic(),
        fields: class
            .elem
            .static_fields
            .iter()
            .map(|field| ir_field_to_swift(field, lookup))
            .collect(),
    }
}

fn ir_field_to_swift(field: &Field, lookup: &impl baml_types::baml_value::TypeLookups) -> FieldSwift {
    let non_streaming = field.elem.r#type.elem.to_non_streaming_type(lookup);
    let swift_type = super::super::ir_to_swift::type_to_swift(&non_streaming, lookup);

    FieldSwift {
        name: field.elem.name.clone(),
        r#type: swift_type,
        docstring: field
            .elem
            .docstring
            .clone()
            .map(|docstring| docstring.0.clone()),
    }
}
