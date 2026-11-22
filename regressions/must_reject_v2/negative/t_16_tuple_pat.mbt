fn compute() -> String {
  let t = (1, "a", true)
  let (x, y, z) = t
  let s = match (x, z) {
    (1, true) => "one-true"
    (_, true) => "true"
    (n, false) => "n:\{n}"
  }
  "\{x}|\{y}|\{z}|\{s}"
}
fn main { println(compute()) }
