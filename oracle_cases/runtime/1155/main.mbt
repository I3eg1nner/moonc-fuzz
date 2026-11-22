fn main {
  let size = 268_435_456
  let b = Bytes::make(size, 42)
  println("requested size = \{size}")
  println("actual length  = \{b.length()}")
  println("b[0] = \{b[0]}")
}
