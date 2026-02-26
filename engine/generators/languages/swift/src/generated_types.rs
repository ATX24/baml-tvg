use crate::r#type::{SerializeType, TypeSwift};

mod class {
    use super::*;

    #[derive(askama::Template)]
    #[template(path = "class.swift.j2", escape = "none", ext = "txt")]
    pub struct ClassSwift {
        pub name: String,
        pub docstring: Option<String>,
        pub fields: Vec<FieldSwift>,
        pub dynamic: bool,
    }

    #[derive(Clone)]
    pub struct FieldSwift {
        pub docstring: Option<String>,
        pub name: String,
        pub r#type: TypeSwift,
    }

    impl FieldSwift {
        pub fn swift_type(&self) -> String {
            self.r#type.serialize_type()
        }
    }
}

mod enums {
    use super::*;

    #[derive(askama::Template)]
    #[template(path = "enums.swift.j2", escape = "none")]
    pub struct EnumSwift {
        pub name: String,
        pub docstring: Option<String>,
        pub values: Vec<(String, Option<String>)>,
        pub dynamic: bool,
    }
}

mod union {
    use super::*;

    #[derive(askama::Template)]
    #[template(path = "unions.swift.j2", escape = "none")]
    pub struct UnionSwift {
        pub name: String,
        pub cffi_name: String,
        pub docstring: Option<String>,
        pub variants: Vec<VariantSwift>,
    }

    #[derive(Clone)]
    pub struct VariantSwift {
        pub name: String,
        pub cffi_name: String,
        pub literal_repr: Option<String>,
        pub type_: TypeSwift,
    }

    impl VariantSwift {
        pub fn swift_type(&self) -> String {
            self.type_.serialize_type()
        }
    }
}

mod type_aliases {
    use super::*;

    pub struct TypeAliasSwift {
        pub name: String,
        pub type_: TypeSwift,
        pub docstring: Option<String>,
    }

    impl TypeAliasSwift {
        pub fn swift_type(&self) -> String {
            self.type_.serialize_type()
        }
    }
}

pub(crate) fn render_swift_types<T: askama::Template>(
    items: &[T],
) -> Result<String, askama::Error> {
    use askama::Template;
    let mut output = String::new();
    for item in items {
        output.push_str(&item.render()?);
        output.push('\n');
    }
    Ok(output)
}

pub use class::{ClassSwift, FieldSwift};
pub use enums::EnumSwift;
pub use type_aliases::TypeAliasSwift;
pub use union::{UnionSwift, VariantSwift};
