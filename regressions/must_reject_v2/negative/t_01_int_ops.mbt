fn compute() -> String {
  let a = 2147483647
  let b = a + 1
  let c = -2147483648
  let d = c - 1
  let e = 1000000 * 1000000
  "\{a}|\{b}|\{c}|\{d}|\{e}|\{a / 7}|\{-7 / 3}|\{-7 % 3}|\{a >> 3}|\{-8 >> 1}|\{1 << 30}"
}
fn main { println(compute()) }
