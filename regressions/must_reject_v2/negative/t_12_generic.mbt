fn[T] id(x : T) -> T { x }
fn[A, B] pair(a : A, b : B) -> (A, B) { (a, b) }
fn compute() -> String {
  let a = id(7)
  let b = id("s")
  let (x, y) = pair(1, "z")
  "\{a}|\{b}|\{x}|\{y}"
}
fn main { println(compute()) }
