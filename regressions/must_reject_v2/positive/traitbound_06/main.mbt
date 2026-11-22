trait T6 { f(Self) -> Int }
struct S6 { x6 : Int }
fn[A : T6] g(a : A) -> Int { a.f() }
fn main { println(g(S6::{x6:6})) }
