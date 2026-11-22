trait T21 { f(Self) -> Int }
struct S21 { x21 : Int }
fn[A : T21] g(a : A) -> Int { a.f() }
fn main { println(g(S21::{x21:21})) }
