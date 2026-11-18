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
