trait T5 { f(Self) -> Int }
struct S5 { x5 : Int }
fn[A : T5] g(a : A) -> Int { a.f() }
fn main { println(g(S5::{x5:5})) }
