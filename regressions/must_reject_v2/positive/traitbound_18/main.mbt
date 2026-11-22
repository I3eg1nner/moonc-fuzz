trait T18 { f(Self) -> Int }
struct S18 { x18 : Int }
fn[A : T18] g(a : A) -> Int { a.f() }
fn main { println(g(S18::{x18:18})) }
