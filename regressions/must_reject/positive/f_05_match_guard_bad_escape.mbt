fn f(n : Int) -> String {
  match n {
    0 | 1 => "small"
    n if n > 10 => "big"
    _ => "mid"
  }
}
fn main {
  println(f(0))
  println(f(5))
  println(f(11))
}

let _ = "\q"
