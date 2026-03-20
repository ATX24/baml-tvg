use internal_baml_core::ir::{Class, Field};

use crate::{ir_to_java::type_to_java, package::CurrentRenderPackage};

pub struct ClassJava<'a> {
    pub name: String,
    pub docstring: Option<String>,
    pub fields: Vec<FieldJava<'a>>,
    pub dynamic: bool,
    pub pkg: &'a CurrentRenderPackage,
}

pub struct FieldJava<'a> {
    pub name: String,
    pub r#type: crate::ir_to_java::TypeJava,
    pub docstring: Option<String>,
    pub pkg: &'a CurrentRenderPackage,
}

pub fn ir_class_to_java<'a>(class: &Class, pkg: &'a CurrentRenderPackage) -> ClassJava<'a> {
    ClassJava {
        name: class.elem.name.clone(),
        docstring: class
            .elem
            .docstring
            .clone()
            .map(|docstring| docstring.0.clone()),
        dynamic: class.attributes.dynamic(),
        pkg,
        fields: class
            .elem
            .static_fields
            .iter()
            .map(|field| ir_field_to_java(field, pkg))
            .collect(),
    }
}

fn ir_field_to_java<'a>(field: &Field, pkg: &'a CurrentRenderPackage) -> FieldJava<'a> {
    let non_streaming = field.elem.r#type.elem.to_non_streaming_type(pkg.lookup());
    let java_type = type_to_java(&non_streaming, pkg.lookup());

    FieldJava {
        name: field.elem.name.clone(),
        r#type: java_type,
        docstring: field
            .elem
            .docstring
            .clone()
            .map(|docstring| docstring.0.clone()),
        pkg,
    }
}
