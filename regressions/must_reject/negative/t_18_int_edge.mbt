fn compute() -> String {
  let a = -2147483648
  let b = 2147483647
  let e = b + 1
  let f = b * 2
  "\{a}|\{b}|\{e}|\{f}|\{a >> 31}|\{b >> 31}"
}
fn main { println(compute()) }
