use baml_types::baml_value::TypeLookups;
use internal_baml_core::ir::TypeAlias;

use crate::{generated_types::TypeAliasSwift, ir_to_swift};

struct LookupWithDrop<'a, T> {
    lookup: &'a T,
    drop_type: Option<&'a String>,
}

impl<'a, T: TypeLookups> TypeLookups for LookupWithDrop<'a, T> {
    fn expand_recursive_type(&self, type_alias: &str) -> anyhow::Result<&baml_types::TypeIR> {
        if self.drop_type.is_some() && self.drop_type.unwrap() == type_alias {
            Err(anyhow::anyhow!(
                "Recursive type alias {type_alias} is not supported in Swift"
            ))
        } else {
            self.lookup.expand_recursive_type(type_alias)
        }
    }
}

pub fn ir_type_alias_to_swift(
    alias: &TypeAlias,
    lookup: &impl TypeLookups,
    drop_type: Option<&String>,
) -> TypeAliasSwift {
    let non_streaming = alias.elem.r#type.elem.to_non_streaming_type(lookup);
    let lookup = LookupWithDrop {
        lookup,
        drop_type,
    };
    TypeAliasSwift {
        name: alias.elem.name.clone(),
        type_: ir_to_swift::type_to_swift(&non_streaming, &lookup),
        docstring: alias
            .elem
            .docstring
            .clone()
            .map(|docstring| docstring.0.clone()),
    }
}

pub fn ir_type_alias_to_swift_stream(
    alias: &TypeAlias,
    lookup: &impl TypeLookups,
    drop_type: Option<&String>,
) -> TypeAliasSwift {
    let partialized = alias.elem.r#type.elem.to_streaming_type(lookup);

    let lookup = LookupWithDrop {
        lookup,
        drop_type,
    };
    TypeAliasSwift {
        name: alias.elem.name.clone(),
        type_: ir_to_swift::stream_type_to_swift(&partialized, &lookup),
        docstring: alias
            .elem
            .docstring
            .clone()
            .map(|docstring| docstring.0.clone()),
    }
}
