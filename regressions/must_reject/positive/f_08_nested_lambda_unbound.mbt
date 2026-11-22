fn main {
  let f = fn(x : Int) {
    fn(y : Int) { x + y }
  }
  println(f(2)(3))
}

let _ = __missing_definition
