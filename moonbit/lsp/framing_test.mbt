///|
test "frame_message uses UTF-8 byte length" {
  let body = "{\"x\":\"hé😀\"}"
  let framed = frame_message(body)
  let idx = framed.find("\r\n\r\n").unwrap()
  let header = framed[0:idx].to_owned()
  let n = @utf8.encode(body).length()
  assert_eq(header, "Content-Length: " + n.to_string())
  // UTF-8 is longer than the MoonBit character count for these code points.
  assert_true(n > body.length())
}

///|
test "parse_frame round-trips one message" {
  let body = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}"
  let framed = frame_message(body)
  match parse_frame(@utf8.encode(framed)) {
    Complete(got, consumed) => {
      assert_eq(got, body)
      assert_eq(consumed, framed.length())
    }
    _ => fail("expected Complete")
  }
}

///|
test "parse_frame reads multiple messages from one buffer" {
  let a = frame_message("{\"id\":1}")
  let b = frame_message("{\"id\":2}")
  let all = @utf8.encode(a + b)
  match parse_frame(all) {
    Complete(body, consumed) => {
      assert_eq(body, "{\"id\":1}")
      match parse_frame(all[consumed:]) {
        Complete(body2, consumed2) => {
          assert_eq(body2, "{\"id\":2}")
          assert_eq(consumed + consumed2, (a + b).length())
        }
        _ => fail("second frame not Complete")
      }
    }
    _ => fail("first frame not Complete")
  }
}

///|
test "parse_frame waits on a split header" {
  let framed = frame_message("{\"id\":1}")
  let bytes = @utf8.encode(framed)
  match parse_frame(bytes[0:10]) {
    Incomplete => ()
    _ => fail("expected Incomplete for split header")
  }
}

///|
test "parse_frame waits on a split body" {
  let framed = frame_message("{\"id\":12345}")
  let bytes = @utf8.encode(framed)
  match parse_frame(bytes[0:bytes.length() - 3]) {
    Incomplete => ()
    _ => fail("expected Incomplete for split body")
  }
}

///|
test "parse_frame rejects a missing header" {
  let bytes = @utf8.encode(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"shutdown\"}",
  )
  match parse_frame(bytes) {
    Malformed(_) => ()
    _ => fail("expected Malformed for missing header")
  }
}

///|
test "parse_frame treats an oversized Content-Length as incomplete" {
  let bytes = @utf8.encode("Content-Length: 100\r\n\r\n{\"id\":1}")
  match parse_frame(bytes) {
    Incomplete => ()
    _ => fail("expected Incomplete for short body")
  }
}

///|
test "parse_frame honours an undersized Content-Length" {
  let bytes = @utf8.encode("Content-Length: 5\r\n\r\n{\"id\":1}")
  match parse_frame(bytes) {
    Complete(body, consumed) => {
      assert_eq(body, "{\"id\"")
      assert_eq(consumed, "Content-Length: 5\r\n\r\n".length() + 5)
    }
    _ => fail("expected Complete with truncated body")
  }
}

///|
test "parse_frame accepts an empty body" {
  match parse_frame(@utf8.encode("Content-Length: 0\r\n\r\n")) {
    Complete(body, consumed) => {
      assert_eq(body, "")
      assert_eq(consumed, 21)
    }
    _ => fail("expected Complete empty body")
  }
}

///|
test "parse_frame treats an empty buffer as incomplete" {
  match parse_frame(b"") {
    Incomplete => ()
    _ => fail("expected Incomplete")
  }
}

///|
test "content_length accepts lower case and junk spacing" {
  assert_eq(content_length("content-length:  42 "), Some(42))
  assert_eq(content_length("Content-Type: x\r\nContent-Length: 7"), Some(7))
  assert_eq(content_length("Content-Length: nope"), None)
  assert_eq(content_length("Content-Length: -1"), None)
  assert_eq(content_length("Content-Type: x"), None)
}

///|
test "frame_declared writes the declared length, not the body length" {
  let f = frame_declared(200, "{\"id\":1}")
  assert_true(f.has_prefix("Content-Length: 200\r\n\r\n"))
  assert_true(f.has_suffix("{\"id\":1}"))
}

///|
test "frame_with_header keeps arbitrary header bytes" {
  let f = frame_with_header("\u{feff}Content-Length: 2", "{}")
  assert_eq(f, "\u{feff}Content-Length: 2\r\n\r\n{}")
  let g = frame_with_header("Content-Length : 2", "{}")
  assert_eq(g, "Content-Length : 2\r\n\r\n{}")
}

///|
test "split_at round-trips and clamps" {
  let (a, b) = split_at("Content-Length: 2\r\n\r\n{}", 15)
  assert_eq(a + b, "Content-Length: 2\r\n\r\n{}")
  assert_eq(a, "Content-Length:")
  assert_eq(split_at("abcdef", -1).0, "")
  assert_eq(split_at("abcdef", 99).1, "")
}

///|
test "scan_stream reads two frames with no remainder" {
  let all = frame_message("{\"id\":1}") + frame_message("{\"id\":2}")
  match scan_stream(@utf8.encode(all)) {
    AllFrames(fs) => {
      assert_eq(fs.length(), 2)
      assert_eq(fs[0], "{\"id\":1}")
      assert_eq(fs[1], "{\"id\":2}")
    }
    _ => fail("expected AllFrames")
  }
}

///|
test "scan_stream flags surplus bytes after an undersized length" {
  let bytes = @utf8.encode(
    frame_declared(5, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"shutdown\"}"),
  )
  match scan_stream(bytes) {
    Desynced(fs, off, _) => {
      assert_eq(fs.length(), 1)
      assert_eq(fs[0], "{\"jso")
      assert_eq(off, "Content-Length: 5\r\n\r\n".length() + 5)
    }
    _ => fail("expected Desynced for surplus bytes")
  }
}

///|
test "scan_stream waits for the rest of an oversized frame" {
  let bytes = @utf8.encode(frame_declared(200, "{\"id\":1}"))
  match scan_stream(bytes) {
    PartialFrame(fs, off) => {
      assert_eq(fs.length(), 0)
      assert_eq(off, 0)
    }
    _ => fail("expected PartialFrame")
  }
}

///|
test "scan_stream rejects a UTF-8 BOM before the header" {
  let bytes = @utf8.encode(frame_with_header("\u{feff}Content-Length: 2", "{}"))
  match scan_stream(bytes) {
    Desynced(fs, off, _) => {
      assert_eq(fs.length(), 0)
      assert_eq(off, 0)
    }
    _ => fail("expected Desynced for BOM")
  }
}

///|
test "scan_stream waits on LF-only headers, unlike moon-lsp" {
  // The server accepts `Content-Length: 2\n\n{}`; this strict parser only
  // recognises CRLF, so it reports a partial frame.  Documented limitation.
  let bytes = @utf8.encode("Content-Length: 2\n\n{}")
  match scan_stream(bytes) {
    PartialFrame(fs, _) => assert_eq(fs.length(), 0)
    _ => fail("expected PartialFrame for LF-only header")
  }
}
