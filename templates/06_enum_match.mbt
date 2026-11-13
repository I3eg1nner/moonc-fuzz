enum E { A(Int); B(String); C }
fn pick(e : E) -> String {
  match e {
    A(n) if n > 0 => "pos:\{n}"
    A(n) => "nonpos:\{n}"
    B(s) => "b:" + s
    C => "c"
  }
}
fn compute() -> String {
  "\{pick(A(3))}|\{pick(A(-3))}|\{pick(B("x"))}|\{pick(C)}"
}
fn main { println(compute()) }
