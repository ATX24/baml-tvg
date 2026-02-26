use internal_baml_core::ir::FunctionNode;

use super::{stream_type_to_swift, type_to_swift};
use crate::functions::FunctionSwift;

pub fn ir_function_to_swift(function: &FunctionNode, lookup: &impl baml_types::baml_value::TypeLookups) -> FunctionSwift {
    FunctionSwift {
        documentation: None,
        name: function.elem.name().to_string(),
        args: function
            .elem
            .inputs()
            .iter()
            .map(|(name, field_type)| {
                (
                    name.clone(),
                    type_to_swift(
                        &field_type.to_non_streaming_type(lookup),
                        lookup,
                    ),
                )
            })
            .collect(),
        return_type: type_to_swift(
            &function.elem.output().to_non_streaming_type(lookup),
            lookup,
        ),
        stream_return_type: stream_type_to_swift(
            &function.elem.output().to_streaming_type(lookup),
            lookup,
        ),
    }
}
