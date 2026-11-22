fn compute() -> String {
  let a = 9223372036854775807L
  let b = a + 1L
  let c = -9223372036854775808L
  let d = c / 3L
  let e = 18446744073709551615UL
  let f = e + 1UL
  "\{a}|\{b}|\{c}|\{d}|\{e}|\{f}"
}
fn main { println(compute()) }
