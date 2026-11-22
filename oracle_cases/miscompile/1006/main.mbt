test {
  let s = "abc"
  guard s is [.., ch]
  assert_eq(ch, 'c')
}
