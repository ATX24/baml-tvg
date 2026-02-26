//! Stub for Vertex AI authentication on iOS.
//! GCP auth is not available on iOS (gcloud CLI and config_dir are unavailable).
//! All auth attempts return a descriptive error at runtime.

use std::{
    future::Future,
    pin::Pin,
    sync::Arc,
};

use anyhow::Result;
use internal_llm_client::vertex::ResolvedGcpAuthStrategy;

pub struct VertexAuth;

impl VertexAuth {
    pub async fn get_or_create(
        _auth_strategy: &ResolvedGcpAuthStrategy,
    ) -> Result<Arc<VertexAuth>> {
        anyhow::bail!(
            "Vertex AI authentication is not supported on iOS. \
             Use a different provider (e.g., OpenAI, Anthropic) or \
             provide a pre-authenticated base_url with an API key."
        )
    }

    pub async fn token(&self, _scopes: &[&str]) -> Result<Arc<VertexToken>> {
        anyhow::bail!("Vertex AI authentication is not supported on iOS")
    }

    pub async fn project_id(&self) -> Result<Arc<str>> {
        anyhow::bail!("Vertex AI authentication is not supported on iOS")
    }
}

/// Minimal token type to satisfy the API surface used by vertex_client.rs.
pub struct VertexToken(String);

impl VertexToken {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}
