async test "repro" {
  assert_eq(@repro.pick(x => if x == 1 { Some(x) } else { None }), Some(1))
}
