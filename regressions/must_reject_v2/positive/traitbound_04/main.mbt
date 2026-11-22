trait T4 { f(Self) -> Int }
struct S4 { x4 : Int }
fn[A : T4] g(a : A) -> Int { a.f() }
fn main { println(g(S4::{x4:4})) }
