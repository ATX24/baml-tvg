// Function representation for Java codegen
use internal_baml_core::ir::FunctionNode;

use super::type_to_java;
use crate::{functions::FunctionJava, package::CurrentRenderPackage};

pub fn ir_function_to_java(function: &FunctionNode, pkg: &CurrentRenderPackage) -> FunctionJava {
    let lookup = pkg.lookup();
    let return_type = type_to_java(&function.elem.output().to_non_streaming_type(lookup), lookup);
    // Derive the partial return type: for class types this references the generated
    // `PartialClassName`; for primitives the partial type is identical to the final type.
    let partial_return_type = partial_type_of(&return_type);
    FunctionJava {
        name: function.elem.name().to_string(),
        args: function
            .elem
            .inputs()
            .iter()
            .map(|(name, field_type)| {
                (
                    name.clone(),
                    type_to_java(&field_type.to_non_streaming_type(lookup), lookup),
                )
            })
            .collect(),
        return_type,
        partial_return_type,
    }
}

/// Derives the streaming/partial variant of a `TypeJava`.
/// Class types are replaced with their `PartialClassName` siblings.
/// All other types keep their original representation (primitives, enums, unions).
fn partial_type_of(ty: &crate::ir_to_java::TypeJava) -> crate::ir_to_java::TypeJava {
    use crate::ir_to_java::TypeJava;
    match ty {
        TypeJava::Class { name, dynamic } => TypeJava::Class {
            name: format!("Partial{name}"),
            dynamic: *dynamic,
        },
        TypeJava::Optional(inner) => TypeJava::Optional(Box::new(partial_type_of(inner))),
        TypeJava::List(inner) => TypeJava::List(Box::new(partial_type_of(inner))),
        TypeJava::Map(k, v) => {
            TypeJava::Map(Box::new(k.as_ref().clone()), Box::new(partial_type_of(v)))
        }
        // Primitives, enums, unions, any — partial == final.
        other => other.clone(),
    }
}
