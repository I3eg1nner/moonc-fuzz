trait T14 { f(Self) -> Int }
struct S14 { x14 : Int }
fn[A : T14] g(a : A) -> Int { a.f() }
fn main { println(g(S14::{x14:14})) }
