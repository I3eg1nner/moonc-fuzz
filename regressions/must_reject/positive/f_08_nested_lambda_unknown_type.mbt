fn main {
  let f = fn(x : IntX) {
    fn(y : Int) { x + y }
  }
  println(f(2)(3))
}
