/// Macros for testing Swift type serialization.
///
/// These macros make it easy to write tests that verify BAML types
/// convert correctly to Swift streaming and non-streaming type strings.
///
/// # Examples
///
/// ```ignore
/// test_swift_type!(
///     r#"class Foo { bar string }"#,
///     "Foo.bar",
///     42,
///     "String",
///     "String?"
/// );
/// ```
#[macro_export]
macro_rules! test_swift_type {
    // Class field or type alias: "Class.field" or "TypeAlias"
    // With line number from type_serialization_tests.md
    (
        $baml:expr,
        $path:expr,
        $line_number:expr,
        $expected_non_streaming:expr,
        $expected_streaming:expr
    ) => {{
        use internal_baml_core::ir::{repr::make_test_ir, IRHelper};
        use $crate::ir_to_swift::classes::{ir_class_to_swift, ir_class_to_swift_stream};
        use $crate::r#type::SerializeType;

        let path = $path;
        let line_num: usize = $line_number;
        let parts: Vec<&str> = path.split('.').collect();

        let ir = make_test_ir($baml).expect("Valid BAML");
        let ir = std::sync::Arc::new(ir);

        if parts.len() == 2 {
            // Class.field case
            let class_name = parts[0];
            let field_name = parts[1];

            let class = ir
                .find_class(class_name)
                .unwrap_or_else(|_| panic!("Class '{}' not found", class_name))
                .item;

            // Test non-streaming
            let class_swift = ir_class_to_swift(class, ir.as_ref());
            let field = class_swift
                .fields
                .iter()
                .find(|f| f.name == field_name)
                .unwrap_or_else(|| {
                    panic!(
                        "Field '{}' not found in class '{}'",
                        field_name, class_name
                    )
                });
            assert_eq!(
                field.r#type.serialize_type(),
                $expected_non_streaming,
                "Non-streaming type mismatch for {} (type_serialization_tests.md:{})",
                path,
                line_num
            );

            // Test streaming
            let class_swift_stream = ir_class_to_swift_stream(class, ir.as_ref());
            let field = class_swift_stream
                .fields
                .iter()
                .find(|f| f.name == field_name)
                .unwrap_or_else(|| {
                    panic!(
                        "Field '{}' not found in streaming class '{}'",
                        field_name, class_name
                    )
                });
            assert_eq!(
                field.r#type.serialize_type(),
                $expected_streaming,
                "Streaming type mismatch for {} (type_serialization_tests.md:{})",
                path,
                line_num
            );
        } else if parts.len() == 1 {
            // Type alias case (no dot)
            use $crate::ir_to_swift::type_aliases::{
                ir_type_alias_to_swift, ir_type_alias_to_swift_stream,
            };

            let alias_name = parts[0];
            let type_alias = ir
                .find_type_alias(alias_name)
                .unwrap_or_else(|_| panic!("Type alias '{}' not found", alias_name))
                .item;

            // Non-streaming
            let alias_swift = ir_type_alias_to_swift(type_alias, ir.as_ref(), None);
            assert_eq!(
                alias_swift.type_.serialize_type(),
                $expected_non_streaming,
                "Non-streaming type alias mismatch for {} (type_serialization_tests.md:{})",
                alias_name,
                line_num
            );

            // Streaming
            let alias_swift_stream = ir_type_alias_to_swift_stream(type_alias, ir.as_ref(), None);
            assert_eq!(
                alias_swift_stream.type_.serialize_type(),
                $expected_streaming,
                "Streaming type alias mismatch for {} (type_serialization_tests.md:{})",
                alias_name,
                line_num
            );
        } else {
            panic!(
                "Invalid path format: {}. Use 'Class.field' or 'TypeAlias' (type_serialization_tests.md:{})",
                path,
                line_num
            );
        }
    }};

    // Enum case: just enum name and list of values
    (
        $baml:expr,
        $enum_name:expr,
        $line_number:expr,
        [$( $value:expr ),* $(,)?]
    ) => {{
        use internal_baml_core::ir::{repr::make_test_ir, IRHelper};
        use $crate::ir_to_swift::enums::ir_enum_to_swift;

        let ir = make_test_ir($baml).expect("Valid BAML");
        let ir = std::sync::Arc::new(ir);
        let line_num: usize = $line_number;

        let enm = ir
            .find_enum($enum_name)
            .unwrap_or_else(|_| panic!("Enum '{}' not found", $enum_name))
            .item;

        let enum_swift = ir_enum_to_swift(enm);
        assert_eq!(enum_swift.name, $enum_name);

        let expected_values: Vec<&str> = vec![$( $value ),*];
        let actual_values: Vec<&str> = enum_swift.values.iter().map(|(v, _)| v.as_str()).collect();
        assert_eq!(
            actual_values,
            expected_values,
            "Enum values mismatch for {} (type_serialization_tests.md:{})",
            $enum_name,
            line_num
        );
    }};
}

// Include auto-generated tests from type_serialization_tests.md
include!(concat!(env!("OUT_DIR"), "/generated_type_tests.rs"));
