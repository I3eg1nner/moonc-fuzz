fn compute() -> String {
  let d = 3
  let a = -2147483648
  let q = if d == 0 { 0 } else { a / d }
  let r = if d == 0 { 0 } else { a % d }
  "\{q}|\{r}"
}
fn main { println(compute()) }
