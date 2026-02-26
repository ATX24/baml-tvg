use baml_types::baml_value::TypeLookups;

#[derive(Clone, PartialEq, Debug)]
pub enum MediaTypeSwift {
    Image,
    Audio,
    Pdf,
    Video,
}

#[derive(Clone, PartialEq, Debug)]
pub enum TypeSwift {
    Null,
    String(Option<String>),
    Int(Option<i64>),
    Float,
    Bool(Option<bool>),
    Media(MediaTypeSwift),
    Class { name: String, dynamic: bool },
    Union { name: String },
    Enum { name: String, dynamic: bool },
    TypeAlias { name: String },
    List(Box<TypeSwift>),
    Map(Box<TypeSwift>, Box<TypeSwift>),
    Any { reason: String },
    Optional(Box<TypeSwift>),
    Checked(Box<TypeSwift>),
    StreamState(Box<TypeSwift>),
}

fn safe_name(name: &str) -> String {
    name.replace(|c: char| !c.is_alphanumeric(), "_")
}

impl TypeSwift {
    pub fn make_optional(self) -> Self {
        TypeSwift::Optional(Box::new(self))
    }

    pub fn make_checked(self) -> Self {
        TypeSwift::Checked(Box::new(self))
    }

    pub fn make_stream_state(self) -> Self {
        TypeSwift::StreamState(Box::new(self))
    }

    pub fn is_stream_state(&self) -> bool {
        matches!(self, TypeSwift::StreamState(_))
    }

    pub fn flatten_unions(self) -> Vec<TypeSwift> {
        match self {
            TypeSwift::Union { .. } => vec![self],
            TypeSwift::Optional(inner) => inner.flatten_unions(),
            TypeSwift::Checked(inner) => inner.flatten_unions(),
            TypeSwift::StreamState(inner) => inner.flatten_unions(),
            _ => vec![],
        }
    }

    pub fn default_name_within_union(&self) -> String {
        match self {
            TypeSwift::Null => "Null".to_string(),
            TypeSwift::Optional(inner) => {
                format!("Optional{}", inner.default_name_within_union())
            }
            TypeSwift::Checked(inner) => format!("Checked{}", inner.default_name_within_union()),
            TypeSwift::StreamState(inner) => {
                format!("StreamState{}", inner.default_name_within_union())
            }
            TypeSwift::String(val) => val.as_ref().map_or("String".to_string(), |v| {
                let safe_name = safe_name(v);
                format!("K{safe_name}")
            }),
            TypeSwift::Int(val) => val.map_or("Int".to_string(), |v| format!("IntK{v}")),
            TypeSwift::Float => "Float".to_string(),
            TypeSwift::Bool(val) => val.map_or("Bool".to_string(), |v| {
                format!("BoolK{}", if v { "True" } else { "False" })
            }),
            TypeSwift::Media(media) => match media {
                MediaTypeSwift::Image => "Image".to_string(),
                MediaTypeSwift::Audio => "Audio".to_string(),
                MediaTypeSwift::Pdf => "PDF".to_string(),
                MediaTypeSwift::Video => "Video".to_string(),
            },
            TypeSwift::TypeAlias { name, .. } => name.clone(),
            TypeSwift::Class { name, .. } => name.clone(),
            TypeSwift::Union { name, .. } => name.clone(),
            TypeSwift::Enum { name, .. } => name.clone(),
            TypeSwift::List(inner) => format!("List{}", inner.default_name_within_union()),
            TypeSwift::Map(key, value) => format!(
                "Map{}Key{}Value",
                key.default_name_within_union(),
                value.default_name_within_union()
            ),
            TypeSwift::Any { .. } => "Any".to_string(),
        }
    }
}

pub trait SerializeType {
    fn serialize_type(&self) -> String;
}

impl SerializeType for TypeSwift {
    fn serialize_type(&self) -> String {
        match self {
            TypeSwift::Null => "Any?".to_string(),
            TypeSwift::Optional(inner) => format!("{}?", inner.serialize_type()),
            TypeSwift::Checked(inner) => format!("Checked<{}>", inner.serialize_type()),
            TypeSwift::StreamState(inner) => format!("StreamState<{}>", inner.serialize_type()),
            TypeSwift::String(..) => "String".to_string(),
            TypeSwift::Int(..) => "Int64".to_string(),
            TypeSwift::Float => "Double".to_string(),
            TypeSwift::Bool(..) => "Bool".to_string(),
            TypeSwift::Media(media) => media.serialize_type(),
            TypeSwift::Class { name, .. } => name.clone(),
            TypeSwift::TypeAlias { name, .. } => name.clone(),
            TypeSwift::Union { name, .. } => name.clone(),
            TypeSwift::Enum { name, .. } => name.clone(),
            TypeSwift::List(inner) => format!("[{}]", inner.serialize_type()),
            TypeSwift::Map(key, value) => {
                format!("[{}: {}]", key.serialize_type(), value.serialize_type())
            }
            TypeSwift::Any { .. } => "Any".to_string(),
        }
    }
}

impl SerializeType for MediaTypeSwift {
    fn serialize_type(&self) -> String {
        match self {
            MediaTypeSwift::Image => "BamlImage".to_string(),
            MediaTypeSwift::Audio => "BamlAudio".to_string(),
            MediaTypeSwift::Pdf => "BamlPDF".to_string(),
            MediaTypeSwift::Video => "BamlVideo".to_string(),
        }
    }
}
