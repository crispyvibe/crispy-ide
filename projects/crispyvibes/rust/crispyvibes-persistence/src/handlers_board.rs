use crate::rpc::Response;

pub fn stub(id: String, method: &str) -> Response {
    Response::not_implemented(id, method)
}
