enum E {
  A(Int)
  B(String)
  C
}
fn show(e : E) -> String {
  match e {
    A(x) => "A\{x}"
    B(s) => "B\{s}"
    C => "C"
  }
}
fn main {
  println(show(A(1)))
  println(show(B("x")))
  println(show(C))

