use std::sync::Arc;

use codex_code_mode_protocol::CellId;
use codex_code_mode_protocol::CodeModeNestedToolCall;
use codex_code_mode_protocol::CodeModeSession;
use codex_code_mode_protocol::CodeModeSessionDelegate;
use codex_code_mode_protocol::CodeModeSessionProvider;
use codex_code_mode_protocol::CodeModeSessionProviderFuture;
use codex_code_mode_protocol::CodeModeSessionResultFuture;
use codex_code_mode_protocol::ExecuteRequest;
use codex_code_mode_protocol::ExecuteToPendingOutcome;
use codex_code_mode_protocol::NotificationFuture;
use codex_code_mode_protocol::StartedCell;
use codex_code_mode_protocol::ToolInvocationFuture;
use codex_code_mode_protocol::WaitOutcome;
use codex_code_mode_protocol::WaitRequest;
use codex_code_mode_protocol::WaitToPendingOutcome;
use codex_code_mode_protocol::WaitToPendingRequest;
use tokio_util::sync::CancellationToken;

const UNAVAILABLE: &str =
    "experimental Code Mode is unavailable on CodexPad's 32-bit iSH runtime";

pub struct NoopCodeModeSessionDelegate;

impl CodeModeSessionDelegate for NoopCodeModeSessionDelegate {
    fn invoke_tool<'a>(
        &'a self,
        _invocation: CodeModeNestedToolCall,
        cancellation_token: CancellationToken,
    ) -> ToolInvocationFuture<'a> {
        Box::pin(async move {
            cancellation_token.cancelled().await;
            Err("code mode nested tools are unavailable".to_string())
        })
    }

    fn notify<'a>(
        &'a self,
        _call_id: String,
        _cell_id: CellId,
        _text: String,
        _cancellation_token: CancellationToken,
    ) -> NotificationFuture<'a> {
        Box::pin(async { Ok(()) })
    }

    fn cell_closed(&self, _cell_id: &CellId) {}
}

#[derive(Default)]
pub struct InProcessCodeModeSessionProvider;

impl CodeModeSessionProvider for InProcessCodeModeSessionProvider {
    fn create_session<'a>(
        &'a self,
        _delegate: Arc<dyn CodeModeSessionDelegate>,
    ) -> CodeModeSessionProviderFuture<'a> {
        Box::pin(async {
            let session: Arc<dyn CodeModeSession> = Arc::new(InProcessCodeModeSession);
            Ok(session)
        })
    }
}

#[derive(Default)]
pub struct InProcessCodeModeSession;

impl InProcessCodeModeSession {
    pub fn new() -> Self {
        Self
    }

    pub fn with_delegate(_delegate: Arc<dyn CodeModeSessionDelegate>) -> Self {
        Self
    }

    pub fn with_delegate_and_task_failure_handler(
        _delegate: Arc<dyn CodeModeSessionDelegate>,
        _task_failure_handler: Arc<dyn Fn(String) + Send + Sync>,
    ) -> Self {
        Self
    }

    pub async fn execute(&self, _request: ExecuteRequest) -> Result<StartedCell, String> {
        Err(UNAVAILABLE.to_string())
    }

    pub async fn execute_to_pending(
        &self,
        _request: ExecuteRequest,
    ) -> Result<ExecuteToPendingOutcome, String> {
        Err(UNAVAILABLE.to_string())
    }

    pub async fn wait(&self, _request: WaitRequest) -> Result<WaitOutcome, String> {
        Err(UNAVAILABLE.to_string())
    }

    pub async fn terminate(&self, _cell_id: CellId) -> Result<WaitOutcome, String> {
        Err(UNAVAILABLE.to_string())
    }

    pub async fn wait_to_pending(
        &self,
        _request: WaitToPendingRequest,
    ) -> Result<WaitToPendingOutcome, String> {
        Err(UNAVAILABLE.to_string())
    }

    pub async fn shutdown(&self) -> Result<(), String> {
        Ok(())
    }
}

impl CodeModeSession for InProcessCodeModeSession {
    fn execute<'a>(
        &'a self,
        request: ExecuteRequest,
    ) -> CodeModeSessionResultFuture<'a, StartedCell> {
        Box::pin(InProcessCodeModeSession::execute(self, request))
    }

    fn wait<'a>(&'a self, request: WaitRequest) -> CodeModeSessionResultFuture<'a, WaitOutcome> {
        Box::pin(InProcessCodeModeSession::wait(self, request))
    }

    fn terminate<'a>(&'a self, cell_id: CellId) -> CodeModeSessionResultFuture<'a, WaitOutcome> {
        Box::pin(InProcessCodeModeSession::terminate(self, cell_id))
    }

    fn shutdown<'a>(&'a self) -> CodeModeSessionResultFuture<'a, ()> {
        Box::pin(InProcessCodeModeSession::shutdown(self))
    }
}
