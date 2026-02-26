pub(crate) mod response_handler;
#[cfg(target_arch = "wasm32")]
pub(super) mod wasm_auth;
#[cfg(target_arch = "wasm32")]
pub(super) use wasm_auth as auth;

#[cfg(all(not(target_arch = "wasm32"), not(target_os = "ios")))]
pub(super) mod std_auth;
#[cfg(all(not(target_arch = "wasm32"), not(target_os = "ios")))]
pub(super) use std_auth as auth;

#[cfg(target_os = "ios")]
pub(super) mod ios_auth;
#[cfg(target_os = "ios")]
pub(super) use ios_auth as auth;

mod types;
mod vertex_client;
pub use vertex_client::VertexClient;
