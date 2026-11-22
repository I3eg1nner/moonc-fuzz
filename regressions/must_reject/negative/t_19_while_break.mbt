fn compute() -> String {
  let mut i = 0
  let mut s = 0
  while i < 20 {
    i = i + 1
    if i % 2 == 0 { continue }
    if i > 9 { break }
    s = s + i
  }
  "\{i}|\{s}"
}
fn main { println(compute()) }
