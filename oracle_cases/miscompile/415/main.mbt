pub fn[A, B] unsafe_coerce(_ : A) -> B = "%identity"

test {
  let f : () -> Int = fn() { 0 }
  let g : () -> Double = unsafe_coerce(f)
  let h : () -> Int = unsafe_coerce(g)
  inspect(h(), content="0")
}
