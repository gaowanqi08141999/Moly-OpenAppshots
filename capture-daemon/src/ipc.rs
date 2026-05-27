use std::convert::Infallible;
use std::net::Shutdown;
use std::sync::Arc;

use hyper::{body::Incoming, service::service_fn, Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use tokio::net::UnixListener;

use crate::DaemonState;

pub async fn start_server(
    socket_path: &str,
    state: Arc<DaemonState>,
) -> Result<(), Box<dyn std::error::Error>> {
    let listener = UnixListener::bind(socket_path)?;

    loop {
        let (stream, _) = listener.accept().await?;
        let state = state.clone();

        tokio::spawn(async move {
            let io = TokioIo::new(stream);
            let conn = hyper::server::conn::http1::Builder::new()
                .serve_connection(io, service_fn(move |req| handle_request(req, state.clone())));

            if let Err(e) = conn.await {
                tracing::error!("Connection error: {}", e);
            }
        });
    }
}

async fn handle_request(
    req: Request<Incoming>,
    state: Arc<DaemonState>,
) -> Result<Response<String>, Infallible> {
    let path = req.uri().path().to_string();
    let method = req.method().clone();

    tracing::debug!("{} {}", method, path);

    let response = match (method.as_str(), path.as_str()) {
        ("POST", "/capture") => handle_capture(state).await,
        ("GET", "/snapshots") => handle_list(req, state).await,
        ("GET", "/health") => Ok(Response::new(r#"{"status":"ok"}"#.into())),
        (_, p) if p.starts_with("/snapshots/") && p.split('/').count() == 3 => {
            let id = p.split('/').nth(2).unwrap();
            handle_get_snapshot(id, state).await
        }
        ("DELETE", p) if p.starts_with("/snapshots/") && p.split('/').count() == 3 => {
            let id = p.split('/').nth(2).unwrap();
            handle_delete_snapshot(id, state).await
        }
        _ => Ok(not_found()),
    };

    // Always wrap in Result<Response, Infallible> for hyper
    Ok(response.unwrap_or_else(|_| internal_error()))
}

async fn handle_capture(state: Arc<DaemonState>) -> Result<Response<String>, AppshotError> {
    let raw = state.capture_engine.capture_frontmost().await?;
    let summary = state.storage.save(&raw)?;

    // Update last_snapshot
    *state.last_snapshot.lock().await = Some(summary.clone());

    let body = serde_json::to_string(&summary).unwrap();
    Ok(Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "application/json")
        .body(body)
        .unwrap())
}

async fn handle_list(
    req: Request<Incoming>,
    state: Arc<DaemonState>,
) -> Result<Response<String>, AppshotError> {
    let query = req.uri().query().unwrap_or("");
    let params: std::collections::HashMap<String, String> =
        url::form_urlencoded::parse(query.as_bytes())
            .into_owned()
            .collect();

    let q = crate::storage::SnapshotQuery {
        app_name: params.get("app").cloned(),
        date_from: params.get("from").cloned(),
        date_to: params.get("to").cloned(),
        limit: params.get("limit").and_then(|v| v.parse().ok()),
        offset: params.get("offset").and_then(|v| v.parse().ok()),
    };

    let list = state.storage.query(&q)?;
    let body = serde_json::to_string(&list).unwrap();
    Ok(Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "application/json")
        .body(body)
        .unwrap())
}

async fn handle_get_snapshot(
    id: &str,
    state: Arc<DaemonState>,
) -> Result<Response<String>, AppshotError> {
    match state.storage.get_full(id)? {
        Some(data) => {
            let body = serde_json::to_string(&serde_json::json!({
                "metadata": serde_json::from_str::<serde_json::Value>(&data.metadata_json).unwrap(),
                "ax_tree": serde_json::from_str::<serde_json::Value>(&data.ax_tree_json).unwrap(),
                "image_base64": data::encoding::BASE64.encode(&data.png_data),
            })).unwrap();
            Ok(Response::builder()
                .status(StatusCode::OK)
                .header("Content-Type", "application/json")
                .body(body)
                .unwrap())
        }
        None => Ok(Response::builder()
            .status(StatusCode::NOT_FOUND)
            .body(r#"{"error":"not found"}"#.into())
            .unwrap()),
    }
}

async fn handle_delete_snapshot(
    id: &str,
    state: Arc<DaemonState>,
) -> Result<Response<String>, AppshotError> {
    let success = state.storage.delete(id)?;
    let body = serde_json::to_string(&serde_json::json!({"success": success})).unwrap();
    Ok(Response::builder()
        .status(StatusCode::OK)
        .header("Content-Type", "application/json")
        .body(body)
        .unwrap())
}

fn not_found() -> Response<String> {
    Response::builder()
        .status(StatusCode::NOT_FOUND)
        .body(r#"{"error":"not found"}"#.into())
        .unwrap()
}

fn internal_error() -> Response<String> {
    Response::builder()
        .status(StatusCode::INTERNAL_SERVER_ERROR)
        .body(r#"{"error":"internal server error"}"#.into())
        .unwrap()
}
