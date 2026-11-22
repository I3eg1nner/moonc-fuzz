trait T20 { f(Self) -> Int }
struct S20 { x20 : Int }
fn[A : T20] g(a : A) -> Int { a.f() }
fn main { println(g(S20::{x20:20})) }
