fn compute() -> String {
  let d = 3
  let a = -7
  let b = 7
  let q1 = if d == 0 { 0 } else { a / d }
  let r1 = if d == 0 { 0 } else { a % d }
  let q2 = if d == 0 { 0 } else { b / d }
  let r2 = if d == 0 { 0 } else { b % d }
  "\{q1}|\{r1}|\{q2}|\{r2}"
}
fn main { println(compute()) }
