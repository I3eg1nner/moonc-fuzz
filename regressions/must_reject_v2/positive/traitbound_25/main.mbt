trait T25 { f(Self) -> Int }
struct S25 { x25 : Int }
fn[A : T25] g(a : A) -> Int { a.f() }
fn main { println(g(S25::{x25:25})) }
