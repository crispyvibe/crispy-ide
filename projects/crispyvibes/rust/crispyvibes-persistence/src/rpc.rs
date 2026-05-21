use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Deserialize)]
pub struct Request {
    pub id: String,
    pub method: String,
    #[serde(default)]
    pub params: Value,
}

#[derive(Serialize)]
pub struct Response {
    pub id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
}

#[derive(Serialize)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
}

impl Response {
    pub fn ok(id: String, result: Value) -> Self {
        Self { id, result: Some(result), error: None }
    }

    pub fn err(id: String, code: i32, message: impl Into<String>) -> Self {
        Self { id, result: None, error: Some(RpcError { code, message: message.into() }) }
    }

    pub fn not_found(id: String, msg: impl Into<String>) -> Self {
        Self::err(id, -32001, msg)
    }

    pub fn not_implemented(id: String, method: &str) -> Self {
        Self::err(id, -32002, format!("{method} not yet implemented"))
    }

    pub fn method_not_found(id: String, method: &str) -> Self {
        Self::err(id, -32601, format!("unknown method: {method}"))
    }

    pub fn invalid_params(id: String, msg: impl Into<String>) -> Self {
        Self::err(id, -32602, msg)
    }
}
