///|
/// Request model for the subset of LSP used by the probe.
///
/// Method names were checked against the installed `moon-lsp`: the
/// `initialize` result advertises `hoverProvider`, `completionProvider`,
/// `documentFormattingProvider` and `documentSymbolProvider`.  `shutdown`,
/// `exit` and `textDocument/didOpen` are part of the base protocol.
/// `textDocument/diagnostic` is not advertised, but the binary still routes
/// it and answers `-32603 Request not supported yet!`, so it is useful as an
/// error-response case.
pub(all) enum RpcMethod {
  Initialize
  Initialized
  DidOpen
  FormatNth
  Hover
  Completion
  Formatting
  DocumentSymbol
  Diagnostic
  Shutdown
  Exit
  Unknown(String)
}

///|
pub impl Eq for RpcMethod with fn equal(a, b) {
  a.name() == b.name()
}

///|
pub extend RpcMethod with Eq::{not_equal, equal}

///|
pub fn RpcMethod::name(self : RpcMethod) -> String {
  match self {
    Initialize => "initialize"
    Initialized => "initialized"
    DidOpen => "textDocument/didOpen"
    FormatNth => "moonbit-lsp/format-nth"
    Hover => "textDocument/hover"
    Completion => "textDocument/completion"
    Formatting => "textDocument/formatting"
    DocumentSymbol => "textDocument/documentSymbol"
    Diagnostic => "textDocument/diagnostic"
    Shutdown => "shutdown"
    Exit => "exit"
    Unknown(name) => name
  }
}

///|
/// One JSON-RPC request or notification.  `id = None` means notification;
/// `params = None` means the `params` member is omitted entirely (JSON-RPC
/// allows that, and `moon-lsp` treats it differently from `params: null`).
pub(all) struct Request {
  id : Int32?
  rpc_method : RpcMethod
  params : String?
}

///|
/// Serialize a request exactly once; this is what the framing layer wraps.
pub fn encode_request(req : Request) -> String {
  let b = StringBuilder()
  b.write_string("{\"jsonrpc\":\"2.0\"")
  match req.id {
    Some(id) => {
      b.write_string(",\"id\":")
      b.write_string(id.to_string())
    }
    None => ()
  }
  b.write_string(",\"method\":")
  b.write_string(json_quote(req.rpc_method.name()))
  match req.params {
    Some(p) => {
      b.write_string(",\"params\":")
      b.write_string(p)
    }
    None => ()
  }
  b.write_string("}")
  b.to_string()
}

///|
pub fn initialize(id : Int32, root_uri : String?) -> Request {
  let root = match root_uri {
    Some(uri) => json_quote(uri)
    None => "null"
  }
  {
    id: Some(id),
    rpc_method: Initialize,
    params: Some(
      "{\"processId\":null,\"rootUri\":" + root + ",\"capabilities\":{}}",
    ),
  }
}

///|
pub fn initialized() -> Request {
  { id: None, rpc_method: Initialized, params: Some("{}"), }
}

///|
pub fn did_open(uri : String, text : String) -> Request {
  {
    id: None,
    rpc_method: DidOpen,
    params: Some(
      "{\"textDocument\":{\"uri\":" +
      json_quote(uri) +
      ",\"languageId\":\"moonbit\",\"version\":1,\"text\":" +
      json_quote(text) +
      "}}",
    ),
  }
}

///|
pub fn format_nth(
  id : Int32,
  content : String,
  n : Int32,
  is_markdown : Bool,
) -> Request {
  {
    id: Some(id),
    rpc_method: FormatNth,
    params: Some(
      "{\"content\":" +
      json_quote(content) +
      ",\"n\":" +
      n.to_string() +
      ",\"isMarkdown\":" +
      (if is_markdown { "true" } else { "false" }) +
      "}",
    ),
  }
}

///|
pub fn text_document_request(
  id : Int32,
  rpc_method : RpcMethod,
  uri : String,
  position : (Int32, Int32)?,
) -> Request {
  let b = StringBuilder()
  b.write_string("{\"textDocument\":{\"uri\":")
  b.write_string(json_quote(uri))
  b.write_string("}")
  match position {
    Some((line, character)) => {
      b.write_string(",\"position\":{\"line\":")
      b.write_string(line.to_string())
      b.write_string(",\"character\":")
      b.write_string(character.to_string())
      b.write_string("}")
    }
    None => ()
  }
  if rpc_method == Formatting {
    b.write_string(",\"options\":{\"tabSize\":2,\"insertSpaces\":true}")
  }
  b.write_string("}")
  { id: Some(id), rpc_method, params: Some(b.to_string()), }
}

///|
/// `params` is the literal JSON text: `None` omits the member, `Some("null")`
/// sends an explicit JSON null, `Some("{}")` sends an empty object.
pub fn shutdown(id : Int32, params : String?) -> Request {
  { id: Some(id), rpc_method: Shutdown, params, }
}

///|
pub fn exit() -> Request {
  { id: None, rpc_method: Exit, params: None, }
}

///|
pub fn unknown(id : Int32, name : String) -> Request {
  { id: Some(id), rpc_method: Unknown(name), params: Some("{}"), }
}

///|
/// Request with a caller-supplied method name and literal params object.
/// Used by the advertised-method matrix, where the params shape varies per
/// method.  The caller is responsible for sending valid JSON.
pub fn raw_request(id : Int32, name : String, params : String) -> Request {
  { id: Some(id), rpc_method: Unknown(name), params: Some(params), }
}
