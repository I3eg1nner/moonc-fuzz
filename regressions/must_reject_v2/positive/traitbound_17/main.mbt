trait T17 { f(Self) -> Int }
struct S17 { x17 : Int }
fn[A : T17] g(a : A) -> Int { a.f() }
fn main { println(g(S17::{x17:17})) }
