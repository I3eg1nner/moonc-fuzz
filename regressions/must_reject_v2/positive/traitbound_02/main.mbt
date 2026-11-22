trait T2 { f(Self) -> Int }
struct S2 { x2 : Int }
fn[A : T2] g(a : A) -> Int { a.f() }
fn main { println(g(S2::{x2:2})) }
