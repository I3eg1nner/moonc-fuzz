fn compute() -> String {
  let mut i = 0
  let mut acc = 0
  while i < 10 {
    acc = acc + i
    i = i + 1
  }
  let mut s = 0
  for j in 1..=5 {
    s = s + j
  }
  "\{acc}|\{s}"
}
fn main { println(compute()) }
