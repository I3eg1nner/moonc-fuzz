fn compute() -> String {
  let a = [3, 1, 2]
  let b : Array[Int] = []
  b.push(7)
  b.push(8)
  let mut sum = 0
  for x in a {
    sum = sum + x
  }
  "\{a.length()}|\{a[0]}|\{b[1]}|\{sum}"
}
fn main { println(compute()) }
