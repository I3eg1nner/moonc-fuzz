fn compute() -> String {
  let a = [5, 3, 9, 1, 7]
  a.sort()
  let mut out = ""
  for x in a { out = out + x.to_string() + "," }
  out
}
fn main { println(compute()) }
