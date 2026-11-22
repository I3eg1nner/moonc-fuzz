fn f(x? : Int = 1, y? : Int = 2) -> Int {
  x + y
}
fn main {
  println(f())
  println(f(x=10))
  println(f(y=20))
  println(f(x=1, y=2))
}

let _ = "\q"
