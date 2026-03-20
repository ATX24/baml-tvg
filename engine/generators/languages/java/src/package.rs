use dir_writer::IntermediateRepr;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Package {
    package_path: Vec<String>,
}

impl Package {
    pub fn new(package: &str) -> Self {
        let parts: Vec<_> = package.split('.').map(|s| s.to_string()).collect();
        if parts.is_empty() {
            panic!("Package cannot be empty");
        }
        Package {
            package_path: parts,
        }
    }

    pub fn to_java_path(&self) -> String {
        self.package_path.join(".")
    }

    pub fn to_dir_path(&self) -> String {
        self.package_path.join("/")
    }
}

impl std::fmt::Display for Package {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.to_java_path())
    }
}

#[derive(Clone)]
pub struct CurrentRenderPackage {
    package: std::sync::Arc<std::sync::Mutex<std::sync::Arc<Package>>>,
    lookup: std::sync::Arc<IntermediateRepr>,
}

impl CurrentRenderPackage {
    pub fn new(package: &str, lookup: std::sync::Arc<IntermediateRepr>) -> Self {
        Self {
            package: std::sync::Arc::new(std::sync::Mutex::new(std::sync::Arc::new(Package::new(
                package,
            )))),
            lookup,
        }
    }

    pub fn lookup(&self) -> &IntermediateRepr {
        self.lookup.as_ref()
    }

    pub fn get(&self) -> std::sync::Arc<Package> {
        self.package.lock().unwrap().clone()
    }

    pub fn set(&self, package: &str) {
        if let Ok(mut orig) = self.package.lock() {
            *orig = std::sync::Arc::new(Package::new(package));
        }
    }
}
